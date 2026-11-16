--!nonstrict
-- Sample data only; the live controller always supplies the current session values.
local groundNames = { "Light", "Low", "Medium", "High", "Ultra" }
local behindNames = { "Short", "Medium", "Long", "Longest" }
local aheadNames = { "Short", "Medium", "Long", "Longest" }
return {
	steering = { category = "steering", mode = "dynamic", sensitivity = 5 },
	centred = { category = "steering", mode = "centred", sensitivity = 10 },
	interface = { category = "interface", mode = "dynamic", sensitivity = 1 },
	graphics = { category = "graphics", mode = "dynamic", sensitivity = 5, groundDetail = 3, groundNames = groundNames, roadAhead = 2, aheadNames = aheadNames, roadBehind = 1, behindNames = behindNames },
	sound = { category = "sound", mode = "dynamic", sensitivity = 5,
		soundLevels = { Music = 30, TireSqueal = 30, OffRoad = 15, Suspension = 70, Engine = 0 } },
	largestSound = { category = "sound", mode = "dynamic", sensitivity = 5, textScale = 1.5, transparency = 0,
		soundLevels = { Music = 0, TireSqueal = 35, OffRoad = 100, Suspension = 30, Engine = 30 } },
	long = { category = "steering", mode = "dynamic", sensitivity = 5,
		modeLabel = "Choose where your steering movement begins on the screen",
		sensitivityLabel = "Pointer sensitivity for your mouse or touch steering movement",
		note = "Higher sensitivity means shorter finger travel. These controls affect pointer steering; keyboard and gamepad steering keep their current response." },
	largest = { category = "steering", mode = "centred", sensitivity = 10, textScale = 1.5, transparency = 0 },
	largestGraphics = { category = "graphics", mode = "dynamic", sensitivity = 5, groundDetail = 5, groundNames = groundNames, roadAhead = 4, aheadNames = aheadNames, roadBehind = 4, behindNames = behindNames, textScale = 1.5, transparency = 0 },
}
