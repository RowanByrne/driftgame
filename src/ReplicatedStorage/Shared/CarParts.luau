--!strict
-- CarParts: turns a v2 car's moving parts (docs/game/features/car-v2.md "The rig").
--
-- One module for every part on every car: `set` / `setAngle` put a part somewhere at once,
-- `open` / `close` / `toggle` move it there over time, and `frames` says where every group
-- of a car is, relative to the car, for `Drift/Render` to draw. It knows the orders that
-- matter (`SEQUENCES`): the hood lifts before its prop rod swings up, and the rod comes
-- down before the hood closes. The hatch's struts need no order: they are `aim` groups and
-- point at each other wherever the hatch is.
--
-- WHERE A PART IS, IS ON THE CAR. Each moving part's state is two attributes on the car
-- Model (CONTRACTS.md "The car rig"):
--     Part_<Name>    Vector3 (from, to, seconds): an amount of its full travel, 0 shut and
--                    1 fully open, moving from `from` to `to` over `seconds`
--     PartAt_<Name>  number: when that move starts, on `CarParts.now()`
-- so any copy of this module, on any client, reads the same part in the same place: the
-- driven car and the remote cars alike, a test's own copy and the game's. Set on a client
-- they stay on that client; set by the server they reach everyone, which is how getting in
-- and out will open the door for all to see. The clock is `GetServerTimeNow`, which every
-- machine shares.
--
-- WHAT A PART IS comes off the car's `Shell` too (`describe`): every group's kind, pivot,
-- axis, travel and what it rides on, as `Cars/Rig` writes them. Nothing here knows the
-- AE86; a car with different parts is just a different shell.
--
-- Nothing here touches physics: it computes CFrames and writes attributes, and `Render`
-- writes the parts (DECISIONS.md, 2026-11-03).

local CarParts = {}

CarParts.ATTR = "Part_"
CarParts.ATTR_AT = "PartAt_"

-- The orders that matter: opening the first name opens each part in turn, each starting
-- when the one before it is there; closing closes them in the reverse order.
CarParts.SEQUENCES = {
	Hood = { "Hood", "HoodProp" },
} :: { [string]: { string } }

local IDENTITY = CFrame.identity

export type Group = {
	name: string,
	kind: string,
	pivot: CFrame, -- in the car's frame, shut
	link: CFrame, -- from the pivot of what it rides on to its own
	axis: Vector3,
	open: number, -- hinge: degrees at full travel
	steer: number, -- hub: degrees it steers, 0 if it does not
	seconds: number,
	at: string?,
	on: string?,
	road: boolean, -- rides the car's road frame (hubs and what is on them), not the body
	wheel: string?, -- hub: the wheel it carries
	rest: Vector3, -- aim: from its pivot to its target's, shut
	model: Model,
}

export type Desc = {
	shell: Instance,
	groups: { Group },
	byName: { [string]: Group },
	order: { Group }, -- anything before what rides on it; aims last
	seat: CFrame?,
	exit: CFrame?,
	floor: { [string]: Vector3 },
}

export type Inputs = {
	steer: number?, -- radians, the front hubs, Roblox's sense: positive is to the left
	spin: number?, -- radians, every wheel about its axle
	lift: { [string]: number }?, -- studs up, per wheel name (`WheelFL`...)
}

-- ------------------------------------------------------------------ reading the rig

local descs: { [Instance]: Desc } = setmetatable({}, { __mode = "k" }) :: any

local function shellOf(inst: Instance): Instance?
	if inst:GetAttribute("Rig") ~= nil then
		return inst
	end
	local shell = inst:FindFirstChild("Shell")
	if shell and shell:GetAttribute("Rig") ~= nil then
		return shell
	end
	return nil
end

-- Is this car (or shell) a v2 rig? Known from the shell's own attribute, which arrives with
-- the shell before any of its groups do.
function CarParts.isRig(inst: Instance?): boolean
	return inst ~= nil and shellOf(inst) ~= nil
end

