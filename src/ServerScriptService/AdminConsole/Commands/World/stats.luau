local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local SAMPLE_SECONDS = 0.5

return {
	Name = "stats",
	Description = "Frame rate, frame time, memory and ping on your screen, then the server's heartbeat and memory. Takes half a second to measure.",
	Group = "World",
	Args = {},
	ClientRun = function(context)
		local frames, worst, total = 0, 0, 0
		local connection = RunService.RenderStepped:Connect(function(dt)
			frames += 1
			total += dt
			worst = math.max(worst, dt)
		end)
		task.wait(SAMPLE_SECONDS)
		connection:Disconnect()
		local fps = if total > 0 then frames / total else 0
		context:Reply(
			string.format(
				"Client: %.0f fps (worst frame %.1f ms), %.0f MB memory, ping %.0f ms, receiving %.1f KB/s, sending %.1f KB/s.",
				fps,
				worst * 1000,
				Stats:GetTotalMemoryUsageMb(),
				Players.LocalPlayer:GetNetworkPing() * 1000,
				Stats.DataReceiveKbps,
				Stats.DataSendKbps
			)
		)
		return nil -- and the server's own numbers
	end,
}
