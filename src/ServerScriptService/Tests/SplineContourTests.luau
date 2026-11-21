--!strict
-- Regression for the third climb that ran through the mountainside, and the
-- alternate seed that used to turn back into its own switchbacks (T-324).
local road = game.ReplicatedStorage.Shared.Road
local Gen = require(road.SplineGen)
local Ground = require(road.Ground)
local Range = require(road.Range)

local Tests = {}

local function columnError(): number
	local field = Ground.field(19, { x = -320, y = 72, z = 147, yaw = 0.9 }, 0.73)
	local r, err = field.range, 0
	for _, v in { -4200, -320, 0, 2280 } do
		local column = Ground.column(field, v)
		for _, k in { -1, 2, 4, 0 } do
			local ridge = Range.ridgeT(r, k, v) - r.shift
			for _, offset in { -2000, -0.001, 0, 0.001, 2800 } do
				local t = ridge + offset
				local x, z = Range.world(r, t, v)
				err = math.max(err, math.abs(column(t) - Ground.h(field, x, z)))
			end
		end
	end
	return err
end

-- Score the bend the driver sees from 400-stud chords, and probe the uncut
-- mountain. Short steering oscillations and a single uphill bank do not count.
local function gorgeApproach(g: Gen.Gen): (number, number, number)
	local sp, f = g.spline, g.ground
	local turns, longest, avoided, lastTurn, run = 0, 0, 0, -math.huge, 0
	local function banks(x: number, z: number, fx: number, fz: number): number
		local h = Ground.h(f, x, z)
		local relief = {}
		for _, d in { 200, 350, 500 } do
			table.insert(relief, math.min(Ground.h(f, x-d*fz, z+d*fx), Ground.h(f, x+d*fz, z-d*fx)) - h)
		end
		table.sort(relief)
		local along = 0.5 * (Ground.h(f, x-350*fx, z-350*fz) + Ground.h(f, x+350*fx, z+350*fz)) - h
		return 0.7 * relief[2] + 0.3 * relief[3] - math.max(0, along)
	end
	for s = 37000, sp.length - 1000, 50 do
		local x, z = sp:planAt(s)
		if Range.ridgeAhead(f.range, x, z) ~= 2 or Range.frame(f.range, x, z) < 25200 then continue end
		local x0, z0 = sp:planAt(s - 400)
		local x1, z1 = sp:planAt(s + 400)
		local dx, dz = x - x0, z - z0
		local angle = math.abs(math.atan2(dx*(z1-z) - dz*(x1-x), dx*(x1-x) + dz*(z1-z)))
		if angle >= math.rad(55) and s - lastTurn >= 650 then turns += 1; lastTurn = s end
		local ax, az = sp:planAt(s - 150)
		local bx, bz = sp:planAt(s + 150)
		local lx, lz = bx-ax, bz-az
		local l = math.sqrt(lx*lx + lz*lz)
		local fx, fz = lx/l, lz/l
		if banks(x, z, fx, fz) >= 35 then run += 50 else run = 0 end
		longest = math.max(longest, run)
		-- Where holding the old heading would enter a walled bed, the route
		-- should sometimes already be turning onto an open hillside.
		for _, ahead in { 800, 1600 } do
			local nx, nz = sp:planAt(s + ahead)
			if math.abs((nx-x)*fz - (nz-z)*fx) < 160 or banks(x+ahead*fx, z+ahead*fz, fx, fz) < 35 then continue end
			local ex, ez = sp:planAt(s + ahead - 150)
			local hx, hz = sp:planAt(s + ahead + 150)
			local n = math.sqrt((hx-ex)^2 + (hz-ez)^2)
			if banks(nx, nz, (hx-ex)/n, (hz-ez)/n) < 20 then avoided += 1; break end
		end
	end
	return turns, longest, avoided
end

