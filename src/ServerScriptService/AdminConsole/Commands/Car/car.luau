return {
	Name = "car",
	Description = "Switches players into another car archetype, as the car button does. With no car named, lists the cars and says which each player is in.",
	Group = "Car",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "Who: names, me, all, others.",
		},
		{
			Type = "car",
			Name = "car",
			Description = "The archetype: liftback, balanced, gripper, slider, bruiser...",
			Optional = true,
		},
	},
}
