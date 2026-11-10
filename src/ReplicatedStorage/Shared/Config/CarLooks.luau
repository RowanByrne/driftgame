--!nonstrict
-- CarLooks: how a fitted build is DRAWN on a car -- paint, wraps, underglow, wheels
-- (docs/game/features/car-customization.md, T-104; CONTRACTS.md "Customization").
--
-- The catalog (`Shared/Customization/Catalog`) says WHAT a part is ("Mesh rims", "glow_ice",
-- the "stripes" wrap); this says how each of those is drawn, and which parts of a car each
-- one is drawn ON. Every number here is programmer art: a placeholder until the real looks
-- are picked (ART-PIPELINE.md).
--
-- WHICH PART IS WHICH IS DATA, NEVER A GUESS. Every shell part has a ROLE, and only parts
-- with a role are ever recoloured:
--   body    the paint: takes `Fit_PaintBody`, the finish, and carries the wrap
--   second  the two-tone: takes `Fit_PaintSecond` and the finish
--   rim     takes the Wheels part's rim style
--   tyre    takes the Wheels part's tyre style
-- Anything else -- glass, lamps, trim, grilles, exhausts, the interior -- has no role and is
-- never touched. The role is decided, in order, by:
--   1. the part's own `Paint` attribute (`RoleAttribute`), when it has one: "body",
--      "second", "rim", "tyre", or "none" to keep a part out whatever its name. THIS IS THE
--      RULE FOR A RIGGED CAR (CONTRACTS.md "The car rig"): an imported model names its
--      parts however it likes, so whoever assembles it tags its paint.
--   2. `Roles[<the car's Body attribute>]`, by part name, for the parts in the shell's
--      `Body` group (or, for the `block` car, the car's own parts). Never for a rigged
--      car's body (its shell carries `Rig`): there, only the attribute counts.
--   3. `WheelRoles`, by part name, for the parts in a `Wheel*` group.

local CarLooks = {}

CarLooks.RoleAttribute = "Paint"

-- Parts by name, per body (the car's `Body` attribute, `Shared/CarModel.dress`). A mirrored
-- piece (`mir = true` in `Shared/Cars/Bodies`) is two parts, `<name>R` and `<name>L`.
CarLooks.Roles = {
	-- the box car: its simulation `Body` is what you see, and its wheels are bare cylinders
	block = {
		body = { "Body" },
		tyre = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" },
	},
	balanced = {
		body = { "Hull", "Shoulder", "Bonnet", "Deck", "ArchFR", "ArchFL", "ArchRR", "ArchRL" },
		second = { "StripeR", "StripeL", "Roof" },
	},
	gripper = {
		body = { "Floor", "Shoulder", "Nose", "Fastback", "Panel" },
		second = { "CanardR", "CanardL", "Roof" },
	},
	slider = {
		body = { "Hull", "Shoulder", "Bonnet", "Deck", "Panel", "ArchFR", "ArchFL", "ArchRR", "ArchRL" },
		second = { "Cowl", "Ducktail" },
	},
	bruiser = {
		body = { "Hull", "Bonnet", "Deck", "ArchFR", "ArchFL", "ArchRR", "ArchRL" },
		second = { "Roof", "Scoop" },
	},
	-- the imported placeholder: its painted panels are all called "Paint"; it has no
	-- two-tone panel of its own
	ae86 = {
		body = { "Paint" },
	},
}

-- In every `Wheel*` group, whatever the body.
CarLooks.WheelRoles = {
	rim = { "Rim" },
	tyre = { "Tire" },
}

-- ---------------------------------------------------------------------- wheels
--
-- A Wheels part's `look = { rim = <name>, tyre = <name> }` (Catalog) is drawn from these.
-- Size is never changed: the wheel is the config's (`Config.Drift.WheelDiameter`).
-- `material` is an Enum.Material name. A textured mesh rim (the AE86's) keeps its texture,
-- which Roblox draws over the colour.

CarLooks.Rims = {
	Mesh = { colour = Color3.fromRGB(205, 208, 214), material = "Metal", reflectance = 0.2 },
	DeepDish = { colour = Color3.fromRGB(236, 236, 240), material = "Metal", reflectance = 0.35 },
	FiveSpoke = { colour = Color3.fromRGB(30, 30, 34), material = "SmoothPlastic", reflectance = 0.05 },
}

CarLooks.Tyres = {
	Street = { colour = Color3.fromRGB(30, 30, 34), material = "SmoothPlastic", reflectance = 0 },
	SemiSlick = { colour = Color3.fromRGB(18, 18, 20), material = "SmoothPlastic", reflectance = 0.04 },
	Hard = { colour = Color3.fromRGB(48, 48, 52), material = "Slate", reflectance = 0 },
}

-- ---------------------------------------------------------------------- wraps
--
-- A wrap is drawn as flat colour shapes on the faces of the car's BODY-role parts, never as
-- an uploaded image (PLATFORM-RISKS.md "Copyright": generic patterns only). Only plain box
-- parts carry one: a wedge's sloped face and a mesh's curves are not the box a face is
-- drawn on, so they keep their paint and no pattern.
--
-- Coordinates are the FACE'S, as fractions: `u` runs along the car (the part's Z) on every
-- face used here, `v` across the top (the part's X) or down a side (the part's Y, 0 at the
-- top). Measured in Studio: Top, Left and Right all put the part's Z along the canvas.
--
--   bands   { from, to } in v: a full-length band
--   cells   a checker band: `size` studs square, `rows` rows, centred at v = `at`
--   dots    a field of `size`-stud squares turned by `rotation`, every `step` studs, rows
--           offset by half a step -- the honeycomb, near enough for programmer art
-- Faces are NormalId names. The wrap's colour is the build's second colour, or, when that
-- is stock, `WrapDark` on a light body and `WrapLight` on a dark one.

CarLooks.Wraps = {
	stripes = {
		faces = { "Top" },
		bands = { { 0.34, 0.44 }, { 0.56, 0.66 } },
	},
	split = {
		faces = { "Left", "Right" },
		bands = { { 0.55, 1 } },
	},
	checker = {
		faces = { "Left", "Right" },
		cells = { size = 0.5, rows = 2, at = 0.5 },
	},
	hex = {
		faces = { "Top", "Left", "Right" },
		dots = { size = 0.45, step = 1.1, rotation = 45 },
	},
}

CarLooks.WrapPixelsPerStud = 20
CarLooks.WrapDark = Color3.fromRGB(24, 24, 28)
CarLooks.WrapLight = Color3.fromRGB(240, 240, 236)
-- A face smaller than this many studs on a side gets no wrap: a lip, a stripe, a flare.
CarLooks.WrapMinFace = 0.6
-- Body colours brighter than this (0..1, Rec. 601 luma) count as light.
CarLooks.WrapLightAbove = 0.5

-- ---------------------------------------------------------------------- underglow
--
-- A light under the car, drawn on every client: an invisible, anchored, non-colliding,
-- non-queryable part in `Workspace.CarLooks` (never inside the car: the car is the server's,
-- holds no Light, and nothing is welded to it, DECISIONS.md 2026-11-03), moved to the car's
-- body every frame after the car is drawn.

CarLooks.Underglow = {
	Height = 0.35, -- the light's height above the road, studs
	Size = Vector3.new(4.6, 0.1, 9), -- the lit footprint, studs (across, up, along)
	Brightness = 6,
	Range = 9,
	Angle = 150, -- the SurfaceLight's spread, degrees
	HaloBrightness = 1.2, -- the PointLight that tints the car's own underside and the road round it
	HaloRange = 11,
	PulsePeriod = 1.4, -- seconds, one full breath
	PulseLow = 0.2, -- the dimmest a pulse gets, as a fraction of Brightness
}

return CarLooks
