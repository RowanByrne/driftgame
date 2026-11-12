--!nonstrict
-- The admin console's own argument types (docs/game/features/admin-console.md). Cmdr
-- requires this on the server and again on every client, so it reads only shared modules.
--
--   car        an archetype key (`Shared/Cars`)
--   place      where `tp` goes: a world, the garage, a playground spot, or a player by name
--   timeOfDay  a keyframe of the day-night cycle by name ("noon", "golden-hour"),
--              "midnight", or an hour on the clock, 0 to 24
--   roadMode   "pieces" or "spline"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)

-- The places `tp` offers to complete. The server takes any playground spot by name as
-- well (`PlaygroundService:GetSpot`), so a spot added to the layout works before it is
-- listed here. Names only: where each one is lives in the services.
local PLACES = {
	"road",
	"playground",
	"track",
	"garage",
	"hill",
	"Spawn",
	"OpenGround",
	"PillarRun",
	"DistrictGate",
	"Boulevard",
	"TightAlley",
	"CircleCentre",
	"RampBase",
	"HillBase",
	"HillTop",
}

local function slug(name: string): string
	return (string.gsub(string.lower(name), "%s+", "-"))
end

local function timeNames(): { string }
	local names = { "midnight" }
	for _, key in Config.DayNight.Keyframes do
		local name = slug(key.Name)
		if not table.find(names, name) then
			table.insert(names, name)
		end
	end
	return names
end

return function(registry)
	local Util = registry.Cmdr.Util

	local carKeys = {}
	for _, key in Cars.Order do
		table.insert(carKeys, key)
	end
	for key in Cars.Archetypes.Cars do
		if not table.find(carKeys, key) then
			table.insert(carKeys, key)
		end
	end
	registry:RegisterType("car", Util.MakeEnumType("car", carKeys))

	registry:RegisterType("roadMode", Util.MakeEnumType("road mode", { "pieces", "spline" }))

	-- The places, then every player in the server by name: `tp me Alex` goes to Alex.
	local function findPlace(text: string, first: boolean?)
		local names = table.clone(PLACES)
		for _, player in Players:GetPlayers() do
			table.insert(names, player.Name)
		end
		return Util.MakeFuzzyFinder(names)(text, first)
	end
	registry:RegisterType("place", {
		Transform = function(text: string)
			return text
		end,
		Validate = function(text: string)
			return #text > 0, "Name a place: road, playground, track, garage, hill, a playground spot, or a player."
		end,
		Autocomplete = function(text: string)
			return findPlace(text)
		end,
		Parse = function(text: string)
			-- an exact match keeps its case; a partial one takes the first completion
			local exact = findPlace(text, true)
			return exact or text
		end,
	})

	local names = timeNames()
	local findTime = Util.MakeFuzzyFinder(names)
	registry:RegisterType("timeOfDay", {
		Transform = function(text: string)
			return text
		end,
		Validate = function(text: string)
			local hour = tonumber(text)
			if hour then
				return hour >= 0 and hour <= 24, "An hour is 0 to 24."
			end
			return findTime(text, true) ~= nil, `Say an hour (0-24) or one of: {table.concat(names, ", ")}.`
		end,
		Autocomplete = function(text: string)
			if tonumber(text) then
				return {}
			end
			return findTime(text)
		end,
		Parse = function(text: string)
			local hour = tonumber(text)
			if hour then
				return hour
			end
			return findTime(text, true)
		end,
	})
end
