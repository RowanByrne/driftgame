--!nonstrict
-- Smoked glass, approved for settings (T-201). All material and type tokens live here.
local Theme = {
	Color = {
		Surface = Color3.fromRGB(20, 25, 29), Tile = Color3.fromRGB(35, 42, 47),
		Text = Color3.fromRGB(244, 245, 244), Secondary = Color3.fromRGB(191, 201, 207),
		Accent = Color3.fromRGB(242, 158, 82), OnAccent = Color3.fromRGB(23, 27, 30),
		Rim = Color3.fromRGB(122, 137, 146), Focus = Color3.fromRGB(255, 255, 255),
		Track = Color3.fromRGB(122, 136, 144), Disabled = Color3.fromRGB(115, 124, 131),
	},
	Font = Font.fromEnum(Enum.Font.GothamMedium), Heading = Font.fromEnum(Enum.Font.GothamBold),
	Radius = 16, TileRadius = 10, Target = 48, BodySize = 18, SecondarySize = 16,
	PaneTransparency = 0.26, TileTransparency = 0.42, Blur = 12,
}
return Theme
