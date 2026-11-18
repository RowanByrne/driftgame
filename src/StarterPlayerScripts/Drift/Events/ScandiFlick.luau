--!strict
-- ScandiFlick: the "Scandinavian flick" conditional score event (features/score-events.md
-- "The user's revision", T-300). A detector on the shared interface ("The shared
-- interface"): `new(sink, rig)`, `Update(dt, state)` each simulation step with the drift
-- model's state, `DebugState()`. It only ever calls `sink.start` and the handle it gets back.
--
-- THE RULE (the user's, after driving it): "scandi flick is valid if you drift 4 wheels one
-- way into at least 2 wheels the other way, then complete the hairpin as valid drift with at
-- least 2 wheels and inside the white lines. 4 wheels and lane accuracy are just bonuses."
-- Paired with the lenient perfect hairpin (`Drift/Events/BendDrift`), whose checks it reuses.
--
--   STARTS when, inside a TRUE hairpin's ENTRY ZONE (`Road/Hairpins.around`: bends turning
--   120 degrees within 250 studs; from `zone` up to `entry`), the car has held a drift
--   turned OUT of the hairpin (the slip a bend the other way would want) past `OutDegrees`
--   on 2+ wheels for `MinHold`. Only the time inside the zone counts. One attempt per
--   hairpin; a put-back makes every one a fresh try. The handle opens here, so the feed
--   shows the attempt live.
--   WHY NOT FOUR WHEELS TO START (T-302 send-back, measured): the user's words were "drift 4
--   wheels one way", and that was the start, but nobody could make one register by hand.
--   On the real car at a key's 0.75 of the finger, a wrong-way press under 0.5 s never gets
--   the fronts past their 30-degree gate (0.3 s peaks at 20 degrees, 0.4 s at 26-28), and
--   0.5 s gives 0.10-0.24 s of four wheels, against a 0.2 s hold inside a 60-stud zone
--   (about a second at speed). So four wheels the wrong way is now part of the four-wheel
--   BONUS, and the start asks for the drift a quick feint does make.
--   THE FLICK: once the wrong-way drift is let go (under `OutDegrees`), a drift turned INTO
--   the hairpin on 2+ wheels must follow within `Window` seconds, and before the apex. Going
--   back to the wrong-way drift inside the window is still holding it: the window starts
--   again when it is let go again. The time between, as measured, is the attempt's `flick`.
--   HOLDS from the flick as a valid drift, the perfect hairpin's: the model's drift, on the
--   ground, above the slide speed, on 2+ wheels sliding, either way round; a lapse up to
--   `Grace` forgiven. From the entry on, the tarmac between the white edge lines: more than
--   `MaxWheelsOut` wheels past them at once voids it (one over is forgiven).
--   COMPLETES (finish true) past the hairpin's exit still holding.
--   VOIDS (finish false): "flick too slow" (the window ran out), "flick too late" (the apex
--   before the flick), "drift broken", "past the edge line", "fell", "put back", "went back"
--   (back out of the zone), "off the road" (out of the road's reach), "too long"
--   (`MaxSeconds`), "road changed".
--
-- THE BONUSES, each adding to its points, and naming the line when it completes:
--   four wheels   all four sliding the wrong way at some moment before the flick (in the
--                 zone, or carried into it), AND all four from the flick to the exit: they
--                 must first all slide by the later of the entry and `FourWithin` after the
--                 flick (the fronts need 30 degrees; the flick lands at 5), then a lapse over
--                 `Grace` loses it
--   lane          your own lane from the entry to the exit, as lane drift's: the double
--                 yellow's side the car's centre is on at the entry, out to the white edge
--                 line; more than `MaxWheelsOut` wheels out at once loses it
-- A lost bonus is lost for this attempt. The handle is updated each live step with size
-- `SizeBase`, plus `Bonus4W` while the four-wheel bonus is still in reach and `BonusLane`
-- while the lane one is: the engine's points (`Kinds.scandiFlick`, `SizeFloor` 0) follow
-- the size held, so a bonus kept the whole way is worth its full share. The line's name on
-- completion is `Labels` (whole strings, never glued): plain, four, lane or both.
--
-- ONE FEED LINE: it joins the bend's group (`info.group = "bend:<entry>"`, as `BendDrift`'s
-- events do), worded SCANDINAVIAN FLICK while live (`groupKind`), so the perfect hairpin and
-- lane drift on the same hairpin share its line. On completion the group takes the banked
-- member with the highest `Static`, the flick, with its bonus name.
--
-- WHICH WHEELS SLIDE: `BendDrift.slidingWheels`, each wheel's own slip gate (the one that
-- lays its tyre mark): the rears past half a degree, the fronts past `MaxSteerDegrees` (30).
--
-- `rig` as the other bend detectors': anything with a `spline` field (a Spline or a
-- function, `BendDrift.splineOf`). The numbers: `Config.ScoreEvents.Detectors.ScandiFlick`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hairpins = require(ReplicatedStorage.Shared.Road.Hairpins)
local BendDrift = require(script.Parent.BendDrift)

