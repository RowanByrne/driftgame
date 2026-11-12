return {
	Name = "start-run",
	Aliases = { "startrun" },
	Description = "Starts an endless run for you, as the start button does. With a seed, lays the road from that seed (only when no road is up).",
	Group = "Run",
	Args = {
		{
			Type = "integer",
			Name = "seed",
			Description = "The road's seed. Leave it out for a fresh one.",
			Optional = true,
		},
	},
}
