--!nonstrict
-- The `gripper` archetype's body: low, wide, and all aerodynamics.
--
-- The archetype is the one that corners on rails and has to be provoked into a slide, so
-- the shape is the one that looks like it is pressed into the road: the lowest roof of
-- the four, the widest track-to-track, a splitter out front, skirts down each side and a
-- rear wing that is the first thing you see from behind.

local paint = Color3.fromRGB(0, 186, 196) -- cyan: nothing else on the road is this colour
local trim = Color3.fromRGB(18, 20, 24) -- the aero, all of it matt black
local glass = Color3.fromRGB(16, 20, 26)
local accent = Color3.fromRGB(240, 248, 250)
local lamp = Color3.fromRGB(226, 246, 255)
local tail = Color3.fromRGB(255, 52, 44)
local rubber = Color3.fromRGB(26, 26, 30)

return {
	Name = "Gripper",
	Silhouette = "low, wide and wedge-shaped: a long flat nose on a splitter, a cockpit"
		.. " canopy barely above the wheels, a fastback tail, and a full-width rear wing on"
		.. " two posts. From behind it is the wing and four small square lights.",

	For = { Wheelbase = 9.6, TrackWidth = 5.6, WheelDiameter = 2.3, WheelWidth = 1.6 },

	Body = {
		-- the hull: shallow, and the lowest of the four
		{ n = "Floor", s = { 7.0, 1.0, 12.6 }, p = { 0, 1.1, 0 }, c = paint },
		{ n = "Shoulder", s = { 7.1, 0.8, 12.0 }, p = { 0, 2.0, 0 }, c = paint },

		-- a long wedge nose falling the whole way to the splitter
		{ n = "Nose", k = "wedge", s = { 6.4, 0.7, 4.6 }, p = { 0, 2.75, -3.6 }, c = paint },

		-- the canopy: 3.65 studs of roof, a stud and a quarter lower than the balanced car
		{ n = "Canopy", s = { 4.9, 1.0, 3.4 }, p = { 0, 2.9, 0.6 }, c = glass, rf = 0.2 },
		{ n = "Windscreen", k = "wedge", s = { 4.9, 1.0, 1.4 }, p = { 0, 2.9, -1.8 }, c = glass, rf = 0.2 },
		{ n = "Roof", s = { 4.5, 0.25, 2.6 }, p = { 0, 3.525, 0.7 }, c = trim },
		{ n = "Fastback", k = "wedge", s = { 6.0, 1.0, 3.4 }, p = { 0, 2.9, 4.0 }, r = { 0, 180, 0 }, c = paint },
		{ n = "Panel", s = { 6.4, 1.2, 0.4 }, p = { 0, 2.1, 5.9 }, c = paint },

		-- the aero, which is the whole point of this one
		{ n = "Splitter", s = { 7.6, 0.25, 2.2 }, p = { 0, 0.5, -5.9 }, c = trim },
		{ n = "Diffuser", s = { 7.0, 0.5, 1.8 }, p = { 0, 0.75, 5.9 }, c = trim },
		{ n = "Wing", s = { 7.0, 0.25, 1.9 }, p = { 0, 4.62, 6.1 }, r = { 6, 0, 0 }, c = trim },
		{ n = "WingPost", s = { 0.3, 1.7, 0.7 }, p = { 2.0, 3.65, 6.0 }, c = trim, mir = true },
		{ n = "Skirt", s = { 0.5, 0.55, 7.2 }, p = { 3.45, 0.85, 0.2 }, c = trim, mir = true },
		{ n = "Canard", s = { 1.0, 0.2, 0.9 }, p = { 3.0, 1.75, -5.4 }, c = accent, mir = true },

		-- lights: slit headlights, and FOUR small square tail lights
		{ n = "Head", s = { 1.9, 0.3, 0.35 }, p = { 2.0, 2.55, -5.95 }, c = lamp, m = "Neon", mir = true },
		{ n = "TailIn", s = { 0.8, 0.8, 0.3 }, p = { 1.4, 2.5, 6.2 }, c = tail, m = "Neon", mir = true },
		{ n = "TailOut", s = { 0.8, 0.8, 0.3 }, p = { 2.7, 2.5, 6.2 }, c = tail, m = "Neon", mir = true },
	},

	Wheel = {
		{ n = "Tire", k = "cylinder", s = { 1.6, 2.3, 2.3 }, p = { 0, 0, 0 }, c = rubber },
		{ n = "Rim", k = "cylinder", s = { 0.75, 1.5, 1.5 }, p = { 0.5, 0, 0 }, c = Color3.fromRGB(236, 196, 40) },
	},
}
