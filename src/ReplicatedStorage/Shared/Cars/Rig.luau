--!strict
-- Rig: the car v2 rig contract, and the gray model's numbers for it
-- (docs/game/features/car-v2.md "The rig", CONTRACTS.md "The car rig").
--
-- A v2 car's `Shell` is a `Body` group plus ONE GROUP PER MOVING THING, each named as
-- `PivotsGray2` (the pivot list the gray model's build writes, copied here verbatim from
-- `..\art\source\car-ae86\pivots-gray2.json`) names it, with its pivot on its real hinge.
-- Every group describes itself in attributes, so the code that moves it (`Shared/CarParts`)
-- and the code that draws it (`Drift/Render`) read the car, not this module: the real
-- meshes slot into the same groups when they pass their gate, and nothing else changes.
--
-- WHAT THIS MODULE IS: the gray model's rig, turned into the game's frame. `groups()` is
-- every group as the builder needs it; `write` and `writePoints` put the contract's
-- attributes on a built shell. The STAND-IN (`Cars/StandIn`) is built from it today.
--
-- AXES. The pivot list is in Blender's frame: X = the car's LEFT, -Y = forward, Z = up,
-- origin on the ground midway between the axles. The game's car frame is X = right,
-- -Z = forward, Y = up, origin `RideHeight` above the road (`Shared/CarModel`). So
--     car = ( -x, z - RideHeight, y )
-- which is a proper rotation (determinant +1): an axis converts the same way and an
-- angle keeps its sign.
--
-- WHAT THE PIVOT LIST DOES NOT SAY, read off `car-ae86-gray2.blend` on 2026-11-10 and
-- written down here: which part rides on which (`ON`), where the lamps are (`LAMPS`), and
-- the points the code reads (`POINTS`, `FLOOR`). If the build ever writes those too, they
-- come from the list instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Rig = {}

-- The shell attribute that marks a v2 rig, and its version.
Rig.VERSION = 2
Rig.SHELL_ATTR = "Rig"

-- The pivot list, verbatim. Lync turns a .json file into a ModuleScript returning it.
Rig.Pivots = require(script.Parent.PivotsGray2) :: any

-- Every kind of group, as the `Kind` attribute names it.
--   body   the static shell: the car's own frame, leaning with the body roll
--   hinge  turns about `Axis` through `Pivot`, `Open` degrees at full travel
--   hub    a wheel's suspension hub: moves up and down by the wheel's lift and, if `Steer`
--          is set, steers with the front wheels. Rides the car's ROAD frame, not the
--          leaning body, so the wheels stay flat on the road as they always have
--   spin   a wheel: spins about its axle, on its hub
--   fixed  rides its `On` group and never moves on its own (calipers, on their hubs)
--   aim    turns about its pivot to point at the `At` group's pivot (the hatch struts)
--   light  a lamp: fixed on its `On` group; `Lamp` says what it is
Rig.KINDS = { "body", "hinge", "hub", "spin", "fixed", "aim", "light" }

Rig.WHEELS = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }

-- A wheel's hub, and the wheel a hub carries.
function Rig.hubOf(wheel: string): string
	return "Hub" .. string.sub(wheel, 6)
end

-- Which group each group rides on, where that is not the body. From the .blend's parents,
-- plus the hubs, which the .blend does not have: there a wheel and its caliper sit on the
-- body, and the game puts a hub between them so the suspension can move both.
Rig.ON = {
	DoorGlassL = "DoorL",
	DoorGlassR = "DoorR",
	StrutTubeL = "Hatch",
	StrutTubeR = "Hatch",
	HeadlightL = "PodL",
	HeadlightR = "PodR",
	WheelFL = "HubFL",
	WheelFR = "HubFR",
	WheelRL = "HubRL",
	WheelRR = "HubRR",
	CaliperFL = "HubFL",
	CaliperFR = "HubFR",
	CaliperRL = "HubRL",
	CaliperRR = "HubRR",
} :: { [string]: string }

