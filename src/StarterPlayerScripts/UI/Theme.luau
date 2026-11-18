--!nonstrict
-- Smoked glass, approved for settings (T-201). All material and type tokens live here.
local Theme = {
	ScoreTape = {
		ink = Color3.fromHex("F0F8FF"), secondary = Color3.fromHex("D5E6FA"),
		shadow = Color3.fromHex("090E19"), lost = Color3.fromHex("FFC0AF"), track = Color3.fromHex("495569"),
		rankFont = Font.new("rbxasset://fonts/families/RobotoCondensed.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic),
		feedFont = Font.new("rbxasset://fonts/families/RobotoCondensed.json", Enum.FontWeight.Bold),
		numberFont = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.SemiBold),
		-- Accent, unfilled lettering and the left edge of the charged tape.
		inks = {
			{"E3E7EC", "A0A7B3", "CAD0D9"}, {"C4D7EB", "A0AEBD", "ABBBCB"},
			{"A8DEF8", "8CA8C3", "80BADB"}, {"70F1FF", "88AEC4", "4CA4E1"},
			{"BDA0FF", "A9A3CA", "5AAAFA"}, {"D4AAFF", "ADA3C8", "8D74F5"},
			{"EDA5F9", "B3A2C9", "9E72FF"}, {"8DF4FF", "99B9CF", "977DFF"},
			{"C2FFF1", "A0C4BE", "60DFFF"},
		},
	},
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
