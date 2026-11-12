local Ops = require(script.Parent.Parent.Parent.Ops)

local function toRoad(player: Player, studs: number?): string
	local road = Ops.need("RoadService")
	local joined = false
	if not road:InRun(player) then
		local cf = Ops.startRun(player)
		if not cf then
			return "Couldn't start a run (no car yet, or you're on the Studio spline test road)."
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
			return "The road has nowhere to put you."
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
		return "You're already in the garage."
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
		return `No place '{name}'. Try road, playground, track, garage, hill, or a spot: {table.concat(names, ", ")}.`
	end
	Ops.leaveRun(player)
	local placed, why = Ops.place(player, cf)
	return if placed then `At {found}, {Ops.placed(placed)}.` else `Not moved: {why}.`
end

return function(context, place: string, studs: number?): string
	local player = context.Executor
	local key = string.lower(place)
	if studs ~= nil and key ~= "road" then
		return "Only tp road takes a distance."
	end
	if key == "road" then
		return toRoad(player, studs)
	elseif key == "garage" then
		return toGarage(player)
	elseif key == "playground" or key == "track" then
		return toWorld(player, key)
	end
	return toSpot(player, place)
end
