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
-- A FLIGHT THAT GOES NOWHERE IS NOT A JUMP (T-301): it starts only once the car is also
-- `MinTravel` studs (flat) from where it left the ground, so a car bouncing in place against
-- a rail, or hopping at a crawl, never starts one.
--
-- IT ENDS once the car has been back down `LandSettle` seconds: banked. A hop inside that is
-- the same jump going on, `MaxBounces` times; another banks it, and the new flight must count
-- on its own (and so meets the engine's repeat and same-spot rules). It is LOST on a fall (`state.fell`), the car put back (a new state),
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
		from = nil :: Vector3?, -- where this flight left the ground
		bounces = 0, -- times back up inside `LandSettle`, this jump
		-- What it has seen, for measuring how often jumps happen (`DebugState`)
		stats = {
			flights = 0, -- every time all four left the ground
			hops = 0, -- flights long enough but going nowhere (under `MinTravel`)
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
	self.from = nil
	self.bounces = 0
end

-- How far, flat, the car is from where this flight left the ground.
function Jump._travel(self: any, state: any): number
	local a, b = self.from, state.position
	if not a or typeof(b) ~= "Vector3" then
		return 0
	end
	local dx, dz = b.X - a.X, b.Z - a.Z
	return math.sqrt(dx * dx + dz * dz)
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
		if self.handle and self.down > 0 then
			-- Back up inside `LandSettle`: a bounce on the landing, the same jump going on --
			-- `MaxBounces` times. After that the car is bouncing, not flying (T-301): the jump
			-- banks, and this flight has to count on its own.
			self.bounces += 1
			if self.bounces > D.MaxBounces then
				self:_end(true)
			end
		end
		if self.air == 0 and not self.handle then
			self.stats.flights += 1
			self.from = state.position
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
		elseif self.air >= D.MinAir and not self.spoiled and self:_travel(state) >= D.MinTravel then
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
		if self.air >= D.MinAir then
			self.stats.hops += 1 -- in the air long enough, but it went nowhere
		end
		self.air = 0
		self.spoiled = false
		self.peakHeight = 0
		self.from = nil
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