-- How long each part takes over its whole travel, in seconds. A part part-way there takes
-- that share of it. Programmer timing, until the parts are animated for real.
Rig.SECONDS = {
	DoorL = 0.8,
	DoorR = 0.8,
	DoorGlassL = 2.0,
	DoorGlassR = 2.0,
	Hood = 1.0,
	HoodProp = 0.6,
	Hatch = 1.2,
	PodL = 0.5,
	PodR = 0.5,
	WiperL = 0.6,
	WiperR = 0.6,
} :: { [string]: number }
Rig.DEFAULT_SECONDS = 0.25 -- needles, pedals, levers, the steering wheel

-- Each lamp's origin (its lens's middle), read off the .blend, in the pivot list's axes.
-- The size and centre are its lens's box, for the stand-in.
Rig.LAMPS = {
	HeadlightL = { o = { 1.9825, -7.5919, 2.3546 }, c = { 1.9825, -7.5812, 2.3651 }, s = { 0.89, 0.6122, 0.6181 } },
	HeadlightR = { o = { -1.9825, -7.5919, 2.3546 }, c = { -1.9825, -7.5812, 2.3651 }, s = { 0.89, 0.6122, 0.6181 } },
	MarkerFrontL = { o = { 3.1003, -7.3, 2.665 }, c = { 3.0881, -7.2984, 2.662 }, s = { 0.4108, 0.9632, 0.1961 } },
	MarkerFrontR = { o = { -3.1003, -7.3, 2.665 }, c = { -3.0881, -7.2984, 2.662 }, s = { 0.4108, 0.9632, 0.1961 } },
	IndicatorRearL = { o = { 3.0144, 8.3432, 2.96 }, c = { 3.0144, 8.3422, 2.9569 }, s = { 0.6288, 1.4881, 0.6062 } },
	IndicatorRearR = { o = { -3.0144, 8.3432, 2.96 }, c = { -3.0144, 8.3422, 2.9569 }, s = { 0.6288, 1.4881, 0.6062 } },
	TailLampL = { o = { 2.01, 9.0529, 3.11 }, c = { 2.01, 9.0433, 3.1091 }, s = { 1.31, 0.049, 0.3018 } },
	TailLampR = { o = { -2.01, 9.0529, 3.11 }, c = { -2.01, 9.0433, 3.1091 }, s = { 1.31, 0.049, 0.3018 } },
	BrakeLampL = { o = { 2.01, 9.0771, 2.81 }, c = { 2.01, 9.0621, 2.8091 }, s = { 1.31, 0.0484, 0.3018 } },
	BrakeLampR = { o = { -2.01, 9.0771, 2.81 }, c = { -2.01, 9.0621, 2.8091 }, s = { 1.31, 0.0484, 0.3018 } },
	ReverseLampL = { o = { 1.68, 9.0768, 2.815 }, c = { 1.68, 9.0618, 2.8141 }, s = { 0.3, 0.0454, 0.2518 } },
	ReverseLampR = { o = { -1.68, 9.0768, 2.815 }, c = { -1.68, 9.0618, 2.8141 }, s = { 0.3, 0.0454, 0.2518 } },
	TailGarnish = { o = { 0, 9.0622, 2.96 }, c = { 0, 9.0473, 2.9591 }, s = { 2.65, 0.0781, 0.6018 } },
	IndicatorFrontL = { o = { 1.94, -8.465, 1.97 }, c = { 1.94, -8.465, 1.97 }, s = { 0.68, 0.05, 0.3 } },
	IndicatorFrontR = { o = { -1.94, -8.465, 1.97 }, c = { -1.94, -8.465, 1.97 }, s = { 0.68, 0.05, 0.3 } },
	ParkLampL = { o = { 2.6981, -8.1179, 1.97 }, c = { 2.6981, -8.1179, 1.97 }, s = { 0.8361, 0.7443, 0.3 } },
	ParkLampR = { o = { -2.6981, -8.1179, 1.97 }, c = { -2.6981, -8.1179, 1.97 }, s = { 0.8361, 0.7443, 0.3 } },
	FogLampL = { o = { 1.69, -8.395, 1.285 }, c = { 1.69, -8.395, 1.285 }, s = { 0.68, 0.05, 0.45 } },
	FogLampR = { o = { -1.69, -8.395, 1.285 }, c = { -1.69, -8.395, 1.285 }, s = { 0.68, 0.05, 0.45 } },
	WarnLamp1 = { o = { -1.225, -1.8725, 3.3265 }, c = { -1.225, -1.8725, 3.3265 }, s = { 0.06, 0.015, 0.033 } },
	WarnLamp2 = { o = { -1.315, -1.8725, 3.3265 }, c = { -1.315, -1.8725, 3.3265 }, s = { 0.06, 0.015, 0.033 } },
	WarnLamp3 = { o = { -1.405, -1.8725, 3.3265 }, c = { -1.405, -1.8725, 3.3265 }, s = { 0.06, 0.015, 0.033 } },
	WarnLamp4 = { o = { -1.495, -1.8725, 3.3265 }, c = { -1.495, -1.8725, 3.3265 }, s = { 0.06, 0.015, 0.033 } },
	WarnLamp5 = { o = { -1.585, -1.8725, 3.3265 }, c = { -1.585, -1.8725, 3.3265 }, s = { 0.06, 0.015, 0.033 } },
	WarnLamp6 = { o = { -1.675, -1.8725, 3.3265 }, c = { -1.675, -1.8725, 3.3265 }, s = { 0.06, 0.015, 0.033 } },
} :: { [string]: { o: { number }, c: { number }, s: { number } } }

