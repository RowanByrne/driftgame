--!strict
-- Jump: a score event, sustained -- the flight is the sustain (docs/game/features/score-events.md,
-- "The user's revision", T-295).
--
-- ALL FOUR WHEELS OFF THE GROUND (`state.airborne`: the model's, for the body clear of the
-- ground by more than its margin, so every wheel is up) for `MinAir` seconds starts it, and
-- those seconds count; a bump, or the 1-stud drop off the tarmac's edge, is over before that.
-- Each step in the air after is held, sized by the height over the ground under the car (over
-- nothing, over the ground it took off from), up to `FullHeight` for size 1.
--
-- IT ENDS once the car has been back down `LandSettle` seconds: banked. A hop inside that is
-- the same jump going on. It is LOST on a fall (`state.fell`), the car put back (a new state),
-- landing tilted past `LandTiltDeg` (on its side or its roof), or a wall touched in the air or
-- on the landing (`VoidOnWall`); a wall touched before it started spoils the flight.
--
-- A detector as the shared interface says: `new(sink, rig)`, `Update(dt, state)` once per
-- simulation step, `DebugState()`. It reaches the engine only through `sink`. Numbers:
-- `Config.ScoreEvents.Detectors.Jump`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Jump = {}
Jump.__index = Jump

function Jump.new(sink: any, rig: any?): any
	return setmetatable({
		sink = sink,
		rig = rig,
		handle = nil :: any,
		air = 0, -- seconds of this flight
		down = 0, -- seconds back on the ground since it landed, while a jump is on
		spoiled = false, -- a wall touched in this flight before it counted
		lastState = nil :: any,
		peakHeight = 0,
		-- What it has seen, for measuring how often jumps happen (`DebugState`)
		stats = {
			flights = 0, -- every time all four left the ground
			jumps = 0, -- flights long enough to count
			banked = 0,
			void = 0,
			voidWhy = {} :: { [string]: number },
			airSeconds = 0, -- in counted jumps
			longestAir = 0,
			highest = 0,
		},
	}, Jump)
end

function Jump._end(self: any, completed: boolean, why: string?)
	local h = self.handle
	if h then
		h:finish(completed)
		local st = self.stats
		if completed then
			st.banked += 1
		else
			st.void += 1
			local w = why or "?"
			st.voidWhy[w] = (st.voidWhy[w] or 0) + 1
		end
		st.longestAir = math.max(st.longestAir, self.air)
	end
	self.handle = nil
	self.air = 0
	self.down = 0
	self.peakHeight = 0
end

function Jump._size(self: any, state: any): number
	local D = Config.ScoreEvents.Detectors.Jump
	local ground = state.groundY or state.fallFrom or 0
	local height = state.position.Y - Config.Drift.RideHeight - ground
	if height > self.peakHeight then
		self.peakHeight = height
		self.stats.highest = math.max(self.stats.highest, height)
	end
	return math.clamp(height / D.FullHeight, 0, 1)
end

function Jump.Update(self: any, dt: number, state: any)
	local D = Config.ScoreEvents.Detectors.Jump
	-- the car put back: a new state (a stand-in with no clock is never taken for one)
	local last = self.lastState
	if last and state ~= last and state.time ~= nil and last.time ~= nil then
		self:_end(false, "reset")
		self.spoiled = false
	end
	self.lastState = state
	if state.fell then
		self:_end(false, "fell")
		return
	end

	if state.airborne then
		if self.air == 0 and not self.handle then
			self.stats.flights += 1
		end
		self.air += dt
		self.down = 0
		if D.VoidOnWall and state.wallHit then
			if self.handle then
				self:_end(false, "wall")
			end
			self.spoiled = true
			return
		end
		local size = self:_size(state)
		if self.handle then
			self.handle:update(size, dt)
			self.stats.airSeconds += dt
		elseif self.air >= D.MinAir and not self.spoiled then
			self.handle = self.sink.start("jump", nil)
			self.stats.jumps += 1
			-- the seconds before it counted are part of the flight
			self.handle:update(size, self.air)
			self.stats.airSeconds += self.air
		end
		return
	end

	-- On the ground.
	if not self.handle then
		self.air = 0
		self.spoiled = false
		self.peakHeight = 0
		return
	end
	if self.down == 0 then
		local up = state.up
		if typeof(up) == "Vector3" and up.Y < math.cos(math.rad(D.LandTiltDeg)) then
			self:_end(false, "tilt")
			return
		end
	end
	if D.VoidOnWall and state.wallHit then
		self:_end(false, "wall")
		return
	end
	self.down += dt
	if self.down >= D.LandSettle then
		self:_end(true)
	end
end

function Jump.DebugState(self: any): any
	return {
		live = self.handle ~= nil,
		air = self.air,
		down = self.down,
		peakHeight = self.peakHeight,
		stats = table.clone(self.stats),
	}
end

return Jump
