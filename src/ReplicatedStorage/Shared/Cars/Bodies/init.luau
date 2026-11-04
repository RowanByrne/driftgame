--!nonstrict
-- Bodies: our own car shapes, assembled out of parts by code
-- (docs/game/features/car-archetypes.md, T-028).
--
-- WHY THESE EXIST. The body the game drew until now is the AE86, which came off the
-- Toolbox and is a real manufacturer's car we are not allowed to publish
-- (`assets/car-ae86/MANIFEST.md`, docs/workflow/PLATFORM-RISKS.md). Pulling three more
-- the same way, one per archetype, multiplies that risk by four. These are boxes and
-- wedges instead: safe, in git as text, parametric, and replaceable the day someone
-- models properly.
--
-- A BODY IS NOT A CAR, and the two axes stay separate (`Shared/Cars`): a body is the
-- shape that is drawn, an archetype is how it drives. `Config.Drift.CarBody = "auto"`
-- draws the ACTIVE archetype's own body, and any other value overrides it for every car
-- -- which is how the AE86 is still driven on any archetype's numbers.
--
-- WHAT A BODY IS. A table: a palette, the geometry it was drawn against, a list of pieces
-- for the hull and a list for one wheel. `build(name)` turns that into the same `Shell`
-- model `Shared/CarModel` already makes for the AE86 -- a `Body` group and four
-- `Wheel*` groups of plain anchored parts, each carrying its place as the `L` attribute
-- that `Drift/Render` writes absolutely every frame. ADDING A FIFTH BODY IS A TABLE, not
-- a module of code.
--
-- TWO RULES, both asserted by `DriftTests`:
--   * nothing here moves itself. Every part is anchored, and no BodyMover, constraint,
--     joint, weld, script, sound, light, emitter or seat is ever created
--     (docs/game/DECISIONS.md, 2026-11-03: Roblox physics never moves this car).
--   * the geometry is the MODEL's, not the art's. `Wheelbase`, `TrackWidth`,
--     `WheelDiameter` and `RideHeight` are the active car's and are where the ground rays
--     go; a body is built AROUND them and never asks them to move. A body says which
--     geometry it was drawn against (`For`) and is scaled onto the live one, so a car
--     with a longer wheelbase gets a longer body rather than a wrong one.
--
-- COORDINATES. Pieces are authored in the car's own frame, front at -Z, right at +X --
-- except Y, WHICH IS MEASURED UP FROM THE ROAD, because "the sill is 0.9 studs off the
-- ground" is the sentence a body is actually drawn with. The builder subtracts
-- `RideHeight` to put it in the car's frame. The road is therefore y = 0 here and
-- y = -RideHeight to everything else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Bodies = {}

export type Piece = {
	n: string, -- the part's name
	k: string?, -- "box" (default), "wedge", "cylinder", "ball"
	s: { number }, -- size, x y z
	p: { number }, -- centre: x across, y ABOVE THE ROAD, z along (front is -Z)
	r: { number }?, -- rotation in degrees, x y z, applied after the offset
	c: Color3, -- colour
	m: string?, -- Enum.Material name, default SmoothPlastic
	tr: number?, -- transparency
	rf: number?, -- reflectance
	mir: boolean?, -- build the mirror image at -x too (named <n>L / <n>R)
	sh: boolean?, -- CastShadow, default true
}

export type Spec = {
	Name: string,
	Silhouette: string,
	For: { Wheelbase: number, TrackWidth: number, WheelDiameter: number, WheelWidth: number },
	Body: { Piece },
	Wheel: { Piece }, -- one wheel, x measured OUTWARD from the car
}

-- The four, by the archetype key each one belongs to. The key IS the body name, which is
-- what makes `CarBody = "auto"` a one-line lookup.
Bodies.Specs = {
	balanced = require(script.Balanced),
	gripper = require(script.Gripper),
	slider = require(script.Slider),
	bruiser = require(script.Bruiser),
}

Bodies.Order = { "balanced", "gripper", "slider", "bruiser" }

function Bodies.exists(name: string): boolean
	return Bodies.Specs[name] ~= nil
end

