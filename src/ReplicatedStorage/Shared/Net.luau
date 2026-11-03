--!strict
-- Net: the remotes registry (docs/workflow/CODING.md "Foundation kit").
-- The server creates every remote in its service's Init; the client waits for them.
-- Every remote is listed in docs/game/CONTRACTS.md. Names are flat: <Feature><Action>.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local WAIT_SECONDS = 20

local folder: Folder
if IS_SERVER then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes", WAIT_SECONDS) :: Folder
	if not folder then
		error("Net: ReplicatedStorage.Remotes never appeared; is the server loader running?")
	end
end

local function get(name: string, className: string): Instance
	local existing = folder:FindFirstChild(name)
	if not existing and not IS_SERVER then
		existing = folder:WaitForChild(name, WAIT_SECONDS)
		if not existing then
			error(`Net: the client waited {WAIT_SECONDS}s for remote '{name}' and it never appeared`)
		end
	end

	if existing then
		if existing.ClassName ~= className then
			error(`Net: remote '{name}' is a {existing.ClassName}, asked for as a {className}`)
		end
		return existing
	end

	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

local Net = {}

function Net.event(name: string): RemoteEvent
	return get(name, "RemoteEvent") :: RemoteEvent
end

-- For state sent every frame or two, where a dropped packet is better than a late one.
function Net.unreliable(name: string): UnreliableRemoteEvent
	return get(name, "UnreliableRemoteEvent") :: UnreliableRemoteEvent
end

function Net.func(name: string): RemoteFunction
	return get(name, "RemoteFunction") :: RemoteFunction
end

return Net
