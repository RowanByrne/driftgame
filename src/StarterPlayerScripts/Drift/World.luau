--!strict
-- World: the only two questions the drift model asks of the Workspace, so the model
-- itself stays pure maths (Drift/Model).
--
--   probe(pos)             the ground under a contact point, and what it is made of
--   sweep(from, to, yaw)   anything solid in the way of this step
--
-- Ground rays prefer parts tagged `DriftSurface` (docs/game/CONTRACTS.md), which is what
-- PlaygroundService tags the world with. While nothing in the world carries that tag --
-- a lane place with only a baseplate, before the playground exists -- they fall back to
-- whatever solid they hit and treat it as road, so the model can be driven and measured
-- anyway.
--
-- A surface carries its own grip and score multipliers, so the model never has to know
-- what a surface is called. A tagged part is tarmac unless its `Surface` attribute says
-- `dirt`; anything solid that is not tagged at all, in a world that does use the tag, is
-- "unspecified" and has almost no grip -- off the road the car barely corrects itself.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Model = require(script.Parent.Model)

local World = {}

local EPSILON = 1e-4

-- A flat plane at `y`, with no walls, and tarmac by default. Used by the automated tests
-- and by any DebugDrive that wants a line it can reason about without the world in the
-- way; pass a grip and a score to make it dirt instead.
function World.flat(y: number, grip: number?, score: number?): Model.World
	local C = Config.Drift
	local hit: Model.Hit = {
		y = y,
		normal = Vector3.yAxis,
		grip = grip or C.GripTarmac,
		score = score or C.ScoreTarmac,
	}
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

	-- What the car is standing on. In a world with nothing tagged every solid is the road,
	-- because there is nothing else it could be; in a world that tags its road, anything
	-- untagged the rays reach is "unspecified" and nearly frictionless.
	local function surfaceOf(part: BasePart): (number, number)
		local tagged = CollectionService:HasTag(part, C.SurfaceTag)
		if not tagged then
			if self.usingTag then
				return C.GripUnspecified, C.ScoreUnspecified
			end
			return C.GripTarmac, C.ScoreTarmac
		end
		if part:GetAttribute(C.SurfaceAttribute) == C.SurfaceDirt then
			return C.GripDirt, C.ScoreDirt
		end
		return C.GripTarmac, C.ScoreTarmac
	end

	function self.probe(pos: Vector3): Model.Hit?
		local result = workspace:Raycast(pos + up, down, groundParams)
		if not result then
			return nil
		end
		local grip, score = surfaceOf(result.Instance)
		return { y = result.Position.Y, normal = result.Normal, grip = grip, score = score }
	end

	function self.sweep(from: Vector3, to: Vector3, yaw: number): (Vector3?, Vector3?)
		local delta = to - from
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude < EPSILON then
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
