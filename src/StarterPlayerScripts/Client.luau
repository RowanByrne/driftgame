--@localscript
-- The client loader (docs/workflow/CODING.md "Layout").
-- Loads every module in Controllers/, and in Studio puts the debug bridge in PlayerScripts.
-- Controllers require each other directly, not through here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage.Shared.Loader)

local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")

-- StarterPlayerScripts is copied into PlayerScripts, so Controllers/ arrives beside this script.
local controllers = Loader.load(playerScripts:WaitForChild("Controllers", 10), "Controllers")

Loader.bridge(controllers, playerScripts)
