--!strict
-- HairpinHint: when a "HAIRPIN AHEAD" line goes into the score feed (T-304, the user's pick
-- of the hint, DECISIONS.md 2026-11-17). Pure: it decides, `ScoreController` shows it.
--
-- WHY: the hairpin events (perfect hairpin, reverse entry, the Scandinavian flick) only count
-- on TRUE hairpins (`Road/Hairpins`: 120 degrees within 250 studs), which come about once
-- every 2 500 to 4 000 studs, and the flick must start inside a 60-stud entry zone, about a
-- second at speed. Without warning a player cannot set one up.
--
-- WHEN: during a run, stepped with the car's state each simulation step. The first step the
-- car is within `Lead` studs (along the road) of a true hairpin's ENTRY ZONE, and not in it
-- yet, it hands back one hint: `{ entry, zone, dir, toZone, speed, seconds }` (`dir` 1 left,
-- -1 right; `seconds` the time to the zone at the car's speed then). It asks the road only
-- every `QueryEvery` studs of travel (`Hairpins.around` at `Lead` ahead), so the hint lands
-- up to that much nearer than `Lead`.
--   ONCE PER HAIRPIN PER PASS: a hairpin hinted is not hinted again until the car is put
--   back (a jump of `JumpStuds` along the road in one step), which starts a new pass.
--   NOT DURING A PUT-BACK: for `Quiet` seconds after one, nothing is hinted.
--   A hairpin the road is not laid far enough past to judge (`open`) is asked about again on
--   the next query; it is hinted once it is known, if the car is still short of its zone.
--
-- `rig` is anything with a `spline` field: the road, or a function returning it (nil off the
-- spline road, where nothing is hinted).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hairpins = require(ReplicatedStorage.Shared.Road.Hairpins)

local HairpinHint = {}
HairpinHint.__index = HairpinHint

HairpinHint.Tuning = {
	Lead = 150, -- studs before a true hairpin's entry zone the hint shows
	QueryEvery = 4, -- studs of travel between looks ahead
	JumpStuds = 80, -- studs along the road in one step that can only be a put-back
	Quiet = 1.0, -- seconds after a put-back with no hint
}

export type Hint = {
	entry: number,
	zone: number,
	dir: number,
	toZone: number,
	speed: number,
	seconds: number,
}

local function splineOf(rig: any): any?
	local sp = rig and rig.spline
	if type(sp) == "function" then
		sp = sp()
	end
	return sp
end

function HairpinHint.new(rig: any)
	local self = setmetatable({
		rig = rig,
		spline = nil :: any,
		s = nil :: number?,
		queriedAt = nil :: number?, -- s of the last look ahead
		clock = 0,
		quietUntil = -math.huge,
		hinted = {} :: { [number]: boolean }, -- hairpins (by entry) hinted this pass
		stats = { hints = 0, putBacks = 0, queries = 0, openSkips = 0 },
		last = nil :: Hint?,
	}, HairpinHint)
	return self
end

-- Back to nothing: a new run.
function HairpinHint.Reset(self: any)
	self.spline = nil
	self.s = nil
	self.queriedAt = nil
	self.quietUntil = -math.huge
	self.hinted = {}
	self.last = nil
end

-- One simulation step. Returns a hint the step one is due, else nil.
function HairpinHint.Update(self: any, dt: number, state: any): Hint?
	local T = HairpinHint.Tuning
	self.clock += dt
	local spline = splineOf(self.rig)
	if spline ~= self.spline then
		self:Reset()
		self.spline = spline
	end
	if not spline then
		return nil
	end
	local prevS = self.s
	local s = Hairpins.locate(spline, state.position, prevS)
	self.s = s
	if not s then
		return nil
	end
	if prevS and math.abs(s - prevS) > T.JumpStuds then
		-- put back: a new pass, and nothing while the car settles
		self.hinted = {}
		self.quietUntil = self.clock + T.Quiet
		self.queriedAt = nil
		self.stats.putBacks += 1
		return nil
	end
	if self.clock < self.quietUntil then
		return nil
	end
	if self.queriedAt and math.abs(s - self.queriedAt) < T.QueryEvery then
		return nil
	end
	self.queriedAt = s
	self.stats.queries += 1
	local h = Hairpins.around(spline, s + T.Lead)
	if not h or self.hinted[h.entry] or s >= h.zone then
		return nil
	end
	if h.open then
		self.stats.openSkips += 1
		return nil
	end
	if not h.hairpin then
		return nil
	end
	self.hinted[h.entry] = true
	local speed = math.sqrt((state.u or 0) ^ 2 + (state.v or 0) ^ 2)
	local toZone = h.zone - s
	local hint: Hint = {
		entry = h.entry,
		zone = h.zone,
		dir = h.dir,
		toZone = toZone,
		speed = speed,
		seconds = if speed > 1 then toZone / speed else math.huge,
	}
	self.last = hint
	self.stats.hints += 1
	return hint
end

function HairpinHint.DebugState(self: any): any
	return {
		s = self.s,
		quiet = self.clock < self.quietUntil,
		stats = table.clone(self.stats),
		last = self.last and table.clone(self.last),
	}
end

return HairpinHint
