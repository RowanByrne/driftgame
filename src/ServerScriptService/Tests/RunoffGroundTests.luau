--!nonstrict
-- RunoffGroundTests: the ground under the road when the ground mesh draws the runoff
-- (T-251, `Config.Spline.Ground.RunoffBy = "ground"`, `Spline:underY`). Pure maths:
--   game.ServerStorage.DebugBridge:Invoke("DebugRunoffGroundTests", "run")
-- What the drawn ground is held to is what the car stands on (`Spline:terrainY`): this
-- checks the surface it is drawn from. The drawn tiles themselves are measured live
-- (`GroundMeshView.DebugRunoffGap`, `DebugDriveGap`).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "RunoffGroundTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)

local Tests = {}

local SEEDS = { 31337, 101, 2024 }
local LENGTH = 3000 -- studs

local function run(check)
	local half = Config.Road.Width * 0.5
	local lip = Config.Spline.Terrain.RoadLip
	local n, offRunoff, offRoad, crease, notLevel = 0, 0, 0, 0, 0
	for _, seed in SEEDS do
		local gen = SplineGen.new(seed)
		gen:extendTo(LENGTH)
		local sp = gen.spline
		local first = sp.firstSample * sp.step
		for s = first + 1, sp.length - 1, 7 do
			for _, side in { -1, 1 } do
				local w = sp:runoffAt(s, side)
				local lw = sp:lipWidthAt(s, side)
				n += 1
				-- past the bevel's foot it is exactly what the car stands on
				for k = 0, 4 do
					local d = side * (half + lw + (w - lw) * k / 4)
					offRunoff = math.max(offRunoff, math.abs(sp:underY(s, d) - sp:terrainY(s, d)))
				end
				-- under the tarmac, `RoadLip` below it
				for k = 0, 4 do
					local d = side * half * k / 4
					offRoad = math.max(offRoad, math.abs(sp:terrainY(s, d) - lip - sp:underY(s, d)))
				end
				-- no crease at the tarmac's edge: the slope across the same either side
				local e = 0.01
				local a = (sp:underY(s, side * half) - sp:underY(s, side * (half - e))) / e
				local b = (sp:underY(s, side * (half + e)) - sp:underY(s, side * half)) / e
				if w > 1 then
					crease = math.max(crease, math.abs(a - b))
				end
				-- level past the runoff's edge
				notLevel = math.max(notLevel, math.abs(sp:underY(s, side * (half + w + 6)) - sp:underY(s, side * (half + w))))
			end
		end
	end
	check("past the bevel, the drawn runoff's surface is what the car stands on", offRunoff < 1e-6, `worst {offRunoff} studs over {n} cross-sections`)
	check("under the tarmac it is RoadLip below the road", offRoad < 1e-6, `worst {offRoad} studs`)
	check("no crease at the tarmac's edge", crease < 0.01, `worst slope change {crease}`)
	check("level past the runoff's edge", notLevel < 1e-6, `worst {notLevel} studs`)
	check("the switch is a known value", Config.Spline.Ground.RunoffBy == "road" or Config.Spline.Ground.RunoffBy == "ground", tostring(Config.Spline.Ground.RunoffBy))
end

function Tests.run(_)
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local ok, err = pcall(run, check)
	if not ok then
		check("the runoff ground tests ran", false, tostring(err))
	end
	local passed = true
	for _, c in checks do
		if not c.ok then
			passed = false
		end
	end
	return { passed = passed, checks = checks }
end

return Tests
