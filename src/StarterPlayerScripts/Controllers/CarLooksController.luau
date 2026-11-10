--!nonstrict
-- CarLooksController: draws every car's fitted looks on this client -- paint, wraps,
-- underglow, rims and tyres (docs/game/features/car-customization.md, T-104).
--
-- Watches every car in `Workspace.Cars`, this player's and everyone else's alike, and
-- redraws one whenever the server says its build changed (`Fitted`, CONTRACTS.md
-- "Customization": watch that, then read the `Fit_*` set with `Customization.read`) or
-- whenever its parts change under it (a car's hundred parts arriving after its Model, or the
-- server re-dressing it in another body). The drawing itself is `Drift/CarLooks`.
--
-- Wraps go in `PlayerGui.CarLooks`; the underglow and the body kits and interiors
-- (`Drift/CarKits`, T-105) in `Workspace.CarLooks`. All are this client's own and none is
-- inside a car.
--
-- The kits follow whatever `CarLooks` last drew on a car (`states[car].build`), so a garage
-- preview drawn through `Garage/Preview` shows its kit too, and its revert takes it off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Customization = require(ReplicatedStorage.Shared.Customization)

local DriftFolder = script.Parent.Parent:WaitForChild("Drift")
local CarLooks = require(DriftFolder.CarLooks)
local CarKits = require(DriftFolder.CarKits)

local CarLooksController = {}

CarLooksController.Priority = 0

local STEP_NAME = "CarLooks"
local FOLDER_NAME = "CarLooks"

function CarLooksController:Init()
	self.states = {} -- car -> CarLooks.State
	self.kits = {} -- car -> CarKits.State
	self.connections = {} -- car -> { RBXScriptConnection }
	self.pending = {} -- car -> true while a redraw is queued
end

local function folderIn(parent: Instance): Folder
	local folder = parent:FindFirstChild(FOLDER_NAME)
	if not folder or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = parent
	end
	return folder :: Folder
end

-- The two folders this draws into, made again if anything ever takes them away (PlayerGui
-- is emptied of some things on a respawn).
function CarLooksController:_parents(): (Instance, Instance)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not self.guiFolder or self.guiFolder.Parent ~= playerGui then
		self.guiFolder = folderIn(playerGui)
	end
	if not self.glowFolder or self.glowFolder.Parent ~= workspace then
		self.glowFolder = folderIn(workspace)
	end
	return self.guiFolder, self.glowFolder
end

function CarLooksController:Start()
	local cars = workspace:WaitForChild("Cars", 30)
	if not cars then
		warn("[CarLooksController] Workspace.Cars never appeared; no car will be drawn with its looks")
		return
	end
	self:_parents()
	cars.ChildAdded:Connect(function(car)
		self:_track(car)
	end)
	cars.ChildRemoved:Connect(function(car)
		self:_untrack(car)
	end)
	for _, car in cars:GetChildren() do
		self:_track(car)
	end

	-- After the cars are drawn (DriftController, Input + 1) and the camera has followed them.
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 2, function()
		CarLooks.step(self.states, workspace:GetServerTimeNow())
		self:_followKits()
		CarKits.step(self.kits)
	end)
end

function CarLooksController:_track(car: Instance)
	if not car:IsA("Model") or self.states[car] then
		return
	end
	local gui, glow = self:_parents()
	self.states[car] = CarLooks.new(car, gui, glow)
	self.kits[car] = CarKits.new(car, glow)
	local function schedule()
		self:_schedule(car)
	end
	local function partsChanged(inst: Instance)
		if inst:IsA("BasePart") or inst:IsA("Model") then
			schedule()
		end
	end
	self.connections[car] = {
		car:GetAttributeChangedSignal(Customization.ATTR_COUNTER):Connect(schedule),
		car:GetAttributeChangedSignal("Body"):Connect(schedule),
		car.DescendantAdded:Connect(partsChanged),
		car.ChildRemoved:Connect(partsChanged),
	}
	schedule()
end

function CarLooksController:_untrack(car: Instance)
	local state = self.states[car]
	if state then
		CarLooks.clear(state)
	end
	if self.kits[car] then
		CarKits.clear(self.kits[car])
	end
	self.kits[car] = nil
	for _, c in self.connections[car] or {} do
		c:Disconnect()
	end
	self.states[car], self.connections[car], self.pending[car] = nil, nil, nil
end

-- A burst of changes (a hundred parts arriving) is one redraw, at the end of the frame.
function CarLooksController:_schedule(car: Instance)
	if self.pending[car] then
		return
	end
	self.pending[car] = true
	task.defer(function()
		self.pending[car] = nil
		self:_draw(car)
	end)
end

function CarLooksController:_draw(car: Instance)
	local state = self.states[car]
	if not state then
		return
	end
	state.guiParent, state.glowParent = self:_parents()
	local ok, err = pcall(CarLooks.apply, state, Customization.read(car))
	if not ok then
		warn(`[CarLooksController] could not draw {car:GetFullName()}: {err}`)
	end
	self:_drawKits(car)
end

-- The car's colour as drawn, for kit shapes painted with the body.
local function bodyColour(state): Color3?
	local first = state.roles and state.roles.body and state.roles.body[1]
	return first and first.Color or nil
end

-- The kits and interior for whatever `CarLooks` last drew on the car.
function CarLooksController:_drawKits(car: Instance)
	local state, kit = self.states[car], self.kits[car]
	if not state or not kit then
		return
	end
	kit.parent = self.glowFolder
	local ok, err = pcall(CarKits.apply, kit, state.build, bodyColour(state))
	if not ok then
		warn(`[CarLooksController] could not draw the kits on {car:GetFullName()}: {err}`)
	end
end

-- A preview (`Garage/Preview`) draws through `CarLooks.apply` straight onto the state, so the
-- kits catch up here, once, whenever the build drawn is not the one they were drawn for.
function CarLooksController:_followKits()
	for car, state in self.states do
		local kit = self.kits[car]
		if kit and kit.build ~= state.build then
			self:_drawKits(car)
		end
	end
end

-- ---------------------------------------------------------------------- Studio only

-- What every car is drawn as: its body, its build, each role's parts with their colour,
-- material and reflectance, how many wrap faces, and the glow (on, mode, colour, brightness
-- and where it sits in the body's frame).
function CarLooksController:DebugState()
	local out = {}
	for car, state in self.states do
		local d = CarLooks.describe(state)
		d.userId = car:GetAttribute("UserId")
		d.fitted = car:GetAttribute(Customization.ATTR_COUNTER)
		d.kits = self.kits[car] and CarKits.describe(self.kits[car])
		out[car.Name .. "_" .. tostring(d.userId)] = d
	end
	return out
end

-- Draw every car again now, without waiting for a change.
function CarLooksController:DebugRedraw()
	for car in self.states do
		self:_draw(car)
	end
	return true
end

return CarLooksController
