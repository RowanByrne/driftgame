--!strict
-- World: the only two questions the drift model asks of the Workspace, so the model
-- itself stays pure maths (Drift/Model).
--
--   probe(pos)             the ground under a contact point
--   sweep(from, to, yaw)   anything solid in the way of this step
--
-- Ground rays prefer parts tagged `DriftSurface` (docs/game/CONTRACTS.md), which is what
-- PlaygroundService tags the world with. While nothing in the world carries that tag --
-- a lane place with only a baseplate, before the playground exists -- they fall back to
-- whatever solid they hit, so the model can be driven and measured anyway.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Model = require(script.Parent.Model)

local World = {}

-- A flat plane at `y`, with no walls. Used by the automated tests and by any DebugDrive
-- that wants a line it can reason about without the world in the way.
function World.flat(y: number): Model.World
	local hit: Model.Hit = { y = y, normal = Vector3.yAxis }
	return {
		probe = function(_pos: Vector3): Model.Hit?
			return hit
		end,
		sweep = nil,
	}
end

export type Live = Model.World & {
	usingTag: boolean,
	surfaceCount: number,
	destroy: () -> (),
}

-- The live Workspace. `ignore` is what the rays must never see: the cars.
function World.live(ignore: { Instance }): Live
	local C = Config.Drift

	local groundParams = RaycastParams.new()
	local sweepParams = RaycastParams.new()
	groundParams.IgnoreWater = true
	sweepParams.IgnoreWater = true

	local self: any = { usingTag = false, surfaceCount = 0 }

	local function refresh()
		local tagged = CollectionService:GetTagged(C.SurfaceTag)
		self.surfaceCount = #tagged
		if #tagged > 0 then
			self.usingTag = true
			groundParams.FilterType = Enum.RaycastFilterType.Include
			groundParams.FilterDescendantsInstances = tagged
		else
			-- Nothing is tagged yet: hit whatever is solid, minus the cars.
			self.usingTag = false
			groundParams.FilterType = Enum.RaycastFilterType.Exclude
			groundParams.FilterDescendantsInstances = ignore
		end
		-- The sweep is for things that are not the road, so it always excludes.
		sweepParams.FilterType = Enum.RaycastFilterType.Exclude
		sweepParams.FilterDescendantsInstances = ignore
	end

	refresh()

	local added = CollectionService:GetInstanceAddedSignal(C.SurfaceTag):Connect(refresh)
	local removed = CollectionService:GetInstanceRemovedSignal(C.SurfaceTag):Connect(refresh)

	local up = Vector3.yAxis * C.GroundRayUp
	local down = Vector3.yAxis * -C.GroundRayLength
	local sweepSize = Vector3.new(C.TrackWidth, C.BodyHeight * 0.6, C.BodyLength)

	function self.probe(pos: Vector3): Model.Hit?
		local result = workspace:Raycast(pos + up, down, groundParams)
		if not result then
			return nil
		end
		return { y = result.Position.Y, normal = result.Normal }
	end

	function self.sweep(from: Vector3, to: Vector3, yaw: number): (Vector3?, Vector3?)
		local delta = to - from
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude < 1e-4 then
			return nil, nil
		end
		local result = workspace:Blockcast(CFrame.new(from) * CFrame.Angles(0, yaw, 0), sweepSize, flat, sweepParams)
		if not result then
			return nil, nil
		end
		-- A surface facing mostly up or down is ground, not a wall: the ground rays own it.
		if math.abs(result.Normal.Y) > 0.7 then
			return nil, nil
		end
		return result.Position, result.Normal
	end

	function self.destroy()
		added:Disconnect()
		removed:Disconnect()
	end

	return self :: Live
end

return World
