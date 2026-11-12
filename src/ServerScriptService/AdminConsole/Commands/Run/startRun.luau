return {
	Name = "start-run",
	Aliases = { "startrun" },
	Description = "Starts an endless run for players, as the start button does (everyone joins the one road). With a seed, lays the road from that seed first (only when no road is up).",
	Group = "Run",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "Who: names, me, all, others. Leave it out for yourself.",
			Optional = true,
		},
		{
			Type = "integer",
			Name = "seed",
			Description = "The road's seed. Leave it out for a fresh one.",
			Optional = true,
		},
	},
}
