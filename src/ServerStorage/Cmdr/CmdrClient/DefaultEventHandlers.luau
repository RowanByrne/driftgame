const TextChatService = game:GetService("TextChatService")

-- LOCAL PATCH (Drift, T-159; docs/game/ARCHITECTURE.md "Vendored libraries"): upstream waits
-- for `TextChatService.TextChannels.RBXSystem` when this module is required, which never
-- comes on a place still on LegacyChatService, and the whole client then hangs on require.
-- The channel is looked up when an announcement arrives instead, and an announcement with no
-- channel goes to the console window.
const function systemChannel(): TextChannel?
	const channels = TextChatService:FindFirstChild("TextChannels")
	const channel = channels and channels:FindFirstChild("RBXSystem")
	return if channel and channel:IsA("TextChannel") then channel else nil
end

return function(CmdrClient)
	CmdrClient:HandleEvent("Message", function(text: string)
		const RBXSystem = systemChannel()
		if RBXSystem then
			RBXSystem:DisplaySystemMessage(`<font color="rgb(249, 217, 56)">[Announcement] {text}</font>`)
		else
			CmdrClient._interface.Window:AddLine(`[Announcement] {text}`)
		end
	end)

	CmdrClient:HandleEvent("AddLine", function(...: any)
		CmdrClient._interface.Window:AddLine(...)
	end)

	CmdrClient:HandleEvent("RunBeforeCommandRegisterHooks", function()
		CmdrClient.Dispatcher:RunBeforeCommandRegisterHooks()
	end)
end
