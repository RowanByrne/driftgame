return {
	Name = "garage-out",
	Aliases = { "garageout" },
	Description = "Drives players' cars out of the garage, as the Drive out button does.",
	Group = "Teleport",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "Who: names, me, all, others. Leave it out for yourself.",
			Optional = true,
		},
	},
}
