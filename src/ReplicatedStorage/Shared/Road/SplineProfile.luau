--!strict
-- Pure rock/cliff profiles shared by generation checks and the mesh (T-190).
local Config = require(game.ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)
local SplineProfile = {}
local function wave(s: number, a: number, b: number): number
	-- two slow sines with no common period: 0..1, smooth, the same everywhere
	return 0.5 + 0.3 * math.sin(s / a) + 0.2 * math.sin(s / b + 1.7)
end

-- `cap`, when given, is the tallest the face may stand (T-190, `SplineHill.cap`): a rock body
-- taller than it is drawn scaled down to it, a cliff deeper than it shallower (and reaching
-- less far out). Without it the face is the size the road alone gives it.
function SplineProfile.profile(spline: Spline.Spline, s: number, side: number, kind: number, cap: number?): { Vector3 }
	local T = Config.Spline.Terrain
	local w = Config.Road.Width * 0.5 + spline:runoffAt(s, side)
	local x, z = spline:planAt(s)
	local yaw = spline:yawAt(s)
	local rx, rz = math.cos(yaw), -math.sin(yaw)
	local y0 = spline:terrainY(s, side * w)
	local g = spline:grandAt(s)
	-- ON THE INSIDE OF A TIGHT BEND (T-193) the profiles fan in round the bend's centre, and a
	-- grand body squeezed in there folds over itself. So a rock body there is no grander than
	-- the bend allows: full grandeur at `TightRockRadius` and wider, none at the tightest bend
	-- And not only at `s`: a body just before or after such a bend reaches out across where the
	-- bend's own profiles turn in, so the bends `TightRockLook` either way count too, less the
	-- further off they are. `room` is how far out from the centre line the body may reach.
	local inside = false
	local room = math.huge
	if kind == Spline.ROCK then
		local look = T.TightRockLook
		local tight = T.TightRockRadius
		local rMin = Config.Spline.MinRadius
		local open = 1
		for u = -look, look, look / 6 do
			local at = s + u
			if at >= 0 and at <= spline.length then
				local kk = spline:curvatureAt(at)
				if kk ~= 0 and (kk > 0) == (side < 0) then
					inside = true
					local here = math.clamp((1 / math.abs(kk) - rMin) / (tight - rMin), 0, 1)
					local share = 0.9 - (0.9 - T.TightRockReach) * (1 - here)
					room = math.min(room, share / math.abs(kk) + math.abs(u))
					open = math.min(open, math.max(here, math.abs(u) / look))
				end
			end
		end
		g *= open
	end
	local function grand(near: number, far: number): number
		return near + (far - near) * g
	end
	local pts: { { number } } -- {out, up}
	if kind == Spline.ROCK then
		local hLo, hHi = grand(T.RockHeight[1], T.GrandRockHeight[1]), grand(T.RockHeight[2], T.GrandRockHeight[2])
		local h = hLo + (hHi - hLo) * wave(s + side * 311, 61, 23)
		local lLo, lHi = grand(T.RockSlope[1], T.GrandRockSlope[1]), grand(T.RockSlope[2], T.GrandRockSlope[2])
		local lean = math.rad(lLo + (lHi - lLo) * wave(s - side * 173, 43, 17))
		local run = h / math.tan(lean)
		local jagSize = 2.5 + 7 * g
		local jag = jagSize * (wave(s * 3.1, 7, 3) - 0.5)
		local jag2 = jagSize * (wave(s * 2.3 + 50, 5, 11) - 0.5)
		local top = grand(T.RockTop[1], T.RockTop[2])
		local crest = h + 4 + 6 * g
		-- lower than near a turnaround, under older road above (T-189): toward `LowRockHeight`
		local low = spline:lowAt(s)
		if low > 0 then
			h += (T.LowRockHeight - h) * low
			run = h / math.tan(lean)
			jag *= 1 - low
			jag2 *= 1 - low
			top += (T.LowRockTop - top) * low
			crest = h + 4 * (1 - low) + 0.5 * low
		end
		pts = {
			{ 0, 0 },
			{ run * 0.3 + jag, h * 0.3 },
			{ run * 0.62 + jag2, h * 0.64 },
			{ run, h },
			{ run + top, crest },
			{ run + top + T.RockBack * h, 0 },
		}
		-- the inside of a bend: never past 90% of the way to its centre, and squeezed in, no
		-- taller than `TightRockAspect` times what it reaches out (T-193)
		if inside then
			room -= w
			local reach = pts[#pts][1]
			if room < reach then
				local scale = math.max(room, 0.5) / reach
				local tallest = math.max(room, 0.5) * T.TightRockAspect
				local lower = math.min(1, tallest / math.max(crest, 1e-3))
				for _, p in pts do
					p[1] *= scale
					p[2] *= lower
				end
			end
		end
	else
		-- never deeper than `GrandCliffDrop`: the valley floor is below that
		local drop = grand(T.CliffDrop, T.GrandCliffDrop) * (0.8 + 0.2 * wave(s - side * 97, 53, 19))
		local jagSize = 1.5 + 4 * g
		local reach = 7 + 9 * g
		pts = {
			{ 0, 0 },
			{ 1.5, -drop * 0.06 },
			{ reach * 0.45 + jagSize * (wave(s * 2.7 + 9, 6, 13) - 0.5), -drop * 0.3 },
			{ reach * 0.7 + jagSize * (wave(s * 1.9 + 31, 8, 5) - 0.5), -drop * 0.62 },
			{ reach, -drop },
		}
	end
	-- no taller than its cap: the room there is between this leg and the next (T-190)
	if cap then
		local tall = math.abs(pts[5][2])
		if tall > cap and tall > 1e-6 then
			local f = math.max(cap, 0) / tall
			local across = if kind == Spline.ROCK then f else math.sqrt(f)
			for _, p in pts do
				p[1] *= across
				p[2] *= f
			end
		end
	end
	local out = {}
	for i, p in pts do
		local d = side * (w + p[1])
		out[i] = Vector3.new(x + d * rx, y0 + p[2], z + d * rz)
	end
	return out
end


return SplineProfile
