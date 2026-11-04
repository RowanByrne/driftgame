--!strict
-- Render: puts a car model where the drift model says it is.
--
-- Every part is anchored, so nothing here asks Roblox to move anything: each part's CFrame
-- is written straight from the simulation state.
--
-- The simulation only ever knows five things: a body and four wheels, at `wheelOffsets()`.
-- A car with the AE86 shell on it (Shared/CarModel) carries five matching groups under
-- `Shell`, and each one is pivoted to the same place as the part it shadows -- so a shelled
-- car and a block car are the same five writes plus five pivots, and the simulation cannot
-- tell them apart.
--
-- Two of those writes are cosmetic, and they are the only reason a car reads as drifting:
--   the body LEANS outward, away from the way the car is sliding, about the centre of
--     mass -- the wheels stay flat on the road;
--   the front wheels POINT ALONG WHERE THE CAR IS TRAVELLING, which is opposite lock the
--     moment the tail is out. The model has no steering angle to draw: the player's finger
--     is the car's rate of turn, so this is read off the slip angle instead.
--
-- `DriftModel` is the simulation (Drift/Model); `Model` is Roblox's class.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Config = require(ReplicatedStorage.Shared.Config)
local DriftModel = require(script.Parent.Model)

local Render = {}

type ShellPart = { part: BasePart, offset: CFrame }
type Shell = { group: Model, parts: { ShellPart } }
type Wheel = { part: BasePart, offset: Vector3, front: boolean, shell: Shell? }

export type Rig = {
	car: Model,
	body: BasePart?,
	bodyShell: Shell?,
	wheels: { Wheel },
	complete: boolean,
}

-- The shell group that shadows a named simulation part, with every part's place in it,
-- ready to be written absolutely. Nil until the whole group has replicated: a Model
-- arrives before its parts, and `N` says how many to wait for.
--
-- Absolute writes, not `Model:PivotTo`. The shell belongs to the server, the server
-- re-asserts its parts' CFrames, and a pivot applies a DELTA -- so every re-assertion is
-- paid twice and the shell walks away from the car (measured: 2 500 studs out inside a
-- minute). The five simulation parts never had the problem because they have always been
-- written absolutely, and now the shell is too.
local function shellOf(car: Model, name: string): Shell?
	local shell = car:FindFirstChild(CarModel.SHELL_NAME)
	if not shell then
		return nil
	end
	local group = shell:FindFirstChild(name)
	if not group or not group:IsA("Model") then
		return nil
	end
	local parts: { ShellPart } = {}
	for _, p in group:GetChildren() do
		if p:IsA("BasePart") then
			local offset = p:GetAttribute("L")
			if typeof(offset) == "CFrame" then
				table.insert(parts, { part = p, offset = offset })
			end
		end
	end
	local want = group:GetAttribute("N")
	if typeof(want) == "number" and #parts < want then
		return nil -- still arriving
	end
	return { group = group, parts = parts }
end

local function placeShell(shell: Shell?, cf: CFrame)
	if not shell then
		return
	end
	for _, entry in shell.parts do
		entry.part.CFrame = cf * entry.offset
	end
end

-- Find the parts, and say whether they are all there yet.
--
-- A car is caught the moment its Model lands in the Cars folder, and a Model replicates
-- before its contents do. With a five-part car that gap was too small to see; with a
-- hundred-part one it is not, and a rig taken inside it holds nothing and draws nothing
-- for the rest of the run. So a rig that is short of parts says so, and is looked up again
-- on the next frame until it is whole. The `Shell` attribute is set by `CarModel` and
-- arrives with the Model itself, so an incomplete rig can tell a block car from a shelled
-- car whose shell has not landed.
local function resolve(rig: Rig)
	local car = rig.car
	local body = car:FindFirstChild(CarModel.BODY_NAME)
	rig.body = if body and body:IsA("BasePart") then body else nil
	rig.bodyShell = shellOf(car, CarModel.BODY_NAME)

	local wheels: { Wheel } = {}
	for name, offset in CarModel.wheelOffsets() do
		local part = car:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(wheels, {
				part = part,
				offset = offset,
				front = CarModel.isFrontWheel(name),
				shell = shellOf(car, name),
			})
		end
	end
	rig.wheels = wheels

	local whole = rig.body ~= nil and #wheels == 4
	if whole and car:GetAttribute(CarModel.SHELL_NAME) then
		whole = rig.bodyShell ~= nil
		for _, wheel in wheels do
			whole = whole and wheel.shell ~= nil
		end
	end
	rig.complete = whole
end

function Render.rig(car: Model): Rig
	local rig: Rig = { car = car, body = nil, bodyShell = nil, wheels = {}, complete = false }
	resolve(rig)
	return rig
end

-- Place the car from a pose. `wheelAngle` is where the front wheels are DRAWN, in radians,
-- Roblox's sense: positive points them to the car's left. Another player's car is drawn
-- through this too: their CFrame arrives over the wire, their wheels and their lean do not,
-- so both are zero for them.
function Render.place(rig: Rig, cf: CFrame, wheelAngle: number, wheelSpin: number, bodyRoll: number?)
	if not rig.complete then
		resolve(rig)
	end

	local bodyCF = cf
	local roll = bodyRoll or 0
	if roll ~= 0 then
		-- Leaning about the centre of mass rather than about the car's origin, which
		-- is the difference between a car rolling on its springs and a box pivoting
		-- on the road.
		local com = Config.Drift.CenterOfMass
		bodyCF = cf * CFrame.new(com) * CFrame.Angles(0, 0, roll) * CFrame.new(-com)
	end
	if rig.body then
		rig.body.CFrame = bodyCF
	end
	placeShell(rig.bodyShell, bodyCF)

	for _, wheel in rig.wheels do
		local base = cf * CFrame.new(wheel.offset)
		if wheel.front then
			base *= CFrame.Angles(0, wheelAngle, 0)
		end
		local wheelCF = base * CFrame.Angles(wheelSpin, 0, 0)
		wheel.part.CFrame = wheelCF
		placeShell(wheel.shell, wheelCF)
	end
end

-- Where a shell group has actually been put, read back off one of its own parts. Only the
-- tests use this: everything else sets the frame rather than asking for it.
function Render.shellFrame(shell: Shell?): CFrame?
	if not shell or #shell.parts == 0 then
		return nil
	end
	local first = shell.parts[1]
	return first.part.CFrame * first.offset:Inverse()
end

-- Place the whole car from one simulation state.
function Render.apply(rig: Rig, state: DriftModel.State)
	Render.place(rig, DriftModel.cframe(state), state.wheelSteer, state.wheelSpin, state.bodyRoll)
end

return Render
