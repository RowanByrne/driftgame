--!strict
-- StandIn: the car v2 stand-in, programmer art built by code on the gray model's rig
-- (docs/game/features/car-v2.md "Left out": "this builds and tests on a stand-in").
--
-- Boxes, wedges and cylinders at the gray model's parts' sizes, each in the group the rig
-- names (`Cars/Rig`) and pivoted on that part's real hinge, so everything in v2 -- the
-- suspension, the doors, getting in and out -- can be built and measured before the real
-- meshes pass their gate. When they do, they go into the SAME groups at the SAME pivots and
-- nothing that moves or draws the car changes.
--
-- Selected like any other body: `Config.Drift.CarBody = "standin"`, or
-- `CarModel.setBody("standin")`. Its wheels are the gray model's, 2.6 across rather than
-- the config's 2.3 (the spec's open question), so they touch the road at the gray model's
-- own hub height, not at `wheelOffsets()`.
--
-- Every piece is written in the PIVOT LIST'S AXES (X = the car's left, -Y = forward,
-- Z = up, ground at 0), the axes the gray model was built in, so a number here can be
-- checked against the .blend directly. `Rig.toCar` turns them into the car's frame.
--
-- Nothing here moves itself: every part is anchored, and nothing that is physics, a
-- script, a light, a sound or an attachment is made (DECISIONS.md, 2026-11-03).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rig = require(script.Parent.Rig)

local StandIn = {}

StandIn.NAME = "standin"

-- ------------------------------------------------------------------ the palette

local COLOURS = {
	paint = Color3.fromRGB(236, 236, 230), -- the panda's white
	black = Color3.fromRGB(32, 32, 36), -- and its black lower half
	trim = Color3.fromRGB(24, 24, 28),
	glass = Color3.fromRGB(44, 58, 72),
	inner = Color3.fromRGB(58, 58, 64),
	metal = Color3.fromRGB(150, 152, 158),
	tyre = Color3.fromRGB(26, 26, 30),
	rim = Color3.fromRGB(196, 198, 204),
	caliper = Color3.fromRGB(176, 40, 36),
	needle = Color3.fromRGB(255, 120, 40),
	headlight = Color3.fromRGB(255, 246, 214),
	clear = Color3.fromRGB(236, 240, 244),
	orange = Color3.fromRGB(255, 150, 30),
	red = Color3.fromRGB(220, 30, 30),
	white = Color3.fromRGB(250, 250, 250),
	yellow = Color3.fromRGB(255, 220, 60),
}

-- A lamp's colour, from what the pivot list says it is.
local function lampColour(what: string): Color3
	if string.find(what, "headlight") then
		return COLOURS.headlight
	elseif string.find(what, "orange") then
		return COLOURS.orange
	elseif string.find(what, "red") then
		return COLOURS.red
	elseif string.find(what, "yellow") then
		return COLOURS.yellow
	elseif string.find(what, "white") then
		return COLOURS.white
	end
	return COLOURS.clear
end

-- ------------------------------------------------------------------ the pieces

-- One piece, in the pivot list's axes:
--   box    `lo` and `hi`, two opposite corners
--   boxc   centre `c` and size `s`, turned `rx` degrees about the list's X through `c`
--   beam   from `a` to `b`, `w` wide along the list's `across` axis ("x" default) and `t`
--          thick: a panel or a rod that is not square to the car
--   cyl    a cylinder from `a` to `b`, `d` across
--   wedge  `lo` and `hi`, its slope falling toward the nose
type Piece = {
	k: string,
	n: string,
	col: string,
	lo: { number }?,
	hi: { number }?,
	c: { number }?,
	s: { number }?,
	rx: number?,
	a: { number }?,
	b: { number }?,
	w: number?,
	t: number?,
	d: number?,
	across: string?,
	tr: number?,
}

local function box(n: string, col: string, lo: { number }, hi: { number }): Piece
	return { k = "box", n = n, col = col, lo = lo, hi = hi }
end

local function boxc(n: string, col: string, c: { number }, s: { number }, rx: number?): Piece
	return { k = "boxc", n = n, col = col, c = c, s = s, rx = rx }
end

local function beam(n: string, col: string, a: { number }, b: { number }, w: number, t: number, across: string?): Piece
	return { k = "beam", n = n, col = col, a = a, b = b, w = w, t = t, across = across }
end

local function cyl(n: string, col: string, a: { number }, b: { number }, d: number): Piece
	return { k = "cyl", n = n, col = col, a = a, b = b, d = d }
