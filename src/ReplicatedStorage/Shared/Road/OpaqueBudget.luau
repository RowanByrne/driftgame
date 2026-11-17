--!strict
-- OpaqueBudget: every opaque content this client makes, counted against a cap for the session
-- (T-284, features/ground-trial.md "The mesh budget").
--
-- WHY. `AssetService:CreateDataModelContentAsync` turns a mesh or an image into OPAQUE CONTENT,
-- which holds none of the client's mesh memory (T-274). But its cost builds up with every one a
-- client makes, however few it keeps: past a few thousand the client freezes for seconds at a
-- time (T-276's bench: from about 2 050 made at 5 a second; the same churn not made opaque
-- never froze in 6 000). The road makes one a chunk it builds, for as long as the player drives.
-- The cost is the session's (measured, T-284: a new Studio playtest starts from nothing).
--
-- SO every maker of opaque content goes through `make` here, and past `Config.Spline.Mesh
-- .OpaqueCap` it is refused, as a client that refuses opaque content refuses it: each maker
-- then does what it does there (the road builds as T-273 did, `Road/SplineMesh` "THE
-- FALLBACK"; the others keep their fixed-size copy or EditableImage). Nothing is made opaque
-- again in that session.
--
-- The cap holds on a client only: a server draws nothing in a game (Studio's tests build chunks
-- there, and count). In Studio, `workspace.__opaque_cap` (a number) stands in for the cap, to
-- try the switch, or to bench past it; `workspace.__no_opaque = true` refuses every one (T-274).

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local OpaqueBudget = {}

local made = 0 -- calls made (each one counts, whatever it answered)
local succeeded = 0
local refused = 0 -- answered other than Success, or errored
local declined = 0 -- asked for past the cap: not made
local byWho: { [string]: number } = {}
local declinedBy: { [string]: number } = {}
local capReachedAt: number? = nil -- os.clock() when the first one was declined for the cap
local worstMs = 0 -- the longest a call took (wall time, the frame free meanwhile)
local totalMs = 0

local isStudio = RunService:IsStudio()
local isClient = RunService:IsClient()

-- The cap this session: `Mesh.OpaqueCap`, or in Studio `workspace.__opaque_cap`. math.huge on
-- a server.
function OpaqueBudget.cap(): number
	if isStudio then
		local v = workspace:GetAttribute("__opaque_cap")
		if type(v) == "number" then
			return v
		end
	end
	if not isClient then
		return math.huge
	end
	return Config.Spline.Mesh.OpaqueCap
end

-- Whether one more may be made now. (Studio: `__no_opaque` refuses every one.)
function OpaqueBudget.allows(): boolean
	if isStudio and workspace:GetAttribute("__no_opaque") == true then
		return false
	end
	return made < OpaqueBudget.cap()
end

-- How many more may be made this session.
function OpaqueBudget.left(): number
	return math.max(0, OpaqueBudget.cap() - made)
end

-- Make `source` (an EditableMesh or EditableImage's content) opaque, counted under `who`.
-- Returns (true, content), or false where the cap (or the client) refuses it: the caller keeps
-- what it had. YIELDS, as `CreateDataModelContentAsync` does.
function OpaqueBudget.make(who: string, source: Content): (boolean, Content?)
	if not OpaqueBudget.allows() then
		declined += 1
		declinedBy[who] = (declinedBy[who] or 0) + 1
		if not capReachedAt and made >= OpaqueBudget.cap() then
			capReachedAt = os.clock()
		end
		return false, nil
	end
	made += 1
	byWho[who] = (byWho[who] or 0) + 1
	local t0 = os.clock()
	local ok, result, content = pcall(function()
		return AssetService:CreateDataModelContentAsync(source)
	end)
	local ms = (os.clock() - t0) * 1000
	totalMs += ms
	worstMs = math.max(worstMs, ms)
	if ok and result == Enum.CreateContentResult.Success and content ~= nil then
		succeeded += 1
		return true, content
	end
	refused += 1
	return false, nil
end

function OpaqueBudget.made(): number
	return made
end

function OpaqueBudget.DebugState()
	return {
		made = made,
		succeeded = succeeded,
		refused = refused,
		declined = declined,
		cap = OpaqueBudget.cap(),
		left = OpaqueBudget.left(),
		over = made >= OpaqueBudget.cap(),
		capReachedAt = capReachedAt,
		byWho = table.clone(byWho),
		declinedBy = table.clone(declinedBy),
		meanMs = if made > 0 then totalMs / made else 0,
		worstMs = worstMs,
	}
end

return OpaqueBudget
