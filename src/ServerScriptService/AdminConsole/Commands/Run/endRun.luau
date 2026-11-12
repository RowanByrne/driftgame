return {
	Name = "end-run",
	Aliases = { "endrun" },
	Description = "Ends players' endless runs and puts each back in the world they started from, as the end button does.",
	Group = "Run",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "Who: names, me, all, others. Leave it out for yourself.",
			Optional = true,
		},
	},
}
