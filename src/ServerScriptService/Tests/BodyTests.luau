--!nonstrict
-- BodyTests: the car's body riding the ground on its four springs
-- (docs/game/features/car-body-physics.md "Testing", T-196; `Suspension.ride`).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugBodyTests", "run")
--
-- Pure model drives on made-up ground: flat, a ledge, a ramp under one side, a ramp under
-- the rear axle only, and the raised road's bevel. No player, no car and no Workspace.
--
-- `run()` returns `{ passed, checks, log }`: `log` is the body's height, pitch and roll
-- through each shape, for the report and for anybody tuning `Config.Drift.Body`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "BodyTests only runs in Studio")

local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Model = require(DriftFolder.Model)
local Suspension = require(DriftFolder.Suspension)
local World = require(DriftFolder.World)

local BodyTests = {}

local function check(checks, name: string, ok: boolean, detail: string)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
end

-- Ground made of a height function, or nil for nothing at all. `level`: every hit's normal
-- is straight up whatever the heights do -- how the spline road answers over its bevel, and
-- how a real ray answers either side of a kerb. Otherwise a slope is a slope (anything
-- steeper than 45 degrees is a face, and reads as level).
local function ground(height: (number, number) -> number?, level: boolean?): Model.World
	local C = Config.Drift
	return {
		probe = function(pos: Vector3): Model.Hit?
			local y = height(pos.X, pos.Z)
			if not y then
				return nil
			end
			local normal = Vector3.yAxis
			if not level then
				local e = 0.05
				local sx = ((height(pos.X + e, pos.Z) or y) - y) / e
				local sz = ((height(pos.X, pos.Z + e) or y) - y) / e
				if math.abs(sx) > 1 then
					sx = 0
				end
				if math.abs(sz) > 1 then
					sz = 0
				end
				normal = Vector3.new(-sx, 1, -sz).Unit
			end
			return { y = y, normal = normal, grip = C.GripTarmac, score = C.ScoreTarmac }
		end,
	}
end

-- The car with no engine and no grip: it goes exactly where it is pushed.
local COAST = { MaxAcceleration = 0, ConstantFriction = 0, SlipFriction = 0, SlipSqFriction = 0 }

-- The finger of the reference drive (see "flat ground" below).
local function steerAt(t: number): number
	if t < 2 then
		return 0
	elseif t < 5 then
		return 0.5
	elseif t < 6 then
		return -0.8
	elseif t < 9 then
		return 0.15
	elseif t < 12 then
		return -0.3
	elseif t < 14 then
		return 1
	end
	return 0
end

-- WHERE THE MODEL PUT THE CAR BEFORE THE BODY RODE ITS SPRINGS: the reference drive (20 s on
-- a flat plane, the finger above), run on `main` at 031ce57, just before T-196, and written down.
-- Position X, Z, heading, velocity X, Z at the end, and a running sum of all of them and the
-- slip angle over every step.
local REFERENCE = {
	balanced = { -280.33712768554688, 130.57618713378906, 4.4866666666666619, 78.588188171386719, 17.986015319824219, -551573.49400958745 },
	slider = { -185.62672424316406, -33.971309661865234, 5.8326666666666434, 38.573253631591797, -79.788658142089844, -240346.86660218221 },
	bruiser = { -665.410400390625, -126.07042694091797, 2.6919999999999908, -34.107749938964844, 70.33599853515625, -942652.6445603139 },
}

local function pitchRoll(s): (number, number)
	local a, b = Suspension.tiltOf(s.yaw, s.up)
	return math.deg(a), math.deg(b)
end

local function wheelsDown(s): number
	local n = 0
	for i = 1, 4 do
		if s.wheelsDown[i] then
			n += 1
		end
	end
	return n
end

--------------------------------------------------------------------------------

