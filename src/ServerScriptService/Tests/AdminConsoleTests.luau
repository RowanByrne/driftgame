--!nonstrict
-- AdminConsoleTests: who may use the admin console, and how often
-- (features/admin-console.md "Testing", T-159). The permission rule is asked with made-up
-- contexts, so a live server's answer is checked from Studio: a stranger on a live server is
-- refused, the owner and the listed admins are let in, and Studio lets everyone in. Run it:
--   game.ServerStorage.DebugBridge:Invoke("DebugAdminConsoleTests", "run")
--
-- With a playtest running it also checks the live registry: every command has a group and a
-- description, so `help` reads well.

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

assert(RunService:IsStudio(), "AdminConsoleTests is Studio only")

local CmdrService = require(ServerScriptService.Services.CmdrService)

local Tests = {}

local OWNER = 1001
local ADMIN = 2002
local STRANGER = 3003

local function live(over)
	local ctx = {
		studio = false,
		creatorType = "User",
		creatorId = OWNER,
		groupRank = nil,
		admins = { ADMIN },
	}
	for k, v in over or {} do
		ctx[k] = v
	end
	return ctx
end

function Tests.run()
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local function ask(userId, ctx)
		local ok, why = CmdrService.allowed(userId, ctx)
		return ok, why
	end

	-- Live, user-owned game
	local ok, why = ask(STRANGER, live())
	check("live: a stranger is refused", ok == false, why)
	ok, why = ask(OWNER, live())
	check("live: the owner is let in", ok == true and why == "owner", why)
	ok, why = ask(ADMIN, live())
	check("live: a listed admin is let in", ok == true and why == "admin list", why)
	ok, why = ask(STRANGER, live({ admins = {} }))
	check("live: an empty admin list lets nobody else in", ok == false, why)
	ok, why = ask(0, live())
	check("live: user id 0 is refused", ok == false, why)
	ok, why = ask(-1, live({ creatorId = -1 }))
	check("live: a negative id matching a bad creator id is refused", ok == false, why)

	-- Live, group-owned game: only the group's owner (rank 255)
	ok, why = ask(STRANGER, live({ creatorType = "Group", creatorId = 777, groupRank = 0 }))
	check("group: a non-member is refused", ok == false, why)
	ok, why = ask(STRANGER, live({ creatorType = "Group", creatorId = 777, groupRank = 254 }))
	check("group: a rank below owner is refused", ok == false, why)
	ok, why = ask(STRANGER, live({ creatorType = "Group", creatorId = 777, groupRank = 255 }))
	check("group: the group's owner is let in", ok == true and why == "group owner", why)
	ok, why = ask(STRANGER, live({ creatorType = "Group", creatorId = STRANGER, groupRank = 0 }))
	check("group: a user whose id equals the group id is not the owner", ok == false, why)
	ok, why = ask(ADMIN, live({ creatorType = "Group", creatorId = 777, groupRank = 0 }))
	check("group: a listed admin is let in", ok == true, why)

	-- Studio
	ok, why = ask(STRANGER, live({ studio = true, admins = {} }))
	check("studio: everyone is let in", ok == true and why == "studio", why)

	-- The rate limit: PerSecond in a second, PerMinute in a minute
	local entry = nil
	local passed = 0
	for _ = 1, 10 do
		local fine
		fine, entry = CmdrService.rate(entry, 100, 3, 50)
		passed += if fine then 1 else 0
	end
	check("rate: 3 a second lets 3 of 10 through", passed == 3, tostring(passed))
	local fine
	fine, entry = CmdrService.rate(entry, 101.01, 3, 50)
	check("rate: the next second lets one through", fine == true)
	entry = nil
	passed = 0
	for i = 1, 100 do
		fine, entry = CmdrService.rate(entry, 200 + i * 1.01, 5, 20)
		passed += if fine then 1 else 0
	end
	check("rate: 20 a minute holds over 100 s of one a second", passed <= 40 and passed >= 20, tostring(passed))

	-- The live registry, when a playtest has loaded Cmdr
	if CmdrService.Cmdr then
		local bad = {}
		local count = 0
		for _, command in CmdrService.Cmdr.Registry:GetCommands() do
			count += 1
			if type(command.Description) ~= "string" or #command.Description < 10 or type(command.Group) ~= "string" then
				table.insert(bad, command.Name)
			end
		end
		check("registry: every command has a group and a description", #bad == 0, table.concat(bad, ", "))
		check("registry: the game's commands are registered", CmdrService.Cmdr.Registry:GetCommand("tp") ~= nil, `{count} commands`)
		check("registry: the skipped built-ins are absent", CmdrService.Cmdr.Registry:GetCommand("fetch") == nil and CmdrService.Cmdr.Registry:GetCommand("blink") == nil and CmdrService.Cmdr.Registry:GetCommand("thru") == nil)
	end

	local all = true
	for _, c in checks do
		all = all and c.ok
	end
	return { passed = all, checks = checks }
end

return Tests
