--!strict
-- ScandiFlick: the "Scandinavian flick" conditional score event (features/score-events.md
-- "The user's revision", T-300). A detector on the shared interface ("The shared
-- interface"): `new(sink, rig)`, `Update(dt, state)` each frame with the drift model's
-- state, `DebugState()`. It only ever calls `sink.start` and the handle it gets back.
--
-- THE RULE (the user's, extreme difficulty): a 4-tyre drift to one side, performed in the
-- detection zone before a hairpin and the opposite way to the hairpin; then a rapid switch
-- (within a time window, "perhaps 1 second") to a 4-tyre drift the other way, the right way
-- for the hairpin; and to complete, the 4-tyre drift held through the rest of the hairpin.
--
--   STARTS when, inside a hairpin's ENTRY ZONE (`Road/Hairpins`: from `zone` up to
--   `entry`), the car has held a 4-wheel drift turned OUT of the hairpin (the slip the way
--   a bend the other way would want) for `MinHold`. Only the time inside the zone counts:
--   a drift carried in from before it still needs `MinHold` inside. One attempt per
--   hairpin. The handle is opened here, so the feed can show the attempt live.
--   THE FLICK: once the wrong-way 4-wheel drift is let go, the right-way 4-wheel drift
--   (turned INTO the hairpin) must follow within `Window` seconds. Going back to the
--   wrong-way drift inside the window is still holding it: the window starts again when it
--   is let go again. The time between the two, as measured, is the attempt's `flick`.
--   HOLDS from that moment while the 4-wheel drift turned into the hairpin holds, above
--   the slide speed. A lapse of up to `Grace` (fewer than four wheels, or the drift gone)
--   is forgiven, as the perfect hairpin forgives one.
--   COMPLETES (finish true) when the car passes the hairpin's exit still holding.
--   VOIDS (finish false): "flick too slow" (the window ran out), "flick too late" (the
--   car reached the apex before the right-way drift), "drift broken" (the lapse ran past
--   `Grace`), "fell", "put back" (a jump along the road), "went back" (back out of the
--   zone), "off the road" (out of the road's reach), "too long" (`MaxSeconds`), "road
--   changed". Leaving the tarmac does not void it: only the perfect hairpin asks for a side.
--   The handle is updated each live frame with size 1, from the start to the end.
--
-- WHICH WHEELS SLIDE: `PerfectHairpin.slidingWheels`, each wheel's own slip gate (the one
-- that lays its tyre mark), so "4-wheel" is the drift that marks with all four: past the
-- fronts' `MaxSteerDegrees` (30) plus their floor, on the ground, either way round. So the
-- flick has to swing the slip from past 30 degrees one way to past 30 the other: about 60
-- degrees of swing at the least, inside the window.
--
-- `rig` as `PerfectHairpin`'s: anything with a `spline` field (a Spline or a function).
-- The tuning numbers are the module's own until `Config/ScoreEvents` takes them (T-295).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hairpins = require(ReplicatedStorage.Shared.Road.Hairpins)
local PerfectHairpin = require(script.Parent.PerfectHairpin)

local ScandiFlick = {}
ScandiFlick.__index = ScandiFlick

ScandiFlick.Kind = "scandiFlick"

ScandiFlick.Tuning = {
	MinHold = 0.2, -- s of the wrong-way 4-wheel drift, inside the entry zone, that starts it
	Window = 1.0, -- s from letting the wrong-way drift go to the right-way 4-wheel drift
	Grace = 0.2, -- s a lapse of the right-way 4-wheel drift is forgiven
	JumpStuds = 80, -- studs along the road in one frame that can only be a put-back
	MaxSeconds = 20, -- an attempt still going after this is void
}

local function hairpinInfo(h: Hairpins.Hairpin?): any
	if not h then
		return nil
	end
	return { zone = h.zone, entry = h.entry, apex = h.apex, exit = h.exit, dir = h.dir, radius = h.radius, turn = h.turn, open = h.open }
end

function ScandiFlick.new(sink: any, rig: any)
	return setmetatable({
		sink = sink,
		rig = rig,
		spline = nil :: any,
		s = nil :: number?,
		d = nil :: number?,
		hairpin = nil :: Hairpins.Hairpin?, -- the one around the car (zone to exit), cached
		marking = { false, false, false, false },
		sliding = 0,
		hold = 0, -- s the wrong-way 4-wheel drift has held inside the zone (not live)
		holdEntry = nil :: number?, -- which hairpin `hold` is for
		tried = {} :: { [number]: boolean }, -- hairpins (by entry) already attempted
		-- the live attempt
		handle = nil :: any,
		live = nil :: Hairpins.Hairpin?,
		phase = "idle", -- "idle" | "out" (holding the wrong way) | "switch" | "in"
		since = 0, -- s since the wrong-way drift was let go (phase "switch")
		flick = nil :: number?, -- s the switch took, once made
		flickAt = nil :: number?, -- s along the road where the right-way drift took hold
		bad4 = 0, -- s the right-way 4-wheel drift has been off (phase "in")
		elapsed = 0,
		stats = { started = 0, completed = 0, voided = 0 },
		last = nil :: any,
	}, ScandiFlick)
end

function ScandiFlick._end(self: any, completed: boolean, reason: string)
	local h = self.live
	if self.handle then
		self.handle:finish(completed)
	end
	if completed then
		self.stats.completed += 1
	else
		self.stats.voided += 1
	end
	self.last = {
		result = if completed then "completed" else "void",
		reason = reason,
		entry = h and h.entry,
		phase = self.phase,
		flick = self.flick,
		flickAt = self.flickAt,
		seconds = self.elapsed,
	}
	self.handle = nil
	self.live = nil
	self.phase = "idle"
	self.hold = 0
end

function ScandiFlick.Update(self: any, dt: number, state: any)
	local T = ScandiFlick.Tuning
	local spline = PerfectHairpin.splineOf(self.rig)
	if spline ~= self.spline then
		if self.live then
			self:_end(false, "road changed")
		end
		self.spline = spline
		self.s, self.d, self.hairpin = nil, nil, nil
		self.tried = {}
		self.hold, self.holdEntry = 0, nil
	end
	if not spline then
		return
	end
	local prevS = self.s
	local s, d = Hairpins.locate(spline, state.position, prevS)
	self.s, self.d = s, d
	if not s or not d then
		if self.live then
			self:_end(false, "off the road")
		end
		self.hold = 0
		return
	end
	local jumped = prevS ~= nil and math.abs(s - prevS) > T.JumpStuds

	-- the conditions, every frame (the wheels' gates keep their hysteresis between frames)
	local n = PerfectHairpin.slidingWheels(state, self.marking)
	self.sliding = n
	local h = self.hairpin
	if not h or h.open or s < h.zone or s > h.exit then
		h = Hairpins.around(spline, s)
		self.hairpin = h
	end
	local want = self.live or h
	local dir = if want then want.dir else 0
	local speedOk = PerfectHairpin.speed(state) >= Config.Fx.Gates.MinMarkSpeed
	local four = state.drifting and not state.airborne and speedOk and n == 4 and dir ~= 0
	local wrong4 = four and state.slip * dir > 0 -- turned out of the hairpin
	local right4 = four and state.slip * dir < 0 -- turned into it

	if self.live then
		local live = self.live
		self.elapsed += dt
		if state.fell then
			self:_end(false, "fell")
			return
		elseif jumped then
			self:_end(false, "put back")
			return
		elseif s < live.zone then
			self:_end(false, "went back")
			return
		elseif self.elapsed > T.MaxSeconds then
			self:_end(false, "too long")
			return
		end
		if self.phase ~= "in" then
			if right4 then
				self.phase = "in"
				self.flick = self.since
				self.flickAt = s
				self.bad4 = 0
			elseif wrong4 then
				self.phase = "out"
				self.since = 0
			else
				self.phase = "switch"
				self.since += dt
				if self.since > T.Window then
					self:_end(false, "flick too slow")
					return
				end
			end
			if self.phase ~= "in" and s >= live.apex then
				self:_end(false, "flick too late")
				return
			end
		else
			if right4 then
				self.bad4 = 0
			else
				self.bad4 += dt
				if self.bad4 > T.Grace then
					self:_end(false, "drift broken")
					return
				end
			end
			if s >= live.exit then
				self:_end(true, "through")
				return
			end
		end
		self.handle:update(1, dt)
		return
	end

	-- not live: holding the wrong way inside a hairpin's entry zone?
	local inZone = h ~= nil and not h.open and not jumped and s >= h.zone and s < h.entry and not self.tried[h.entry]
	if not (inZone and wrong4 and not state.fell) then
		self.hold = 0
		return
	end
	local hz = h :: Hairpins.Hairpin
	if self.holdEntry ~= hz.entry then
		self.hold = 0
		self.holdEntry = hz.entry
	end
	self.hold += dt
	if self.hold < T.MinHold - 1e-9 then
		return
	end
	self.tried[hz.entry] = true
	self.live = hz
	self.phase = "out"
	self.since = 0
	self.flick, self.flickAt = nil, nil
	self.bad4 = 0
	self.elapsed = 0
	self.stats.started += 1
	self.handle = self.sink.start(ScandiFlick.Kind, {
		entry = hz.entry,
		exit = hz.exit,
		dir = hz.dir,
		radius = hz.radius,
		at = s,
		angle = math.deg(math.abs(state.slip)),
	})
end

function ScandiFlick.DebugState(self: any): any
	return {
		s = self.s,
		d = self.d,
		hairpin = hairpinInfo(self.hairpin),
		live = self.live ~= nil,
		liveHairpin = hairpinInfo(self.live),
		phase = self.phase,
		sliding = self.sliding,
		hold = self.hold,
		since = self.since,
		flick = self.flick,
		flickAt = self.flickAt,
		bad4 = self.bad4,
		elapsed = self.elapsed,
		stats = table.clone(self.stats),
		last = self.last and table.clone(self.last),
	}
end

return ScandiFlick
