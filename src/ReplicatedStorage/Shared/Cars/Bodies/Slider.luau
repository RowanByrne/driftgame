--!nonstrict
-- The `slider` archetype's body: the stripped drift missile. No roof.
--
-- The archetype slides at a touch and never catches itself, so the shape is the one that
-- was built to be thrown away: long nose, long tail, big arches over all four corners,
-- the roof cut off and a bare roll hoop and two seats left where it was. From behind it
-- is one unbroken light bar, which nothing else here has.

local paint = Color3.fromRGB(232, 46, 142) -- magenta
local trim = Color3.fromRGB(46, 22, 52)
local steel = Color3.fromRGB(186, 190, 198) -- the hoop: bare metal, deliberately not paint
local glass = Color3.fromRGB(26, 30, 38)
local lamp = Color3.fromRGB(255, 246, 214)
local tail = Color3.fromRGB(255, 52, 44)
local rubber = Color3.fromRGB(26, 26, 30)

return {
	Name = "Slider",
	Silhouette = "a long low roadster with the roof cut off: a long flat bonnet, a raked"
		.. " screen, a bare roll hoop over two visible seats, a ducktail, and fat arches over"
		.. " every corner. From behind it is one full-width light bar.",

	For = { Wheelbase = 9.6, TrackWidth = 5.6, WheelDiameter = 2.3, WheelWidth = 1.6 },

	Body = {
		{ n = "Hull", s = { 6.2, 1.5, 14.0 }, p = { 0, 1.5, 0 }, c = paint },
		{ n = "Shoulder", s = { 6.4, 0.8, 13.4 }, p = { 0, 2.65, 0 }, c = paint },

		-- the longest bonnet of the four, falling the whole way to the nose
		{ n = "Bonnet", k = "wedge", s = { 6.0, 0.5, 5.2 }, p = { 0, 3.3, -4.0 }, c = paint },
		{ n = "Cowl", s = { 5.6, 0.5, 1.0 }, p = { 0, 3.3, -1.0 }, c = trim },

		-- a raked screen with nothing above it
		{ n = "Windscreen", s = { 5.4, 1.5, 0.18 }, p = { 0, 3.75, -0.85 }, r = { 32, 0, 0 }, c = glass, rf = 0.2 },

		-- the hoop, and the seats it is there to protect: both visible, because there is
		-- no roof over them
		{ n = "Hoop", s = { 5.0, 0.35, 0.35 }, p = { 0, 4.22, 1.2 }, c = steel },
		{ n = "HoopPost", s = { 0.35, 1.0, 0.35 }, p = { 2.3, 3.55, 1.2 }, c = steel, mir = true },
		{ n = "Seat", s = { 1.2, 1.0, 2.0 }, p = { 1.4, 3.5, 0.6 }, c = trim, mir = true },

		{ n = "Deck", s = { 6.2, 0.5, 3.6 }, p = { 0, 3.3, 5.0 }, c = paint },
		{ n = "Ducktail", s = { 6.2, 0.35, 1.6 }, p = { 0, 3.75, 6.3 }, r = { -9, 0, 0 }, c = trim },
		{ n = "Panel", s = { 6.2, 1.0, 0.5 }, p = { 0, 2.55, 7.1 }, c = paint },

		{ n = "Lip", s = { 6.4, 0.5, 1.2 }, p = { 0, 1.1, -7.6 }, c = trim },
		{ n = "Exhaust", k = "cylinder", s = { 1.0, 0.5, 0.5 }, p = { 0, 1.2, 7.3 }, r = { 0, 90, 0 }, c = steel },

		-- the arches: the widest part of this car, and over all four corners
		{ n = "ArchF", s = { 0.6, 1.1, 3.4 }, p = { 3.15, 2.1, -4.8 }, c = paint, mir = true },
		{ n = "ArchR", s = { 0.6, 1.1, 3.4 }, p = { 3.15, 2.1, 4.8 }, c = paint, mir = true },

		{ n = "Head", s = { 1.3, 0.45, 0.35 }, p = { 2.0, 2.9, -7.05 }, c = lamp, m = "Neon", mir = true },
		-- ONE bar, full width: the signature from behind
		{ n = "LightBar", s = { 5.6, 0.45, 0.3 }, p = { 0, 2.75, 7.45 }, c = tail, m = "Neon" },
	},

	Wheel = {
		{ n = "Tire", k = "cylinder", s = { 1.6, 2.3, 2.3 }, p = { 0, 0, 0 }, c = rubber },
		{ n = "Rim", k = "cylinder", s = { 0.75, 1.45, 1.45 }, p = { 0.5, 0, 0 }, c = Color3.fromRGB(150, 60, 190) },
	},
}
