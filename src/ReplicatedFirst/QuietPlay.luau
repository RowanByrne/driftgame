--!strict
-- QuietPlay: an agent's playtest makes no sound (docs/workflow/TESTING.md "Studio test kit").
-- Sounds and music ask this before they play. It is only ever true in Studio.

local RunService = game:GetService("RunService")

local WINDOW_SECONDS = 60

local QuietPlay = {}

function QuietPlay.isQuiet(): boolean
	if not RunService:IsStudio() then
		return false
	end
	-- The deliberate audio test: set workspace.__studio_audio, and clear it afterwards.
	if workspace:GetAttribute("__studio_audio") == true then
		return false
	end
	local marker = workspace:GetAttribute("__agent_play")
	if typeof(marker) ~= "number" then
		return false
	end
	return (DateTime.now().UnixTimestamp - (marker :: number)) <= WINDOW_SECONDS
end

return QuietPlay
