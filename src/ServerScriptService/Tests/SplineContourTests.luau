--!strict
-- Regression for the third climb that ran through the mountainside, and the
-- alternate seed that used to turn back into its own switchbacks (T-324).
local road = game.ReplicatedStorage.Shared.Road
local Gen = require(road.SplineGen)
local Ground = require(road.Ground)
local Range = require(road.Range)

local Tests = {}

function Tests.run()
	local g = Gen.new(7)
	local sp = g.spline
	local first, last = nil, nil
	local cut, fill, walls, pitch = 0, 0, 0, 0
	local reached = 0
	local s = 36575 -- first 25-stud sample after the handoff
	while reached < 4 and sp.length < 100000 and not g.stats.stalled do
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
	local checks = {
		{ name = "The native road crosses two more ridges", ok = reached >= 4 and not g.stats.stalled },
		{ name = "Cuts and fills stay below 60 studs", ok = cut < 60 and fill < 60 },
		{ name = "The third climb runs clear of prolonged walls on both shoulders", ok = walls < 200 },
		{ name = "A 600-stud gain takes longer than the original 4,800 studs", ok = climb > 5000 },
		{ name = "Short pitches use the additional grade", ok = pitch > 8.1 and pitch <= 14.001 },
		{ name = "Seed 19 clears its switchback stack and reaches the third ridge", ok = not other.stats.stalled and Range.ridgeAhead(other.ground.range, ox, oz) >= 3 },
	}
	local passed = 0
	for _, c in checks do if c.ok then passed += 1 end end
	return { passed = passed, total = #checks, checks = checks, climb = climb, peakCut = cut, peakFill = fill, walledStuds = walls, maxGrade = pitch }
end

return Tests
