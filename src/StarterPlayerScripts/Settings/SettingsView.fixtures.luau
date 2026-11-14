--!nonstrict
-- Sample data only; the live controller always supplies the current session values.
return {
	steering = { category = "steering", mode = "dynamic", sensitivity = 5 },
	centred = { category = "steering", mode = "centred", sensitivity = 10 },
	interface = { category = "interface", mode = "dynamic", sensitivity = 1 },
	long = { category = "steering", mode = "dynamic", sensitivity = 5,
		modeLabel = "Choose where your steering movement begins on the screen",
		sensitivityLabel = "Pointer sensitivity for your mouse or touch steering movement",
		note = "Higher sensitivity means shorter finger travel. These controls affect pointer steering; keyboard and gamepad steering keep their current response." },
	largest = { category = "steering", mode = "centred", sensitivity = 10, textScale = 1.5, transparency = 0 },
}
