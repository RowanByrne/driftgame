return {
	Name = "run-info",
	Aliases = { "runinfo" },
	Description = "Shows the endless run: whether a road is up, its seed and mode, who's on it, and where a player is along it.",
	Group = "Run",
	Args = {
		{
			Type = "player",
			Name = "player",
			Description = "Whose place on the road to show. Leave it out for yourself.",
			Optional = true,
		},
	},
}
