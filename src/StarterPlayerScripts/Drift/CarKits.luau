--!nonstrict
-- CarKits: draws a fitted build's body kits and interior on a car -- bumpers, skirts,
-- spoilers, flares; cage, seats, steering wheel, audio (docs/game/features/car-customization.md,
-- T-105; CONTRACTS.md "Customization", the slot rows). Where each slot sits and what each
-- piece is made of is `Config.CarKits`; this turns that into parts.
--
-- THE CLIENT DRAWS, THE SERVER DECIDES. `Controllers/CarLooksController` hands this the
-- build the car's `Fit_*` attributes say (or a garage preview), the same build `Drift/CarLooks`
-- draws the paint from.
--
-- NOTHING GOES INSIDE THE CAR, and nothing is welded (DECISIONS.md 2026-11-03). Each car's
-- kit parts are a Model of this client's own, `Kits_<car>`, in the caller's folder
-- (`Workspace.CarLooks` in the game) -- anchored, never collidable, never queryable, never
-- touched. `step` moves every one of them each frame to `Body.CFrame * its place`, the way
-- the underglow is moved: the simulation's `Body` part is where `Drift/Render` puts the
-- shell's body, lean and suspension included, so a kit rides exactly with the body you see.
-- Not added to the shell as `L` parts: the shell is the server's, `Render` caches its
-- groups once whole, and its body boxes are the floor the suspension rests the car on.
--
-- STOCK IS NO PARTS. A build with no kit and no interior leaves nothing at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Config = require(ReplicatedStorage.Shared.Config)
local Customization = require(ReplicatedStorage.Shared.Customization)

local CarKits = {}

local SHELL = "Shell"
local BODY = "Body"
local CATEGORIES = { "BodyKit", "Interior" }

export type Slot = { cf: CFrame, span: Vector3, from: string }

export type State = {
	car: Model,
	parent: Instance?,
	model: Model?,
	parts: { BasePart },
	locals: { CFrame },
	slots: { [string]: Slot },
	fitted: { [string]: string }, -- slot -> piece
	signature: string?,
	build: any,
	draws: number,
}

local function cfg()
	return Config.CarKits
end

-- ---------------------------------------------------------------------- where the slots are

-- The box around the body that is drawn, in the car's frame: the shell's `Body` group parts
-- (by their `L`), or the car's own `Body` part when it has no shell. Nil with neither.
function CarKits.box(car: Instance): (Vector3?, Vector3?)
	local parts = {}
	local shell = car:FindFirstChild(SHELL)
	local group = shell and shell:FindFirstChild(BODY)
	if group then
		for _, p in group:GetChildren() do
			if p:IsA("BasePart") and typeof(p:GetAttribute("L")) == "CFrame" then
				table.insert(parts, { cf = p:GetAttribute("L"), size = p.Size })
			end
		end
	end
	if #parts == 0 then
		local body = car:FindFirstChild(BODY)
		if body and body:IsA("BasePart") then
			table.insert(parts, { cf = CFrame.identity, size = body.Size })
		end
	end
	if #parts == 0 then
		return nil, nil
	end
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, entry in parts do
		local h = entry.size * 0.5
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = entry.cf * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
					lo, hi = lo:Min(w), hi:Max(w)
				end
			end
		end
	end
	return lo, hi
end

-- Which body a car wears: its `Body` attribute, or "block" when it has no shell.
function CarKits.bodyName(car: Instance): string
	local body = car:GetAttribute("Body")
	if type(body) == "string" then
		return body
	end
	return if car:FindFirstChild(SHELL) then "?" else "block"
end

local function lerp(lo: Vector3, hi: Vector3, f: Vector3): Vector3
	return lo + (hi - lo) * f
end

