return {
	Name = "tp-to",
	Aliases = { "tpto" },
	Description = "Teleports your car to a point in the world, facing a heading (degrees, 0 = -Z). Ends your run first if you're in one and the point is off the road.",
	Group = "Teleport",
	Args = {
		{ Type = "number", Name = "x", Description = "X" },
		{ Type = "number", Name = "y", Description = "Y (the car's ride height above the ground)" },
		{ Type = "number", Name = "z", Description = "Z" },
		{ Type = "number", Name = "heading", Description = "Degrees, 0 faces -Z, 90 faces -X.", Optional = true, Default = 0 },
	},
}
