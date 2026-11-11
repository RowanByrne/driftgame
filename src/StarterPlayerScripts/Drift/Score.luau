--!strict
-- Score: the endless run's score and its multiplier ladder (docs/game/features/endless-score.md).
--
-- PURE. No instance, no remote, no clock: it is handed a step's length and the car's state
-- and does arithmetic. `ScoreController` owns one and steps it once per simulation step
-- while a run is on, which is also why the score is the same at 30, 60 and 120 FPS -- it
-- sees the same 1/120 s steps the car does. `ScoreTests` runs it on the real model.
--
-- THE MATHS IS THE REFERENCE'S (features/drift-model.md "Score"); the numbers are
-- `Config.Score`. Only while the car is drifting and going the way its nose points:
--
--     base      = |slip| * speed * surfaceScore * ScoreRate * dt
--     score    += base * multiplier
--     progress += clamp(base * ProgressRate - (grounded and MultiplierDecay * rung * dt or 0),
--                       -MaxProgressDown * dt, MaxProgressUp * dt)
--
-- and every step, drifting or not, the bar moves by that clamp with `base = 0` when the car
-- is not scoring. A full bar is the next rung; below `MinProgress` is the one before it.
--
-- BASIC SCORING ONLY (the user, T-119: "don't do the wall hit yet. for now just basic
-- scoring."). A wall or a fall costs nothing of its own, and there is no reverse-drift or
-- air-time bonus. The score already earned is never taken away; only the ladder drains.
--
-- In the air `surfaceScore` is 0 (the model's, `Drift/Model`), so a jump scores nothing,
-- and `grounded` is false, so the ladder does not drain either: it holds until the wheels
-- come back down.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Score = {}
Score.__index = Score

-- What a step reads off the car. `Drift/Model.State` has all of these; a test may hand in
-- a table with just these five.
export type CarState = {
	slip: number, -- radians, signed: nose to velocity
	u: number, -- studs/s along the nose
	v: number, -- studs/s across it
	surfaceScore: number, -- the ground's share, averaged over the four wheels; 0 airborne
	grounded: boolean,
}

export type Reading = {
	score: number, -- the run so far, as a float. Floor it to show it
	multiplier: number, -- the rung, 1 .. MaxMultiplier
	progress: number, -- the bar toward the next rung: MinProgress .. 1. Below 0 is the
	-- grace before a rung is lost; draw it as empty
	best: number, -- the best run this session, this one included
	scoring: boolean, -- whether the last step earned points
	driftSeconds: number, -- this run's time spent scoring
	peakMultiplier: number, -- this run's highest rung
}

export type Score = typeof(setmetatable(
	{} :: {
		score: number,
		multiplier: number,
		progress: number,
		best: number,
		scoring: boolean,
		driftSeconds: number,
		peakMultiplier: number,
	},
	Score
))

function Score.new(): Score
	local self = setmetatable({
		score = 0,
		multiplier = 1,
		progress = 0,
		best = 0, -- the best FINISHED run; `Get` folds the live one in
		scoring = false,
		driftSeconds = 0,
		peakMultiplier = 1,
	}, Score)
	return self
end

-- Points a step of `dt` seconds earns before the multiplier, or 0 when the car is not
-- scoring: under `MinSlipAngleForDrift`, or sliding backwards (past 90 degrees of slip
-- the nose points away from the travel, and `u` goes negative).
function Score.base(dt: number, state: CarState): number
	local slip = math.abs(state.slip)
	if slip < math.rad(Config.Drift.MinSlipAngleForDrift) or state.u <= 0 then
		return 0
	end
	local speed = math.sqrt(state.u * state.u + state.v * state.v)
	return slip * speed * state.surfaceScore * Config.Score.ScoreRate * dt
end

function Score.Step(self: Score, dt: number, state: CarState)
	if dt <= 0 then
		return
	end
	local C = Config.Score
	local base = Score.base(dt, state)
	self.scoring = base > 0
	if self.scoring then
		self.score += base * self.multiplier
		self.driftSeconds += dt
	end

	local decay = if state.grounded then C.MultiplierDecay * self.multiplier * dt else 0
	self.progress += math.clamp(base * C.ProgressRate - decay, -C.MaxProgressDown * dt, C.MaxProgressUp * dt)

	if self.progress > 1 then
		if self.multiplier < C.MaxMultiplier then
			self.multiplier += 1
			self.progress -= 1
			self.peakMultiplier = math.max(self.peakMultiplier, self.multiplier)
		else
			self.progress = 1 -- the top rung: the bar stays full, it has nowhere to go
		end
	elseif self.progress <= C.MinProgress then
		if self.multiplier > 1 then
			self.multiplier -= 1
			self.progress += 1 - C.MinProgress
		end
	end
	-- The bottom rung has no rung below it to lose, so its bar stops at empty rather than
	-- sinking into the grace it can never use.
	if self.multiplier == 1 and self.progress < 0 then
		self.progress = 0
	end
end

-- A new run: the run's numbers back to nothing, and the one just finished counted toward
-- the best first.
function Score.Reset(self: Score)
	self.best = math.max(self.best, self.score)
	self.score = 0
	self.multiplier = 1
	self.progress = 0
	self.scoring = false
	self.driftSeconds = 0
	self.peakMultiplier = 1
end

function Score.Get(self: Score): Reading
	return {
		score = self.score,
		multiplier = self.multiplier,
		progress = self.progress,
		best = math.max(self.best, self.score),
		scoring = self.scoring,
		driftSeconds = self.driftSeconds,
		peakMultiplier = self.peakMultiplier,
	}
end

return Score
