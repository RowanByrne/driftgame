--!nonstrict
-- The parts catalog: every customization category, its parts, and what each part does
-- (docs/game/features/car-customization.md "Rules and numbers").
--
-- DATA ONLY. Adding a part is a line here, never code: `Shared/Customization` reads this
-- table, checks it (`Customization.problems`, run by `CustomizationTests`), and both ends
-- of the wire use the same copy, so the client's menu and the server's checks can never
-- disagree about what a part is.
--
-- EVERY PART IS A PLACEHOLDER (T-101). The names, the looks and the numbers are an agent's
-- first guess, to give the menus, the drawing and the feel something real to work on; the
-- user names and picks the real ones.
--
-- A PART:
--   id      unique across the WHOLE catalog, never reused: it is what the store keeps
--   name    what the player reads
--   perf    performance: { [car key] = fraction }, e.g. `MaxAcceleration = 0.1` is +10%
--           on the car's own number. Keys are the tuner's car keys (`Shared/Cars/Garage`
--           "the sliders"), only the ones its category owns, never past `MaxDelta`
--   look    what is drawn, by category (see `LookFields`). Absent = draws nothing new
--   price   UNUSED: everything is free while meta progression is undecided (GDD.md).
--           The field is here so a price drops into a frame that already has room for it
--   unlock  UNUSED, the same: how a part is got. "free" for every part today
--
-- STOCK IS TODAY'S CAR EXACTLY: every category's stock part has no `perf` and no `look`,
-- and `Customization.resolve` returns the archetype's own numbers untouched for it.

local Catalog = {}

Catalog.Version = 1

-- The most any one part may move a number it touches, either way. A starting bound that
-- keeps the approved drift feel (DECISIONS.md 2026-11-03): no build can move a key further
-- than this, because each key belongs to exactly one category (`Categories[].keys`) and a
-- build holds one part per category.
Catalog.MaxDelta = 0.15

-- What the server takes off the wire. Here rather than in `Config.Drift` because they are
-- the catalog's own rules, and the client reads the same numbers.
Catalog.Limits = {
	FitsPerSecond = 8, -- asks a second per UserId, questions included; a flood is dropped
	MaxIdLength = 64, -- longer than any id here; anything longer is refused before a lookup
}

-- The pieces a part's look may name, per category. KIT and INTERIOR slots are groups the
-- car rig will carry (`CONTRACTS.md` "Customization"); the drawing steps (T-104, T-105)
-- put programmer-art boxes in them.
Catalog.LookFields = {
	Suspension = { rideHeight = "number", stiffness = "number" },
	Wheels = { rim = "string", tyre = "string" },
	BodyKit = { slots = "table" },
	Underglow = { colour = "Color3", mode = "string" },
	Interior = { slots = "table" },
}

Catalog.Slots = {
	BodyKit = { "KitFront", "KitRear", "KitSkirts", "KitSpoiler", "KitFlares" },
	Interior = { "InteriorCage", "InteriorSeat", "InteriorWheel", "InteriorAudio" },
}

-- Bounds on the numbers a look carries. `rideHeight` is studs from the car's own (down is
-- negative), drawn only: the simulation's `RideHeight` is geometry and is not moved by a
-- part. `stiffness` multiplies the v2 suspension's own `Stiffness` (car-v2.md).
Catalog.LookBounds = {
	rideHeight = { min = -0.5, max = 0.5 },
	stiffness = { min = 0.7, max = 1.5 },
}

Catalog.UnderglowModes = { "off", "steady", "pulse" }

