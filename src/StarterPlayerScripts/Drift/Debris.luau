--!nonstrict
-- Debris: the mud a wheel throws sliding on grass, as small low-poly 3D clods (T-283,
-- features/tyre-particles.md "The mud: low-poly clods").
--
-- WHY PARTS AND NOT PARTICLES. A particle is a flat picture turned to face the camera, so
-- however it is painted it reads as a sticker over a 3D world (the user, driving the painted
-- sprites: "it just doesn't work... i don't think it's about the art style"). A clod here is a
-- small anchored part in the ground's own material and colour, so the scene lights and shades
-- it like the ground it came out of, it casts a shadow, and it tumbles in 3D.
--
-- THE SHAPES ARE ROBLOX'S OWN WEDGES. Each clod is a `CornerWedgePart` or a `WedgePart` of
-- its own uneven size, so tumbling it reads as a jagged shard of soil of 8 triangles or fewer
-- (the user asked for 30 at most). NO EDITABLEMESH, ON PURPOSE: a first build made six
-- 20-triangle rocks as EditableMeshes, and those took the client's EditableMesh budget that
-- the tyre-mark ribbons need, so no marks were built at all (measured in DR-Lane2: both
-- ribbons failed "no EditableMesh", the console "reaching memory budget limits"). A real rock
-- mesh would have to be an uploaded asset.
--
-- THE COST IS BOUNDED BY THE POOL. `Chunks.Pool` parts are made once, in a client-only
-- folder (`Config.Fx.Names.DebrisFolder`), and never again: a throw takes the next slot round
-- the ring (the oldest), and every frame the clods in flight or sinking are moved together
-- with one `Workspace:BulkMoveTo`. A clod flies under gravity and drag, bounces once off the
-- plane of the ground it was thrown from, lies there, and sinks into it at the end of its life,
-- so it goes without a property being faded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Debris = {}
Debris.__index = Debris

local PARK = CFrame.new(0, 1e5, 0)

-- The shapes the pool cycles through, and the most triangles any of them has.
local SHAPES = { "CornerWedgePart", "WedgePart" }
Debris.TRIANGLES = 8

type Slot = {
	part: BasePart,
	alive: boolean,
	pos: Vector3,
	vel: Vector3,
	rot: CFrame, -- orientation only
	axis: Vector3,
	spin: number, -- rad/s about `axis`
	age: number,
	life: number,
	plane: Vector3, -- a point on the ground it was thrown from...
	normal: Vector3, -- ...and that ground's up
	bounces: number,
	landed: boolean,
	rest: Vector3, -- where it came to rest
	half: number, -- half its height: how far its centre sits off the ground at rest
}

-- `parent` is where the folder goes (Workspace unless said: the tests use ServerStorage).
function Debris.new(parent: Instance?)
	return setmetatable({
		parent = parent or Workspace,
		folder = nil :: Folder?,
		ready = false,
		slots = {} :: { Slot },
		ring = 0,
		moveParts = {} :: { BasePart },
		moveFrames = {} :: { CFrame },
		spawned = 0,
		rng = Random.new(Config.Fx.Ground.Chunks.Seed),
	}, Debris)
end

