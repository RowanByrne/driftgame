--!strict
-- Scrape: sparks off every floor point that rests on something, and a scrape sound,
-- louder the faster it slides (docs/game/features/car-v2.md "Floor scraping", T-097).
--
-- LOOKS ONLY. Everything here is read off the model's own per-step floor contacts
-- (`state.floorContacts`, `Drift/Suspension.contacts`) and nothing is written back: the
-- car's motion is the same with this module running or not, and `ScrapeTests` drives the
-- same ledge both ways to say so.
--
-- ONE POINT, ONE SPARK. The model lists a floor point once per support it gathered, and an
-- edge crossing can sit on top of a floor point, so the same place can come in two or
-- three times. Contacts closer than `MergeDistance` are merged (the fastest one's speed is
-- kept) before any spark is lit.
--
-- THE SPARKS ARE NOT IN THE CAR. Each spark slot is an anchored, non-colliding,
-- non-queryable, invisible part with one `ParticleEmitter`, moved to its point every frame
-- (DECISIONS.md 2026-11-03: no weld, joint or constraint in the car). The parts sit in a
-- folder of their own -- the camera's, on the client -- so no ray, no rig and no car
-- model ever sees them. Each part is turned so its top faces back from the slide and up,
-- and the emitter throws from its top.
--
-- THE SOUND is one looped `Sound` on the car's body, as `Drift/SkidSound`'s are: playing
-- only while something scrapes, at a volume lerped toward
-- `lerp(MinVolume, MaxVolume, fastest point's speed / SpeedForMax)`. In an agent's quiet
-- playtest it is never started and its volume stays 0; the logic's volume is still
-- computed and reported.
--
-- NOTHING IS CREATED OR DESTROYED WHILE DRIVING: the slots are built once, the sound once
-- per body, and `Update` holds no table.
--
-- The driven car only. Other players' cars do not carry their floor contacts.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

-- An agent's playtest makes no sound: the same block as `Drift/SkidSound`.
local QUIET = (function(): boolean
	local module = ReplicatedFirst:FindFirstChild("QuietPlay")
	if not module or not module:IsA("ModuleScript") then
		return false
	end
	local ok, quiet = pcall(function()
		return (require(module) :: any).isQuiet()
	end)
	return ok and quiet == true
end)()

local Scrape = {}
Scrape.__index = Scrape

type Slot = {
	part: BasePart,
	emitter: ParticleEmitter,
	on: boolean, -- what was last WRITTEN
	rate: number,
}

export type Scrape = typeof(setmetatable(
	{} :: {
		folder: Folder?,
		parent: Instance?,
		slots: { Slot },
		body: BasePart?,
		sound: Sound?,
		playing: boolean,
		enabled: boolean,
		volume: number, -- the lerped logic volume, 0 .. 1, before the master
		target: number,
		-- The merged points this frame, in preallocated arrays.
		n: number,
		px: { number },
		py: { number },
		pz: { number },
		ps: { number },
		fastest: number, -- studs/s, the fastest merged point this frame
		raw: number, -- contacts the model listed this frame, before merging
	},
	Scrape
))

local function S()
	return Config.Fx.Scrape
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

-- How far up its range a point sliding at `speed` is: 0 below `MinSpeed`, else 0 .. 1.
function Scrape.share(speed: number): number
	local P = S()
	if speed < P.MinSpeed then
		return 0
	end
	return math.clamp((speed - P.MinSpeed) / math.max(P.SpeedForMax - P.MinSpeed, 1e-3), 0, 1)
end

-- The volume a scrape at `speed` asks for, before the lerp and the master. 0 for none.
function Scrape.volumeFor(speed: number): number
	local P = S()
	if speed < P.MinSpeed then
		return 0
	end
	return lerp(P.MinVolume, P.MaxVolume, Scrape.share(speed))
end

function Scrape.rateFor(speed: number): number
	local P = S()
	if speed < P.MinSpeed then
		return 0
	end
	return lerp(P.RateMin, P.RateMax, Scrape.share(speed))
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

-- `parent` is where the spark folder goes: the camera on the client when nil, a test's own
-- folder in `ScrapeTests`.
function Scrape.new(parent: Instance?): Scrape
	local max = S().MaxPoints
	return setmetatable({
		folder = nil,
		parent = parent,
		slots = {},
		body = nil,
		sound = nil,
		playing = false,
		enabled = true,
		volume = 0,
		target = 0,
		n = 0,
		px = table.create(max, 0),
		py = table.create(max, 0),
		pz = table.create(max, 0),
		ps = table.create(max, 0),
		fastest = 0,
		raw = 0,
	}, Scrape) :: any
