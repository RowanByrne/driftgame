--!nonstrict
-- The `balanced` archetype's body: the upright three-box coupe, the middle of the four.
--
-- A BODY IS A TABLE, not code (`Shared/Cars/Bodies`). Y is measured UP FROM THE ROAD,
-- front is -Z, right is +X, and `mir = true` builds the mirror image at -x as well. The
-- geometry in `For` is the car geometry this was drawn against; the builder scales it
-- onto whatever the active archetype actually has, so the wheels stay where the ground
-- rays go.

local paint = Color3.fromRGB(228, 230, 234) -- signal white: the plain one
local trim = Color3.fromRGB(40, 42, 48)
local glass = Color3.fromRGB(22, 26, 32)
local accent = Color3.fromRGB(196, 62, 54) -- the block car's red, kept as its stripe
local lamp = Color3.fromRGB(255, 246, 214)
local tail = Color3.fromRGB(255, 52, 44)
local rubber = Color3.fromRGB(26, 26, 30)

return {
	Name = "Balanced",
	Silhouette = "an upright three-box coupe: a bonnet, a tall glasshouse set back over the"
		.. " rear wheels, a short boot deck, and two upright tail lights. The one with a roof"
		.. " and nothing sticking out of it.",

	For = { Wheelbase = 9.6, TrackWidth = 5.6, WheelDiameter = 2.3, WheelWidth = 1.6 },

	Body = {
		-- the hull, in two decks so there is a shoulder line rather than one slab
		{ n = "Hull", s = { 6.4, 1.5, 13.2 }, p = { 0, 1.45, 0 }, c = paint },
		{ n = "Shoulder", s = { 6.7, 0.9, 12.6 }, p = { 0, 2.65, 0 }, c = paint },

		-- bonnet: a wedge falls from the base of the screen to the nose
		{ n = "Bonnet", k = "wedge", s = { 6.2, 0.55, 4.2 }, p = { 0, 3.375, -3.9 }, c = paint },

		-- the glasshouse, upright and set back: the shape you name it by
		{ n = "Cabin", s = { 5.9, 1.5, 5.4 }, p = { 0, 3.85, 0.9 }, c = glass, rf = 0.15 },
		{ n = "Windscreen", k = "wedge", s = { 5.7, 1.5, 1.8 }, p = { 0, 3.85, -2.7 }, c = glass, rf = 0.15 },
		{
			n = "Backlight",
			k = "wedge",
			s = { 5.7, 1.5, 1.6 },
			p = { 0, 3.85, 4.4 },
			r = { 0, 180, 0 },
			c = glass,
			rf = 0.15,
		},
		{ n = "Roof", s = { 5.5, 0.3, 4.4 }, p = { 0, 4.75, 1.1 }, c = trim },

		{ n = "Deck", s = { 6.3, 0.5, 2.6 }, p = { 0, 3.35, 5.6 }, c = paint },

		-- bumpers and the grille
		{ n = "BumperF", s = { 6.7, 1.0, 1.0 }, p = { 0, 1.6, -6.6 }, c = trim },
		{ n = "BumperR", s = { 6.7, 1.0, 1.0 }, p = { 0, 1.6, 6.9 }, c = trim },
		{ n = "Grille", s = { 4.0, 0.6, 0.3 }, p = { 0, 2.3, -7.15 }, c = trim },

		-- mirrored: a stripe down each flank, an arch over each wheel
		{ n = "Stripe", s = { 0.14, 0.35, 12.6 }, p = { 3.36, 2.65, 0 }, c = accent, mir = true },
		{ n = "ArchF", s = { 0.55, 1.0, 3.2 }, p = { 3.3, 2.0, -4.8 }, c = paint, mir = true },
		{ n = "ArchR", s = { 0.55, 1.0, 3.2 }, p = { 3.3, 2.0, 4.8 }, c = paint, mir = true },

		-- lights: a pair of wide headlights, a pair of UPRIGHT tail lights
		{ n = "Head", s = { 1.5, 0.5, 0.35 }, p = { 2.2, 2.9, -7.1 }, c = lamp, m = "Neon", mir = true },
		{ n = "Tail", s = { 1.3, 1.0, 0.35 }, p = { 2.4, 2.9, 7.35 }, c = tail, m = "Neon", mir = true },
	},

	-- One wheel; x is measured OUTWARD, away from the car, and the builder draws all four.
	Wheel = {
		{ n = "Tire", k = "cylinder", s = { 1.6, 2.3, 2.3 }, p = { 0, 0, 0 }, c = rubber },
		{ n = "Rim", k = "cylinder", s = { 0.75, 1.45, 1.45 }, p = { 0.5, 0, 0 }, c = Color3.fromRGB(198, 200, 206) },
	},
}
