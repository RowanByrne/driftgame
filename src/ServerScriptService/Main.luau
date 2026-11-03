--@script:server
-- The server loader (docs/workflow/CODING.md "Layout").
-- Loads every module in Services/, and in Studio puts the debug bridge in ServerStorage.
-- Services require each other directly, not through here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Loader = require(ReplicatedStorage.Shared.Loader)

local services = Loader.load(ServerScriptService:FindFirstChild("Services"), "Services")

Loader.bridge(services, ServerStorage, ServerScriptService:FindFirstChild("Tests"))