function Tests.run()
	local g = Gen.new(7)
	local sp = g.spline
	local first, last = nil, nil
	local cut, fill, walls, pitch = 0, 0, 0, 0
	local reached = 0
	local s = 36575 -- first 25-stud sample after the handoff
	-- (115 000 since T-337: descents traverse the face in more, shorter legs, by design, so the
	-- road is longer to each ridge; this seed's reaches the fourth at about 103 700)
	while reached < 4 and sp.length < 115000 and not g.stats.stalled do
		g:extendTo(sp.length + 1000)
		while s <= sp.length do
			local x, z = sp:planAt(s)
			local t = Range.frame(g.ground.range, x, z)
			reached = Range.ridgeAhead(g.ground.range, x, z)
			local y = sp:heightAt(s)
			local off = Ground.h(g.ground, x, z) - y
			cut, fill = math.max(cut, off), math.max(fill, -off)
			pitch = math.max(pitch, math.deg(math.atan(math.abs(sp:gradeAt(s)))))
			if reached == 2 then
				if t > 25000 and y >= 300 and not first then first = s end
				if first and y >= 900 and not last then last = s end
				local lx, ly, lz = sp:surfaceXYZ(s, -37)
				local rx, ry, rz = sp:surfaceXYZ(s, 37)
				if math.min(Ground.h(g.ground, lx, lz) - ly, Ground.h(g.ground, rx, rz) - ry) > 30 then
					walls += 25
				end
			end
			s += 25
			if reached >= 4 then break end
		end
		task.wait()
	end
	local other = Gen.new(19)
	while other.spline.length < 100000 and not other.stats.stalled do
		other:extendTo(other.spline.length + 1000)
		local x, z = other.spline:tip()
		if Range.ridgeAhead(other.ground.range, x, z) >= 3 then break end
		task.wait()
	end
	local ox, oz = other.spline:tip()
	local climb = if first and last then last - first else 0
	local turns, channelRun, avoided = gorgeApproach(g)
	-- (T-332: the third climb crosses its face in legs, joined by hairpins, where before it bent
	-- about at random: its broad bends are its hairpins now, and are counted as those)
	local hairpins = 0
	for _, tr in g.turns do
		if tr[3] == "turnaround" and tr[1] >= 37000 then
			local x, z = sp:planAt(tr[1])
			if Range.ridgeAhead(g.ground.range, x, z) == 2 and Range.frame(g.ground.range, x, z) >= 25200 then
				hairpins += 1
			end
		end
	end
	local checks = {
		{ name = "The third uphill face crosses in legs, with at least 3 hairpins", ok = hairpins >= 3 },
		{ name = "The route leaves a projected gorge mouth for the hillside", ok = avoided > 0 },
		{ name = "The uphill approach avoids sustained head-on gorge driving", ok = channelRun < 300 },
		{ name = "Survey columns match the world height across rotated ridge boundaries", ok = columnError() < 1e-6 },
		{ name = "The native road crosses two more ridges", ok = reached >= 4 and not g.stats.stalled },
		{ name = "Cuts and fills stay below 60 studs", ok = cut < 60 and fill < 60 },
		{ name = "The third climb runs clear of prolonged walls on both shoulders", ok = walls < 200 },
		{ name = "A 600-stud gain takes longer than the original 4,800 studs", ok = climb > 5000 },
		{ name = "Short pitches use the additional grade", ok = pitch > 8.1 and pitch <= 14.001 },
		{ name = "Seed 19 clears its switchback stack and reaches the third ridge", ok = not other.stats.stalled and Range.ridgeAhead(other.ground.range, ox, oz) >= 3 },
	}
	local passed = 0
	for _, c in checks do if c.ok then passed += 1 end end
	return { passed = passed, total = #checks, checks = checks, climb = climb, peakCut = cut, peakFill = fill, walledStuds = walls,
		maxGrade = pitch, broadBends = turns, hairpins = hairpins, longestChannel = channelRun, avoidedMouthSamples = avoided }
end

return Tests