-- Everything about a car's rig, read off its shell. Nil for a car that is not a v2 rig, or
-- one whose groups have not all arrived yet (a Model replicates before its contents, and
-- `G` on the shell says how many groups to wait for); ask again next frame.
function CarParts.describe(inst: Instance): Desc?
	local shell = shellOf(inst)
	if not shell then
		return nil
	end
	local cached = descs[shell]
	if cached then
		return cached
	end

	local groups: { Group } = {}
	local byName: { [string]: Group } = {}
	for _, child in shell:GetChildren() do
		local kind = child:GetAttribute("Kind")
		if child:IsA("Model") and type(kind) == "string" then
			local pivot = child:GetAttribute("Pivot")
			local axis = child:GetAttribute("Axis")
			local g: Group = {
				name = child.Name,
				kind = kind,
				pivot = if typeof(pivot) == "CFrame" then pivot else IDENTITY,
				link = IDENTITY,
				axis = if typeof(axis) == "Vector3" then axis.Unit else Vector3.xAxis,
				open = (child:GetAttribute("Open") :: number?) or 0,
				steer = (child:GetAttribute("Steer") :: number?) or 0,
				seconds = (child:GetAttribute("Seconds") :: number?) or 0,
				at = child:GetAttribute("At") :: string?,
				on = child:GetAttribute("On") :: string?,
				road = kind == "hub",
				wheel = child:GetAttribute("Wheel") :: string?,
				rest = Vector3.zero,
				model = child,
			}
			table.insert(groups, g)
			byName[g.name] = g
		end
	end
	local want = shell:GetAttribute("G")
	if typeof(want) ~= "number" or #groups < want then
		return nil -- still arriving
	end

	-- Anything before what rides on it. A group whose `On` names nothing rides the body.
	local order: { Group } = {}
	local placed: { [string]: boolean } = {}
	local aims: { Group } = {}
	local pending = table.clone(groups)
	while #pending > 0 do
		local left = {}
		for _, g in pending do
			if g.on and not byName[g.on] then
				warn(`[CarParts] '{g.name}' rides on '{g.on}', which this car does not have; it rides the body`)
				g.on = nil
			end
			if g.kind == "aim" then
				table.insert(aims, g)
			elseif g.on == nil or placed[g.on] then
				table.insert(order, g)
				placed[g.name] = true
			else
				table.insert(left, g)
			end
		end
		if #left == #pending then
			error(`[CarParts] the rig's groups ride on each other in a circle: {#left} left`)
		end
		pending = left
	end
	for _, g in aims do
		table.insert(order, g)
	end

	for _, g in order do
		local parent = g.on and byName[g.on]
		if parent then
			g.road = g.road or parent.road
			g.link = CFrame.new(g.pivot.Position - parent.pivot.Position)
		else
			g.link = CFrame.new(g.pivot.Position)
		end
		if g.kind == "aim" and g.at and byName[g.at] then
			g.rest = byName[g.at].pivot.Position - g.pivot.Position
		end
	end

	local floor: { [string]: Vector3 } = {}
	for name, value in shell:GetAttributes() do
		if string.sub(name, 1, 5) == "Floor" and typeof(value) == "Vector3" then
			floor[name] = value
		end
	end
	local seat, exit = shell:GetAttribute("Seat"), shell:GetAttribute("Exit")
	local desc: Desc = {
		shell = shell,
		groups = groups,
		byName = byName,
		order = order,
		seat = if typeof(seat) == "CFrame" then seat else nil,
		exit = if typeof(exit) == "CFrame" then exit else nil,
		floor = floor,
	}
	descs[shell] = desc
	return desc
end

-- ------------------------------------------------------------------ the state

type Anim = { from: number, to: number, seconds: number, at: number }
type State = { anims: { [string]: Anim } }

local states: { [Instance]: State } = setmetatable({}, { __mode = "k" }) :: any

-- The shared clock: the same on the server and every client.
function CarParts.now(): number
	return workspace:GetServerTimeNow()
end

local function parse(car: Instance, name: string): Anim?
	local v = car:GetAttribute(CarParts.ATTR .. name)
	if typeof(v) ~= "Vector3" then
		return nil
	end
	local at = car:GetAttribute(CarParts.ATTR_AT .. name)
	return { from = v.X, to = v.Y, seconds = v.Z, at = if type(at) == "number" then at else 0 }
