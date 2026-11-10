--!strict
-- Rig: the car v2 rig contract, and the one place a rigged car's shell is put together
-- (docs/game/features/car-v2.md "The rig", CONTRACTS.md "The car rig").
--
-- A v2 car's `Shell` is a `Body` group plus ONE GROUP PER MOVING THING -- a door, a hood,
-- a wheel on its hub, a needle, a lamp -- each a Model whose attributes say what it is and
-- where its hinge is. The code that moves the groups (`Shared/CarParts`) and the code that
-- draws them (`Drift/Render`) read the car, never a list of parts, so ANY model that is
-- assembled through `assemble` drops in: an imported car is its meshes, each placed in the
-- car's frame, plus a table naming each moving group's kind and pivot.
--
-- Nothing here is any particular car. The names the game expects for the parts it drives
-- itself (the hubs and wheels, the driver's door, the hood and its prop rod) are in
-- CONTRACTS.md "The car rig".
--
-- THE CAR'S FRAME is the simulation's: origin `RideHeight` above the road, front -Z,
-- right +X, up +Y (`Shared/CarModel.wheelOffsets`). `fromBlender` turns a point exported
-- from Blender's usual car axes (X = the car's left, -Y = forward, Z = up, origin on the
-- ground) into it, if the imported model comes that way.

local Rig = {}

-- The shell attribute that marks a v2 rig, and its version.
Rig.VERSION = 2
Rig.SHELL_ATTR = "Rig"

-- Every kind of group, as the `Kind` attribute names it.
--   body   the static shell: the car's own frame, leaning with the body roll
--   hinge  turns about `Axis` through `Pivot`, `Open` degrees at full travel
--   hub    a wheel's suspension hub: moves up and down by the wheel's lift and, if `Steer`
--          is set, steers with the front wheels. Rides the car's ROAD frame, not the
--          leaning body, so the wheels stay flat on the road as they always have
--   spin   a wheel: spins about its axle (the car's X), on its hub
--   fixed  rides its `On` group and never moves on its own (a caliper, on its hub)
--   aim    turns about its pivot to point at the `At` group's pivot (a gas strut's halves)
--   light  a lamp: fixed on its `On` group; `Lamp` says what it is
Rig.KINDS = { body = true, hinge = true, hub = true, spin = true, fixed = true, aim = true, light = true }

Rig.WHEELS = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }

-- A wheel's hub: `WheelFL` rides `HubFL`.
function Rig.hubOf(wheel: string): string
	return "Hub" .. string.sub(wheel, 6)
end

-- A point from Blender's car axes into the car's frame. A direction converts the same way
-- with `ride = 0`; the change of axes is a proper rotation, so an angle keeps its sign.
function Rig.fromBlender(p: Vector3, ride: number): Vector3
	return Vector3.new(-p.X, p.Z - ride, p.Y)
end

export type GroupSpec = {
	name: string,
	kind: string,
	pivot: Vector3, -- the hinge, in the car's frame, with the part shut
	axis: Vector3?, -- hinge: the axis, car frame
	open: number?, -- hinge: degrees at full travel, sign included
	steer: number?, -- hub: degrees of steering, if it steers
	at: string?, -- aim: the group it points at
	on: string?, -- the group it rides on; nil is the body (or, for a hub, the road)
	seconds: number?, -- hinge: seconds over the whole travel
	lamp: string?, -- light: what it is
	wheel: string?, -- hub: the wheel it carries
	parts: { BasePart }, -- placed in the car's frame, shut
}

export type ShellSpec = {
	body: { BasePart }, -- the static shell, placed in the car's frame
	groups: { GroupSpec },
	seat: CFrame?, -- the driver's seat: where the seated avatar's hips go, facing forward
	exit: CFrame?, -- on the road beside the driver's door: where the avatar's feet go
	floor: { [string]: Vector3 }?, -- `Floor<..>` points under the car, for the suspension
}

-- Write a group's contract attributes.
function Rig.write(group: Instance, spec: GroupSpec)
	assert(Rig.KINDS[spec.kind], `[Rig] '{spec.name}' has no kind '{spec.kind}'`)
	group:SetAttribute("Kind", spec.kind)
	group:SetAttribute("Pivot", CFrame.new(spec.pivot))
	group:SetAttribute("Axis", if spec.axis then spec.axis.Unit else nil)
	group:SetAttribute("Open", spec.open)
	group:SetAttribute("Steer", spec.steer)
	group:SetAttribute("At", spec.at)
	group:SetAttribute("On", spec.on)
	group:SetAttribute("Seconds", spec.seconds)
	group:SetAttribute("Lamp", spec.lamp)
	group:SetAttribute("Wheel", spec.wheel)
end

-- Every part follows the rules that keep a car out of Roblox physics (DECISIONS.md,
-- 2026-11-03), and carries `L`, its place in its group's frame: `Drift/Render` writes it
-- `groupFrame * L` absolutely every frame, never a pivot (T-020).
local function adopt(part: BasePart, pivot: CFrame, group: Model)
	part:SetAttribute("L", pivot:Inverse() * part.CFrame)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- the ground rays must not hit the car
	part.CanTouch = false
	part.Locked = true
	part.Parent = group
end

local function newGroup(name: string, parts: { BasePart }, pivot: CFrame): Model
	local g = Instance.new("Model")
	g.Name = name
	for _, part in parts do
		adopt(part, pivot, g)
	end
	g.WorldPivot = pivot
	-- How many parts to wait for: a Model replicates before its contents (`Drift/Render`).
	g:SetAttribute("N", #parts)
	return g
end

-- A v2 `Shell` from its parts, ready for `CarModel.dress`. The parts are taken over: put in
-- their groups, anchored, and given their `L`.
function Rig.assemble(spec: ShellSpec): Model
	local shell = Instance.new("Model")
	shell.Name = "Shell"
	local body = newGroup("Body", spec.body, CFrame.identity)
	body:SetAttribute("Kind", "body")
	body.Parent = shell
	for _, g in spec.groups do
		local group = newGroup(g.name, g.parts, CFrame.new(g.pivot))
		Rig.write(group, g)
		group.Parent = shell
	end
	shell:SetAttribute(Rig.SHELL_ATTR, Rig.VERSION)
	-- How many rig groups to wait for, `Body` included (`Drift/Render`).
	shell:SetAttribute("G", #spec.groups + 1)
	shell:SetAttribute("Seat", spec.seat)
	shell:SetAttribute("Exit", spec.exit)
	for name, p in spec.floor or {} do
		assert(string.sub(name, 1, 5) == "Floor", `[Rig] floor point '{name}' must be named Floor<..>`)
		shell:SetAttribute(name, p)
	end
	shell.WorldPivot = CFrame.identity
	return shell
end

return Rig