end

local function makeSlot(i: number, folder: Folder): Slot
	local P = S()
	local K = P.Sparks
	local part = Instance.new("Part")
	part.Name = string.format(Config.Fx.Names.Spark, i)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(0, -10000, 0)

	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparks"
	e.Enabled = false
	e.Rate = P.RateMin
	e.EmissionDirection = Enum.NormalId.Top
	e.Color = ColorSequence.new(K.Colour)
	e.LightEmission = K.LightEmission
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, K.Size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0)
	e.Lifetime = NumberRange.new(K.Lifetime[1], K.Lifetime[2])
	e.Speed = NumberRange.new(K.Speed[1], K.Speed[2])
	e.SpreadAngle = Vector2.new(K.SpreadAngle, K.SpreadAngle)
	e.Acceleration = Vector3.new(0, -K.Gravity, 0)
	e.Drag = K.Drag
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Squash = NumberSequence.new(1.5) -- streaks, not dots
	e.Parent = part
	part.Parent = folder
	return { part = part, emitter = e, on = false, rate = e.Rate }
end

-- The spark slots, once. Called by `Attach`, and by `Update` if nothing attached yet.
function Scrape.Build(self: Scrape)
	if self.folder and self.folder.Parent then
		return
	end
	local parent = self.parent or workspace.CurrentCamera
	if not parent then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = Config.Fx.Names.SparkFolder
	table.clear(self.slots)
	for i = 1, S().MaxPoints do
		table.insert(self.slots, makeSlot(i, folder))
	end
	folder.Parent = parent
	self.folder = folder
end

-- The scrape sound on the car's body, once per body; the slots, once. Cheap to call every
-- frame, the same shape as `Drift/SkidSound:Attach`.
function Scrape.Attach(self: Scrape, rig: any): boolean
	Scrape.Build(self)
	local body = rig and rig.body
	if body and self.body == body then
		return true
	end
	if self.sound then
		self.sound:Destroy()
		self.sound = nil
	end
	self.playing = false
	self.body = body
	if not body then
		return false
	end
	local P = S()
	local id = P.SoundId
	if type(id) == "string" and id ~= "" then
		local sound = Instance.new("Sound")
		sound.Name = Config.Fx.Names.Scrape
		sound.SoundId = id
		sound.Looped = true
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = P.RollOffMin
		sound.RollOffMaxDistance = P.RollOffMax
		sound.Volume = 0
		sound.Parent = body
		self.sound = sound
	end
	return true
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

-- Merge the model's contacts into distinct points. No table is made.
local function gather(self: Scrape, contacts: { any }?)
	self.n = 0
	self.fastest = 0
	self.raw = 0
	if not contacts then
		return
	end
	local P = S()
	local max = P.MaxPoints
	local merge2 = P.MergeDistance * P.MergeDistance
	local px, py, pz, ps = self.px, self.py, self.pz, self.ps
	for _, c in contacts do
		self.raw += 1
		local p: Vector3 = c.position
		local sp: number = c.speed
		local found = 0
		for k = 1, self.n do
			local dx, dy, dz = px[k] - p.X, py[k] - p.Y, pz[k] - p.Z
			if dx * dx + dy * dy + dz * dz <= merge2 then
				found = k
				break
			end
		end
		if found > 0 then
			if sp > ps[found] then
				ps[found] = sp
			end
		elseif self.n < max then
			self.n += 1
			px[self.n], py[self.n], pz[self.n], ps[self.n] = p.X, p.Y, p.Z, sp
		else
			-- Full: replace the slowest if this one is faster.
			local slow, at = math.huge, 0
			for k = 1, self.n do
				if ps[k] < slow then
					slow, at = ps[k], k
				end
			end
			if sp > slow then
				px[at], py[at], pz[at], ps[at] = p.X, p.Y, p.Z, sp
			end
		end
	end
	for k = 1, self.n do
		if ps[k] > self.fastest then
			self.fastest = ps[k]
		end
	end
end

