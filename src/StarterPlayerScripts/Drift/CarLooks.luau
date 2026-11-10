--!nonstrict
-- CarLooks: draws a fitted build on a car -- paint, finish, wraps, underglow, rims and tyres
-- (docs/game/features/car-customization.md, T-104; CONTRACTS.md "Customization").
--
-- THE CLIENT DRAWS, THE SERVER DECIDES. The server publishes what is fitted as `Fit_*`
-- attributes on the car; `Controllers/CarLooksController` reads them with
-- `Customization.read` and hands the build to `apply` here. Nothing here asks for anything
-- or changes what a car is: every write is a colour, a material or a reflectance on a
-- client's own copy of a part, or an instance that lives OUTSIDE the car.
--
-- STOCK IS THE CAR EXACTLY AS IT IS TODAY. The first time a part is about to be drawn on, its
-- own Color, Material and Reflectance are written down (`originals`), and whatever a build
-- leaves at "stock" is drawn from that record -- so going back to stock is the original
-- numbers, bit for bit, not a guess at them.
--
-- WHICH PARTS: `Config.CarLooks` "roles" -- the part's `Paint` attribute first (the rule for
-- a rigged car), then the body's own list of part names, then the wheel groups' names. A
-- part with no role is never touched: glass, lamps, trim, the interior.
--
-- NOTHING GOES INSIDE THE CAR. The car is the server's and holds no Light, no GUI and nothing
-- welded (DECISIONS.md 2026-11-03; `CarModel.strayOffenders`). Wraps are SurfaceGuis in a
-- folder of the caller's (PlayerGui on a client) adorned to the parts, so they ride with
-- whatever moves the part; the underglow is a part in `Workspace.CarLooks`, moved every
-- frame by `step` to sit under the car's body.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Customization = require(ReplicatedStorage.Shared.Customization)

local CarLooks = {}

CarLooks.ROLES = { "body", "second", "rim", "tyre" }
local IS_ROLE = { body = true, second = true, rim = true, tyre = true }

local SHELL = "Shell"
local BODY_GROUP = "Body"

export type State = {
	car: Model,
	guiParent: Instance?,
	glowParent: Instance?,
	guis: { SurfaceGui },
	glow: BasePart?,
	surface: SurfaceLight?,
	halo: PointLight?,
	glowMode: string,
	glowColour: Color3?,
	build: any,
	roles: { [string]: { BasePart } },
	draws: number,
}

-- part -> { Color, Material, Reflectance }, as the part was before anything here touched
-- it. Weak, so a part that leaves (a re-dress, a car going away) leaves this too.
local originals: { [BasePart]: { Color: Color3, Material: Enum.Material, Reflectance: number } } =
	setmetatable({}, { __mode = "k" }) :: any

local function cfg()
	return Config.CarLooks
end

function CarLooks.original(part: BasePart)
	local o = originals[part]
	if not o then
		o = { Color = part.Color, Material = part.Material, Reflectance = part.Reflectance }
		originals[part] = o
	end
	return o
end

-- ---------------------------------------------------------------------- roles

local nameIndex: { [string]: { [string]: string } } = {}

local function namesFor(list): { [string]: string }
	local out = {}
	for role, names in list or {} do
		for _, name in names do
			out[name] = role
		end
	end
	return out
end

local function bodyNames(body: string?): { [string]: string }
	local key = body or "?"
	local index = nameIndex[key]
	if not index then
		index = namesFor(cfg().Roles[body or ""])
		nameIndex[key] = index
	end
	return index
end

local wheelNames: { [string]: string }? = nil

-- The role a part plays, or nil. Its own `Paint` attribute wins ("none" keeps it out).
function CarLooks.roleOf(part: BasePart, names: { [string]: string }?): string?
	local tagged = part:GetAttribute(cfg().RoleAttribute)
	if type(tagged) == "string" then
		return if IS_ROLE[tagged] then tagged else nil
	end
	return names and names[part.Name] or nil
end

-- Which body a car wears: its `Body` attribute (`CarModel.dress`), or "block" when it has
-- no shell at all.
function CarLooks.bodyName(car: Instance): string?
	local body = car:GetAttribute("Body")
	if type(body) == "string" then
		return body
	end
	return if car:FindFirstChild(SHELL) then nil else "block"
