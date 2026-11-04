--!nonstrict
-- The `bruiser` archetype's body: tall, boxy and heavy.
--
-- The archetype carries speed in a straight line and has to be turned early, so the shape
-- is the one that looks like it weighs something: the longest and tallest of the four,
-- flat panels and square corners everywhere, a dark slab of chassis under a high
-- shoulder, a bonnet scoop, a bull bar at each end and twin exhausts. From behind it is
-- two wide horizontal light bars, high up.

local paint = Color3.fromRGB(242, 140, 24) -- amber
local trim = Color3.fromRGB(38, 33, 28) -- the heavy black steel it is all bolted to
local glass = Color3.fromRGB(20, 20, 24)
local lamp = Color3.fromRGB(255, 240, 196)
local tail = Color3.fromRGB(255, 52, 44)
local rubber = Color3.fromRGB(26, 26, 30)

return {
	Name = "Bruiser",
	Silhouette = "a tall square slab: a dark chassis under an amber body, a flat high"
		.. " bonnet with a scoop, an upright cab with the tallest roof here, bull bars at both"
		.. " ends and twin pipes. From behind it is two wide horizontal light bars.",

	For = { Wheelbase = 9.6, TrackWidth = 5.6, WheelDiameter = 2.3, WheelWidth = 1.6 },

	Body = {
		-- the dark chassis slab, and the body riding high on top of it
		{ n = "Chassis", s = { 7.0, 1.8, 14.6 }, p = { 0, 1.5, 0 }, c = trim },
		{ n = "Hull", s = { 7.2, 1.7, 14.0 }, p = { 0, 3.25, 0 }, c = paint },

		-- a flat bonnet: no wedge anywhere on this car
		{ n = "Bonnet", s = { 6.8, 0.5, 5.6 }, p = { 0, 4.35, -4.2 }, c = paint },
		{ n = "Scoop", s = { 2.2, 0.7, 2.2 }, p = { 0, 4.9, -3.4 }, c = trim },

		-- the cab, upright and square, with the highest roof of the four
		{ n = "Cabin", s = { 6.5, 1.4, 5.2 }, p = { 0, 4.8, 1.6 }, c = glass, rf = 0.1 },
		{ n = "Windscreen", k = "wedge", s = { 6.4, 1.4, 1.6 }, p = { 0, 4.8, -1.8 }, c = glass, rf = 0.1 },
		{
			n = "Backlight",
			k = "wedge",
			s = { 6.4, 1.4, 1.4 },
			p = { 0, 4.8, 4.9 },
			r = { 0, 180, 0 },
			c = glass,
			rf = 0.1,
		},
		{ n = "Roof", s = { 6.3, 0.4, 5.6 }, p = { 0, 5.7, 1.6 }, c = trim },
		{ n = "Deck", s = { 6.8, 0.5, 2.6 }, p = { 0, 4.35, 6.0 }, c = paint },

		-- bull bars: the widest thing on the car, at both ends
		{ n = "BarF", s = { 7.4, 1.3, 1.2 }, p = { 0, 2.2, -7.4 }, c = trim },
		{ n = "BarR", s = { 7.4, 1.3, 1.2 }, p = { 0, 2.2, 7.4 }, c = trim },

		{ n = "ArchF", s = { 0.7, 1.7, 4.2 }, p = { 3.3, 2.6, -4.8 }, c = paint, mir = true },
		{ n = "ArchR", s = { 0.7, 1.7, 4.2 }, p = { 3.3, 2.6, 4.8 }, c = paint, mir = true },
		{ n = "Sill", s = { 0.6, 0.5, 7.0 }, p = { 3.3, 1.0, 0.2 }, c = trim, mir = true },
		{ n = "Pipe", k = "cylinder", s = { 1.2, 0.75, 0.75 }, p = { 1.8, 1.3, 7.9 }, r = { 0, 90, 0 }, c = trim, mir = true },

		{ n = "Head", s = { 1.7, 0.9, 0.35 }, p = { 2.4, 3.4, -8.05 }, c = lamp, m = "Neon", mir = true },
		-- two WIDE horizontal bars, high on the tail
		{ n = "Tail", s = { 2.5, 0.6, 0.35 }, p = { 2.0, 3.8, 8.05 }, c = tail, m = "Neon", mir = true },
	},

	Wheel = {
		{ n = "Tire", k = "cylinder", s = { 1.6, 2.3, 2.3 }, p = { 0, 0, 0 }, c = rubber },
		{ n = "Rim", k = "cylinder", s = { 0.8, 1.3, 1.3 }, p = { 0.48, 0, 0 }, c = Color3.fromRGB(96, 98, 104) },
	},
}
