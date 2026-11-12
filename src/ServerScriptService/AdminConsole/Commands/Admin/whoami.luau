return {
	Name = "whoami",
	Description = "Says whether the server lets a player use the admin console, and why (Studio, the owner, or the admin list).",
	Group = "Admin",
	Args = {
		{
			Type = "player",
			Name = "player",
			Description = "Who to ask about. Leave it out for yourself.",
			Optional = true,
		},
	},
}
