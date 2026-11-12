return {
	Name = "seed",
	Description = "Shows the road's seed. With a seed, lays the road again from that seed and puts everyone who was on it back at its start (with no road up, starts a run for you on it).",
	Group = "Run",
	Args = {
		{
			Type = "integer",
			Name = "seed",
			Description = "The seed to drive. Leave it out to see the current one.",
			Optional = true,
		},
	},
}
