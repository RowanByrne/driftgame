return {
	Name = "ground",
	Description = "Shows or sets the ground the next spline run is drawn with, for the ground-first trial: current (today's), mesh or terrain. Only between runs.",
	Group = "Run",
	Args = {
		{
			Type = "groundMode",
			Name = "mode",
			Description = "current, mesh or terrain. Leave it out to see the current one.",
			Optional = true,
		},
	},
}
