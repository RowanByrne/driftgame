--!nonstrict
-- Ops: what the admin console's server commands share (docs/game/features/admin-console.md).
--
-- Every command reaches the game through the services' own public methods; this only finds
-- them and does the few sums several commands need. Nothing here moves a car except through
-- `CarService:Place`, the one door the server puts a car through on purpose.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local Ops = {}

-- A loaded service by name (the same module the loader required), or nil.
function Ops.service(name: string): any?
	local services = ServerScriptService:FindFirstChild("Services")
	local module = services and services:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, loaded = pcall(require, module)
	return if ok and type(loaded) == "table" then loaded else nil
end

function Ops.need(name: string): any
	local svc = Ops.service(name)
	if not svc then
		error(`{name} isn't loaded in this place`, 0)
	end
	return svc
end

function Ops.v3(v: Vector3?): string
	if typeof(v) ~= "Vector3" then
		return "?"
	end
	return string.format("%.1f, %.1f, %.1f", v.X, v.Y, v.Z)
end

function Ops.headingOf(cf: CFrame): number
	local look = cf.LookVector
	return math.deg(math.atan2(-look.X, -look.Z)) % 360
end

function Ops.isStudio(): boolean
	return RunService:IsStudio()
end

function Ops.inRun(player: Player): boolean
	local road = Ops.service("RoadService")
	return road ~= nil and road:InRun(player) == true
end

-- Tell the player's client where its run stands, exactly as an answer to the start button
-- does: `RoadRun` carries `RoadService:RunState` (CONTRACTS.md). The run button and the score
-- start and stop on this, so a run started or ended here must be told like one.
function Ops.tellRun(player: Player)
	local road = Ops.service("RoadService")
	if road and player.Parent then
		Net.event("RoadRun"):FireClient(player, road:RunState(player))
	end
end

-- `RoadService:StartRun`, then told.
function Ops.startRun(player: Player): CFrame?
	local cf = Ops.need("RoadService"):StartRun(player)
	Ops.tellRun(player)
	return cf
end

-- `RoadService:EndRun`, then told.
function Ops.endRun(player: Player): CFrame?
	local cf = Ops.need("RoadService"):EndRun(player)
	Ops.tellRun(player)
	return cf
end

-- Take a player off the road if they're on it (the car goes back to the world they came
-- from). Returns whether they were.
function Ops.leaveRun(player: Player): boolean
	if not Ops.inRun(player) then
		return false
	end
	Ops.endRun(player)
	return true
end

-- Put the player's car at `cf`, now, through `CarService:Place`. Returns the pose it went to,
-- or nil and why not.
function Ops.place(player: Player, cf: CFrame): (CFrame?, string?)
	local cars = Ops.need("CarService")
	local placed = cars:Place(player, cf)
	if not placed then
		return nil, "the car couldn't be placed (no car yet?)"
	end
	return placed, nil
end

-- "Placed at x, y, z facing h°."
function Ops.placed(cf: CFrame): string
	return `at {Ops.v3(cf.Position)}, facing {math.round(Ops.headingOf(cf))}°`
end

-- The seed of the road that's up, or nil.
function Ops.seed(): number?
	local road = Ops.service("RoadService")
	if not road or not road:HasRoad() then
		return nil
	end
	return road:DebugState().seed
end

-- How far along the spline road a position is, in studs from the road's start, or nil (off
-- the road, the piece road, or not in Studio: it reads the live generator, which only the
-- Studio debug hook hands out).
function Ops.roadDistance(position: Vector3): number?
	local road = Ops.service("RoadService")
	if not RunService:IsStudio() or not road or not road:HasRoad() then
		return nil
	end
	local gen = road:DebugGenerator()
	if not gen or not gen.spline then
		return nil
	end
	local n, t = gen:locate(position)
	local piece = n and gen:piece(n)
	if not piece then
		return nil
	end
	return piece.s0 + t * piece.length
end

-- Where on the spline road `studs` from its start is, as a pose a car can be put down at.
-- Moves the road's window forward to it if it isn't built yet. Studio only: it needs the
-- live generator and `DebugAdvanceTo`, which only exist there. nil and why for a distance
-- the road can't give: behind the closing barrier, or a road that stopped growing.
function Ops.roadPose(studs: number): (CFrame?, string?)
	if not RunService:IsStudio() then
		return nil, "tp road <studs> is Studio only (it needs RoadService's Studio debug hooks)"
	end
	local road = Ops.need("RoadService")
	if not road:HasRoad() then
		return nil, "no road is up"
	end
	local gen = road:DebugGenerator()
	if not gen or not gen.spline then
		return nil, "tp road <studs> needs the spline road (road-mode spline)"
	end
	for _ = 1, 400 do
		local last = gen:piece(gen.last)
		if last and last.s1 >= studs then
			break
		end
		local before = gen.last
		road:DebugAdvanceTo(gen.last)
		if gen.last == before then
			return nil, `the road stopped growing at {math.floor(last and last.s1 or 0)} studs`
		end
	end
	local last = gen:piece(gen.last)
	if not last or last.s1 < studs then
		return nil, `that's further than the road could be laid in one go ({math.floor(last and last.s1 or 0)} studs)`
	end

	-- Not behind the closing barrier: it stands `BarrierBehind` pieces behind the window's
	-- centre, and `SafeStart(nil)` is a pose on that centre piece.
	local centre = road:SafeStart(nil)
	local centreN = centre and gen:locate(centre.Position) or gen.first
	local lowest = gen:piece(math.max(gen.first, (centreN or gen.first) - Config.Road.BarrierBehind + 1))
	if lowest and studs < lowest.s0 then
		return nil, `that stretch is behind the closing barrier: the road you can reach starts at {math.ceil(lowest.s0)} studs`
	end

	local piece = gen:pieceAtS(studs)
	if not piece then
		return nil, "no piece of road there"
	end
	road:DebugAdvanceTo(piece.n)
	return gen:poseOn(piece, studs - piece.s0, Config.Drift.RideHeight), nil
end

return Ops