local ScandiFlick = {}
ScandiFlick.__index = ScandiFlick

ScandiFlick.Kind = "scandiFlick"

ScandiFlick.Tuning = Config.ScoreEvents.Detectors.ScandiFlick

function ScandiFlick.new(sink: any, rig: any)
	return setmetatable({
		sink = sink,
		rig = rig,
		spline = nil :: any,
		s = nil :: number?,
		d = nil :: number?,
		hairpin = nil :: Hairpins.Hairpin?, -- the one around the car (zone to exit), cached
		marking = { false, false, false, false },
		ds = { 0, 0, 0, 0 },
		sliding = 0,
		hold = 0, -- s the wrong-way drift has held inside the zone (not live)
		outFour = false, -- all four slid the wrong way during this hold or attempt
		holdEntry = nil :: number?, -- which hairpin `hold` is for
		tried = {} :: { [number]: boolean }, -- hairpins (by entry) already attempted
		-- the live attempt
		handle = nil :: any,
		info = nil :: any, -- the handle's info: its `label` is set on completion
		live = nil :: Hairpins.Hairpin?,
		phase = "idle", -- "idle" | "out" (holding the wrong way) | "switch" | "in"
		since = 0, -- s since the wrong-way drift was let go (phase "switch")
		flick = nil :: number?, -- s the switch took, once made
		flickAt = nil :: number?, -- s along the road where the right-way drift took hold
		afterFlick = 0, -- s since the flick
		badDrift = 0, -- s the valid drift has been off (phase "in")
		bad4 = 0, -- s fewer than four have slid, once they all have
		fourOn = false, -- all four have slid since the flick
		four = true, -- the four-wheel bonus is still in reach
		lane = true, -- the lane bonus is still in reach
		side = 0, -- the own lane's side of the double yellow, from the entry
		entered = false, -- past the entry during this attempt
		out = 0, -- wheels past the edge lines
		laneOut = 0, -- wheels out of the own lane
		elapsed = 0,
		stats = { started = 0, completed = 0, voided = 0, four = 0, lane = 0 },
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
		if self.four then
			self.stats.four += 1
		end
		if self.lane then
			self.stats.lane += 1
		end
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
		four = self.four,
		outFour = self.outFour,
		lane = self.lane,
		label = self.info and self.info.label,
		seconds = self.elapsed,
	}
	self.handle = nil
	self.info = nil
	self.live = nil
	self.phase = "idle"
	self.hold = 0
end

-- The size this step: the base, plus each bonus still in reach.
function ScandiFlick._size(self: any): number
	local T = ScandiFlick.Tuning
	return T.SizeBase + (if self.four then T.Bonus4W else 0) + (if self.lane then T.BonusLane else 0)
end

-- The line's whole name for the bonuses kept.
function ScandiFlick._label(self: any): string
	local L = ScandiFlick.Tuning.Labels
	if self.four and self.lane then
		return L.both
	elseif self.four then
		return L.four
	elseif self.lane then
		return L.lane
	end
	return L.plain
end

function ScandiFlick.Update(self: any, dt: number, state: any)
	local T = ScandiFlick.Tuning
	local spline = BendDrift.splineOf(self.rig)
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
	if jumped and not self.live then
		self.tried = {} -- put back on the road: every hairpin is a fresh try
	end

	-- the conditions, every step (the wheels' gates keep their hysteresis between steps)
	local n = BendDrift.slidingWheels(state, self.marking)
	self.sliding = n
	local h = self.hairpin
	if not h or h.open or s < h.zone or s > h.exit then
		h = Hairpins.around(spline, s)
		self.hairpin = h
	end
	local want = self.live or h
	local dir = if want then want.dir else 0
	local drifting = state.drifting and not state.airborne and BendDrift.speed(state) >= Config.Fx.Gates.MinMarkSpeed
	-- turned out of the hairpin: past `OutDegrees` on 2+ wheels; and on all four
	local wrong = drifting and n >= 2 and dir ~= 0 and state.slip * dir > math.rad(T.OutDegrees)
	local wrong4 = wrong and n == 4
	local right2 = drifting and n >= 2 and dir ~= 0 and state.slip * dir < 0 -- turned into it

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
		-- the lines, from the entry on
		local ds = BendDrift.wheelsAcross(state, spline, s, d, self.ds)
		if not self.entered and s >= live.entry then
			self.entered = true
			self.side = Hairpins.sideOf(d, Hairpins.lineAt(spline, s) or 0)
			if self.side == 0 then
				self.lane = false -- on the paint at the entry: no lane to keep
			end
		end
		if self.entered then
			self.out = BendDrift.wheelsOut(ds, 0)
			if self.out > T.MaxWheelsOut then
				self:_end(false, "past the edge line")
				return
			end
			if self.lane then
				self.laneOut = BendDrift.wheelsOut(ds, self.side)
				if self.laneOut > T.MaxWheelsOut then
					self.lane = false
				end
			end
		end

		if self.phase ~= "in" then
			if right2 then
				self.phase = "in"
				self.flick = self.since
				self.flickAt = s
				self.afterFlick = 0
				self.badDrift = 0
				self.fourOn, self.bad4 = false, 0
				if not self.outFour then
					self.four = false -- never on four the wrong way: no four-wheel bonus
				end
			elseif wrong then
				self.phase = "out"
				self.since = 0
				if wrong4 then
					self.outFour = true
				end
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
			self.afterFlick += dt
			if drifting and n >= 2 then
				self.badDrift = 0
			else
				self.badDrift += dt
				if self.badDrift > T.Grace then
					self:_end(false, "drift broken")
					return
				end
			end
			-- the four-wheel bonus
			if self.four then
				local all = drifting and n == 4
				if not self.fourOn then
					if all then
						self.fourOn, self.bad4 = true, 0
					elseif self.entered and self.afterFlick > T.FourWithin then
						self.four = false
					end
				elseif all then
					self.bad4 = 0
				else
					self.bad4 += dt
					if self.bad4 > T.Grace then
						self.four = false
					end
				end
			end
			if s >= live.exit then
				-- the line's name for what was kept, then the last step's points, then the finish
				self.info.label = self:_label()
				self.handle:update(self:_size(), dt)
				self:_end(true, "through")
				return
			end
		end
		self.handle:update(self:_size(), dt)
		return
	end

	-- not live: holding the wrong way inside a hairpin's entry zone?
	local inZone = h ~= nil and not h.open and not jumped and s >= h.zone and s < h.entry and not self.tried[h.entry]
	if not (inZone and wrong and not state.fell) then
		self.hold = 0
		self.outFour = false
		return
	end
	local hz = h :: Hairpins.Hairpin
	if self.holdEntry ~= hz.entry then
		self.hold = 0
		self.outFour = false
		self.holdEntry = hz.entry
	end
	self.hold += dt
	if wrong4 then
		self.outFour = true
	end
	if self.hold < T.MinHold - 1e-9 then
		return
	end
	self.tried[hz.entry] = true
	self.live = hz
	self.phase = "out"
	self.since = 0
	self.flick, self.flickAt = nil, nil
	self.badDrift, self.bad4, self.fourOn = 0, 0, false
	self.four, self.lane = true, true
	self.side, self.entered, self.out, self.laneOut = 0, false, 0, 0
	self.elapsed = 0
	self.stats.started += 1
	self.info = {
		entry = hz.entry,
		exit = hz.exit,
		dir = hz.dir,
		radius = hz.radius,
		hairpin = hz.hairpin,
		at = s,
		angle = math.deg(math.abs(state.slip)),
		-- one feed line with the bend's other events, worded as the flick while live
		group = `bend:{hz.entry}`,
		groupKind = ScandiFlick.Kind,
	}
	self.handle = self.sink.start(ScandiFlick.Kind, self.info)
end

-- Studio help for finding one (asked only here, never per step): the next true hairpin
-- ahead within `lookAhead` studs (default 5000) of the car, and how far to its zone.
function ScandiFlick.nextHairpin(self: any, lookAhead: number?): any
	local spline, s = self.spline, self.s
	if not spline or not s then
		return nil
	end
	for _, h in Hairpins.find(spline, s, s + (lookAhead or 5000)) do
		if h.entry > s then
			return { entry = h.entry, zone = h.zone, dir = h.dir, open = h.open, toZone = h.zone - s, turn = h.hairpinTurn }
		end
	end
	return nil
end

function ScandiFlick.DebugState(self: any): any
	return {
		next = self:nextHairpin(),
		s = self.s,
		d = self.d,
		hairpin = BendDrift.info(self.hairpin),
		live = self.live ~= nil,
		liveHairpin = BendDrift.info(self.live),
		phase = self.phase,
		sliding = self.sliding,
		hold = self.hold,
		since = self.since,
		flick = self.flick,
		flickAt = self.flickAt,
		badDrift = self.badDrift,
		four = self.four,
		fourOn = self.fourOn,
		outFour = self.outFour,
		lane = self.lane,
		side = self.side,
		out = self.out,
		laneOut = self.laneOut,
		elapsed = self.elapsed,
		stats = table.clone(self.stats),
		last = self.last and table.clone(self.last),
	}
end

return ScandiFlick
