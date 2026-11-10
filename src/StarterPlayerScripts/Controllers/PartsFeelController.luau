--!nonstrict
-- PartsFeelController: makes this player's fitted performance parts change how their car
-- drives on this client (T-106, docs/game/features/car-customization.md "Parts change the
-- feel"). All the work is `Shared/Cars/BuildFeel`: it watches this player's own car's
-- `Fitted` and keeps `Cars`' build layer equal to its `Fit_*` attributes, so `Config.Drift`
-- reads the parts' numbers on the next simulation step after a Fit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildFeel = require(ReplicatedStorage.Shared.Cars.BuildFeel)

local PartsFeelController = {}

function PartsFeelController:Init() end

function PartsFeelController:Start()
	self._stop = BuildFeel.follow(Players.LocalPlayer)
end

function PartsFeelController:DebugState()
	return BuildFeel.DebugState()
end

return PartsFeelController
