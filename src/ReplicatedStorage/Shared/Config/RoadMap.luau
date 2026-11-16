--!strict
-- RoadMap: every number the road-ahead map is drawn with (features/road-ahead-map.md, T-234),
-- and none of them in the logic.
--
-- The map is a see-through panel in the top left that draws the next stretch of the spline
-- road as a line, with an arrow for the car. ROAD-UP (the user, 2026-11-15): the road's own
-- direction at the car is up, so the map turns only as the road bends, never with a drift;
-- the arrow turns to show the car's nose against the road.

return {
	-- ------------------------------------------------------------------ the panel
	-- Chosen from the measured screen, never a guess at the device: a screen whose short
	-- side is under `PhoneBelow` px gets the phone size.
	Size = 220, -- px square, on a big screen
	PhoneSize = 140, -- px square, on a small one
	PhoneBelow = 500, -- px: the short side below which the screen is small
	Margin = 16, -- px from the top left of the safe area (below Roblox's top bar)
	Inset = 8, -- px inside the panel's edge where the line is cut off
	PanelColor = Color3.fromRGB(20, 25, 29), -- `UI/Theme` Surface
	PanelTransparency = 0.6,
	RimColor = Color3.fromRGB(122, 137, 146), -- `UI/Theme` Rim
	RimTransparency = 0.6,
	CornerRadius = 12, -- px

	-- THE TOP CENTRE IS TAKEN: the run button, its line and the score panel make a column
	-- `CentreColumn` px wide down to `ScoreBottom` px below the inset. On a screen too
	-- narrow for the map to sit beside that column (phone portrait), it drops below it.
	CentreColumn = 220, -- px
	CentreGap = 8, -- px kept clear between the map and the column
	ScoreBottom = 146, -- px below the inset: the score panel's bottom (80 + 58) and a gap

	-- ------------------------------------------------------------------- the road
	AheadStuds = 800, -- road drawn in front of the car
	BehindStuds = 100, -- and the tail behind it
	PointEvery = 16, -- studs between the line's points
	-- How many studs fit from the arrow to the panel's top edge (less `Inset`): the scale.
	-- 800 makes a straight road run exactly to the top; a winding one stays well inside.
	StudsToTop = 800,
	ArrowFromBottom = 0.22, -- share of the panel's height the arrow sits above its bottom

	LineColor = Color3.fromRGB(244, 245, 244), -- `UI/Theme` Text: off-white
	LineTransparency = 0.15,
	BehindTransparency = 0.55, -- the tail already driven, fainter
	LineWidth = 4, -- px on a big screen
	PhoneLineWidth = 3, -- px on a small one

	-- A TIGHT BEND is any stretch whose radius is `TightRadius` studs or less: drawn orange
	-- and thicker, so a hairpin reads before it is in view.
	TightRadius = 220, -- studs
	TightColor = Color3.fromRGB(242, 158, 82), -- `UI/Theme` Accent, #f29e52
	TightExtraWidth = 2, -- px on top of the line's width

	-- ------------------------------------------------------------------ the arrow
	ArrowColor = Color3.fromRGB(255, 255, 255),
	ArrowSize = 22, -- px, the glyph's height on a big screen
	PhoneArrowSize = 16,
	-- the car's sideways place on the road is drawn true, but never more than this far off
	-- the line: a car on the grass still reads as on the road
	ArrowMaxOffset = 14, -- px

	-- ----------------------------------------------------------------- the timing
	RedrawHz = 20, -- times a second the line is recomputed
	-- The up direction follows the road's heading at the car through a smoothing of this
	-- many seconds, so a hairpin turns the map round rather than snapping it.
	TurnSmoothing = 0.35, -- seconds
	-- How far off the road (studs from the centre line) the car may be and still be found
	-- by search after a respawn or a teleport; past it the map holds its last place.
	SearchReach = 200,
}