-- ---------------------------------------------------------------------- the categories
--
-- `kind` says what a part in it may carry: "performance" (perf, no look), "both" (perf
-- and look) or "looks" (look, never perf). `keys` are the car keys its parts may move, and
-- no key is in two categories.
Catalog.Categories = {
	{
		id = "Engine",
		label = "Engine",
		kind = "performance",
		keys = { "MaxAcceleration", "TopSpeed" },
		parts = {
			{ id = "engine_stock", name = "Stock" },
			{
				id = "engine_intake",
				name = "Intake and exhaust",
				perf = { MaxAcceleration = 0.05, TopSpeed = 0.03 },
			},
			{
				id = "engine_street",
				name = "Street tune",
				perf = { MaxAcceleration = 0.1, TopSpeed = 0.05 },
			},
			{
				id = "engine_race",
				name = "Race build",
				perf = { MaxAcceleration = 0.15, TopSpeed = 0.1 },
			},
			{
				id = "engine_longgears",
				name = "Long gears",
				perf = { MaxAcceleration = -0.08, TopSpeed = 0.15 },
			},
		},
	},
	{
		id = "Suspension",
		label = "Suspension",
		kind = "both",
		keys = { "MaxSteeringSpeed", "MaxFriction", "SlipSqFriction", "DownforcePerSpeed" },
		parts = {
			{ id = "susp_stock", name = "Stock" },
			{
				id = "susp_lowering",
				name = "Lowering springs",
				perf = { MaxFriction = 0.05 },
				look = { rideHeight = -0.2, stiffness = 1.15 },
			},
			{
				id = "susp_coilover",
				name = "Street coilovers",
				perf = { MaxFriction = 0.08, MaxSteeringSpeed = 0.05, DownforcePerSpeed = 0.1 },
				look = { rideHeight = -0.3, stiffness = 1.3 },
			},
			{
				id = "susp_drift",
				name = "Drift coilovers",
				perf = { MaxSteeringSpeed = 0.1, SlipSqFriction = -0.1 },
				look = { rideHeight = -0.4, stiffness = 1.4 },
			},
			{
				id = "susp_lifted",
				name = "Lifted",
				perf = { MaxFriction = -0.05, DownforcePerSpeed = -0.1 },
				look = { rideHeight = 0.3, stiffness = 0.85 },
			},
		},
	},
	{
		id = "Wheels",
		label = "Wheels & tyres",
		kind = "both",
		keys = { "ConstantFriction", "SlipFriction" },
		parts = {
			{ id = "wheels_stock", name = "Stock" },
			{
				id = "wheels_mesh",
				name = "Mesh rims",
				look = { rim = "Mesh", tyre = "Street" },
			},
			{
				id = "wheels_dish",
				name = "Deep dish",
				perf = { ConstantFriction = 0.03 },
				look = { rim = "DeepDish", tyre = "Street" },
			},
			{
				id = "wheels_semislick",
				name = "Semi-slicks",
				perf = { ConstantFriction = 0.12, SlipFriction = 0.1 },
				look = { rim = "FiveSpoke", tyre = "SemiSlick" },
			},
			{
				id = "wheels_drift",
				name = "Drift tyres",
				perf = { ConstantFriction = -0.08, SlipFriction = -0.05 },
				look = { rim = "Mesh", tyre = "Hard" },
			},
		},
	},
	{
		id = "BodyKit",
		label = "Body kits",
		kind = "looks",
		keys = {},
		parts = {
			{ id = "kit_stock", name = "Stock" },
			{
				id = "kit_street",
				name = "Street kit",
				look = { slots = { KitFront = "LipSmall", KitSkirts = "Skirts" } },
			},
			{
				id = "kit_wide",
				name = "Wide body",
				look = { slots = { KitFront = "LipWide", KitRear = "Diffuser", KitSkirts = "Skirts", KitFlares = "Flares" } },
			},
			{
				id = "kit_wing",
				name = "Track wing",
				look = { slots = { KitSpoiler = "WingHigh", KitRear = "Diffuser" } },
			},
			{
				id = "kit_ducktail",
				name = "Ducktail",
				look = { slots = { KitSpoiler = "Ducktail", KitFront = "LipSmall" } },
			},
		},
	},
	{
		id = "Underglow",
		label = "Underglow",
		kind = "looks",
		keys = {},
		parts = {
			{ id = "glow_stock", name = "Stock (off)" },
			{ id = "glow_ice", name = "Ice blue", look = { colour = Color3.fromRGB(90, 200, 255), mode = "steady" } },
			{ id = "glow_magenta", name = "Magenta pulse", look = { colour = Color3.fromRGB(255, 60, 200), mode = "pulse" } },
			{ id = "glow_lime", name = "Lime", look = { colour = Color3.fromRGB(150, 255, 70), mode = "steady" } },
			{ id = "glow_amber", name = "Amber pulse", look = { colour = Color3.fromRGB(255, 170, 40), mode = "pulse" } },
		},
	},
	{
		id = "Interior",
		label = "Interior",
		kind = "looks",
		keys = {},
		parts = {
			{ id = "int_stock", name = "Stock" },
			{ id = "int_cage", name = "Half cage", look = { slots = { InteriorCage = "HalfCage" } } },
			{ id = "int_buckets", name = "Bucket seats", look = { slots = { InteriorSeat = "Bucket" } } },
			{ id = "int_wheel", name = "Deep-dish wheel", look = { slots = { InteriorWheel = "DeepDish" } } },
			{
				id = "int_full",
				name = "Full build",
				look = {
					slots = { InteriorCage = "FullCage", InteriorSeat = "Bucket", InteriorWheel = "DeepDish", InteriorAudio = "SubBox" },
				},
			},
		},
	},
}

