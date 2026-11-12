--!strict
-- HeadlightsController: every car's headlights on this client, on from dusk to dawn
-- (docs/game/features/day-night.md, T-144 step 2).
--
-- WHEN: `SkyController:LightsOn()`, the same moment the sky shows, worked out from the
-- server's clock, so every client switches every car at the same moment and nothing is sent.
--
-- WHAT, per car in `Workspace.Cars`, this player's and everyone else's:
--   * the beams: a SpotLight per lamp, and a SurfaceLight under a long flat strip hung over
--     the road ahead to throw the light past a SpotLight's 60 studs, evenly
--     (`Config.DayNight.Headlights.Beams`), each in an invisible part of this client's own in
--     `Workspace.Headlights`, moved with the car every frame after the cars are drawn. NOTHING GOES INSIDE THE CAR (DECISIONS.md
--     2026-11-03): the car is the server's and holds no Light.
--   * the pop-up pods of a car rig (`PodL`, `PodR`) open through `CarParts.open`, which
--     writes the part's state on this client's copy of the car (CONTRACTS.md "The car rig").
--   * the lenses glow: the headlights' and tail lamps' lens parts are made Neon in their glow
--     colour on this client, and put back exactly as they were when the lights go off.
--
-- IN THE GARAGE ROOM the lights stay off, pods down: the room keeps its own lamps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarParts = require(ReplicatedStorage.Shared.CarParts)
local Config = require(ReplicatedStorage.Shared.Config)

local SkyController = require(script.Parent.SkyController)

local HeadlightsController = {}
HeadlightsController.Priority = 0

local STEP_NAME = "Headlights"
local FOLDER_NAME = "Headlights"

type Lens = { part: BasePart, material: Enum.Material, colour: Color3, glow: Color3 }

type State = {
	car: Model,
	beams: { BasePart },
	spots: { Light },
	level: number, -- 0 out .. 1 full
	on: boolean, -- what this car is switched to
	lenses: { Lens }?, -- while glowing: what each lens was
	dirty: boolean, -- the car's parts changed: find its lenses again
	conn: RBXScriptConnection?,
}

local states: { [Model]: State } = {}
local folder: Folder? = nil
local garageBox: { cf: CFrame, half: Vector3 }? = nil
local garageLooked = false
local stats = { switches = 0, podMoves = 0 }

local function H()
	return Config.DayNight.Headlights
end

local function folderNow(): Folder
	if not folder or folder.Parent ~= workspace then
		local f = workspace:FindFirstChild(FOLDER_NAME)
		if not f or not f:IsA("Folder") then
			f = Instance.new("Folder")
			f.Name = FOLDER_NAME
			f.Parent = workspace
		end
		folder = f :: Folder
	end
	return folder :: Folder
end

local function inGarage(p: Vector3): boolean
	if not garageLooked then
		local room = workspace:FindFirstChild("GarageRoom")
		if room and room:IsA("Model") then
			local cf, size = room:GetBoundingBox()
			garageBox = { cf = cf, half = size * 0.5 }
			garageLooked = true
		end
	end
	local box = garageBox
	if not box then
		return false
	end
	local rel = box.cf:PointToObjectSpace(p)
	return math.abs(rel.X) <= box.half.X and math.abs(rel.Y) <= box.half.Y and math.abs(rel.Z) <= box.half.Z
end

local function body(car: Model): BasePart?
	local b = car:FindFirstChild("Body")
	return if b and b:IsA("BasePart") then b else nil
end

local function makeBeam(car: Model, i: number): (BasePart, Light)
	local h = H()
	local spec = h.Beams[i]
	local part = Instance.new("Part")
	part.Name = `Headlight{i}_{car.Name}`
	part.Size = if spec.Strip then Vector3.new(spec.Strip.X, 0.2, spec.Strip.Y) else Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- no ray, ours or the camera's, may ever hit it
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	local spot: SpotLight | SurfaceLight
	if spec.Strip then
		local surface = Instance.new("SurfaceLight")
		surface.Face = Enum.NormalId.Bottom
		surface.Angle = spec.Angle
		spot = surface
	else
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Angle = spec.Angle
		spot = beam
	end
	spot.Range = spec.Range or h.Range
	spot.Color = h.Colour
	spot.Shadows = h.Shadows
	spot.Brightness = 0
	spot.Enabled = false
	spot.Parent = part
	part.Parent = folderNow()
	return part, spot
end

local function lensesOf(car: Model): { Lens }
	local glow = H().Glow
	local list = {}
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			local colour = glow[d.Name]
			if colour then
				table.insert(list, { part = d, material = d.Material, colour = d.Color, glow = colour })
			end
		end
	end
	return list
end

