--!nonstrict
-- BuildFeel: the driving client's half of "fitted parts change how the car drives" (T-106,
-- docs/game/features/car-customization.md "Rules and numbers").
--
-- The server publishes every player's build on their car as attributes (`Fit_*`, then
-- `Fitted` up by one, CONTRACTS.md "Customization"). `follow(player)` watches THAT player's
-- own car and keeps `Cars`' build layer equal to it, so `Config.Drift` resolves the fitted
-- parts' numbers on the very next simulation step after a Fit, with nothing in the model
-- changed. The layer holds the build for all four archetypes (`Customization.layer`), so a
-- car switch lands on the right numbers too.
--
-- CLIENT ONLY in use: the server never calls `follow` (it holds every player at once and
-- passes each one's build to `Cars.resolve` itself, `CarService:_numbers`). Pure enough to
-- require anywhere; nothing happens until `follow` is called.

local Cars = require(script.Parent)
local Customization = require(script.Parent.Parent.Customization)

local BuildFeel = {}

local CARS_FOLDER = "Cars" -- `Workspace.Cars` (CONTRACTS.md "Paths")

local state = {
	applied = 0, -- how many times the layer has been set from a car
	fitted = nil, -- the `Fitted` counter last applied
	build = nil, -- the build last applied
}

-- Put one build on this VM's car, or the stock car for nil.
function BuildFeel.apply(build: Customization.Build?)
	Cars.setBuild(if build then Customization.layer(build) else nil)
	state.build = if build then Customization.copy(build) else nil
	state.applied += 1
end

-- Watch `player`'s own car and keep the build layer equal to what the server fitted on it.
-- Returns a function that stops watching and puts the stock car back.
function BuildFeel.follow(player: Player): () -> ()
	local connections: { RBXScriptConnection } = {}
	local carConnections: { [Instance]: RBXScriptConnection } = {}

	local function read(car: Instance)
		local fitted = car:GetAttribute(Customization.ATTR_COUNTER)
		-- A car whose attributes have not arrived yet reads as stock; wait for the server's
		-- `Fitted` rather than drop a fitted build for a frame.
		if type(fitted) ~= "number" then
			return
		end
		state.fitted = fitted
		BuildFeel.apply(Customization.read(car))
	end

	local function watch(car: Instance)
		if car:GetAttribute("UserId") ~= player.UserId or carConnections[car] then
			return
		end
		carConnections[car] = car:GetAttributeChangedSignal(Customization.ATTR_COUNTER):Connect(function()
			read(car)
		end)
		read(car)
	end

	local function consider(car: Instance)
		if car:GetAttribute("UserId") == player.UserId then
			watch(car)
			return
		end
		-- CarService attributes a car before parenting it, but be safe about the order.
		local c
		c = car:GetAttributeChangedSignal("UserId"):Connect(function()
			if car:GetAttribute("UserId") == player.UserId then
				c:Disconnect()
				watch(car)
			end
		end)
		table.insert(connections, c)
	end

	task.spawn(function()
		local folder = workspace:WaitForChild(CARS_FOLDER, 30)
		if not folder then
			warn("[BuildFeel] Workspace.Cars never appeared; fitted parts will not change the feel")
			return
		end
		table.insert(connections, folder.ChildAdded:Connect(consider))
		table.insert(connections, folder.ChildRemoved:Connect(function(car)
			local c = carConnections[car]
			if c then
				c:Disconnect()
				carConnections[car] = nil
			end
			-- The layer is KEPT: a respawn's new car carries the same build and replaces it.
		end))
		for _, car in folder:GetChildren() do
			consider(car)
		end
	end)

	return function()
		for _, c in connections do
			c:Disconnect()
		end
		for _, c in carConnections do
			c:Disconnect()
		end
		table.clear(connections)
		table.clear(carConnections)
		BuildFeel.apply(nil)
	end
end

function BuildFeel.DebugState()
	return {
		applied = state.applied,
		fitted = state.fitted,
		build = state.build,
		layer = Cars.build(),
		active = Cars.activeKey(),
		topSpeed = Cars.active().TopSpeed,
		maxAcceleration = Cars.active().MaxAcceleration,
	}
end

return BuildFeel