-- ---------------------------------------------------------------------- paint & wraps
--
-- The seventh category is not a part slot: a car's paint is four choices, each from its
-- own list. "stock" everywhere means "whatever the body is painted today", so a stock
-- build recolours nothing. Wraps are generic patterns ONLY: no real logos, sponsors or
-- licensed designs, ever (PLATFORM-RISKS.md "Copyright", the spec's "Platform risks").
Catalog.Paint = {
	id = "Paint",
	label = "Paint & wraps",
	kind = "looks",
	-- The four fields a paint holds, and which list each one is chosen from.
	fields = {
		body = "colours", -- the body colour
		second = "colours", -- the second colour, for the two-tone and the wrap
		finish = "finishes",
		wrap = "wraps",
	},
	fieldOrder = { "body", "second", "finish", "wrap" },
	stock = { body = "stock", second = "stock", finish = "stock", wrap = "none" },
	colours = {
		{ id = "stock", name = "Stock" },
		{ id = "white", name = "Panda white", colour = Color3.fromRGB(236, 236, 232) },
		{ id = "black", name = "Night black", colour = Color3.fromRGB(22, 22, 26) },
		{ id = "red", name = "Rally red", colour = Color3.fromRGB(200, 30, 36) },
		{ id = "blue", name = "Deep blue", colour = Color3.fromRGB(30, 70, 170) },
		{ id = "yellow", name = "Signal yellow", colour = Color3.fromRGB(245, 200, 30) },
		{ id = "green", name = "Forest green", colour = Color3.fromRGB(30, 110, 60) },
		{ id = "silver", name = "Silver", colour = Color3.fromRGB(170, 174, 180) },
		{ id = "orange", name = "Sunset orange", colour = Color3.fromRGB(240, 110, 30) },
		{ id = "purple", name = "Midnight purple", colour = Color3.fromRGB(70, 30, 110) },
	},
	finishes = {
		{ id = "stock", name = "Stock" },
		{ id = "gloss", name = "Gloss", material = "SmoothPlastic", reflectance = 0.15 },
		{ id = "matte", name = "Matte", material = "SmoothPlastic", reflectance = 0 },
		{ id = "metallic", name = "Metallic", material = "Metal", reflectance = 0.25 },
	},
	wraps = {
		{ id = "none", name = "None" },
		{ id = "stripes", name = "Twin stripes" },
		{ id = "split", name = "Two-tone split" },
		{ id = "checker", name = "Checker" },
		{ id = "hex", name = "Hex" },
	},
}

return Catalog
