--!nonstrict
-- TrackService: a hand-placed track, adopted and made drivable.
--
-- The playground (PlaygroundService) is built by code and is in git. A TRACK is the other
-- kind of world: a model someone placed in the place file by hand, which git never sees
-- (AGENTS.md "Hand-built content").
--
-- A PLACE HAS BOTH (T-026). It used to have one or the other, because both were built at
-- the origin and the playground's 2 000-stud plate would have buried the track inside it;
-- this service made the playground stand down. The user asked for both at once, so the
-- one that can be moved moves: the track stays exactly where its author put it, and
-- PlaygroundService builds its world at `Config.Drift.PlaygroundOffsetFromTrack` when it
-- asks here and is told there is a track. Nothing in this file places anything.
--
-- What adopting a track means:
--   * EVERY part of it gets the `DriftSurface` tag, because that is the only thing the
--     car's ground rays look for (docs/game/CONTRACTS.md), and what differs is the
--     `Surface` value: grey reads as road and is tarmac, everything else is dirt and so
--     has half the grip. Leaving scenery untagged was the first attempt and it was wrong
--     -- the rays filter to an INCLUDE list, so an untagged part is not low-grip ground,
--     it is not there at all, and a car put down on the grass fell straight through it.
--   * the place's baseplate stays and is tagged as the floor of last resort, because a
--     track is an island and off its edge there was nothing.
--   * anything that could hand it to Roblox physics is anchored. A hand-placed model is a
--     stranger's work and may contain anything; the car is kinematic and the world must be
--     too (DECISIONS.md, 2026-11-03).
--   * a spawn is found ON the road, by ray, rather than trusting a marker that may not
--     exist.
--
-- Nothing here is specific to one track. Drop a differently named model in and set
-- `Config.Drift.TrackName`.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local TrackService = {}

TrackService.Priority = 110 -- before PlaygroundService (100), which asks whether to build

local C = Config.Drift

local adopted: Model? = nil
local spawnCFrame: CFrame? = nil
local floor: BasePart? = nil
local counts = { road = 0, scenery = 0, anchored = 0, parts = 0 }

-- Is this part road, or is it scenery?
--
-- Read off colour, because a hand-placed track carries no attributes of ours and its part
-- names are whatever its author typed. Tarmac is grey: its channels are close together and
-- it is neither black nor white. Grass, hedges and kerbs are not, which is what we want --
-- a kerb that scored as road would make the edge of the track free, and the edge of the
-- track is where a drift is won or lost.
local function readsAsRoad(part: BasePart): boolean
	local c = part.Color
	local spread = math.max(c.R, c.G, c.B) - math.min(c.R, c.G, c.B)
	return spread < C.TrackRoadColourSpread and c.R > C.TrackRoadMinBrightness and c.R < C.TrackRoadMaxBrightness
end

-- The track, if this place has one.
local function findTrack(): Model?
	local found = workspace:FindFirstChild(C.TrackName)
	if found and found:IsA("Model") then
		return found
	end
	return nil
end

-- Tag what is road, anchor everything, and count what was done so a test can check it.
local function adopt(track: Model)
	counts = { road = 0, scenery = 0, anchored = 0, parts = 0 }
	for _, d in track:GetDescendants() do
		if d:IsA("BasePart") then
			counts.parts += 1
			if not d.Anchored then
				d.Anchored = true
				counts.anchored += 1
			end
			-- EVERYTHING gets tagged, road and scenery alike, and only the SURFACE differs.
			--
			-- Leaving scenery untagged was this service's first attempt and it was wrong:
			-- the ground rays filter to an INCLUDE list of tagged parts, so an untagged
			-- part is not low-grip ground, it is NOT THERE. Measured before this fix: a car
			-- put down on the track's grass was `grounded = false` and falling at 21.9
			-- studs/s through it. "Off the road is nearly frictionless" needs the ground to
			-- exist first.
			--
			-- Verticals are not a problem here: since T-026 the wall sweep sorts a hit by
			-- its NORMAL and not by its tag, so a hedge's side is a wall whether or not its
			-- top is drivable.
			CollectionService:AddTag(d, C.SurfaceTag)
			if readsAsRoad(d) then
				d:SetAttribute(C.SurfaceAttribute, "tarmac")
				counts.road += 1
			else
				d:SetAttribute(C.SurfaceAttribute, C.SurfaceDirt)
				counts.scenery += 1
			end
		elseif d:IsA("BodyMover") or d:IsA("Constraint") or d:IsA("JointInstance") then
			-- A hand-placed model is a stranger's work. The car is kinematic and so is its
			-- world; anything that moves itself is deleted rather than left to surprise us.
			d:Destroy()
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
end