local function runAll()
	local C = Config.Drift
	local P = C.Suspension
	local dt = C.FixedStep
	local ride = C.RideHeight
	local give = P.Travel - P.Rest
	local checks = {}
	local log = {}

	------------------------------------------------------------ at rest
	do
		local s = Model.new(CFrame.new(0, ride, 0))
		local flat = World.flat(0)
		local worst = 0
		local rideY = Vector3.new(0, ride, 0).Y -- as a position holds it: a float
		Cars.withTuning(COAST, function()
			for _ = 1, 600 do
				Model.step(s, { steer = 0 }, dt, flat)
				worst = math.max(worst, math.abs(s.position.Y - rideY), math.abs(s.heave))
				for i = 1, 4 do
					worst = math.max(worst, math.abs(s.travel[i] - P.Rest), math.abs(s.wheelLift[i]))
				end
			end
		end)
		-- and dropped from half a stud up: it lands, and settles where it sat
		local d = Model.new(CFrame.new(0, ride + 0.5, 0))
		local lowest, settled = math.huge, nil
		Cars.withTuning(COAST, function()
			for i = 1, 360 do
				Model.step(d, { steer = 0 }, dt, flat)
				lowest = math.min(lowest, d.position.Y)
				if not settled and math.abs(d.position.Y - ride) < 0.005 and math.abs(d.heave) < 0.05 then
					settled = i * dt
				elseif settled and math.abs(d.position.Y - ride) > 0.005 then
					settled = nil
				end
			end
		end)
		check(
			checks,
			"at rest the car sits at today's ride height, every wheel at Rest, and nothing moves",
			worst == 0 and s.up == Vector3.yAxis and settled ~= nil and settled < 1 and lowest >= ride - give - 1e-4,
			string.format(
				"5 s standing on a flat plane: the height, the vertical speed, every wheel's travel and lift moved %.1e at most (ride height %.2f, Rest %.2f). Dropped from half a stud up: lowest %.3f (the bump stops are at %.3f), back within 0.005 of ride height for good after %.2f s",
				worst,
				ride,
				P.Rest,
				lowest,
				ride - give,
				settled or -1
			)
		)
	end

	------------------------------------------------------------ flat ground: the same drive
	do
		local flat = World.flat(0)
		local worstGap, moved, rows = 0, 0, {}
		local rideY = Vector3.new(0, C.RideHeight, 0).Y
		for _, car in { "balanced", "slider", "bruiser" } do
			Cars.withActive(car, function()
				local s = Model.new(CFrame.new(0, C.RideHeight, 0))
				local sum = 0
				for _ = 1, 2400 do
					Model.step(s, { steer = steerAt(s.time) }, dt, flat)
					sum += s.position.X + s.position.Z * 0.5 + s.yaw * 3 + s.velocity.X * 0.1 + s.velocity.Z * 0.2 + s.slip + s.u * 0.01 + s.v * 0.02
					moved = math.max(moved, math.abs(s.position.Y - rideY), math.abs(s.heave))
					if s.up ~= Vector3.yAxis or s.airborne then
						moved = math.huge
					end
				end
				local ref = REFERENCE[car]
				local got = { s.position.X, s.position.Z, s.yaw, s.velocity.X, s.velocity.Z, sum }
				local gap = 0
				for i = 1, 5 do
					gap = math.max(gap, math.abs(got[i] - ref[i]))
				end
				gap = math.max(gap, math.abs(sum - ref[6]) / math.abs(ref[6]))
				worstGap = math.max(worstGap, gap)
				table.insert(rows, string.format("%s %.1e", car, gap))
			end)
		end
		check(
			checks,
			"on flat ground the car drives and drifts exactly as it did before the body rode its springs",
			worstGap < 1e-6 and moved == 0,
			string.format(
				"20 s of straights, slides and a spin, three cars, against the same drive on the model before T-196: the end position, heading and velocity and the running sum of every step differ by at most %s. The body moved %.1e studs off ride height and never tilted",
				table.concat(rows, ", "),
				moved
			)
		)
	end

	------------------------------------------------------------ a ledge
	-- The ground drops at z = -40. A low one (1 stud) and a real one (3): both drop the car,
	-- as a fall and not as an ease, and it lands on four wheels.
	do
		local function ledge(drop: number, speed: number)
			local world = ground(function(_x, z)
				return if z > -40 then 0 else -drop
			end)
			local s = Model.new(CFrame.new(0, ride, 0))
			s.velocity = Vector3.new(0, 0, -speed)
			local r = { air = 0, fall = 0, nose = 0, lowest = math.huge, hung = 0, fewest = 4, landed = nil, settled = nil, rows = {} }
			local flatS = Model.new(CFrame.new(0, ride, 0))
			flatS.velocity = Vector3.new(0, 0, -speed)
			local flat = World.flat(0)
			r.apart = 0
			Cars.withTuning(COAST, function()
				for i = 1, 360 do
					Model.step(s, { steer = 0 }, dt, world)
					Model.step(flatS, { steer = 0 }, dt, flat)
					r.apart = math.max(r.apart, math.abs(s.position.Z - flatS.position.Z) + math.abs(s.position.X - flatS.position.X))
					local a = pitchRoll(s)
					if s.airborne then
						r.air += 1
					end
					r.fall = math.min(r.fall, s.heave)
					r.nose = math.min(r.nose, a)
					if s.position.Z < -40 - C.BodyLength then
						r.lowest = math.min(r.lowest, s.position.Y + drop)
					end
					r.fewest = math.min(r.fewest, wheelsDown(s))
					if wheelsDown(s) == 0 then
						r.hung += 1
					elseif r.fewest < 4 and not r.landed and wheelsDown(s) == 4 and s.position.Z < -40 - C.Wheelbase then
						r.landed = s.time
					end
					if r.landed and not r.settled and math.abs(s.position.Y + drop - ride) < 0.01 and math.abs(s.heave) < 0.05 and math.abs(a) < 0.1 then
						r.settled = s.time - r.landed
					end
					if i % 6 == 0 and s.position.Z < -30 and #r.rows < 24 then
						table.insert(r.rows, string.format("z %.1f: height %+.2f over the low ground, falling %.1f, pitch %+.1f deg, %d wheels down%s", s.position.Z, s.position.Y + drop - ride, s.heave, a, wheelsDown(s), if s.airborne then ", airborne" else ""))
					end
				end
			end)
			r.state = s
			return r
		end
		local low, high = ledge(1, 60), ledge(3, 60)
		table.insert(log, "LEDGE 3 studs at 60 studs/s:\n  " .. table.concat(high.rows, "\n  "))
		table.insert(log, "LEDGE 1 stud at 60 studs/s:\n  " .. table.concat(low.rows, "\n  "))
		check(
			checks,
			"a ledge drops the car: it falls, lands on four wheels and settles",
			high.air > 0 and high.fall < -10 and high.hung > 0 and high.landed ~= nil and high.settled ~= nil and high.settled < 1
				and high.lowest >= ride - give - 1e-3 and wheelsDown(high.state) == 4
				and low.fall < -3 and low.fewest <= 2 and low.landed ~= nil and low.settled ~= nil and low.air == 0 and low.apart == 0,
			string.format(
				"3-stud ledge at 60 studs/s: all four wheels in the air for %d steps, airborne to the drift model for %d, falling at up to %.1f studs/s, nose down %.1f deg at most; never lower than %.3f over the ground below (bump stops %.3f); settled %.2f s after all four were down. 1-stud ledge: falling at up to %.1f studs/s, down to %d wheels on the ground, nose down %.1f deg, settled %.2f s after all four were down; never airborne to the drift model, and %.1e studs off the same drive on flat ground",
				high.hung,
				high.air,
				-high.fall,
				-high.nose,
				high.lowest,
				ride - give,
				high.settled or -1,
				-low.fall,
				low.fewest,
				-low.nose,
				low.settled or -1,
				low.apart
			)
		)
	end

	------------------------------------------------------------ one side up a ramp
	-- A ramp 0.8 high under the LEFT wheels only (x < 0), 12 degrees, then level: the car
	-- tips toward the right, and each left corner is kicked up as its own wheel climbs.
	do
		local t = math.tan(math.rad(12))
		local world = ground(function(x, z)
			if x >= 0 then
				return 0
			end
			return math.clamp((-z - 40) * t, 0, 0.8)
		end)
		local s = Model.new(CFrame.new(0, ride, 0))
		s.velocity = Vector3.new(0, 0, -40)
		local roll, frontUp, rearUp, air, rows = 0, nil, nil, 0, {}
		local rightTravel = P.Rest
		Cars.withTuning(COAST, function()
			for i = 1, 300 do
				Model.step(s, { steer = 0 }, dt, world)
				local a, b = pitchRoll(s)
				roll = math.min(roll, b)
				if s.airborne then
					air += 1
				end
				-- the front left wheel on the ramp and the rear not yet: nose up, left side up
				local front, rear = -s.position.Z + C.Wheelbase * 0.5, -s.position.Z - C.Wheelbase * 0.5
				if front > 42 and rear < 40 and (not frontUp or a > frontUp.a) then
					frontUp = { a = a, b = b }
				end
				-- settled on the raised side: the lean it rides at
				if rear > 60 and not rearUp then
					rearUp = { a = a, b = b, y = s.position.Y }
				end
				rightTravel = math.max(rightTravel, s.travel[2], s.travel[4])
				if i % 6 == 0 and -s.position.Z > 30 and #rows < 22 then
					table.insert(rows, string.format("z %.1f: height %+.3f, pitch %+.2f deg, roll %+.2f deg, travel %.2f %.2f %.2f %.2f", s.position.Z, s.position.Y - ride, a, b, s.travel[1], s.travel[2], s.travel[3], s.travel[4]))
				end
			end
		end)
		table.insert(log, "RAMP 0.8 high under the left wheels at 40 studs/s (travel FL FR RL RR):\n  " .. table.concat(rows, "\n  "))
		local lean = math.deg(math.atan(0.8 / C.TrackWidth))
		check(
			checks,
			"one side up a ramp tips the car toward the other side",
			frontUp ~= nil and frontUp.a > 0.5 and frontUp.b < -0.5 and rearUp ~= nil and rearUp.b < -lean * 0.6 and roll > -C.Body.MaxRoll - 1e-6 and air == 0,
			string.format(
				"0.8 studs under the left wheels at 40 studs/s: with only the front left on the ramp the nose is up %.1f deg and the left side up %.1f; riding along it the car leans %.1f deg to the right (the ground itself is %.1f) with its middle %.2f higher; most roll %.1f deg (limit %d); the right wheels were pushed up to %.2f of travel; airborne %d steps",
				frontUp and frontUp.a or 0,
				frontUp and -frontUp.b or 0,
				rearUp and -rearUp.b or 0,
				lean,
				rearUp and rearUp.y - ride or 0,
				-roll,
				C.Body.MaxRoll,
				rightTravel,
				air
			)
		)
	end

	------------------------------------------------------------ the rear up a ramp, the front planted
	-- A car sliding sideways, to its own right. Behind its middle (z > 0) the ground is a
	-- ramp up to 1.2 studs; under its front axle the ground stays flat. So the rear wheels
	-- climb -- the right one first, then both -- and the front ones never leave the flat.
	do
		local t = math.tan(math.rad(12))
		local world = ground(function(x, z)
			if z <= 0 then
				return 0
			end
			return math.clamp((x - 20) * t, 0, 1.2)
		end, true)
		local s = Model.new(CFrame.new(0, ride, 0))
		local oneRear, bothRear, frontOff, air, rows = nil, nil, 0, 0, {}
		local flatS = Model.new(CFrame.new(0, ride, 0))
		local flat = World.flat(0)
		local apart = 0
		Cars.withTuning(COAST, function()
			for i = 1, 360 do
				s.velocity = Vector3.new(25, s.velocity.Y, 0)
				flatS.velocity = Vector3.new(25, flatS.velocity.Y, 0)
				Model.step(s, { steer = 0 }, dt, world)
				Model.step(flatS, { steer = 0 }, dt, flat)
				apart = math.max(apart, (Vector3.new(s.position.X, 0, s.position.Z) - Vector3.new(flatS.position.X, 0, flatS.position.Z)).Magnitude)
				local a, b = pitchRoll(s)
				if not (s.wheelsDown[1] and s.wheelsDown[2]) then
					frontOff += 1
				end
				if s.airborne then
					air += 1
				end
				-- the rear RIGHT wheel a third of a stud up its ramp, the rear left still on the flat
				local rr, rl = s.position.X + C.TrackWidth * 0.5, s.position.X - C.TrackWidth * 0.5
				if (rr - 20) * t > 0.3 and rl < 20 and not oneRear then
					oneRear = { a = a, b = b }
				end
				-- both rear wheels on top
				if rl > 20 + 1.2 / t + 6 and not bothRear then
					bothRear = { a = a, b = b, y = s.position.Y }
				end
				if i % 6 == 0 and s.position.X > 14 and #rows < 26 then
					table.insert(rows, string.format("x %.1f: height %+.3f, pitch %+.2f deg, roll %+.2f deg, travel %.2f %.2f %.2f %.2f, down %d", s.position.X, s.position.Y - ride, a, b, s.travel[1], s.travel[2], s.travel[3], s.travel[4], wheelsDown(s)))
				end
			end
		end)
		table.insert(log, "ONE REAR WHEEL FIRST up a 1.2-stud ramp, sliding sideways at 25 studs/s, the front on the flat (travel FL FR RL RR):\n  " .. table.concat(rows, "\n  "))

		-- And both rear wheels together: the car pushed backwards (+Z) at 20 studs/s up a ramp
		-- that only its rear axle reaches. The front axle stays on the flat throughout.
		local straight = ground(function(_x, z)
			return math.clamp((z - 10) * t, 0, 1.2)
		end)
		local b2 = Model.new(CFrame.new(0, ride, 0))
		local planted, noseDown, top, rows2 = 0, 0, nil, {}
		local lowF, highF = P.Rest, P.Rest
		Cars.withTuning(COAST, function()
			for i = 1, 600 do
				-- up the ramp, then held with the rear axle on top and the front still short of it
				local vz = if b2.position.Z < 12.5 then 20 else 0
				b2.velocity = Vector3.new(0, b2.velocity.Y, vz)
				Model.step(b2, { steer = 0 }, dt, straight)
				local a = pitchRoll(b2)
				noseDown = math.min(noseDown, a)
				if not (b2.wheelsDown[1] and b2.wheelsDown[2]) then
					planted += 1
				end
				lowF, highF = math.min(lowF, b2.travel[1], b2.travel[2]), math.max(highF, b2.travel[1], b2.travel[2])
				if i == 600 then
					top = { a = a, y = b2.position.Y }
				end
				if i % 6 == 0 and b2.position.Z > 3 and #rows2 < 22 then
					table.insert(rows2, string.format("z %.1f: height %+.3f, pitch %+.2f deg, travel %.2f %.2f %.2f %.2f, down %d", b2.position.Z, b2.position.Y - ride, a, b2.travel[1], b2.travel[2], b2.travel[3], b2.travel[4], wheelsDown(b2)))
				end
			end
		end)
		table.insert(log, "BOTH REAR WHEELS up a 1.2-stud ramp, backwards at 20 studs/s, the front on the flat (travel FL FR RL RR):\n  " .. table.concat(rows2, "\n  "))

		local nose = math.deg(math.atan(1.2 / C.Wheelbase))
		check(
			checks,
			"both rear wheels up a ramp pitch the car on to its nose while the fronts stay planted; one rear lifts only that corner",
			top ~= nil and top.a < -nose * 0.9 and top.a > -nose * 1.1 and planted == 0
				and bothRear ~= nil and bothRear.a < -nose * 0.7 and math.abs(bothRear.b) < 1
				and oneRear ~= nil and oneRear.a < -0.3 and oneRear.b > 0.3
				and air == 0 and apart < 1e-6,
			string.format(
				"1.2-stud ramp under the rear axle only. Both rear wheels up it together: the nose goes down %.1f deg at most and rests %.1f down (the ground under the wheels is %.1f), the middle %.2f higher; the front wheels were off the ground for %d steps, their travel %.2f to %.2f (Rest %.2f). One rear wheel first, sliding sideways: with only it on the ramp the nose is down %.1f deg and that side up %.1f (the front wheels left the ground for %d steps as the car rocked across its corners); with both on top the nose is down %.1f deg and the roll %.2f; airborne %d steps; %.1e studs off the same slide on flat ground",
				-noseDown,
				top and -top.a or 0,
				nose,
				top and top.y - ride or 0,
				planted,
				lowF,
				highF,
				P.Rest,
				oneRear and -oneRear.a or 0,
				oneRear and oneRear.b or 0,
				frontOff,
				bothRear and -bothRear.a or 0,
				bothRear and bothRear.b or 0,
				air,
				apart
			)
		)
	end

	------------------------------------------------------------ one wheel rejoining at speed
	-- The raised road (features/mountain-road.md): the grass is `lip` below the tarmac, down
	-- a bevel `across` studs wide whose hits all read level, as `Drift/SplineWorld`'s do. A car
	-- at speed with its right wheels down on the grass comes back across the bevel.
	do
		local T = Config.Spline.Terrain
		local lip, across = T.RoadLip, T.RoadLipWidth
		local world = ground(function(x, _z)
			return -lip * math.clamp((x - 10) / across, 0, 1)
		end, true)
		local flat = World.flat(0)
		local worst = { rise = 0, heave = 0, pitch = 0, roll = 0, air = 0, hop = 0, longest = 0, apart = 0 }
		local rows = {}
		for _, speed in { 60, 120, 179 } do
			for _, closing in { 6, 18, 40, 60 } do
				-- right wheels 1.5 studs out past the foot of the bevel, settled there first
				local x0 = 10 + across + 1.5 - C.TrackWidth * 0.5
				local s = Model.new(CFrame.new(x0, ride, 0))
				local flatS = Model.new(CFrame.new(x0, ride, 0))
				local rise, heave, hop, run, longest, air, pitch, roll, apart = 0, 0, 0, 0, 0, 0, 0, 0, 0
				Cars.withTuning(COAST, function()
					for i = 1, 600 do
						local vx = if i > 240 then -closing else 0
						s.velocity = Vector3.new(vx, s.velocity.Y, -speed)
						flatS.velocity = Vector3.new(vx, flatS.velocity.Y, -speed)
						Model.step(s, { steer = 0 }, dt, world)
						Model.step(flatS, { steer = 0 }, dt, flat)
						if i > 240 then
							local a, b = pitchRoll(s)
							apart = math.max(apart, (Vector3.new(s.position.X, 0, s.position.Z) - Vector3.new(flatS.position.X, 0, flatS.position.Z)).Magnitude)
							rise = math.max(rise, s.position.Y - ride)
							heave = math.max(heave, s.heave)
							pitch, roll = math.max(pitch, math.abs(a)), math.max(roll, math.abs(b))
							if s.airborne then
								air += 1
							end
							if wheelsDown(s) < 3 then
								hop += 1
								run += 1
								longest = math.max(longest, run)
							else
								run = 0
							end
						end
					end
				end)
				table.insert(rows, string.format("%d studs/s, closing at %d: middle up to %+.3f over ride height, rising at up to %.1f, pitch %.1f deg, roll %.1f deg, fewer than three wheels down for %d steps (%d in a row)", speed, closing, rise, heave, pitch, roll, hop, longest))
				worst.rise = math.max(worst.rise, rise)
				worst.heave = math.max(worst.heave, heave)
				worst.pitch, worst.roll = math.max(worst.pitch, pitch), math.max(worst.roll, roll)
				worst.air += air
				worst.hop = math.max(worst.hop, hop)
				worst.longest = math.max(worst.longest, longest)
				worst.apart = math.max(worst.apart, apart)
			end
		end
		table.insert(log, string.format("REJOINING over the road's bevel (%.1f up, %.1f across), right wheels first:\n  ", lip, across) .. table.concat(rows, "\n  "))
		check(
			checks,
			"one side rejoining the road at speed never launches the car",
			worst.air == 0 and worst.rise < lip * 0.75 and worst.longest < 0.5 / dt and worst.apart < 1e-6,
			string.format(
				"60, 120 and 179 studs/s, closing on the bevel at 6, 18, 40 and 60: the car's middle never rose more than %.3f studs over ride height (the lip is %.1f), rising at up to %.1f studs/s; most pitch %.1f deg, most roll %.1f (it starts at 10.3, astride the bevel); never airborne to the drift model; fewer than three wheels down for at most %d steps in a row; %.1e studs off the same line on flat ground",
				worst.rise,
				lip,
				worst.heave,
				worst.pitch,
				worst.roll,
				worst.longest,
				worst.apart
			)
		)
	end

	------------------------------------------------------------ the limits
	-- Thrown off a ramp with one side: whatever the springs do, the body never tips past its
	-- limits off the ground's own frame, and it comes down on its wheels.
	do
		local t = math.tan(math.rad(25))
		local world = ground(function(x, z)
			local d = -z - 30
			if x < 0 and d > 0 and d < 5 / t then
				return d * t
			end
			return 0
		end)
		local s = Model.new(CFrame.new(0, ride, 0))
		s.velocity = Vector3.new(0, 0, -120)
		local pitch, roll, air, low = 0, 0, 0, math.huge
		Cars.withTuning(COAST, function()
			for _ = 1, 600 do
				Model.step(s, { steer = 0 }, dt, world)
				local a, b = Suspension.tiltOf(s.yaw, s.up)
				local ag, bg = Suspension.tiltOf(s.yaw, s.groundUp)
				pitch, roll = math.max(pitch, math.abs(math.deg(a - ag))), math.max(roll, math.abs(math.deg(b - bg)))
				if s.airborne then
					air += 1
				end
				if -s.position.Z > 60 then
					low = math.min(low, s.position.Y)
				end
			end
		end)
		local a, b = pitchRoll(s)
		check(
			checks,
			"thrown by a ramp under one side, the car never tips past its limits and lands on its wheels",
			pitch <= C.Body.MaxPitch + 1e-3 and roll <= C.Body.MaxRoll + 1e-3 and air > 0 and wheelsDown(s) == 4
				and math.abs(s.position.Y - ride) < 0.01 and math.abs(a) < 0.1 and math.abs(b) < 0.1 and low >= ride - give - 1e-3,
			string.format(
				"a 25-degree ramp 5 high under the left wheels at 120 studs/s: airborne %d steps; most pitch %.1f deg (limit %d), most roll %.1f (limit %d) off the ground's frame; lowest %.3f after it (bump stops %.3f); 5 s on it stands level at ride height, %d wheels down",
				air,
				pitch,
				C.Body.MaxPitch,
				roll,
				C.Body.MaxRoll,
				low,
				ride - give,
				wheelsDown(s)
			)
		)
	end

	------------------------------------------------------------ the same drive twice, and its cost
	do
		local t = math.tan(math.rad(15))
		local world = ground(function(x, z)
			local d = -z - 20
			if d > 0 and d < 5 / t then
				return d * t + (if x < 0 then 0.3 else 0)
			end
			return 0
		end)
		local function once(): Vector3
			local s = Model.new(CFrame.new(0, ride, 0))
			s.velocity = Vector3.new(0, 0, -70)
			for _ = 1, 480 do
				Model.step(s, { steer = 0.2 }, dt, world)
			end
			return s.position
		end
		local a, b = once(), once()
		local s = Model.new(CFrame.new(0, ride, 0))
		local flat = World.flat(0)
		local t0 = os.clock()
		for _ = 1, 6000 do
			Model.step(s, { steer = 0.3 }, dt, flat)
		end
		local plain = (os.clock() - t0) / 6000 * 1e6
		local bumpy = ground(function(x, z)
			return 0.3 * math.sin(x * 0.7) * math.sin(z * 0.9)
		end, true)
		local r = Model.new(CFrame.new(0, ride, 0))
		t0 = os.clock()
		for _ = 1, 6000 do
			Model.step(r, { steer = 0.3 }, dt, bumpy)
		end
		local rough = (os.clock() - t0) / 6000 * 1e6
		check(
			checks,
			"the same drive twice is the same line, and a step is cheap",
			(a - b).Magnitude == 0 and plain < 100 and rough < 150,
			string.format("a jump with a finger held, twice: %.1e studs apart. A step costs %.1f us on flat ground and %.1f us on ground that works all four springs every step (a step is 8333 us)", (a - b).Magnitude, plain, rough)
		)
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks, log = table.concat(log, "\n") }
end

-- On the default car, whichever one a player happens to be in.
function BodyTests.run()
	return Cars.withActive("balanced", runAll)
end

return BodyTests
