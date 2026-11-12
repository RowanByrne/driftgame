return {
	Name = "road-mode",
	Aliases = { "roadmode" },
	Description = "Shows or sets which road the next run lays: the spline road or the old pieces. Only between runs.",
	Group = "Run",
	Args = {
		{
			Type = "roadMode",
			Name = "mode",
			Description = "spline or pieces. Leave it out to see the current one.",
			Optional = true,
		},
	},
}
