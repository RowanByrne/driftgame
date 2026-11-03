--!strict
-- Render: puts a car model where the drift model says it is.
--
-- Every part is anchored, so nothing here asks Roblox to move anything: each part's CFrame
-- is written straight from the simulation state. The front wheels turn with the steering
-- and all four roll with the car's speed, which is the only way a player can read the
-- steering angle off a box with four cylinders.
--
-- `DriftModel` is the simulation (Drift/Model); `Model` is Roblox's class.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
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

-- Place the car from a pose. `wheelAngle` is where the front wheels really point, in
-- radians: not the stick, the wheels. In a drift those are opposite, and front wheels
-- pointing out of the corner while the car goes round it is the one thing on a box with
-- four cylinders that reads as a drift at all. Another player's car is drawn through this
-- too: their CFrame arrives over the wire, their steering angle does not.
function Render.place(rig: Rig, cf: CFrame, wheelAngle: number, wheelSpin: number)
	if rig.body then
		rig.body.CFrame = cf
	end
	for _, wheel in rig.wheels do
		local base = cf * CFrame.new(wheel.offset)
		if wheel.front then
			-- Roblox yaw turns left for a positive angle; the model's angle is positive right.
			base *= CFrame.Angles(0, -wheelAngle, 0)
		end
		wheel.part.CFrame = base * CFrame.Angles(wheelSpin, 0, 0)
	end
end

-- Place the whole car from one simulation state.
function Render.apply(rig: Rig, state: DriftModel.State)
	Render.place(rig, DriftModel.cframe(state), state.wheelAngle, state.wheelSpin)
end

return Render
