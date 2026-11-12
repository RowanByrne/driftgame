local Players = game:GetService("Players")

local Ops = require(script.Parent.Parent.Parent.Ops)

local SIDE = 12 -- studs to the side of a player's car that `tp <players> <player>` lands

local function toRoad(player: Player, studs: number?): string
	local road = Ops.need("RoadService")
	local joined = false
	if not road:InRun(player) then
		local cf = Ops.startRun(player)
		if not cf then
			return "Couldn't start a run (no car yet, or on the Studio spline test road)."
		end
		joined = true
		if studs == nil then
			return `Joined the run on seed {tostring(Ops.seed())}, {Ops.placed(cf)}.`
		end
	end
	if studs == nil then
		local believed = Ops.need("CarService"):BelievedPosition(player.UserId)
		local cf = road:SafeStart(believed)
		if not cf then
			return "The road has nowhere to put the car."
		end
		local placed, why = Ops.place(player, cf)
		return if placed then `Back on the road, {Ops.placed(placed)}.` else `Not moved: {why}.`
	end
	local cf, why = Ops.roadPose(studs)
	if not cf then
		return if joined then `Joined the run, but not moved along it: {why}.` else `Not moved: {why}.`
	end
	local placed, placeWhy = Ops.place(player, cf)
	if not placed then
		return `Not moved: {placeWhy}.`
	end
	return `On the road {math.floor(studs)} studs from its start, {Ops.placed(placed)}.`
end

local function toGarage(player: Player): string
	local visit = Ops.need("GarageVisitService")
	if visit:InGarage(player) then
		return "Already in the garage."
	end
	Ops.leaveRun(player)
	local ok, why = visit:Enter(player, "console")
	if not ok then
		return `Not into the garage: {tostring(why)}.`
	end
	return "In the garage, on the turntable. garage-out drives you out."
end

local function toWorld(player: Player, world: string): string
	local cars = Ops.need("CarService")
	local cf = cars:Worlds()[world]
	if not cf then
		return `This place has no {world}.`
	end
	Ops.leaveRun(player)
	local placed, why = Ops.place(player, cf)
	return if placed then `At the {world} spawn, {Ops.placed(placed)}.` else `Not moved: {why}.`
end

local function toSpot(player: Player, name: string): string
	local playground = Ops.need("PlaygroundService")
	local lower = string.lower(name)
	local cf, found = nil, nil
	if lower == "hill" or lower == "hilltop" then
		cf, found = playground:HillTopCFrame(), "HillTop"
		if not cf then
			return "This place has no test hill."
		end
	else
		for spot, at in playground.Spots do
			if string.lower(spot) == lower then
				cf, found = at, spot
				break
			end
		end
	end
	if not cf then
		local names = {}
		for spot in playground.Spots do
			table.insert(names, spot)
		end
		table.sort(names)
		return `No place or player '{name}'. Try road, playground, track, garage, hill, a player's name, or a spot: {table.concat(names, ", ")}.`
	end
	Ops.leaveRun(player)
	local placed, why = Ops.place(player, cf)
	return if placed then `At {found}, {Ops.placed(placed)}.` else `Not moved: {why}.`
end

-- To another player's car: on the road beside them if they're in a run (joining it), or a
-- car's length to their side anywhere else.
local function toPlayer(player: Player, other: Player): string
	if other == player then
		return "That's you."
	end
	local cars = Ops.need("CarService")
	local at = cars:BelievedPosition(other.UserId)
	if not at then
		return `{other.Name}'s car hasn't been placed yet.`
	end
	local cf
	if Ops.inRun(other) then
		local road = Ops.need("RoadService")
		if not road:InRun(player) and not Ops.startRun(player) then
			return "Couldn't join their run."
		end
		cf = road:SafeStart(at)
	else
		Ops.leaveRun(player)
		cf = CFrame.new(at + Vector3.new(SIDE, 2, 0))
	end
	if not cf then
		return `Nowhere to put you near {other.Name}.`
	end
	local placed, why = Ops.place(player, cf)
	return if placed then `Next to {other.Name}, {Ops.placed(placed)}.` else `Not moved: {why}.`
end

local function playerNamed(name: string): Player?
	local lower = string.lower(name)
	for _, p in Players:GetPlayers() do
		if string.lower(p.Name) == lower or string.lower(p.DisplayName) == lower then
			return p
		end
	end
	return nil
end

return function(context, players: { Player }, place: string, studs: number?): string
	local key = string.lower(place)
	if studs ~= nil and key ~= "road" then
		return "Only tp road takes a distance."
	end
	local other = if key == "road" or key == "garage" or key == "playground" or key == "track" then nil else playerNamed(place)
	return Ops.forEach(context, players, function(player)
		if other then
			return toPlayer(player, other)
		elseif key == "road" then
			return toRoad(player, studs)
		elseif key == "garage" then
			return toGarage(player)
		elseif key == "playground" or key == "track" then
			return toWorld(player, key)
		end
		return toSpot(player, place)
	end)
end
