return {
	Name = "tp",
	Description = "Teleports your car: road (joins the run, or back on it), road <studs> (that far along the spline road; Studio only), playground, track, garage (drives you in), hill (the test hill's top), or any playground spot by name.",
	Group = "Teleport",
	Args = {
		{
			Type = "place",
			Name = "place",
			Description = "road, playground, track, garage, hill, or a playground spot (Spawn, Boulevard, RampBase...)",
		},
		{
			Type = "number",
			Name = "studs",
			Description = "With road: how far along the road from its start. Studio only.",
			Optional = true,
		},
	},
}
