--!nonstrict
-- SAMPLE DATA, not game state: snapshots for `GarageMenuView`, one per state the menus
-- can be in, for previewing and measuring the screen without playing to that state
-- (docs/workflow/UI.md "Each screen is a view"). Built from the real catalog through
-- `MenuModel`, so the rows are the rows a player sees.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Customization = require(ReplicatedStorage.Shared.Customization)
local MenuModel = require(script.Parent.MenuModel)

local stock = Customization.stock()
local raced = Customization.fit(stock, "Engine", "engine_street") or stock

local function snap(category, pick, status, pending, fitted)
	return MenuModel.snapshot({
		fitted = fitted or stock,
		category = category,
		pick = pick,
		status = status,
		pending = pending,
	})
end

local fixtures = {
	-- Just in: the engine list, nothing picked.
	engine = snap("Engine", nil, { text = "Pick a part to see it on the car.", tone = "info" }),
	-- A performance part picked over a fitted one: bars up and down.
	enginePicked = snap("Engine", "engine_longgears", {
		text = "Previewing Long gears. Fit to keep it, Back to put the fitted part back.",
		tone = "info",
	}, false, raced),
	-- Waiting for the server.
	enginePending = snap("Engine", "engine_race", { text = "Asking the server...", tone = "pending" }, true),
	-- The server said no.
	refused = snap("Wheels", nil, { text = "Not fitted: wrong category. Back on the fitted part.", tone = "error" }),
	-- Four bars a row: the tallest list.
	suspension = snap("Suspension", "susp_coilover", { text = "", tone = "info" }),
	looksOnly = snap("Interior", "int_full", { text = "", tone = "info" }),
	paint = snap("Paint", { body = "red", finish = "metallic" }, { text = "Previewing Body colour Rally red", tone = "info" }),
	fitted = snap("Underglow", nil, { text = "Fitted: Magenta pulse.", tone = "ok" }, false,
		Customization.fit(stock, "Underglow", "glow_magenta")),
}

-- Long text: a status line half again as long as any real one, and a long part name.
local long = snap("BodyKit", "kit_wide", {
	text = "Not fitted: the server is still loading your saved car. Try again in a moment; nothing was changed on your car.",
	tone = "error",
})
long.rows[2].name = "Street kit with an extremely long placeholder name to stress the row"
fixtures.longText = long

return fixtures
