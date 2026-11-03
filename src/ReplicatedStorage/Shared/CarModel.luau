--!strict
-- CarModel: the prototype car, built by code, shared so the server and client agree on it
-- (docs/game/features/drift-model.md "Art and sound").
--
-- A box and four cylinders, our own shape, no manufacturer's outline, name or badge.
--
-- HARD RULE (docs/game/DECISIONS.md, 2026-11-03): Roblox physics never moves this car.
-- Every part is anchored, and the model holds no BodyMover, VectorForce, AlignPosition,
-- AlignOrientation, constraint or joint. DriftTests asserts it, because this is the rule
-- most easily broken later.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CarModel = {}

CarModel.WHEEL_NAMES = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }

-- Where each wheel sits, relative to the car's origin. Front is -Z (the look vector).
function CarModel.wheelOffsets(): { [string]: Vector3 }
	local C = Config.Drift
	local halfBase = C.Wheelbase * 0.5
	local halfTrack = C.TrackWidth * 0.5
	local y = C.WheelDiameter * 0.5 - C.RideHeight
	return {
		WheelFL = Vector3.new(-halfTrack, y, -halfBase),
		WheelFR = Vector3.new(halfTrack, y, -halfBase),
		WheelRL = Vector3.new(-halfTrack, y, halfBase),
		WheelRR = Vector3.new(halfTrack, y, halfBase),
	}
end

function CarModel.isFrontWheel(name: string): boolean
	return name == "WheelFL" or name == "WheelFR"
end

local function newPart(name: string, size: Vector3, colour: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = colour
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true -- never physics
	part.CanCollide = false -- our own sweep handles walls
	part.CanQuery = false -- our own ground rays must not hit the car
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- A fresh car model at the origin. The caller parents it and pivots it into place.
function CarModel.build(): Model
	local C = Config.Drift

	local model = Instance.new("Model")
	model.Name = "Car"

	local body = newPart("Body", Vector3.new(C.BodyWidth, C.BodyHeight, C.BodyLength), Color3.fromRGB(196, 62, 54))
	body.Parent = model
	model.PrimaryPart = body

	-- A Roblox cylinder's axis runs along its local X, which is the car's right, so a wheel
	-- needs no extra rotation to sit the right way round.
	local wheelSize = Vector3.new(C.WheelWidth, C.WheelDiameter, C.WheelDiameter)
	for name, offset in CarModel.wheelOffsets() do
		local wheel = newPart(name, wheelSize, Color3.fromRGB(28, 28, 32))
		wheel.Shape = Enum.PartType.Cylinder
		wheel.CFrame = CFrame.new(offset)
		wheel.Parent = model
	end

	model:PivotTo(CFrame.identity)
	return model
end

-- Everything in a car model that would hand it back to Roblox physics. Empty is the rule.
function CarModel.physicsOffenders(model: Instance): { string }
	local offenders = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BodyMover") or d:IsA("Constraint") or d:IsA("JointInstance") or d:IsA("Motor") then
			table.insert(offenders, `{d:GetFullName()} is a {d.ClassName}`)
		elseif d:IsA("BasePart") and not d.Anchored then
			table.insert(offenders, `{d:GetFullName()} is not anchored`)
		end
	end
	return offenders
end

return CarModel