function Bodies.spec(name: string): Spec?
	return Bodies.Specs[name]
end

-- ---------------------------------------------------------------------- one part

local function colourOf(c): Color3
	return if typeof(c) == "Color3" then c else Color3.fromRGB(200, 200, 200)
end

-- A piece, in the frame its group is drawn in. `scale` is the live geometry over the one
-- the body was drawn against; `lift` is what to take off Y to go from road-relative to
-- the car's own frame. `flip` is -1 for the mirrored copy.
--
-- Scaling a ROTATED piece by three different numbers is not exact -- a rotated box cannot
-- stay a box under a non-uniform scale -- so the size is scaled in the piece's own axes
-- and the placement in the car's. Today every scale is exactly 1 (every archetype shares
-- the approved car's geometry) and the question is academic; when it is not, the error is
-- a fraction of a stud on a cosmetic panel and the wheels, which are what the simulation
-- rays from, are scaled on their own and are exact.
local function makePart(d: Piece, scale: Vector3, lift: number, flip: number): BasePart
	local kind = d.k or "box"
	local part: BasePart
	if kind == "wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if kind == "cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif kind == "ball" then
			p.Shape = Enum.PartType.Ball
		end
		part = p
	end

	part.Name = if flip < 0 then d.n .. "L" else (if d.mir then d.n .. "R" else d.n)
	part.Size = Vector3.new(d.s[1] * scale.X, d.s[2] * scale.Y, d.s[3] * scale.Z)

	local at = CFrame.new(d.p[1] * scale.X * flip, d.p[2] * scale.Y - lift, d.p[3] * scale.Z)
	if d.r then
		-- A mirror image turns the other way about Y and Z and the same way about X.
		at *= CFrame.Angles(math.rad(d.r[1]), math.rad(d.r[2]) * flip, math.rad(d.r[3]) * flip)
	end
	-- A wedge needs nothing extra: it is a triangular prism extruded along its own X, so
	-- it is already symmetric across the plane a mirror image is reflected in. Its slope
	-- runs from the tall face at +Z down to the thin edge at -Z, which is a bonnet
	-- falling toward the nose as it stands and a fastback at `r = {0, 180, 0}`.
	part.CFrame = at
	-- Where this part sits in its group, written down rather than inferred: `Drift/Render`
	-- reads it once and then writes every shell part an ABSOLUTE CFrame each frame. A
	-- `Model:PivotTo` would be a delta, and the server re-asserts these, so the shell
	-- would walk away from the car (`Shared/CarModel`).
	part:SetAttribute("L", at)

	part.Color = colourOf(d.c)
	part.Material = if d.m then (Enum.Material :: any)[d.m] else Enum.Material.SmoothPlastic
	part.Transparency = d.tr or 0
	part.Reflectance = d.rf or 0
	part.CastShadow = d.sh ~= false

	-- The five rules that keep a car out of Roblox's hands entirely.
	part.Anchored = true
	part.CanCollide = false -- our own sweep handles walls
	part.CanQuery = false -- the ground rays must not hit the car
	part.CanTouch = false
	part.Locked = true
	return part
end

local function group(name: string, pieces: { Piece }, scale: Vector3, lift: number): Model
	local g = Instance.new("Model")
	g.Name = name
	local n = 0
	for _, d in pieces do
		makePart(d, scale, lift, 1).Parent = g
		n += 1
		if d.mir then
			makePart(d, scale, lift, -1).Parent = g
			n += 1
		end
	end
	g.WorldPivot = CFrame.identity
	-- How many parts to expect: a Model replicates before its contents, so a client has to
	-- know when it has all of them (`Drift/Render`, `resolve`).
	g:SetAttribute("N", n)
	return g
end

-- ---------------------------------------------------------------------- one car