end

local function wedge(n: string, col: string, lo: { number }, hi: { number }): Piece
	return { k = "wedge", n = n, col = col, lo = lo, hi = hi }
end

local function glass(p: Piece): Piece
	p.tr = 0.35
	return p
end

local function flipX(v: { number }?): { number }?
	return if v then { -v[1], v[2], v[3] } else nil
end

-- The same pieces on the other side of the car.
local function mirror(pieces: { Piece }): { Piece }
	local out = {}
	for _, p in pieces do
		local q = table.clone(p)
		if p.lo and p.hi then
			-- a box's two corners swap in x when it is reflected
			q.lo = { -p.hi[1], p.lo[2], p.lo[3] }
			q.hi = { -p.lo[1], p.hi[2], p.hi[3] }
		end
		q.c, q.a, q.b = flipX(p.c), flipX(p.a), flipX(p.b)
		table.insert(out, q)
	end
	return out
end

-- Both sides at once, for the body's own pieces: `<n>L` at +x, `<n>R` at -x.
local function pair(pieces: { Piece }): { Piece }
	local out = {}
	for _, p in pieces do
		local l = table.clone(p)
		l.n = p.n .. "L"
		table.insert(out, l)
	end
	for _, p in mirror(pieces) do
		p.n = p.n .. "R"
		table.insert(out, p)
	end
	return out
end

local function concat(...: { Piece }): { Piece }
	local out = {}
	for _, list in { ... } do
		for _, p in list do
			table.insert(out, p)
		end
	end
	return out
end

-- The static shell. Hollow where it opens: the engine bay under the hood, the cabin behind
-- the doors, and the boot under the hatch, so an opened part shows something behind it.
local BODY: { Piece } = concat({
	-- the nose and the engine bay
	box("NoseLower", "black", { -3.35, -8.35, 0.68 }, { 3.35, -2.9, 2.0 }),
	box("NoseFront", "black", { -2.6, -8.35, 2.0 }, { 2.6, -8.0, 2.35 }),
	box("NosePanel", "paint", { -1.39, -8.35, 2.35 }, { 1.39, -8.0, 3.2 }),
	box("Engine", "metal", { -1.3, -6.3, 1.4 }, { 1.3, -3.6, 3.0 }),
	box("Firewall", "trim", { -2.6, -3.3, 2.0 }, { 2.6, -2.9, 3.95 }),
	box("BumperF", "black", { -3.53, -8.5, 0.68 }, { 3.53, -8.3, 1.05 }),
	-- the cabin: a floor, the sills, the dash, two seats and a console
	box("Floor", "inner", { -2.9, -2.9, 0.6 }, { 2.9, 2.6, 1.0 }),
	box("Dash", "inner", { -2.9, -2.9, 2.6 }, { 2.9, -1.9, 3.75 }),
	box("Console", "inner", { -0.35, -1.9, 1.0 }, { 0.35, 0.6, 2.0 }),
	box("Roof", "paint", { -2.9, -0.05, 5.5 }, { 2.9, 4.4, 5.72 }),
	glass(beam("Windscreen", "glass", { 0, -3.0, 3.92 }, { 0, 0.0, 5.6 }, 5.9, 0.06)),
	-- the back: the boot under the hatch, the tail and the bumper
	box("RearLower", "paint", { -3.35, 2.6, 0.7 }, { 3.35, 9.0, 2.6 }),
	box("TailPanel", "black", { -3.35, 8.6, 2.6 }, { 3.35, 9.0, 3.3 }),
	box("BumperR", "black", { -3.52, 9.0, 0.92 }, { 3.52, 9.21, 2.3 }),
}, pair({
	wedge("Fender", "paint", { 2.6, -8.35, 2.0 }, { 3.25, -2.9, 3.85 }),
	box("Sill", "black", { 2.9, -2.9, 0.6 }, { 3.4, 2.6, 1.05 }),
	box("Cushion", "inner", { 0.5, -0.6, 1.0 }, { 2.4, 1.25, 1.95 }),
	beam("Backrest", "inner", { 1.45, 1.05, 1.95 }, { 1.45, 1.75, 3.9 }, 1.8, 0.35),
	beam("APillar", "trim", { 2.95, -3.0, 3.92 }, { 2.85, 0.0, 5.6 }, 0.18, 0.18),
	box("BPillar", "trim", { 2.75, 2.6, 3.9 }, { 3.05, 2.8, 5.55 }),
	glass(box("Quarter", "glass", { 2.85, 2.8, 3.9 }, { 2.95, 4.4, 5.5 })),
	box("QuarterPanel", "paint", { 2.95, 2.6, 2.6 }, { 3.35, 7.6, 3.85 }),
}))

