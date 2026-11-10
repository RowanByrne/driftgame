--!nonstrict
-- Garage/MenuModel: what the garage menus show, worked out from the build (T-103).
--
-- PURE: a fitted build, the open category and the player's pick in, the view's snapshot
-- out (`GarageMenuView` "SNAPSHOT"). No instance, no remote. `GarageController` feeds it,
-- and `GarageVisitTests` checks it on the server with no client.
--
-- A PICK is what the player has chosen but not fitted: a part id in a part category, or a
-- table of paint fields `{ [field] = optionId }` (only the ones that differ from what is
-- fitted) in Paint. The PREVIEW is the fitted build with the pick applied, through the same
-- `Customization.fit` the server uses -- so a preview is never something the server could
-- not build.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Customization = require(ReplicatedStorage.Shared.Customization)
local Garage = require(ReplicatedStorage.Shared.Cars.Garage)

local MenuModel = {}

local PAINT = Customization.PAINT

local SECTION_LABELS = {
	body = "Body colour",
	second = "Second colour",
	finish = "Finish",
	wrap = "Wrap",
}

local sliderByKey = {}
for _, slider in Garage.Sliders do
	sliderByKey[slider.key] = slider
end

function MenuModel.tabs(): { { id: string, label: string } }
	local out = {}
	for _, id in Customization.CategoryOrder do
		local category = Customization.category(id)
		table.insert(out, { id = id, label = category and category.label or id })
	end
	return out
end

function MenuModel.isPaint(category: string): boolean
	return category == PAINT
end

-- Is anything picked?
function MenuModel.hasPick(category: string, pick: any): boolean
	if MenuModel.isPaint(category) then
		return type(pick) == "table" and next(pick) ~= nil
	end
	return type(pick) == "string"
end

-- The fitted build with the pick on it, or the fitted build when there is no pick (or the
-- pick is not one the catalog takes).
function MenuModel.preview(fitted, category: string, pick: any)
	if not MenuModel.hasPick(category, pick) then
		return fitted
	end
	local out = Customization.fit(fitted, category, pick)
	return out or fitted
end

-- Pick a paint option: the new pick table. Choosing what is fitted takes that field out
-- of the pick again, so a pick that matches the car is no pick at all.
function MenuModel.pickPaint(fitted, pick: any, field: string, id: string)
	local out = if type(pick) == "table" then table.clone(pick) else {}
	if fitted.paint[field] == id then
		out[field] = nil
	else
		out[field] = id
	end
	return out
end

-- Pick a part: the new pick. The fitted part is no pick.
function MenuModel.pickPart(fitted, category: string, id: string): string?
	if fitted.parts[category] == id then
		return nil
	end
	return id
end

-- What a part does to the numbers its category owns, as before/after bars. `before` is
-- the fitted car, `after` the car with this part on, both as a bar length: the stock car's
-- number at the middle, `MaxDelta` either side at the ends. Only the numbers that change.
function MenuModel.bars(fitted, category: string, partId: string)
	local cat = Customization.category(category)
	if not cat or not cat.keys or #cat.keys == 0 then
		return {}
	end
	local candidate = Customization.fit(fitted, category, partId)
	if not candidate then
		return {}
	end
	local before = Customization.resolve(fitted)
	local after = Customization.resolve(candidate)
	local stock = Customization.resolve(Customization.stock(fitted.base))
	local span = 2 * Customization.MaxDelta
	local out = {}
	for _, key in cat.keys do
		local b, a, s = before[key], after[key], stock[key]
		if b and a and s and a ~= b then
			local function length(v: number): number
				if s == 0 then
					return 0.5
				end
				return math.clamp(0.5 + (v / s - 1) / span, 0.04, 1)
			end
			local change = if b ~= 0 then (a - b) / math.abs(b) else 0
			local slider = sliderByKey[key]
			table.insert(out, {
				key = key,
				label = slider and slider.label or key,
				before = length(b),
				after = length(a),
				beforeValue = b,
				afterValue = a,
				up = a > b,
				text = string.format("%+d%%", math.round(change * 100)),
			})
		end
	end
	return out
end

-- The view's snapshot. `state` = { fitted, category, pick, status, pending }.
function MenuModel.snapshot(state)
	local fitted = state.fitted
	local category = state.category
	local cat = Customization.category(category)
	local snap = {
		category = category,
		title = cat and cat.label or category,
		tabs = MenuModel.tabs(),
		status = state.status or { text = "", tone = "info" },
		pending = state.pending == true,
		canFit = MenuModel.hasPick(category, state.pick),
		canBack = MenuModel.hasPick(category, state.pick),
	}
	if MenuModel.isPaint(category) then
		snap.kind = "paint"
		local pick = if type(state.pick) == "table" then state.pick else {}
		local sections = {}
		for _, field in Customization.Paint.fieldOrder do
			local options = {}
			local chosen = pick[field] or fitted.paint[field]
			for _, option in Customization.paintOptions(field) do
				table.insert(options, {
					id = option.id,
					name = option.name,
					colour = option.colour,
					fitted = fitted.paint[field] == option.id,
					selected = pick[field] ~= nil and chosen == option.id,
				})
			end
			local list = Customization.Paint.fields[field]
			table.insert(sections, {
				field = field,
				label = SECTION_LABELS[field] or field,
				grid = list == "colours",
				options = options,
			})
		end
		snap.paint = sections
	else
		snap.kind = "parts"
		local rows = {}
		for _, part in Customization.partsIn(category) do
			local fittedHere = fitted.parts[category] == part.id
			table.insert(rows, {
				id = part.id,
				name = part.name,
				fitted = fittedHere,
				selected = state.pick == part.id,
				bars = if fittedHere then {} else MenuModel.bars(fitted, category, part.id),
			})
		end
		snap.rows = rows
		local picked = if type(state.pick) == "string" then Customization.part(state.pick) else nil
		if picked then
			snap.title = `{snap.title}: {picked.name}`
		end
	end
	return snap
end

-- The name of what is picked, for the status line.
function MenuModel.pickName(category: string, pick: any): string
	if MenuModel.isPaint(category) then
		local names = {}
		for _, field in Customization.Paint.fieldOrder do
			local id = type(pick) == "table" and pick[field]
			if id then
				local option = Customization.paintOption(field, id)
				table.insert(names, `{SECTION_LABELS[field] or field} {option and option.name or id}`)
			end
		end
		return table.concat(names, ", ")
	end
	local part = Customization.part(pick)
	return part and part.name or tostring(pick)
end

return MenuModel