function Scrape.Update(self: Scrape, state: any, dt: number?)
	if #self.slots == 0 then
		Scrape.Build(self)
	end
	local P = S()
	local step = math.max(dt or 0, 0)
	local airborne = state == nil or state.airborne == true
	if self.enabled and state and not airborne then
		gather(self, state.floorContacts)
	else
		gather(self, nil)
	end

	-- Which way the sparks fly: back from the car's slide, and up.
	local dir = Vector3.yAxis
	if state and state.velocity then
		local v: Vector3 = state.velocity
		local flat = Vector3.new(v.X, 0, v.Z)
		if flat.Magnitude > 0.5 then
			dir = (Vector3.yAxis - flat.Unit * 1.2).Unit
		end
	end
	local side = if math.abs(dir.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis:Cross(dir).Unit
	local back = side:Cross(dir)

	local min = P.MinSpeed
	for i, slot in self.slots do
		local on = i <= self.n and self.ps[i] >= min
		if on then
			slot.part.CFrame = CFrame.fromMatrix(Vector3.new(self.px[i], self.py[i] + P.Lift, self.pz[i]), side, dir, back)
			local rate = Scrape.rateFor(self.ps[i])
			if math.abs(rate - slot.rate) > 0.5 then
				slot.rate = rate
				slot.emitter.Rate = rate
			end
		end
		if slot.on ~= on then
			slot.on = on
			slot.emitter.Enabled = on
		end
	end

	-- The sound.
	self.target = Scrape.volumeFor(self.fastest)
	local before = self.volume
	self.volume += (self.target - before) * math.clamp(step * P.VolumeLerpSpeed, 0, 1)
	if self.target == 0 and self.volume < 0.01 then
		self.volume = 0
	end
	local sound = self.sound
	if sound then
		local want = self.volume > 0
		if want ~= self.playing then
			self.playing = want
			if want and not QUIET then
				sound:Play()
			elseif not want then
				sound:Stop()
			end
		end
		local vol = if want and not QUIET then self.volume * P.Volume else 0
		if math.abs(sound.Volume - vol) > 1e-4 then
			sound.Volume = vol
		end
	end
end

-- Everything off now: a jump (spawn, respawn, teleport, park) must not carry sparks across.
function Scrape.Cut(self: Scrape)
	self.n = 0
	self.fastest = 0
	self.volume = 0
	self.target = 0
	for _, slot in self.slots do
		if slot.on then
			slot.on = false
			slot.emitter.Enabled = false
		end
	end
	if self.sound then
		if self.playing then
			self.sound:Stop()
		end
		self.sound.Volume = 0
	end
	self.playing = false
end

function Scrape.SetEnabled(self: Scrape, on: boolean): boolean
	self.enabled = on == true
	if not self.enabled then
		Scrape.Cut(self)
	end
	return self.enabled
end

function Scrape.Destroy(self: Scrape)
	Scrape.Cut(self)
	if self.sound then
		self.sound:Destroy()
		self.sound = nil
	end
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
	table.clear(self.slots)
	self.body = nil
end

function Scrape.CountInstances(self: Scrape): number
	local n = 0
	for _, slot in self.slots do
		n += (if slot.part.Parent then 1 else 0) + (if slot.emitter.Parent then 1 else 0)
	end
	n += if self.folder and self.folder.Parent then 1 else 0
	n += if self.sound and self.sound.Parent then 1 else 0
	return n
end

-- What the sparks and the scrape are doing, and where. Allocates; tests and by hand only.
function Scrape.DebugState(self: Scrape)
	local sparks = {}
	for i, slot in self.slots do
		if slot.on then
			table.insert(sparks, {
				slot = i,
				position = slot.part.Position,
				ground = Vector3.new(self.px[i], self.py[i], self.pz[i]),
				speed = self.ps[i],
				rate = slot.emitter.Rate,
			})
		end
	end
	return {
		quiet = QUIET,
		enabled = self.enabled,
		attached = self.body ~= nil,
		instances = Scrape.CountInstances(self),
		rawContacts = self.raw, -- as the model listed them
		points = self.n, -- after merging
		sparks = sparks, -- the lit slots
		fastest = self.fastest,
		target = self.target,
		volume = self.volume, -- the logic's, before the master and the mute
		soundId = if self.sound then self.sound.SoundId else nil,
		wants = self.playing,
		playing = if self.sound then self.sound.IsPlaying else false,
		soundVolume = if self.sound then self.sound.Volume else 0,
	}
end

return Scrape
