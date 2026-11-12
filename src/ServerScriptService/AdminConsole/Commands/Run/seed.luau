return {
	Name = "seed",
	Description = "Shows the road's seed. With a seed, restarts your run on the road that seed lays (only when nobody else is on the road).",
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
