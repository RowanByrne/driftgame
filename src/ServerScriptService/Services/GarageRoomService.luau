--!nonstrict
-- GarageRoomService: builds the garage interior and hands out its named points
-- (docs/game/features/car-customization.md, docs/game/WORLD.md "Garage"; T-102).
--
-- The room is a grey-box built by code at Init, to the picked concept
-- (assets/garage-concept/garage-01.png): a small street-tuning garage with a turntable in
-- the middle, the roller door open onto a dusk street. It stands on its own, far out on -X
-- at `Config.GarageRoom.Origin`, clear of every other world.
--
-- WHAT LATER STEPS READ. Never a coordinate: a named point, by `GetPoint(name)`, which is
-- a world CFrame (Layout.PointOrder lists them):
--   TurntableTop  the deck's centre, on its top, facing the way the car came in
--   CarEntry      on the street outside the door, facing in
--   CarExit       just outside the door, facing out
--   CamWide / CamWheels / CamUnderside / CamCabin   camera poses, looking at the car
-- Car points are ON the surface: stand a car at the point raised by its ride height.
-- The turntable is `Turntable()`, a Model whose PrimaryPart is the deck;
-- `SetTurntableAngle` spins it about its own centre (and a car on it is the caller's).
--
-- Getting a player into the room -- the trigger, the menus, the camera -- is T-103's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(ServerScriptService.GarageRoom.Build)
local Layout = require(ServerScriptService.GarageRoom.Layout)

local GarageRoomService = {}
GarageRoomService.Priority = 90 -- after PlaygroundService (100), before anything spawns a car

GarageRoomService.Root = nil :: Model?

local built = nil -- { turntable, deck, points } from Build.room
local turntableHome = CFrame.identity -- the turntable's pivot at angle 0
local turntableAngle = 0
local builds = 0

local function frame(): CFrame
	local tuning = Config.GarageRoom
	return CFrame.new(tuning.Origin) * CFrame.Angles(0, math.rad(tuning.Yaw or 0), 0)
end

local function isRoom(child: Instance): boolean
	return child:IsA("Model") and child:GetAttribute("GarageRoom") == true
end

function GarageRoomService:Init()
	self:Build()
end

-- Build the room, taking down any room already there first, so it is never doubled.
function GarageRoomService:Build(): Model
	for _, child in Workspace:GetChildren() do
		if isRoom(child) then
			child:Destroy()
		end
	end
	local model, parts = Build.room(frame(), Workspace)
	built = parts
	self.Root = model
	turntableHome = parts.turntable:GetPivot()
	turntableAngle = 0
	builds += 1
	return model
end

-- A named point's world CFrame, or nil for a name the room does not have.
function GarageRoomService:GetPoint(name: string): CFrame?
	local point = built and built.points[name]
	if point and point.Parent then
		return point.CFrame
	end
	return nil
end

function GarageRoomService:PointNames(): { string }
	return table.clone(Layout.PointOrder)
end

-- The turntable: a Model, PrimaryPart `Deck`, pivoted at the deck's top centre.
function GarageRoomService:Turntable(): Model?
	return built and built.turntable
end

-- Spin the turntable to `radians` about its own vertical axis (absolute, not a step).
function GarageRoomService:SetTurntableAngle(radians: number)
	if type(radians) ~= "number" or radians ~= radians or not built then
		return
	end
	turntableAngle = radians % (math.pi * 2)
	built.turntable:PivotTo(turntableHome * CFrame.Angles(0, turntableAngle, 0))
end

function GarageRoomService:TurntableAngle(): number
	return turntableAngle
end

function GarageRoomService:DebugState()
	local root = self.Root
	local parts = 0
	if root then
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
	end
	local points = {}
	if built then
		for name, part in built.points do
			points[name] = part.Position
		end
	end
	local cf, size
	if root and root.Parent then
		cf, size = root:GetBoundingBox()
	end
	return {
		built = root ~= nil and root.Parent ~= nil,
		builds = builds,
		origin = frame().Position,
		parts = parts,
		boundsCentre = cf and cf.Position,
		boundsSize = size,
		turntableAngle = turntableAngle,
		points = points,
	}
end

return GarageRoomService
