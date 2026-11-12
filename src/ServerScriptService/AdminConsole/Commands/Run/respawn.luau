return {
	Name = "respawn",
	Description = "Puts players' cars back now, with no cooldown: on the road for anyone in a run (where they were, never behind the closing barrier), otherwise at the spawn of the world they're in.",
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