end

-- Every part of the car that has a role, `{ [role] = { BasePart } }`.
function CarLooks.roles(car: Instance): { [string]: { BasePart } }
	local out = { body = {}, second = {}, rim = {}, tyre = {} }
	local function take(part: Instance, names)
		if part:IsA("BasePart") then
			local role = CarLooks.roleOf(part, names)
			if role then
				table.insert(out[role], part)
			end
		end
	end

	local shell = car:FindFirstChild(SHELL)
	if not shell then
		-- the block car: its own five parts are what is drawn
		local names = bodyNames("block")
		for _, part in car:GetChildren() do
			take(part, names)
		end
		return out
	end

	wheelNames = wheelNames or namesFor(cfg().WheelRoles)
	-- A rigged car's body is an imported model whose part names are its own: only its `Paint`
	-- attributes say what is paint. Its wheel groups still answer to `Rim` and `Tire`.
	local names = if shell:GetAttribute("Rig") ~= nil then nil else bodyNames(CarLooks.bodyName(car))
	for _, group in shell:GetChildren() do
		local groupNames = nil
		if group.Name == BODY_GROUP then
			groupNames = names
		elseif string.sub(group.Name, 1, 5) == "Wheel" then
			groupNames = wheelNames
		end
		-- any other group of a rig: only parts tagged with `Paint`
		for _, part in group:GetDescendants() do
			take(part, groupNames)
		end
	end
	return out
end

-- ---------------------------------------------------------------------- paint

local function setLook(part: BasePart, colour: Color3, material: Enum.Material, reflectance: number)
	if part.Color ~= colour then
		part.Color = colour
	end
	if part.Material ~= material then
		part.Material = material
	end
	if part.Reflectance ~= reflectance then
		part.Reflectance = reflectance
	end
end

local function material(name: any): Enum.Material?
	if type(name) ~= "string" then
		return nil
	end
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok then m else nil
end

-- What a build asks of each role: `{ colour?, material?, reflectance? }`, nil fields meaning
-- "the part's own".
function CarLooks.targets(build): { [string]: { colour: Color3?, material: Enum.Material?, reflectance: number? } }
	local paint = build.paint
	local finish = Customization.paintOption("finish", paint.finish) or {}
	local fm, fr = material(finish.material), finish.reflectance
	local looks = Customization.looks(build)
	local wheels = looks.Wheels
	local rim = wheels and cfg().Rims[wheels.rim]
	local tyre = wheels and cfg().Tyres[wheels.tyre]
	return {
		body = { colour = Customization.paintColour(paint.body), material = fm, reflectance = fr },
		second = { colour = Customization.paintColour(paint.second), material = fm, reflectance = fr },
		rim = if rim then { colour = rim.colour, material = material(rim.material), reflectance = rim.reflectance } else {},
		tyre = if tyre
			then { colour = tyre.colour, material = material(tyre.material), reflectance = tyre.reflectance }
			else {},
	}
end

-- ---------------------------------------------------------------------- wraps

local function luma(c: Color3): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

-- The face's extent in studs: `u` along the part's Z, `v` across (Top: X) or down (sides: Y).
local function faceSize(part: BasePart, face: string): (number, number)
	local s = part.Size
	if face == "Top" or face == "Bottom" then
		return s.Z, s.X
	end
	return s.Z, s.Y -- Left, Right
end

local function frame(parent: Instance, colour: Color3, x: number, y: number, w: number, h: number): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = colour
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.Parent = parent
	return f
end

local MAX_SHAPES = 300 -- per face: a guard, not a look

local function drawPattern(gui: SurfaceGui, pattern, colour: Color3, u: number, v: number)
	local n = 0
	for _, band in pattern.bands or {} do
		frame(gui, colour, 0, band[1], 1, band[2] - band[1])
		n += 1
	end
	local cells = pattern.cells
	if cells then
		local size = cells.size
		local cols = math.floor(u / size)
		local top = cells.at * v - cells.rows * size * 0.5
		local left = (u - cols * size) * 0.5
		for r = 0, cells.rows - 1 do
			for c = 0, cols - 1 do
				if (r + c) % 2 == 0 and n < MAX_SHAPES then
					frame(gui, colour, (left + c * size) / u, (top + r * size) / v, size / u, size / v)
					n += 1
				end
			end
		end
	end
	local dots = pattern.dots
	if dots then
		local step = dots.step
		local row = 0
		local y = step * 0.5
		while y < v and n < MAX_SHAPES do
			local x = if row % 2 == 0 then step * 0.5 else step
			while x < u and n < MAX_SHAPES do
				local f = frame(gui, colour, x / u, y / v, dots.size / u, dots.size / v)
				f.AnchorPoint = Vector2.new(0.5, 0.5)
				f.Rotation = dots.rotation or 0
				n += 1
				x += step
			end
			y += step
			row += 1
		end
	end
	return n
