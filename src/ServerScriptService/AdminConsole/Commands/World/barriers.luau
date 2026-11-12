return {
	Name = "barriers",
	Description = "Stands the guardrails down or puts them back, for everyone: the test hill's and the piece road's (the spline road has none). The testing HUD's barriers button does the same. No argument toggles them.",
	Group = "World",
	Args = {
		{
			Type = "boolean",
			Name = "on",
			Description = "on or off. Leave it out to toggle.",
			Optional = true,
		},
	},
}
