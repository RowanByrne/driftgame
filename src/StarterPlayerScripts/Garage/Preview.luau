--!nonstrict
-- Garage/Preview: a picked part drawn on this player's own car, on this client only, and
-- taken off again (T-103; docs/game/features/car-customization.md "How it plays" 3-4).
--
-- A PREVIEW NEVER SAVES. It is drawn through `Drift/CarLooks` onto the very state
-- `CarLooksController` keeps for the car -- so there is one wrap and one glow on the car,
-- never two -- and nothing is asked of the server. Reverting is that controller drawing the
-- car again from what the server published (`Fit_*`), the same path every other client
-- draws it by, so Back lands exactly on the fitted look.
--
-- Body kits and interiors have no drawing yet (T-105): previewing one changes nothing on
-- the car, which is right until they do.

local Players = game:GetService("Players")

local Preview = {}

local function looksController()
	local controllers = Players.LocalPlayer:WaitForChild("PlayerScripts"):FindFirstChild("Controllers")
	local module = controllers and controllers:FindFirstChild("CarLooksController")
	if not module then
		return nil
	end
	local ok, controller = pcall(require, module)
	return if ok then controller else nil
end

local function carLooks()
	local drift = Players.LocalPlayer:WaitForChild("PlayerScripts"):FindFirstChild("Drift")
	local module = drift and drift:FindFirstChild("CarLooks")
	return module and require(module)
end

-- Draw `build` on `car` here, now. False when the car has no looks state yet.
function Preview.draw(car: Model, build): boolean
	local controller = looksController()
	local CarLooks = carLooks()
	local state = controller and controller.states and controller.states[car]
	if not state or not CarLooks then
		return false
	end
	local ok, err = pcall(CarLooks.apply, state, build)
	if not ok then
		warn(`[Garage/Preview] could not draw a preview: {err}`)
	end
	return ok
end

-- The car back to what the server says is fitted.
function Preview.revert(car: Model): boolean
	local controller = looksController()
	if not controller or not controller.states or not controller.states[car] then
		return false
	end
	controller:_draw(car)
	return true
end

-- What the car is drawn as now (`CarLooks.describe`), for the tests.
function Preview.describe(car: Model)
	local controller = looksController()
	local CarLooks = carLooks()
	local state = controller and controller.states and controller.states[car]
	if not state or not CarLooks then
		return nil
	end
	return CarLooks.describe(state)
end

return Preview