-- The points the code reads, in the pivot list's axes, each facing the car's forward.
--   Seat  the driver's cushion, top middle: right-hand drive, behind the steering wheel
--         (x = -1.45, the wheel's own x). Where the seated avatar's hips go
--   Exit  on the ground beside the driver's door, clear of it swung fully open (62 deg):
--         where the avatar's feet go when it gets out
Rig.POINTS = {
	Seat = { -1.45, 0.3, 1.9 },
	Exit = { -5.0, 0.6, 0 },
} :: { [string]: { number } }

-- The floor: a flat box under the car, at its lowest point (the sills and the front valance,
-- 0.6 off the ground on the .blend), its corners at the bumpers and the body's sides, plus
-- the middle of each edge and the centre. Named front/middle/rear then left/centre/right.
-- The suspension step rests the car on these when the wheels cannot hold it.
local FLOOR_Z = 0.6
local FLOOR_X = 3.0
local FLOOR_FRONT, FLOOR_REAR = -8.2, 9.0
Rig.FLOOR = {
	FloorFL = { FLOOR_X, FLOOR_FRONT, FLOOR_Z },
	FloorFC = { 0, FLOOR_FRONT, FLOOR_Z },
	FloorFR = { -FLOOR_X, FLOOR_FRONT, FLOOR_Z },
	FloorML = { FLOOR_X, 0, FLOOR_Z },
	FloorMC = { 0, 0, FLOOR_Z },
	FloorMR = { -FLOOR_X, 0, FLOOR_Z },
	FloorRL = { FLOOR_X, FLOOR_REAR, FLOOR_Z },
	FloorRC = { 0, FLOOR_REAR, FLOOR_Z },
	FloorRR = { -FLOOR_X, FLOOR_REAR, FLOOR_Z },
} :: { [string]: { number } }

-- ------------------------------------------------------------------ axes

local function rideHeight(): number
	return Config.Drift.RideHeight
end

-- A point in the pivot list's axes, in the car's frame.
function Rig.toCar(p: { number }, ride: number?): Vector3
	return Vector3.new(-p[1], p[3] - (ride or rideHeight()), p[2])
end

-- A direction in the pivot list's axes, in the car's frame.
function Rig.dirToCar(a: { number }): Vector3
	return Vector3.new(-a[1], a[3], a[2])
end

-- ------------------------------------------------------------------ the groups

export type GroupSpec = {
	name: string,
	kind: string,
	pivot: CFrame, -- in the car's frame, closed; no rotation
	axis: Vector3?, -- hinge and spin, unit, car frame
	open: number?, -- hinge: degrees at full travel
	steer: number?, -- hub: degrees of steering, if it steers
	at: string?, -- aim: the group it points at
	on: string?, -- the group it rides on; nil is the body (or, for a hub, the road)
	seconds: number?, -- hinge: seconds over the whole travel
	lamp: string?, -- light: what it is
	wheel: string?, -- hub: the wheel it carries
}

-- Every group but `Body`, in the car's frame. Hubs first, then the pivot list's parts in
-- name order, then the lamps: an order that does not matter to anything, kept stable so a
-- built shell is the same shell every time.
function Rig.groups(ride: number?): { GroupSpec }
	local out: { GroupSpec } = {}
	local parts = Rig.Pivots.parts

	for _, wheel in Rig.WHEELS do
		local d = parts[wheel]
		table.insert(out, {
			name = Rig.hubOf(wheel),
			kind = "hub",
			pivot = CFrame.new(Rig.toCar(d.origin, ride)),
			steer = d.steer,
			wheel = wheel,
		})
	end

	local names = {}
	for name in parts do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local d = parts[name]
		local spec: GroupSpec = {
			name = name,
			kind = d.kind,
			pivot = CFrame.new(Rig.toCar(d.origin, ride)),
			on = Rig.ON[name],
		}
		if d.kind == "hinge" then
			spec.axis = Rig.dirToCar(d.axis).Unit
			spec.open = d.angle
			spec.seconds = Rig.SECONDS[name] or Rig.DEFAULT_SECONDS
		elseif d.kind == "spin" then
			spec.axis = Rig.dirToCar(d.axis).Unit
		elseif d.kind == "steer" or d.kind == "fixed" then
			-- A caliper. In the pivot list it steers on its own; in the game its hub does
			-- the steering and it simply rides there.
			spec.kind = "fixed"
		elseif d.kind == "aim" then
			spec.at = d.at
		end
		table.insert(out, spec)
	end

	local lamps = {}
	for name in Rig.Pivots.lights do
		table.insert(lamps, name)
	end
	table.sort(lamps)
	for _, name in lamps do
		local at = Rig.LAMPS[name]
		table.insert(out, {
			name = name,
			kind = "light",
			pivot = CFrame.new(Rig.toCar(at.o, ride)),
			on = Rig.ON[name],
			lamp = Rig.Pivots.lights[name],
		})
	end
	return out
end

-- ------------------------------------------------------------------ the attributes

-- Write a group's contract attributes. `N` (how many parts to wait for) is the builder's.
function Rig.write(group: Instance, spec: GroupSpec)
	group:SetAttribute("Kind", spec.kind)
	group:SetAttribute("Pivot", spec.pivot)
	group:SetAttribute("Axis", spec.axis)
	group:SetAttribute("Open", spec.open)
	group:SetAttribute("Steer", spec.steer)
	group:SetAttribute("At", spec.at)
	group:SetAttribute("On", spec.on)
	group:SetAttribute("Seconds", spec.seconds)
	group:SetAttribute("Lamp", spec.lamp)
	group:SetAttribute("Wheel", spec.wheel)
end

-- Mark a shell as a v2 rig and write its points: the seat, the exit, the floor.
function Rig.writePoints(shell: Instance, groupCount: number, ride: number?)
	shell:SetAttribute(Rig.SHELL_ATTR, Rig.VERSION)
	-- How many rig groups to wait for, `Body` included: a Model replicates before its
	-- contents, so a client has to know when it has all of them (`Drift/Render`).
	shell:SetAttribute("G", groupCount)
	for name, p in Rig.POINTS do
		shell:SetAttribute(name, CFrame.new(Rig.toCar(p, ride)))
	end
	for name, p in Rig.FLOOR do
		shell:SetAttribute(name, Rig.toCar(p, ride))
	end
end

return Rig