local function setGlow(state: State, on: boolean)
	if on then
		if state.lenses and not state.dirty then
			return
		end
		if state.lenses then
			for _, l in state.lenses do
				l.part.Material, l.part.Color = l.material, l.colour
			end
		end
		state.dirty = false
		local lenses = lensesOf(state.car)
		for _, l in lenses do
			l.part.Material = Enum.Material.Neon
			l.part.Color = l.glow
		end
		state.lenses = lenses
	elseif state.lenses then
		for _, l in state.lenses do
			if l.part.Parent then
				l.part.Material, l.part.Color = l.material, l.colour
			end
		end
		state.lenses = nil
	end
end

local function setPods(state: State, on: boolean)
	local car = state.car
	if not CarParts.isRig(car) then
		return
	end
	for _, name in H().Pods do
		local amount = CarParts.amount(car, name)
		local want = if on then 1 else 0
		local going = car:GetAttribute(CarParts.ATTR .. name)
		local target = if typeof(going) == "Vector3" then going.Y else amount
		if target ~= want then
			if on then
				CarParts.open(car, name)
			else
				CarParts.close(car, name)
			end
			stats.podMoves += 1
		end
	end
end

local function track(car: Instance)
	if not car:IsA("Model") or states[car] then
		return
	end
	local state: State = {
		car = car,
		beams = {},
		spots = {},
		level = 0,
		on = false,
		lenses = nil,
		dirty = false,
		conn = nil,
	}
	state.conn = car.DescendantAdded:Connect(function()
		state.dirty = true
	end)
	states[car] = state
end

local function untrack(car: Instance)
	local state = states[car :: Model]
	if not state then
		return
	end
	states[car :: Model] = nil
	if state.conn then
		state.conn:Disconnect()
	end
	setGlow(state, false)
	for _, b in state.beams do
		b:Destroy()
	end
end

local movingParts: { BasePart } = {}
local movingFrames: { CFrame } = {}

local function step(dt: number)
	local h = H()
	local night = SkyController:LightsOn()
	local rate = if h.Fade > 0 then dt / h.Fade else 1
	table.clear(movingParts)
	table.clear(movingFrames)
	for car, state in states do
		local b = body(car)
		if not b then
			continue
		end
		local on = night and not inGarage(b.Position)
		if on ~= state.on then
			state.on = on
			stats.switches += 1
			setPods(state, on)
		end
		setGlow(state, on)
		state.level = math.clamp(state.level + (if on then rate else -rate), 0, 1)
		if state.level <= 0 then
			for _, spot in state.spots do
				spot.Enabled = false
			end
			continue
		end
		for i, beam in h.Beams do
			if not state.beams[i] then
				state.beams[i], state.spots[i] = makeBeam(car, i)
			end
			local spot = state.spots[i]
			spot.Enabled = true
			spot.Brightness = beam.Brightness * state.level
			table.insert(movingParts, state.beams[i])
			table.insert(movingFrames, b.CFrame * CFrame.new(beam.At) * CFrame.Angles(-math.rad(beam.Tilt), 0, 0))
		end
	end
	if #movingParts > 0 then
		workspace:BulkMoveTo(movingParts, movingFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function HeadlightsController:Init() end

function HeadlightsController:Start()
	local cars = workspace:WaitForChild("Cars", 30)
	if not cars then
		warn("[HeadlightsController] Workspace.Cars never appeared; no car will have headlights")
		return
	end
	cars.ChildAdded:Connect(track)
	cars.ChildRemoved:Connect(untrack)
	for _, car in cars:GetChildren() do
		track(car)
	end
	-- After the cars are drawn and the camera has followed them, as the underglow is.
	local last = os.clock()
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 2, function()
		local t = os.clock()
		step(t - last)
		last = t
	end)
end

-- Every car's lights: switched on, how bright, pods, lenses glowing, where the beams are
-- against the car's body (studs, body frame).
function HeadlightsController:DebugState(): { [string]: any }
	local cars = {}
	for car, state in states do
		local b = body(car)
		local beams = {}
		for i, beam in state.beams do
			local rel = if b then b.CFrame:PointToObjectSpace(beam.Position) else beam.Position
			local look = if b then b.CFrame:VectorToObjectSpace(beam.CFrame.LookVector) else beam.CFrame.LookVector
			beams[i] = {
				enabled = state.spots[i].Enabled,
				brightness = state.spots[i].Brightness,
				at = { rel.X, rel.Y, rel.Z },
				look = { look.X, look.Y, look.Z },
			}
		end
		local pods = {}
		if CarParts.isRig(car) then
			for _, name in H().Pods do
				pods[name] = CarParts.amount(car, name)
			end
		end
		local glowing = {}
		if state.lenses then
			for _, l in state.lenses do
				table.insert(glowing, `{l.part.Name}:{l.part.Material.Name}`)
			end
		end
		cars[car.Name] = {
			on = state.on,
			level = state.level,
			beams = beams,
			pods = pods,
			glowing = glowing,
			inGarage = if b then inGarage(b.Position) else nil,
		}
	end
	return {
		night = SkyController:LightsOn(),
		cars = cars,
		switches = stats.switches,
		podMoves = stats.podMoves,
		folderParts = if folder then #folder:GetChildren() else 0,
	}
end

return HeadlightsController