-- Every slot's origin and span on this car, `{ [slot] = { cf, span, from } }`; `from` is
-- "rig" when the car's own `Shell` attributes placed it, else "body". Empty while the car
-- has no body to measure.
function CarKits.slots(car: Instance): { [string]: Slot }
	local C = cfg()
	local out = {}
	local lo, hi = CarKits.box(car)
	if lo and hi then
		local D = Config.Drift
		local b = C.Bodies[CarKits.bodyName(car)] or C.Bodies.Default
		local width = hi.X - lo.X
		local midX = (lo.X + hi.X) * 0.5
		local S = C.Spans
		local wheels = CarModel.wheelOffsets()
		local front, rear = wheels.WheelFL.Z, wheels.WheelRL.Z
		local wheelY = wheels.WheelFL.Y
		local axleMid = (front + rear) * 0.5
		local base = math.abs(rear - front)

		out.KitFront = { cf = CFrame.new(midX, lo.Y, lo.Z), span = Vector3.new(width, S.KitFront.height, S.KitFront.depth) }
		out.KitRear = { cf = CFrame.new(midX, lo.Y, hi.Z), span = Vector3.new(width, S.KitRear.height, S.KitRear.depth) }
		out.KitSkirts = {
			cf = CFrame.new(midX, lo.Y, axleMid),
			span = Vector3.new(width, S.KitSkirts.height, math.max(0.5, base - C.ArchGap * D.WheelDiameter)),
		}
		local deck = lerp(lo, hi, b.deck)
		out.KitSpoiler = { cf = CFrame.new(midX, deck.Y, deck.Z), span = Vector3.new(width, S.KitSpoiler.height, S.KitSpoiler.depth) }
		out.KitFlares = { cf = CFrame.new(midX, wheelY, axleMid), span = Vector3.new(width, D.WheelDiameter, base) }

		local cmin, cmax = lerp(lo, hi, b.cabin.min), lerp(lo, hi, b.cabin.max)
		local cabin = {
			cf = CFrame.new((cmin.X + cmax.X) * 0.5, cmin.Y, (cmin.Z + cmax.Z) * 0.5),
			span = cmax - cmin,
		}
		for _, slot in C.Slots.Interior do
			out[slot] = { cf = cabin.cf, span = cabin.span }
		end
		for _, slot in out do
			slot.from = "body"
		end
	end

	-- a car that says where its own slots are
	local shell = car:FindFirstChild(SHELL)
	if shell then
		for _, list in C.Slots do
			for _, slot in list do
				local at = shell:GetAttribute(slot)
				if typeof(at) == "CFrame" or typeof(at) == "Vector3" then
					local size = shell:GetAttribute(slot .. "Size")
					local span = if typeof(size) == "Vector3" then size elseif out[slot] then out[slot].span else nil
					if span then
						out[slot] = {
							cf = if typeof(at) == "CFrame" then at else CFrame.new(at),
							span = span,
							from = "rig",
						}
					end
				end
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------- the pieces

-- A piece's shapes, its `with` first.
function CarKits.shapes(pieceName: string, depth: number?): { any }
	local piece = cfg().Pieces[pieceName]
	if not piece or (depth or 0) > 4 then
		return {}
	end
	local out = {}
	if piece.with then
		for _, s in CarKits.shapes(piece.with, (depth or 0) + 1) do
			table.insert(out, s)
		end
	end
	for _, s in piece.shapes do
		table.insert(out, s)
	end
	return out
end

-- Each part a shape makes: `{ local CFrame (car frame), size }`, mirrors included.
function CarKits.place(shape, slot: Slot): { { cf: CFrame, size: Vector3 } }
	local span = slot.span
	local size = span * shape.s + (shape.sa or Vector3.zero)
	size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	local p = span * shape.p + (shape.pa or Vector3.zero)
	local r = shape.r or Vector3.zero
	local rot = CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
	local out = {}
	local xs = if shape.mx and p.X ~= 0 then { 1, -1 } else { 1 }
	local zs = if shape.mz and p.Z ~= 0 then { 1, -1 } else { 1 }
	for _, sx in xs do
		for _, sz in zs do
			-- a mirror image is moved, not turned: every mirrored shape is a box
			table.insert(out, {
				cf = slot.cf * CFrame.new(p.X * sx, p.Y, p.Z * sz) * rot,
				size = size,
			})
		end
	end
	return out
end

local function colourOf(name: any, bodyColour: Color3?): Color3
	local C = cfg()
	if name == C.BodyColour then
		return bodyColour or C.Colours.trim
	end
	return C.Colours[name] or C.Colours.trim
end

local function newPart(shape): BasePart
	local part: BasePart = if shape.k == "wedge" then Instance.new("WedgePart") else Instance.new("Part")
	part.Anchored = true -- never physics
	part.CanCollide = false
	part.CanQuery = false -- no ray, ours or the camera's, may ever hit a kit
	part.CanTouch = false
	part.CastShadow = true
	part.Locked = true
	part.Material = (Enum.Material :: any)[cfg().Material]
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Which piece is in which slot for a build: `{ [slot] = piece }`, empty for stock.
function CarKits.fitted(build): { [string]: string }
	local out = {}
	if not build then
		return out
	end
	local looks = Customization.looks(build)
	for _, category in CATEGORIES do
		local look = looks[category]
		for slot, piece in (look and look.slots) or {} do
			if type(slot) == "string" and type(piece) == "string" then
				out[slot] = piece
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------- the whole car

