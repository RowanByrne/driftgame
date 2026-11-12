return {
	Name = "tp",
	Description = "Teleports players' cars: road (joins the run, or back on it), road <studs> (that far along the spline road; Studio only), playground, track, garage (drives in), hill (the test hill's top), any playground spot by name, or another player (beside their car, on their road if they're in a run). Leaving the road ends that player's run first.",
	Group = "Teleport",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "Who to move: names, me, all, others.",
		},
		{
			Type = "place",
			Name = "place",
			Description = "road, playground, track, garage, hill, a playground spot (Spawn, Boulevard, RampBase...), or a player's name",
		},
		{
			Type = "number",
			Name = "studs",
			Description = "With road: how far along the road from its start. Studio only.",
			Optional = true,
		},
	},
}
