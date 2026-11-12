return {
	Name = "tp-to",
	Aliases = { "tpto" },
	Description = "Teleports players' cars to a point in the world, facing a heading (degrees, 0 = -Z). Ends a player's run first if the point is off the road.",
	Group = "Teleport",
	Args = {
		{ Type = "players", Name = "players", Description = "Who to move: names, me, all, others." },
		{ Type = "number", Name = "x", Description = "X" },
		{ Type = "number", Name = "y", Description = "Y (the car's ride height above the ground)" },
		{ Type = "number", Name = "z", Description = "Z" },
		{ Type = "number", Name = "heading", Description = "Degrees, 0 faces -Z, 90 faces -X.", Optional = true, Default = 0 },
	},
}