-- A `Shell` model for `name`, built against whatever geometry the ACTIVE car has right
-- now. Nothing here yields and nothing is cached: a body is twenty-odd parts of pure
-- Instance.new, which is microseconds, and a cache would be a stale body the first time
-- an archetype's geometry differs.
function Bodies.build(name: string): Model?
	local spec: Spec? = Bodies.Specs[name]
	if not spec then
		return nil
	end
	local C = Config.Drift
	local f = spec.For

	-- The body follows the wheelbase along the car and the track across it, because those
	-- are the two numbers that say where the wheels it has to sit between actually are.
	local bodyScale = Vector3.new(C.TrackWidth / f.TrackWidth, 1, C.Wheelbase / f.Wheelbase)
	-- The wheel follows its own diameter and width, so it touches the road exactly.
	local d = C.WheelDiameter / f.WheelDiameter
	local wheelScale = Vector3.new(C.WheelWidth / f.WheelWidth, d, d)

	local shell = Instance.new("Model")
	shell.Name = "Shell"
	group("Body", spec.Body, bodyScale, C.RideHeight).Parent = shell

	-- A wheel group is drawn in the wheel part's OWN frame, which already carries the
	-- steer and the spin, so it is built about the origin -- and the wheel's x is measured
	-- outward, away from the car, so one list draws all four.
	for _, wheelName in { "WheelFL", "WheelFR", "WheelRL", "WheelRR" } do
		local outward = if wheelName == "WheelFL" or wheelName == "WheelRL" then -1 else 1
		local pieces = {}
		for _, piece in spec.Wheel do
			local copy = table.clone(piece)
			copy.p = { piece.p[1] * outward, piece.p[2], piece.p[3] }
			copy.mir = false
			table.insert(pieces, copy)
		end
		group(wheelName, pieces, wheelScale, 0).Parent = shell
	end

	shell.WorldPivot = CFrame.identity
	return shell
end

-- ---------------------------------------------------------------------- measuring

-- The box a built group actually occupies, in the frame it was built in: every part's
-- eight corners, so a rotated panel counts for its real extent. Used by the tests and by
-- `Bodies.report`; nothing in the game needs it.
function Bodies.bounds(g: Instance): (Vector3, Vector3)
	local lo, hi = Vector3.new(1e9, 1e9, 1e9), Vector3.new(-1e9, -1e9, -1e9)
	for _, p in g:GetDescendants() do
		if p:IsA("BasePart") then
			local at = p:GetAttribute("L")
			local cf = if typeof(at) == "CFrame" then at else p.CFrame
			local h = p.Size * 0.5
			for i = -1, 1, 2 do
				for j = -1, 1, 2 do
					for k = -1, 1, 2 do
						local pt = cf * Vector3.new(h.X * i, h.Y * j, h.Z * k)
						lo, hi = lo:Min(pt), hi:Max(pt)
					end
				end
			end
		end
	end
	return lo, hi
end

-- Every body's real dimensions, measured off the parts rather than claimed: length,
-- width, overall height and roof height, all above the road, and the part count. The
-- table that shows the four are different shapes.
function Bodies.report(): { { [string]: any } }
	local out = {}
	for _, name in Bodies.Order do
		local shell = Bodies.build(name)
		if shell then
			local body = shell:FindFirstChild("Body")
			local lo, hi = Bodies.bounds(body)
			local lift = Config.Drift.RideHeight
			local roofPart = body and body:FindFirstChild("Roof")
			local roof = hi.Y + lift
			if roofPart and roofPart:IsA("BasePart") then
				local at = roofPart:GetAttribute("L")
				roof = (if typeof(at) == "CFrame" then at.Position.Y else roofPart.Position.Y)
					+ roofPart.Size.Y * 0.5
					+ lift
			end
			local parts = 0
			for _, p in shell:GetDescendants() do
				if p:IsA("BasePart") then
					parts += 1
				end
			end
			table.insert(out, {
				key = name,
				name = Bodies.Specs[name].Name,
				silhouette = Bodies.Specs[name].Silhouette,
				length = hi.Z - lo.Z,
				width = hi.X - lo.X,
				height = hi.Y - lo.Y,
				top = hi.Y + lift, -- the highest point of anything, above the road
				roof = roof, -- the roof (or what stands in for one), above the road
				ground = lo.Y + lift, -- the lowest point of the hull, above the road
				parts = parts,
			})
			shell:Destroy()
		end
	end
	return out
end

return Bodies