-- The left-hand parts; the right-hand ones are their mirror images.
local DOOR: { Piece } = {
	box("Panel", "paint", { 3.2, -2.7, 1.05 }, { 3.5, 2.6, 3.9 }),
	beam("Frame", "trim", { 3.0, -2.6, 3.9 }, { 2.88, -0.05, 5.5 }, 0.12, 0.12),
	box("Rail", "trim", { 2.8, -0.05, 5.4 }, { 2.95, 2.6, 5.55 }),
}
local DOOR_GLASS: { Piece } = {
	glass(beam("Glass", "glass", { 2.97, 0.445, 3.88 }, { 2.3, 0.445, 5.45 }, 3.81, 0.05, "y")),
}
local POD: { Piece } = {
	box("Cover", "paint", { 1.395, -8.0, 3.25 }, { 2.57, -6.8, 3.4 }),
	box("Housing", "black", { 1.45, -7.9, 2.75 }, { 2.52, -6.85, 3.25 }),
}
local HUB_WHEEL = function(x: number, y: number): { Piece }
	-- x is the hub's own; outward is +x on the left
	return {
		cyl("Tire", "tyre", { x - 0.57, y, 1.29 }, { x + 0.58, y, 1.29 }, 2.574),
		cyl("Rim", "rim", { x + 0.5, y, 1.29 }, { x + 0.6, y, 1.29 }, 1.6),
		boxc("Spoke", "trim", { x + 0.62, y, 1.29 }, { 0.04, 1.5, 0.22 }),
	}
end

local PARTS: { [string]: { Piece } } = {
	DoorL = DOOR,
	DoorR = mirror(DOOR),
	DoorGlassL = DOOR_GLASS,
	DoorGlassR = mirror(DOOR_GLASS),
	Hood = {
		beam("Panel", "paint", { 0, -3.0, 3.95 }, { 0, -6.8, 3.42 }, 5.17, 0.08),
		box("Nose", "paint", { -1.39, -8.0, 3.25 }, { 1.39, -6.8, 3.42 }),
	},
	HoodProp = { beam("Rod", "metal", { 2.3, -6.5, 3.0 }, { 2.3, -3.7094, 3.4625 }, 0.05, 0.05) },
	Hatch = {
		beam("Panel", "paint", { 0, 4.37, 5.69 }, { 0, 7.62, 4.02 }, 6.04, 0.08),
		glass(beam("Glass", "glass", { 0, 4.62, 5.58 }, { 0, 7.4, 4.14 }, 5.17, 0.12)),
		box("Deck", "paint", { -3.02, 7.62, 3.86 }, { 3.02, 8.96, 4.04 }),
		box("Lip", "paint", { -3.02, 8.86, 3.3 }, { 3.02, 8.96, 3.9 }),
	},
	PodL = POD,
	PodR = mirror(POD),
	WheelFL = HUB_WHEEL(2.8, -4.8),
	WheelFR = mirror(HUB_WHEEL(2.8, -4.8)),
	WheelRL = HUB_WHEEL(2.8, 4.8),
	WheelRR = mirror(HUB_WHEEL(2.8, 4.8)),
	CaliperFL = { boxc("Caliper", "caliper", { 2.99, -4.29, 1.29 }, { 0.28, 0.3, 0.52 }) },
	CaliperFR = { boxc("Caliper", "caliper", { -2.99, -4.29, 1.29 }, { 0.28, 0.3, 0.52 }) },
	CaliperRL = { boxc("Caliper", "caliper", { 2.99, 5.31, 1.29 }, { 0.28, 0.3, 0.52 }) },
	CaliperRR = { boxc("Caliper", "caliper", { -2.99, 5.31, 1.29 }, { 0.28, 0.3, 0.52 }) },
	NeedleSpeedo = { boxc("Needle", "needle", { -0.9913, -1.86, 3.5259 }, { 0.2139, 0.02, 0.1402 }) },
	NeedleTacho = { boxc("Needle", "needle", { -1.7712, -1.86, 3.5259 }, { 0.2139, 0.02, 0.1402 }) },
	NeedleFuel = { boxc("Needle", "needle", { -1.4273, -1.86, 3.6327 }, { 0.0894, 0.02, 0.0793 }) },
	NeedleTemp = { boxc("Needle", "needle", { -1.4273, -1.86, 3.4226 }, { 0.0894, 0.02, 0.0793 }) },
	GearLever = { boxc("Lever", "trim", { 0, -1.2, 2.54 }, { 0.23, 0.23, 0.72 }) },
	Handbrake = { boxc("Lever", "trim", { 0, 0.155, 2.085 }, { 0.14, 0.93, 0.17 }) },
	PedalAccel = { boxc("Pedal", "metal", { -1.97, -2.4718, 1.7861 }, { 0.17, 0.3452, 1.1197 }) },
	PedalBrake = { boxc("Pedal", "metal", { -1.51, -2.4796, 1.8201 }, { 0.3, 0.3296, 1.0517 }) },
	PedalClutch = { boxc("Pedal", "metal", { -1.01, -2.4796, 1.8201 }, { 0.3, 0.3296, 1.0517 }) },
	WiperL = { boxc("Arm", "trim", { 1.2258, -3.2271, 4.0088 }, { 2.0498, 0.2058, 0.1427 }) },
	WiperR = { boxc("Arm", "trim", { -1.0742, -3.0571, 4.0088 }, { 2.0498, 0.2058, 0.1427 }) },
}