-- Where a car starts: a point ON the road, found by ray, not a marker we hope exists.
-- Rays are cast down over a grid across the track and the first that lands on a tagged
-- part wins, preferring the middle of the track so a run does not start in a corner.
local function findSpawn(track: Model): CFrame?
	local cf, size = track:GetBoundingBox()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { track }

	local best, bestDistance = nil, math.huge
	local steps = C.TrackSpawnSearchSteps
	for ix = 0, steps do
		for iz = 0, steps do
			local x = cf.Position.X + (ix / steps - 0.5) * size.X
			local z = cf.Position.Z + (iz / steps - 0.5) * size.Z
			local from = Vector3.new(x, cf.Position.Y + size.Y, z)
			local hit = workspace:Raycast(from, Vector3.new(0, -size.Y * 3, 0), params)
			if hit and CollectionService:HasTag(hit.Instance, C.SurfaceTag) then
				local d = (Vector3.new(x, 0, z) - Vector3.new(cf.Position.X, 0, cf.Position.Z)).Magnitude
				if d < bestDistance then
					bestDistance = d
					best = Vector3.new(x, hit.Position.Y + C.RideHeight, z)
				end
			end
		end
	end
	if not best then
		return nil
	end
	return CFrame.new(best)
end

function TrackService:Init()
	local track = findTrack()
	if not track then
		return
	end
	-- The baseplate STAYS, and is tagged as the floor of last resort.
	--
	-- This service used to destroy it, the way PlaygroundService does -- and that is right
	-- for the playground, which builds its own plate in its place. A track does not: it is
	-- an island, and off its edge there was nothing at all. The user drove off and asked
	-- for the plate back ("put the baseplate back when you playtest it shouldn't
	-- disappear"), and they were right.
	--
	-- It is safe underneath: the track's road surfaces run from y = -0.05 upward and only
	-- two of 3693 dip below the plate's top at all, by five hundredths of a stud.
	local plate = workspace:FindFirstChild(C.TrackFloorName)
	if plate and plate:IsA("BasePart") then
		plate.Anchored = true
		CollectionService:AddTag(plate, C.SurfaceTag)
		plate:SetAttribute(C.SurfaceAttribute, C.SurfaceDirt)
		floor = plate
	end

	adopt(track)
	spawnCFrame = findSpawn(track)
	adopted = track
	if not spawnCFrame then
		-- No road found is the same as no track: the playground then owns the origin
		-- again, and a car has somewhere to start.
		warn(`[TrackService] adopted '{track.Name}' but found no road to spawn on; it will be left where it is and the playground built at the origin`)
		adopted = nil
	end
end

--------------------------------------------------------------------------------
-- Contract (docs/game/CONTRACTS.md)
--------------------------------------------------------------------------------

-- Has this place got a track? PlaygroundService asks before building -- not to decide
-- WHETHER to build any more, but WHERE -- and CarService asks before choosing a spawn.
function TrackService:HasTrack(): boolean
	return adopted ~= nil
end

function TrackService:SpawnCFrame(): CFrame?
	return spawnCFrame
end

-- The track's world-space box, so a test can prove the two worlds do not overlap. `nil`
-- where there is no track.
function TrackService:Bounds(): { min: Vector3, max: Vector3 }?
	if not adopted then
		return nil
	end
	local cf, size = adopted:GetBoundingBox()
	return { min = cf.Position - size * 0.5, max = cf.Position + size * 0.5 }
end

function TrackService:DebugState()
	local size = if adopted then select(2, adopted:GetBoundingBox()) else Vector3.zero
	local bounds = self:Bounds()
	return {
		hasTrack = adopted ~= nil,
		name = if adopted then adopted.Name else nil,
		size = size,
		min = bounds and bounds.min or nil,
		max = bounds and bounds.max or nil,
		parts = counts.parts,
		road = counts.road,
		scenery = counts.scenery,
		anchoredHere = counts.anchored,
		spawn = spawnCFrame and spawnCFrame.Position or nil,
		floor = floor and floor.Name or nil,
	}
end

-- Measure the track against the car: how wide its roads are, in studs and in car widths.
-- Studio only, and the answer to "is this track the right scale for this car?".
function TrackService:DebugRoadWidths(lines: number?)
	if not adopted then
		return { hasTrack = false }
	end
	local cf, size = adopted:GetBoundingBox()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { adopted }

	local widths = {}
	local n = lines or 8
	for i = 1, n do
		local z = cf.Position.Z + (i / (n + 1) - 0.5) * size.Z
		local run = 0
		for x = -size.X / 2, size.X / 2, 1 do
			local from = Vector3.new(cf.Position.X + x, cf.Position.Y + size.Y, z)
			local hit = workspace:Raycast(from, Vector3.new(0, -size.Y * 3, 0), params)
			if hit and CollectionService:HasTag(hit.Instance, C.SurfaceTag) then
				run += 1
			else
				if run > C.TrackMinRoadRun then
					table.insert(widths, run)
				end
				run = 0
			end
		end
		if run > C.TrackMinRoadRun then
			table.insert(widths, run)
		end
	end
	table.sort(widths)
	local sum = 0
	for _, w in widths do
		sum += w
	end
	local carWidth = C.BodyWidth
	return {
		hasTrack = true,
		crossings = #widths,
		narrowest = widths[1],
		median = widths[math.max(1, math.floor(#widths / 2))],
		widest = widths[#widths],
		mean = if #widths > 0 then sum / #widths else 0,
		carWidth = carWidth,
		medianInCarWidths = if #widths > 0 then widths[math.max(1, math.floor(#widths / 2))] / carWidth else 0,
	}
end

return TrackService
