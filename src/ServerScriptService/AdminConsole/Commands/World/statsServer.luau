local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local SAMPLE_SECONDS = 0.5

return function(): string
	local frames, worst, total = 0, 0, 0
	local connection = RunService.Heartbeat:Connect(function(dt)
		frames += 1
		total += dt
		worst = math.max(worst, dt)
	end)
	task.wait(SAMPLE_SECONDS)
	connection:Disconnect()
	return string.format(
		"Server: %.0f heartbeats/s (worst %.1f ms), physics %.0f fps, %.0f MB memory, %d player(s), up %.0f s.",
		if total > 0 then frames / total else 0,
		worst * 1000,
		workspace:GetRealPhysicsFPS(),
		Stats:GetTotalMemoryUsageMb(),
		#Players:GetPlayers(),
		workspace.DistributedGameTime
	)
end