-- The steering wheel: a disc square to its column, and a spoke so its turning shows.
do
	local d = Rig.Pivots.parts.SteeringWheel
	local o, ax = d.origin, d.axis
	local function along(k: number, side: number): { number }
		return { o[1] + side, o[2] + ax[2] * k, o[3] + ax[3] * k }
	end
	PARTS.SteeringWheel = {
		cyl("Rim", "trim", along(-0.05, 0), along(0.05, 0), 1.45),
		-- on the driver's side of the disc: the column's axis points back at the driver
		beam("Spoke", "metal", along(0.08, -0.6), along(0.08, 0.6), 0.15, 0.06, "z"),
	}
end

-- The struts, sized as the gray model's build sizes them: the tube fits between the pins
-- with the hatch shut, and the rod still reaches into it with the hatch fully open.
do
	local P = Rig.Pivots.parts
	local hatch = P.Hatch
	local function vec(p: { number }): Vector3
		return Vector3.new(p[1], p[2], p[3])
	end
	local O = vec(hatch.origin)
	local openRot = CFrame.fromAxisAngle(vec(hatch.axis).Unit, math.rad(hatch.angle))
	for _, side in { "L", "R" } do
		local H = vec(P["StrutTube" .. side].origin) -- on the hatch
		local B = vec(P["StrutRod" .. side].origin) -- on the body
		local H1 = O + openRot * (H - O)
		local shut, opened = (H - B).Magnitude, (H1 - B).Magnitude
		local tube = shut - 0.10
		local rod = math.min(shut - 0.03, opened - tube + 0.14)
		local dir = (B - H).Unit
		local tip = H + dir * tube
		local end_ = B - dir * rod
		PARTS["StrutTube" .. side] = {
			beam("Tube", "trim", { H.X, H.Y, H.Z }, { tip.X, tip.Y, tip.Z }, 0.12, 0.12),
		}
		PARTS["StrutRod" .. side] = {
			beam("Rod", "metal", { B.X, B.Y, B.Z }, { end_.X, end_.Y, end_.Z }, 0.056, 0.056),
		}
	end
end

-- Every lamp: its lens's box, in its own colour. The headlights are plates that face
-- forward once their pods are up, so shut they lean back with them (44.7 degrees).
for name, what in Rig.Pivots.lights do
	local at = Rig.LAMPS[name]
	if string.sub(name, 1, 9) == "Headlight" then
		PARTS[name] = { boxc("Lens", "lamp:" .. what, at.c, { 0.85, 0.08, 0.85 }, -Rig.Pivots.parts.PodL.angle) }
	else
		PARTS[name] = { boxc("Lens", "lamp:" .. what, at.c, at.s) }
	end
end

StandIn.BODY = BODY
StandIn.PARTS = PARTS

-- ------------------------------------------------------------------ building