end

-- A part a wrap can be drawn on: a plain box. A wedge's slope and a mesh's curves are not
-- the box its faces would be drawn on.
local function wrappable(part: BasePart): boolean
	return part.ClassName == "Part" and (part :: Part).Shape == Enum.PartType.Block
end

local function clearWraps(state: State)
	for _, gui in state.guis do
		gui:Destroy()
	end
	table.clear(state.guis)
end

local function drawWrap(state: State, build, bodyParts: { BasePart })
	clearWraps(state)
	local C = cfg()
	local pattern = C.Wraps[build.paint.wrap]
	if not pattern or not state.guiParent then
		return
	end
	local colour = Customization.paintColour(build.paint.second)
	if not colour then
		local body = Customization.paintColour(build.paint.body)
			or (bodyParts[1] and CarLooks.original(bodyParts[1]).Color)
			or Color3.new(1, 1, 1)
		colour = if luma(body) > C.WrapLightAbove then C.WrapDark else C.WrapLight
	end
	for _, part in bodyParts do
		if wrappable(part) then
			for _, face in pattern.faces do
				local u, v = faceSize(part, face)
				if u >= C.WrapMinFace and v >= C.WrapMinFace then
					local gui = Instance.new("SurfaceGui")
					gui.Name = `Wrap_{state.car.Name}_{part.Name}_{face}`
					gui.Face = (Enum.NormalId :: any)[face]
					gui.Adornee = part
					gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
					gui.PixelsPerStud = C.WrapPixelsPerStud
					gui.LightInfluence = 1
					gui.ResetOnSpawn = false
					gui.ClipsDescendants = true
					drawPattern(gui, pattern, colour, u, v)
					gui.Parent = state.guiParent
					table.insert(state.guis, gui)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------- underglow

local function clearGlow(state: State)
	if state.glow then
		state.glow:Destroy()
	end
	state.glow, state.surface, state.halo = nil, nil, nil
	state.glowMode, state.glowColour = "off", nil
end

local function drawGlow(state: State, look)
	local mode = look and look.mode or "off"
	if mode == "off" or typeof(look.colour) ~= "Color3" or not state.glowParent then
		clearGlow(state)
		return
	end
	local U = cfg().Underglow
	if not state.glow then
		local part = Instance.new("Part")
		part.Name = `Underglow_{state.car.Name}`
		part.Size = U.Size
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false -- no ray, ours or the camera's, may ever hit it
		part.CanTouch = false
		part.CastShadow = false
		part.Locked = true
		local surface = Instance.new("SurfaceLight")
		surface.Face = Enum.NormalId.Bottom
		surface.Range = U.Range
		surface.Angle = U.Angle
		surface.Shadows = false
		surface.Parent = part
		local halo = Instance.new("PointLight")
		halo.Range = U.HaloRange
		halo.Shadows = false
		halo.Parent = part
		state.glow, state.surface, state.halo = part, surface, halo
		CarLooks.place(state)
		part.Parent = state.glowParent
	end
	state.glowMode, state.glowColour = mode, look.colour
	state.surface.Color = look.colour
	state.halo.Color = look.colour
	CarLooks.pulse(state, 0)
end

-- Where the glow goes: under the car's body, `Height` above the road. Nil while the car has
-- no body part.
function CarLooks.glowFrame(car: Instance): CFrame?
	local body = car:FindFirstChild(BODY_GROUP)
	if not body or not body:IsA("BasePart") then
		return nil
	end
	local U = cfg().Underglow
	return body.CFrame * CFrame.new(0, -Config.Drift.RideHeight + U.Height, 0)
