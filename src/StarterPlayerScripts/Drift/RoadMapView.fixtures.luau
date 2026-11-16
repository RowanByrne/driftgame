--!strict
-- SAMPLE DATA, not game state: snapshots for `RoadMapView`, for previewing and measuring the
-- map without driving to the bend (docs/workflow/UI.md "Each screen is a view"). Each road
-- is laid here from a list of (length, radius) pieces, road-up, the car at the origin.

local EVERY = 16
local TIGHT = 220

-- pieces: { length, radius (nil straight, + left, - right) }; `behind` studs come first
local function road(pieces: { { number } }, behind: number, arrowDeg: number, arrowR: number?)
	local r, a, tight = {}, {}, {}
	-- start `behind` studs back down a straight, heading up
	local x, y, yaw = 0, -behind, 0
	local n = 0
	local function point()
		n += 1
		r[n], a[n] = x, y
	end
	point()
	local behindSegs = 0
	local travelled = 0
	local function go(len: number, radius: number?)
		local steps = math.max(1, math.ceil(len / EVERY))
		local ds = len / steps
		for _ = 1, steps do
			local k = if radius then 1 / radius else 0
			-- plan: yaw 0 is up, positive turns left
			yaw += k * ds * 0.5
			x += -math.sin(yaw) * ds
			y += math.cos(yaw) * ds
			yaw += k * ds * 0.5
			tight[n] = math.abs(k) >= 1 / TIGHT
			travelled += ds
			if travelled <= behind then
				behindSegs = n
			end
			point()
		end
	end
	go(behind, nil)
	for _, p in pieces do
		go(p[1], p[2])
	end
	return {
		mode = "map",
		r = r,
		a = a,
		tight = tight,
		behind = behindSegs,
		arrow = { r = arrowR or 0, a = 0, deg = arrowDeg },
	}
end

return {
	-- A long straight: the line runs to the top edge.
	straight = road({ { 800 } }, 100, 0),
	-- A sweeper then a hairpin left, the car mid-drift (nose 35 degrees right).
	hairpin = road({ { 200 }, { 250, -400 }, { 120 }, { 220, 70 }, { 100 } }, 100, 35, 6),
	-- Two hairpins stacked, the mountain's switchback: the tightest the line folds.
	switchback = road({ { 120 }, { 220, 70 }, { 60 }, { 220, -70 }, { 60 }, { 120 } }, 100, -20),
	-- The car on the grass beside the road: the arrow off the line, held at the edge.
	offRoad = road({ { 300 }, { 300, 300 }, { 200 } }, 100, 70, 40),
	hidden = { mode = "hidden" },
}