-- Make the pool, once. Safe to call again.
function Debris.Build(self)
	if self.folder then
		return
	end
	local C = Config.Fx.Ground.Chunks
	local rng = self.rng
	local folder = Instance.new("Folder")
	folder.Name = Config.Fx.Names.DebrisFolder
	for i = 1, C.Pool do
		local part = Instance.new(SHAPES[(i - 1) % #SHAPES + 1]) :: BasePart
		part.Name = string.format("Clod_%d", i)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = C.CastShadow
		part.Material = C.Material
		part.Color = C.Colours[rng:NextInteger(1, #C.Colours)]
		-- Each slot its own uneven size, picked once: the variety is in the pool, not per throw.
		local d = rng:NextNumber(C.Size[1], C.Size[2])
		local u = C.Uneven
		local size = Vector3.new(
			d * rng:NextNumber(u[1], u[2]),
			d * C.Squash * rng:NextNumber(u[1], u[2]),
			d * rng:NextNumber(u[1], u[2])
		)
		part.Size = size
		part.Transparency = 1
		part.CFrame = PARK
		part.Parent = folder
		table.insert(self.slots, {
			part = part,
			alive = false,
			pos = Vector3.zero,
			vel = Vector3.zero,
			rot = CFrame.identity,
			axis = Vector3.yAxis,
			spin = 0,
			age = 0,
			life = 1,
			plane = Vector3.zero,
			normal = Vector3.yAxis,
			bounces = 0,
			landed = false,
			rest = Vector3.zero,
			half = math.min(size.X, size.Y, size.Z) * 0.5,
		})
	end
	folder.Parent = self.parent
	self.folder = folder
	self.ready = true
end

local function park(slot: Slot)
	if slot.alive then
		slot.alive = false
		slot.part.Transparency = 1
		slot.part.CFrame = PARK
	end
end

-- Throw one. `from` is the source attachment's world CFrame: the clod leaves along its
-- UpVector, inside the spread cone. `ground` and `up` are the ground it lands on;
-- `carVelocity` is inherited in part.
function Debris.Spawn(self, from: CFrame, ground: Vector3, up: Vector3, carVelocity: Vector3)
	if not self.ready then
		return
	end
	local C = Config.Fx.Ground.Chunks
	local rng = self.rng
	local slots = self.slots
	local i = self.ring % #slots + 1
	self.ring = i
	local slot = slots[i]

	local spread = math.rad(C.SpreadDegrees)
	local dir = (from * CFrame.Angles(rng:NextNumber(-spread, spread), 0, rng:NextNumber(-spread, spread))).UpVector
	slot.pos = from.Position + Vector3.new(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.25, 0.25))
	slot.vel = dir * rng:NextNumber(C.Speed[1], C.Speed[2]) + carVelocity * C.InheritVelocity
	slot.rot = CFrame.fromOrientation(rng:NextNumber(0, 6.283), rng:NextNumber(0, 6.283), rng:NextNumber(0, 6.283))
	slot.axis = rng:NextUnitVector()
	slot.spin = math.rad(rng:NextNumber(C.SpinDegrees[1], C.SpinDegrees[2])) * (if rng:NextNumber() < 0.5 then -1 else 1)
	slot.age = 0
	slot.life = rng:NextNumber(C.Lifetime[1], C.Lifetime[2])
	slot.plane = ground
	slot.normal = up
	slot.bounces = 0
	slot.landed = false
	if not slot.alive then
		slot.alive = true
		slot.part.Transparency = 0
	end
	self.spawned += 1
end

-- Fly, bounce, rest and sink every clod out of the pool, and move them all at once. One that
-- is lying still and not yet sinking is not moved.
function Debris.Step(self, dt: number)
	if not self.ready or dt <= 0 then
		return
	end
	local C = Config.Fx.Ground.Chunks
	local parts, frames = self.moveParts, self.moveFrames
	table.clear(parts)
	table.clear(frames)
	local gravity = Vector3.new(0, -C.Gravity * dt, 0)
	local dragKeep = math.exp(-C.Drag * dt)
	for _, s in self.slots do
		if not s.alive then
			continue
		end
		s.age += dt
		if s.age >= s.life then
			park(s)
			continue
		end
		local at: Vector3
		if not s.landed then
			s.vel = (s.vel + gravity) * dragKeep
			s.pos += s.vel * dt
			s.rot = CFrame.fromAxisAngle(s.axis, s.spin * dt) * s.rot
			local height = (s.pos - s.plane):Dot(s.normal) - s.half
			if height < 0 then
				local into = s.vel:Dot(s.normal)
				s.pos -= s.normal * height
				if into < 0 and s.bounces < C.Bounces and -into > C.MinBounceSpeed then
					local along = s.vel - s.normal * into
					s.vel = along * C.BounceKeep - s.normal * into * C.Bounce
					s.spin *= 0.5
					s.bounces += 1
				else
					s.landed = true
					s.rest = s.pos
				end
			end
			at = s.pos
		else
			local left = s.life - s.age
			if left >= C.SinkSeconds then
				continue -- lying still: nothing to move
			end
			at = s.rest - s.normal * ((1 - left / C.SinkSeconds) * s.half * 2.2)
		end
		table.insert(parts, s.part)
		table.insert(frames, s.rot + at)
	end
	if #parts > 0 then
		if (self.folder :: Folder):IsDescendantOf(Workspace) then
			Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		else -- the tests' pool, outside the world
			for i, part in parts do
				part.CFrame = frames[i]
			end
		end
	end
end

-- Every clod back in the pool (a jump, or the effects switched off).
function Debris.Clear(self)
	for _, s in self.slots do
		park(s)
	end
end

function Debris.Destroy(self)
	if self.folder then
		self.folder:Destroy()
	end
	self.folder = nil
	self.ready = false
	table.clear(self.slots)
end

-- Allocates; tests and by hand only.
function Debris.DebugState(self)
	local live, flying = 0, 0
	for _, s in self.slots do
		if s.alive then
			live += 1
			if not s.landed then
				flying += 1
			end
		end
	end
	return {
		ready = self.ready,
		pool = #self.slots,
		shapes = #SHAPES, -- built-in wedge shapes; no EditableMesh
		triangles = Debris.TRIANGLES,
		live = live,
		flying = flying,
		spawned = self.spawned,
	}
end

return Debris