local function cframeOf(p: Piece, ride: number): (CFrame, Vector3)
	if p.k == "box" or p.k == "wedge" then
		local lo, hi = p.lo :: { number }, p.hi :: { number }
		local c = { (lo[1] + hi[1]) * 0.5, (lo[2] + hi[2]) * 0.5, (lo[3] + hi[3]) * 0.5 }
		-- list axes (x, y, z) are the car's (x, z, y) in size
		local size = Vector3.new(hi[1] - lo[1], hi[3] - lo[3], hi[2] - lo[2])
		return CFrame.new(Rig.toCar(c, ride)), size
	elseif p.k == "boxc" then
		local s = p.s :: { number }
		local cf = CFrame.new(Rig.toCar(p.c :: { number }, ride))
		if p.rx then
			cf *= CFrame.fromAxisAngle(Rig.dirToCar({ 1, 0, 0 }), math.rad(p.rx))
		end
		return cf, Vector3.new(s[1], s[3], s[2])
	elseif p.k == "beam" then
		local a, b = Rig.toCar(p.a :: { number }, ride), Rig.toCar(p.b :: { number }, ride)
		local axis = p.across or "x"
		local across = Rig.dirToCar(if axis == "y" then { 0, 1, 0 } elseif axis == "z" then { 0, 0, 1 } else { 1, 0, 0 })
		local look = (b - a).Unit
		local x = (across - look * across:Dot(look)).Unit
		local z = -look
		local y = z:Cross(x)
		return CFrame.fromMatrix((a + b) * 0.5, x, y, z), Vector3.new(p.w :: number, p.t :: number, (b - a).Magnitude)
	elseif p.k == "cyl" then
		-- a Roblox cylinder's axis is its own X
		local a, b = Rig.toCar(p.a :: { number }, ride), Rig.toCar(p.b :: { number }, ride)
		local x = (b - a).Unit
		local hint = if math.abs(x.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
		local z = x:Cross(hint).Unit
		local y = z:Cross(x)
		local d = p.d :: number
		return CFrame.fromMatrix((a + b) * 0.5, x, y, z), Vector3.new((b - a).Magnitude, d, d)
	end
	error(`[StandIn] no piece kind '{p.k}'`)
end

local function makePart(p: Piece, ride: number, pivot: CFrame): BasePart
	local part: BasePart
	if p.k == "wedge" then
		part = Instance.new("WedgePart")
	else
		local q = Instance.new("Part")
		if p.k == "cyl" then
			q.Shape = Enum.PartType.Cylinder
		end
		part = q
	end
	local cf, size = cframeOf(p, ride)
	part.Name = p.n
	part.Size = size
	part.CFrame = cf
	-- Where it sits in its group's own frame, which is its pivot: `Drift/Render` writes
	-- every part `groupFrame * L` absolutely, every frame -- never a pivot (T-020).
	part:SetAttribute("L", pivot:Inverse() * cf)

	local col = p.col
	if string.sub(col, 1, 5) == "lamp:" then
		part.Color = lampColour(string.sub(col, 6))
	else
		part.Color = (COLOURS :: any)[col] or COLOURS.paint
	end
	part.Material = if col == "glass" then Enum.Material.Glass else Enum.Material.SmoothPlastic
	part.Transparency = p.tr or 0
	part.CastShadow = p.tr == nil

	-- The five rules that keep a car out of Roblox's hands entirely.
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- the ground rays must not hit the car
	part.CanTouch = false
	part.Locked = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function group(name: string, pieces: { Piece }, ride: number, pivot: CFrame): Model
	local g = Instance.new("Model")
	g.Name = name
	for _, p in pieces do
		makePart(p, ride, pivot).Parent = g
	end
	g.WorldPivot = pivot
	g:SetAttribute("N", #pieces)
	return g
end

-- A fresh stand-in `Shell`, in the car's frame (the caller's car sits at the origin, as
-- `CarModel.build` makes it). Nothing yields and nothing is cached: it is a couple of
-- hundred `Instance.new` calls.
function StandIn.build(): Model
	local ride = Config.Drift.RideHeight
	local shell = Instance.new("Model")
	shell.Name = "Shell"

	local body = group("Body", BODY, ride, CFrame.identity)
	body:SetAttribute("Kind", "body")
	body.Parent = shell

	local count = 1
	for _, spec in Rig.groups(ride) do
		local g = group(spec.name, PARTS[spec.name] or {}, ride, spec.pivot)
		Rig.write(g, spec)
		g.Parent = shell
		count += 1
	end
	Rig.writePoints(shell, count, ride)
	shell.WorldPivot = CFrame.identity
	return shell
end

return StandIn
