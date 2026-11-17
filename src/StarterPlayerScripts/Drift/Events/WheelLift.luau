--!strict
-- WheelLift: a score event, sustained, easy and small (docs/game/features/score-events.md,
-- "The user's revision", T-295).
--
-- ONE OR TWO WHEELS OFF THE GROUND WHILE THE OTHERS DRIVE: the car on the ground
-- (`state.grounded`), not resting on its floor over an edge (`state.hanging` is the hang
-- grind's), with one or two of `state.wheelsDown` false -- not three, which is a car all but
-- in the air. Today's road has no kerbs, so a lift comes from drifting over a crest, a change
-- of bank, or the tarmac's edge.
--
-- It starts once that has held `MinHold` seconds (a one-step flicker never shows), and those
-- seconds count; a gap up to `Grace` does not end it. Sized by which wheels: one wheel up
-- `OneWheelSize`, both on one side `TwoWheelSize` (`TWO WHEELS`), any other two
-- `OtherTwoSize`. It banks when it ends -- after `Grace` down, or the car leaving the ground
-- altogether (a jump takes over) -- and is lost on a fall or the car put back.
--
-- A detector as the shared interface says: `new(sink, rig)`, `Update(dt, state)` once per
-- simulation step, `DebugState()`. Numbers: `Config.ScoreEvents.Detectors.WheelLift`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WheelLift = {}
WheelLift.__index = WheelLift

function WheelLift.new(sink: any, rig: any?): any
	return setmetatable({
		sink = sink,
		rig = rig,
		handle = nil :: any,
		on = 0, -- seconds the lift has held, this spell
		gap = 0, -- seconds without it while a lift is on
		lastState = nil :: any,
		stats = {
			spells = 0, -- every time a wheel came up, however briefly
			lifts = 0, -- spells long enough to count
			banked = 0,
			void = 0,
			seconds = 0, -- held, in counted lifts
			longest = 0,
			twoWheels = 0, -- counted lifts that reached two wheels on one side
		},
		reachedTwo = false,
	}, WheelLift)
end

-- Is the car on a lift now, and its size.
function WheelLift.lift(state: any): (boolean, number)
	local D = Config.ScoreEvents.Detectors.WheelLift
	if not state.grounded or state.hanging then
		return false, 0
	end
	local w = state.wheelsDown
	if not w then
		return false, 0
	end
	local up = 0
	for i = 1, 4 do
		if not w[i] then
			up += 1
		end
	end
	if up == 1 then
		return true, D.OneWheelSize
	elseif up == 2 then
		-- FL FR RL RR: one side is FL+RL or FR+RR
		if (not w[1] and not w[3]) or (not w[2] and not w[4]) then
			return true, D.TwoWheelSize
		end
		return true, D.OtherTwoSize
	end
	return false, 0
end

function WheelLift._end(self: any, completed: boolean)
	local h = self.handle
	if h then
		h:finish(completed)
		local st = self.stats
		if completed then
			st.banked += 1
		else
			st.void += 1
		end
		st.longest = math.max(st.longest, self.on)
		if self.reachedTwo then
			st.twoWheels += 1
		end
	end
	self.handle = nil
	self.on = 0
	self.gap = 0
	self.reachedTwo = false
end

function WheelLift.Update(self: any, dt: number, state: any)
	local D = Config.ScoreEvents.Detectors.WheelLift
	-- the car put back: a new state (a stand-in with no clock is never taken for one)
	local last = self.lastState
	if last and state ~= last and state.time ~= nil and last.time ~= nil then
		self:_end(false)
	end
	self.lastState = state
	if state.fell then
		self:_end(false)
		return
	end

	local lifted, size = WheelLift.lift(state)
	if lifted then
		if self.on == 0 and not self.handle then
			self.stats.spells += 1
		end
		self.on += dt
		self.gap = 0
		if size >= D.TwoWheelSize then
			self.reachedTwo = true
		end
		if self.handle then
			self.handle:update(size, dt)
			self.stats.seconds += dt
		elseif self.on >= D.MinHold then
			self.handle = self.sink.start("wheelLift", nil)
			self.stats.lifts += 1
			self.handle:update(size, self.on)
			self.stats.seconds += self.on
		end
		return
	end

	-- Off the ground altogether: a clean end, the jump's to take over.
	if state.airborne then
		self:_end(true)
		return
	end
	-- A gap up to `Grace` neither ends a lift nor stops one building up to `MinHold`.
	self.gap += dt
	if self.gap > D.Grace then
		if self.handle then
			self:_end(true)
		else
			self.on = 0
			self.gap = 0
			self.reachedTwo = false
		end
	end
end

function WheelLift.DebugState(self: any): any
	return {
		live = self.handle ~= nil,
		on = self.on,
		gap = self.gap,
		stats = table.clone(self.stats),
	}
end

return WheelLift
