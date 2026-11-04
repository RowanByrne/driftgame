--!strict
-- Render: puts a car model where the drift model says it is.
--
-- Every part is anchored, so nothing here asks Roblox to move anything: each part's CFrame
-- is written straight from the simulation state.
--
-- Two of those writes are cosmetic, and they are the only reason a box with four cylinders
-- reads as a drifting car at all:
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

type Wheel = { part: BasePart, offset: Vector3, front: boolean }

export type Rig = {
	car: Model,
	body: BasePart?,
	wheels: { Wheel },
}

function Render.rig(car: Model): Rig
	local wheels: { Wheel } = {}
	for name, offset in CarModel.wheelOffsets() do
		local part = car:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(wheels, { part = part, offset = offset, front = CarModel.isFrontWheel(name) })
		end
	end
	local body = car:FindFirstChild("Body")
	return {
		car = car,
		body = if body and body:IsA("BasePart") then body else nil,
		wheels = wheels,
	}
end

-- Place the car from a pose. `wheelAngle` is where the front wheels are DRAWN, in radians,
-- Roblox's sense: positive points them to the car's left. Another player's car is drawn
-- through this too: their CFrame arrives over the wire, their wheels and their lean do not,
-- so both are zero for them.
function Render.place(rig: Rig, cf: CFrame, wheelAngle: number, wheelSpin: number, bodyRoll: number?)
	if rig.body then
		local roll = bodyRoll or 0
		if roll ~= 0 then
			-- Leaning about the centre of mass rather than about the car's origin, which
			-- is the difference between a car rolling on its springs and a box pivoting
			-- on the road.
			local com = Config.Drift.CenterOfMass
			rig.body.CFrame = cf * CFrame.new(com) * CFrame.Angles(0, 0, roll) * CFrame.new(-com)
		else
			rig.body.CFrame = cf
		end
	end
	for _, wheel in rig.wheels do
		local base = cf * CFrame.new(wheel.offset)
		if wheel.front then
			base *= CFrame.Angles(0, wheelAngle, 0)
		end
		wheel.part.CFrame = base * CFrame.Angles(wheelSpin, 0, 0)
	end
end

-- Place the whole car from one simulation state.
function Render.apply(rig: Rig, state: DriftModel.State)
	Render.place(rig, DriftModel.cframe(state), state.wheelSteer, state.wheelSpin, state.bodyRoll)
end

return Render