end

function CarLooks.place(state: State)
	if state.glow then
		local cf = CarLooks.glowFrame(state.car)
		if cf then
			state.glow.CFrame = cf
		end
	end
end

-- How bright the glow is at `now` (seconds; `GetServerTimeNow` in the game, so every client
-- breathes in step). Steady is always full.
function CarLooks.brightness(mode: string, now: number): number
	local U = cfg().Underglow
	if mode ~= "pulse" then
		return 1
	end
	local wave = 0.5 + 0.5 * math.cos(2 * math.pi * now / U.PulsePeriod)
	return U.PulseLow + (1 - U.PulseLow) * wave
end

function CarLooks.pulse(state: State, now: number)
	if not state.surface then
		return
	end
	local U = cfg().Underglow
	local k = CarLooks.brightness(state.glowMode, now)
	state.surface.Brightness = U.Brightness * k
	state.halo.Brightness = U.HaloBrightness * k
end

-- Every lit car, once a frame, after the cars are drawn: one bulk move for all the glows.
local movingParts, movingFrames = {}, {}
function CarLooks.step(states: { [any]: State }, now: number)
	table.clear(movingParts)
	table.clear(movingFrames)
	for _, state in states do
		if state.glow then
			local cf = CarLooks.glowFrame(state.car)
			if cf then
				table.insert(movingParts, state.glow)
				table.insert(movingFrames, cf)
			end
			if state.glowMode == "pulse" then
				CarLooks.pulse(state, now)
			end
		end
	end
	if #movingParts > 0 then
		workspace:BulkMoveTo(movingParts, movingFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- ---------------------------------------------------------------------- the whole car

function CarLooks.new(car: Model, guiParent: Instance?, glowParent: Instance?): State
	return {
		car = car,
		guiParent = guiParent,
		glowParent = glowParent,
		guis = {},
		glow = nil,
		surface = nil,
		halo = nil,
		glowMode = "off",
		glowColour = nil,
		build = nil,
		roles = {},
		draws = 0,
	}
end

-- Draw `build` on the state's car: every role part from its original and the build, the
-- wrap afresh, the underglow on, off or recoloured. Safe to call as often as the car
-- changes; a stock build leaves every part exactly as it was found.
function CarLooks.apply(state: State, build)
	local roles = CarLooks.roles(state.car)
	local targets = CarLooks.targets(build)
	for role, parts in roles do
		local t = targets[role]
		for _, part in parts do
			local o = CarLooks.original(part)
			setLook(part, t.colour or o.Color, t.material or o.Material, t.reflectance or o.Reflectance)
		end
	end
	drawWrap(state, build, roles.body)
	drawGlow(state, Customization.looks(build).Underglow)
	state.build = build
	state.roles = roles
	state.draws += 1
end

-- Everything this drew taken away again: the parts back to their originals, the wrap and
-- the glow gone. For a car that is leaving, or a test cleaning up.
function CarLooks.clear(state: State)
	for _, parts in CarLooks.roles(state.car) do
		for _, part in parts do
			local o = originals[part]
			if o then
				setLook(part, o.Color, o.Material, o.Reflectance)
			end
		end
	end
	clearWraps(state)
	clearGlow(state)
end

-- What is drawn, for the tests and the debug bridge.
function CarLooks.describe(state: State)
	local roles = {}
	for role, parts in state.roles do
		local list = {}
		for _, part in parts do
			table.insert(list, {
				name = part.Name,
				colour = part.Color:ToHex(),
				material = part.Material.Name,
				reflectance = part.Reflectance,
			})
		end
		roles[role] = list
	end
	local offset = nil
	if state.glow then
		local body = state.car:FindFirstChild(BODY_GROUP)
		if body and body:IsA("BasePart") then
			offset = body.CFrame:PointToObjectSpace(state.glow.Position)
		end
	end
	return {
		body = CarLooks.bodyName(state.car),
		build = state.build,
		roles = roles,
		wraps = #state.guis,
		glow = {
			on = state.glow ~= nil,
			mode = state.glowMode,
			colour = state.glowColour and state.glowColour:ToHex() or nil,
			brightness = state.surface and state.surface.Brightness or 0,
			offset = offset,
		},
		draws = state.draws,
	}
end

return CarLooks
