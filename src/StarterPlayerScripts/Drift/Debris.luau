--!nonstrict
-- Debris: real 3D chunks of soil and turf thrown by a wheel sliding on grass (T-283,
-- features/tyre-particles.md "Grass and mud: three ways, compared").
--
-- WHY PARTS AND NOT PARTICLES. A particle is a flat picture turned to face the camera, so
-- however it is painted it reads as a sticker over a 3D world (the user, driving the
-- painted sprites: "it just doesn't work... i don't think it's about the art style"). A chunk
-- here is a small anchored part in the ground's own material and colour, so the scene lights
-- and shades it like the ground it came out of, it casts a shadow, and it tumbles in 3D.
--
-- THE COST IS BOUNDED BY THE POOL. `Config.Fx.Ground.Chunks.Pool` parts are made once, in a
-- client-only folder (`Config.Fx.Names.DebrisFolder`), and never again: a spawn takes the
-- next slot round the ring (the oldest), and every frame the chunks in flight are moved
-- together with one `Workspace:BulkMoveTo`. A chunk flies under gravity and drag, bounces
-- once off the plane of the ground it was thrown from, lies there, and sinks into it at the
-- end of its life, so it goes without a property being faded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Debris = {}
Debris.__index = Debris

local PARK = CFrame.new(0, 1e5, 0)

export type Kind = "clod" | "turf"

type Slot = {
	part: BasePart,
	kind: Kind,
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
	half: number, -- half its smallest size: how far its centre sits off the ground at rest
}

-- `parent` is where the folder goes (Workspace unless said: the tests use ServerStorage).
function Debris.new(parent: Instance?)
	return setmetatable({
		parent = parent or Workspace,
		folder = nil :: Folder?,
		slots = {} :: { Slot },
		ring = { clod = 0, turf = 0 },
		byKind = { clod = {}, turf = {} } :: { [Kind]: { Slot } },
		moveParts = {} :: { BasePart },
		moveFrames = {} :: { CFrame },
		spawned = 0,
		rng = Random.new(283),
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
	local clods = math.floor(C.Pool * C.ClodShare + 0.5)
	for i = 1, C.Pool do
		local kind: Kind = if i <= clods then "clod" else "turf"
		local look = if kind == "clod" then C.Clod else C.Turf
		local part = Instance.new("Part")
		part.Name = string.format("%s_%d", kind, i)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = C.CastShadow
		part.Material = look.Material
		part.Color = look.Colours[rng:NextInteger(1, #look.Colours)]
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		-- Each slot its own size, picked once: the variety is in the pool, not per throw.
		local size = Vector3.new(
			rng:NextNumber(look.Size[1].X, look.Size[2].X),
			rng:NextNumber(look.Size[1].Y, look.Size[2].Y),
			rng:NextNumber(look.Size[1].Z, look.Size[2].Z)
		)
		part.Size = size
		part.Transparency = 1
		part.CFrame = PARK
		part.Parent = folder
		local slot: Slot = {
			part = part,
			kind = kind,
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
		}
		table.insert(self.slots, slot)
		table.insert(self.byKind[kind], slot)
	end
	folder.Parent = self.parent
	self.folder = folder
end

local function park(slot: Slot)
	if slot.alive then
		slot.alive = false
		slot.part.Transparency = 1
		slot.part.CFrame = PARK
	end
end

-- Throw one. `from` is the source attachment's world CFrame: the chunk leaves along its
-- UpVector, inside the kind's spread cone. `ground` and `up` are the ground it lands on;
-- `carVelocity` is inherited in part.
function Debris.Spawn(self, kind: Kind, from: CFrame, ground: Vector3, up: Vector3, carVelocity: Vector3)
	if not self.folder then
		return
	end
	local list = self.byKind[kind]
	if #list == 0 then
		return
	end
	local C = Config.Fx.Ground.Chunks
	local look = if kind == "clod" then C.Clod else C.Turf
	local rng = self.rng
	local i = self.ring[kind] % #list + 1
	self.ring[kind] = i
	local slot = list[i]

	local spread = math.rad(look.SpreadDegrees)
	local dir = (from * CFrame.Angles(rng:NextNumber(-spread, spread), 0, rng:NextNumber(-spread, spread))).UpVector
	local speed = rng:NextNumber(look.Speed[1], look.Speed[2])
	slot.pos = from.Position + Vector3.new(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3))
	slot.vel = dir * speed + carVelocity * C.InheritVelocity
	slot.rot = CFrame.fromOrientation(rng:NextNumber(0, 6.283), rng:NextNumber(0, 6.283), rng:NextNumber(0, 6.283))
	slot.axis = rng:NextUnitVector()
	slot.spin = math.rad(rng:NextNumber(look.SpinDegrees[1], look.SpinDegrees[2])) * (if rng:NextNumber() < 0.5 then -1 else 1)
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

-- Fly, bounce, rest and sink everything in the air or on the ground, and move it all at once.
function Debris.Step(self, dt: number)
	if not self.folder or dt <= 0 then
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
			-- At rest; in the last `SinkSeconds` of its life it sinks into the ground.
			local left = s.life - s.age
			local sink = if left < C.SinkSeconds then 1 - left / C.SinkSeconds else 0
			at = s.rest - s.normal * (sink * s.half * 2.2)
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

-- Everything back in the pool (a jump, or a switch away from chunks).
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
	table.clear(self.slots)
	self.byKind = { clod = {}, turf = {} }
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
		built = self.folder ~= nil,
		pool = #self.slots,
		live = live,
		flying = flying,
		spawned = self.spawned,
	}
end

return Debris