function CarKits.new(car: Model, parent: Instance?): State
	return {
		car = car,
		parent = parent,
		model = nil,
		parts = {},
		locals = {},
		slots = {},
		fitted = {},
		signature = nil,
		build = nil,
		draws = 0,
	}
end

function CarKits.clear(state: State)
	if state.model then
		state.model:Destroy()
	end
	state.model = nil
	table.clear(state.parts)
	table.clear(state.locals)
	table.clear(state.fitted)
	state.signature = nil
end

local function signatureOf(car, fitted, slots, bodyColour: Color3?): string
	local keys = {}
	for slot in fitted do
		table.insert(keys, slot)
	end
	table.sort(keys)
	local bits = { CarKits.bodyName(car), bodyColour and bodyColour:ToHex() or "-" }
	for _, slot in keys do
		local s = slots[slot]
		table.insert(bits, `{slot}={fitted[slot]}@{s and tostring(s.cf.Position) .. tostring(s.span) or "?"}`)
	end
	return table.concat(bits, "|")
end

-- Draw `build`'s kits and interior on the state's car. `bodyColour` is what `c = "body"`
-- shapes are painted (the car's body as drawn). Safe to call as often as anything changes:
-- the same pieces on the same body in the same colour are left alone.
function CarKits.apply(state: State, build, bodyColour: Color3?)
	state.build = build
	local fitted = CarKits.fitted(build)
	if next(fitted) == nil then
		CarKits.clear(state)
		state.slots = {}
		return
	end
	local slots = CarKits.slots(state.car)
	local signature = signatureOf(state.car, fitted, slots, bodyColour)
	if signature == state.signature and state.model and state.model.Parent then
		return
	end
	CarKits.clear(state)
	state.slots = slots
	if not state.parent then
		return
	end

	local model = Instance.new("Model")
	model.Name = `Kits_{state.car.Name}`
	local body = state.car:FindFirstChild(BODY)
	local origin = if body and body:IsA("BasePart") then body.CFrame else CFrame.identity
	for slotName, pieceName in fitted do
		local slot = slots[slotName]
		local piece = cfg().Pieces[pieceName]
		if not slot or not piece then
			continue -- a slot this car has no place for yet, or a piece with no art
		end
		if piece.slot ~= slotName then
			warn(`[CarKits] piece '{pieceName}' belongs in {piece.slot}, not {slotName}`)
			continue
		end
		state.fitted[slotName] = pieceName
		for i, shape in CarKits.shapes(pieceName) do
			for j, placed in CarKits.place(shape, slot) do
				local part = newPart(shape)
				part.Name = `{slotName}_{pieceName}_{i}_{j}`
				part.Size = placed.size
				part.Color = colourOf(shape.c, bodyColour)
				part.CFrame = origin * placed.cf
				part:SetAttribute("KitSlot", slotName)
				part.Parent = model
				table.insert(state.parts, part)
				table.insert(state.locals, placed.cf)
			end
		end
	end
	model.Parent = state.parent
	state.model = model
	state.signature = signature
	state.draws += 1
end

-- Every kit part of every car, once a frame, after the cars are drawn: one bulk move.
local movingParts, movingFrames = {}, {}
function CarKits.step(states: { [any]: State })
	table.clear(movingParts)
	table.clear(movingFrames)
	for _, state in states do
		if #state.parts > 0 then
			local body = state.car:FindFirstChild(BODY)
			if body and body:IsA("BasePart") then
				local origin = body.CFrame
				for i, part in state.parts do
					table.insert(movingParts, part)
					table.insert(movingFrames, origin * state.locals[i])
				end
			end
		end
	end
	if #movingParts > 0 then
		workspace:BulkMoveTo(movingParts, movingFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- What is drawn, for the tests and the debug bridge: each fitted slot, its piece, how many
-- parts, where the slot is (car frame) and where it came from.
function CarKits.describe(state: State)
	local slots = {}
	local counts = {}
	for _, part in state.parts do
		local slot = part:GetAttribute("KitSlot")
		counts[slot] = (counts[slot] or 0) + 1
	end
	for slot, piece in state.fitted do
		local s = state.slots[slot]
		slots[slot] = {
			piece = piece,
			parts = counts[slot] or 0,
			at = s and s.cf.Position,
			span = s and s.span,
			from = s and s.from,
		}
	end
	return { body = CarKits.bodyName(state.car), parts = #state.parts, slots = slots, draws = state.draws }
end

return CarKits