end

local function stateOf(car: Instance): State
	local state = states[car]
	if state then
		return state
	end
	local s: State = { anims = {} }
	for attr in car:GetAttributes() do
		if string.sub(attr, 1, #CarParts.ATTR) == CarParts.ATTR then
			local name = string.sub(attr, #CarParts.ATTR + 1)
			s.anims[name] = parse(car, name)
		end
	end
	-- Another copy of this module, or the server, moved a part: read it again. Only this
	-- car's own parts are re-read, and only when they change, so a frame reads no attribute.
	car.AttributeChanged:Connect(function(attr: string)
		local name: string? = nil
		if string.sub(attr, 1, #CarParts.ATTR) == CarParts.ATTR then
			name = string.sub(attr, #CarParts.ATTR + 1)
		elseif string.sub(attr, 1, #CarParts.ATTR_AT) == CarParts.ATTR_AT then
			name = string.sub(attr, #CarParts.ATTR_AT + 1)
		end
		if name then
			s.anims[name] = parse(car, name)
		end
	end)
	car.Destroying:Connect(function()
		states[car] = nil
	end)
	states[car] = s
	return s
end

local function evaluate(anim: Anim?, now: number): number
	if not anim then
		return 0
	end
	if anim.seconds <= 0 or now >= anim.at + anim.seconds then
		return anim.to -- exactly where it was sent, so a part that went out and back is shut
	end
	if now <= anim.at then
		return anim.from
	end
	local t = (now - anim.at) / anim.seconds
	return anim.from + (anim.to - anim.from) * (t * t * (3 - 2 * t))
end

-- Write a move, and read it straight back: the attribute holds it as 32-bit numbers, and
-- this copy must hold exactly what every other copy will read.
local function write(car: Instance, name: string, from: number, to: number, seconds: number, at: number)
	car:SetAttribute(CarParts.ATTR_AT .. name, at)
	car:SetAttribute(CarParts.ATTR .. name, Vector3.new(from, to, seconds))
	stateOf(car).anims[name] = parse(car, name)
end

local function groupOf(car: Instance, name: string): Group
	local desc = CarParts.describe(car)
	local g = desc and desc.byName[name]
	if not g then
		error(`[CarParts] {car:GetFullName()} has no rigged part '{name}'`, 3)
	end
	return g
end

-- ------------------------------------------------------------------ moving parts

-- How far along its travel a part is, 0 shut to 1 fully open, at `now` (default: now).
function CarParts.amount(car: Instance, name: string, now: number?): number
	return evaluate(stateOf(car).anims[name], now or CarParts.now())
end

-- The angle a hinge is turned to, in degrees, at `now`.
function CarParts.angle(car: Instance, name: string, now: number?): number
	return CarParts.amount(car, name, now) * groupOf(car, name).open
end

-- Put a part at `amount` of its travel at once.
function CarParts.set(car: Instance, name: string, amount: number)
	groupOf(car, name)
	write(car, name, amount, amount, 0, 0)
end

-- Turn a hinge to `degrees` at once, in its own sense (the sign its full travel has):
-- a needle to a speed, the steering wheel to a lock.
function CarParts.setAngle(car: Instance, name: string, degrees: number)
	local g = groupOf(car, name)
	if g.open == 0 then
		error(`[CarParts] '{name}' is not a hinge`, 2)
	end
	write(car, name, degrees / g.open, degrees / g.open, 0, 0)
end

-- Move a part (or a sequence) to `target` (0 shut, 1 open) over its own time, starting at
-- `now`. Returns how many seconds the whole move takes.
function CarParts.move(car: Instance, name: string, target: number, now: number?): number
	local t = now or CarParts.now()
	local steps = CarParts.SEQUENCES[name] or { name }
	if target < 0.5 then
		-- shutting: the last part of the sequence goes first
		local reversed = {}
		for i = #steps, 1, -1 do
			table.insert(reversed, steps[i])
		end
		steps = reversed
	end
	local start = t
	for _, step in steps do
		local g = groupOf(car, step)
		if g.kind ~= "hinge" then
			error(`[CarParts] '{step}' is a {g.kind}, and only a hinge opens`, 2)
		end
		local from = CarParts.amount(car, step, t)
		write(car, step, from, target, g.seconds * math.abs(target - from), start)
		-- the next step starts when this one, as the car holds it, has arrived
		local held = stateOf(car).anims[step]
		start += if held then held.seconds else 0
	end
	return start - t
end

function CarParts.open(car: Instance, name: string, now: number?): number
	return CarParts.move(car, name, 1, now)
end

function CarParts.close(car: Instance, name: string, now: number?): number
	return CarParts.move(car, name, 0, now)
end

-- Open it if it is nearer shut, shut it if it is nearer open.
function CarParts.toggle(car: Instance, name: string, now: number?): number
	local t = now or CarParts.now()
	local first = (CarParts.SEQUENCES[name] or { name })[1]
	return CarParts.move(car, name, if CarParts.amount(car, first, t) < 0.5 then 1 else 0, t)
end

-- Is anything on this car still moving?
function CarParts.busy(car: Instance, now: number?): boolean
	local t = now or CarParts.now()
	for _, anim in stateOf(car).anims do
		if anim.seconds > 0 and t < anim.at + anim.seconds then
			return true
		end
	end
	return false
end

-- Every part that has been moved, and where it is: for `DebugState`s.
function CarParts.amounts(car: Instance, now: number?): { [string]: number }
	local t = now or CarParts.now()
	local out = {}
	for name, anim in stateOf(car).anims do
		out[name] = evaluate(anim, t)
	end
	return out
end

-- ------------------------------------------------------------------ the frames

-- The shortest turn that takes direction `a` onto direction `b`.
local function turnBetween(a: Vector3, b: Vector3): CFrame
	local ua, ub = a.Unit, b.Unit
	local cross = ua:Cross(ub)
	local s = cross.Magnitude
	if s < 1e-6 then
		return IDENTITY
	end
	return CFrame.fromAxisAngle(cross / s, math.atan2(s, ua:Dot(ub)))
end

-- Where every group of a car is, at `now`, as the frame its parts' `L` are relative to:
-- relative to the leaning BODY for most, and to the car's ROAD frame (unleaned) for the
-- hubs and what rides on them -- `Group.road` says which. `out` is filled and returned, so
-- a caller drawing every frame can hand the same table back each time.
function CarParts.frames(
	car: Instance,
	desc: Desc,
	now: number?,
	inputs: Inputs?,
	out: { [string]: CFrame }?
): { [string]: CFrame }
	local frames = out or {}
	local t = now or CarParts.now()
	local anims = stateOf(car).anims
	local steer = inputs and inputs.steer or 0
	local spin = inputs and inputs.spin or 0
	local lift = inputs and inputs.lift

	for _, g in desc.order do
		local parent = if g.on then frames[g.on] else IDENTITY
		local cf = parent * g.link
		local kind = g.kind
		if kind == "hinge" then
			local a = evaluate(anims[g.name], t) * g.open
			if a ~= 0 then
				cf *= CFrame.fromAxisAngle(g.axis, math.rad(a))
			end
		elseif kind == "hub" then
			local y = if lift and g.wheel then lift[g.wheel] or 0 else 0
			if y ~= 0 then
				cf = CFrame.new(0, y, 0) * cf
			end
			if g.steer ~= 0 and steer ~= 0 then
				cf *= CFrame.Angles(0, steer, 0)
			end
		elseif kind == "spin" then
			if spin ~= 0 then
				cf *= CFrame.Angles(spin, 0, 0)
			end
		end
		frames[g.name] = cf
	end

	-- The aims, last: each turns about its own pin to point at its partner's, wherever
	-- that has been carried. Turning one does not move its pin, so the order between the
	-- two halves of a strut does not matter.
	for _, g in desc.order do
		if g.kind == "aim" and g.at then
			local here = frames[g.name].Position
			local there = frames[g.at]
			if there then
				frames[g.name] = CFrame.new(here) * turnBetween(g.rest, there.Position - here)
			end
		end
	end
	return frames
end

return CarParts
