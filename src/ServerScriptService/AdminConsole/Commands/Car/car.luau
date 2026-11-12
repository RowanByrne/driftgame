return {
	Name = "car",
	Description = "Switches you into another car archetype, as the car button does. With no car named, lists them and says which you're in.",
	Group = "Car",
	Args = {
		{
			Type = "car",
			Name = "car",
			Description = "The archetype: liftback, balanced, gripper, slider, bruiser...",
			Optional = true,
		},
	},
}
