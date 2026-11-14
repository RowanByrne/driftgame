--!strict
-- Render: puts a car model where the drift model says it is.
--
-- Every part is anchored, so nothing here asks Roblox to move anything: each part's CFrame
-- is written straight from the simulation state.
--
-- THE CAR IS DRAWN AT THE FRAME'S OWN MOMENT, NOT AT THE LAST STEP (T-025). The model
-- steps at `FixedStep` and keeps the leftover in an accumulator, so a frame almost never
-- lands on a step boundary: at 179 studs/s one step is 1.49 studs, and drawing the car at
-- the last COMPLETED step leaves it a varying fraction of that behind where it really is.
-- A varying lag is a judder -- the car creeps and snaps, frame after frame -- and it is
-- what the user saw. So `apply` takes the accumulator's leftover and carries the pose
-- forward across it (`Render.subStep`): position by the velocity, heading by the yaw rate,
-- wheel spin by the road speed. All three are exact to first order and the model's own
-- second-order terms over 1/120 s are under three thousandths of a stud, so this is not a
-- guess at where the car will be -- it is where the car IS at the moment the frame is
-- drawn. It removes lag rather than adding any; the camera reads the same carried-forward
-- pose, so what the player sees on screen moves smoothly too.
--
-- The simulation only ever knows five things: a body and four wheels, at `wheelOffsets()`.
-- A car with the AE86 shell on it (Shared/CarModel) carries five matching groups under
-- `Shell`, and each one is pivoted to the same place as the part it shadows -- so a shelled
-- car and a block car are the same five writes plus five pivots, and the simulation cannot
-- tell them apart.
--
-- Two of those writes are cosmetic, and they are the only reason a car reads as drifting:
--   the body LEANS outward, away from the way the car is sliding, about the centre of
--     mass -- the wheels stay flat on the road;
--   the front wheels POINT ALONG WHERE THE CAR IS TRAVELLING, which is opposite lock the
--     moment the tail is out. The model has no steering angle to draw: the player's finger
--     is the car's rate of turn, so this is read off the slip angle instead.
--
-- A CAR V2 RIG (`Shared/Cars/Rig`, the shell carries a `Rig` attribute) has a group for
-- every moving part, each with its pivot on its real hinge. `Shared/CarParts` says where
-- each group is relative to the car -- a door open, the hood up, a wheel on its hub -- and
-- this writes every one of them each frame from the body's frame, so an opened door rides
-- with the car exactly as the body does. The hubs, and the wheels and calipers on them,
-- ride the car's ROAD frame like the wheels always have: the body leans, they do not. Each
-- wheel takes a vertical lift (`setWheelLift`, default 0) that moves its hub, for the
-- suspension to drive. The five simulation parts are written exactly as before.
--
-- THE SUSPENSION (T-095, Drift/Suspension). `apply` draws the model's own: every wheel at
-- its lift -- on a rig through its hub, on today's cars through the wheel's own part and
-- `Wheel*` group, the same `rig.lift` either way -- and the body at its sprung offset on the
-- car's frame, under the lean. A car standing on flat ground has every lift and the offset
-- at exactly zero, so it is drawn to the bit where it always was. And it hands the model
-- the car's FLOOR: a rig's own `Floor*` points, or else the underside of the body that is
-- actually drawn, read off its lower parts' boxes (`Suspension.floorFromBoxes`), or the
-- block car's box -- so the floor that rests on a ledge is the one you can see.
--
-- `DriftModel` is the simulation (Drift/Model); `Model` is Roblox's class.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local CarParts = require(ReplicatedStorage.Shared.CarParts)
local Config = require(ReplicatedStorage.Shared.Config)
local DriftModel = require(script.Parent.Model)
local Suspension = require(script.Parent.Suspension)

local Render = {}

type ShellPart = { part: BasePart, offset: CFrame }
type Shell = { group: Model, parts: { ShellPart } }
type Wheel = { part: BasePart, offset: Vector3, front: boolean, shell: Shell? }

type RigGroup = { name: string, shell: Shell, road: boolean }

export type Rig = {
	car: Model,
	body: BasePart?,
	bodyShell: Shell?,
	wheels: { Wheel },
	complete: boolean,
	-- a v2 rig only: every group but the body, in the order `CarParts` places them
	desc: CarParts.Desc?,
	groups: { RigGroup }?,
	frames: { [string]: CFrame },
	lift: { [string]: number }, -- studs up, per wheel name: the suspension's (`apply`)
	inputs: CarParts.Inputs,
	floor: { Suspension.FloorPoint }?, -- the floor the model rests this car on (T-095)
}

-- The shell group that shadows a named simulation part, with every part's place in it,
-- ready to be written absolutely. Nil until the whole group has replicated: a Model
-- arrives before its parts, and `N` says how many to wait for.
--
-- Absolute writes, not `Model:PivotTo`. The shell belongs to the server, the server
-- re-asserts its parts' CFrames, and a pivot applies a DELTA -- so every re-assertion is
-- paid twice and the shell walks away from the car (measured: 2 500 studs out inside a
-- minute). The five simulation parts never had the problem because they have always been
-- written absolutely, and now the shell is too.
local function shellOf(car: Model, name: string): Shell?
	local shell = car:FindFirstChild(CarModel.SHELL_NAME)
	if not shell then
		return nil
	end
	local group = shell:FindFirstChild(name)
	if not group or not group:IsA("Model") then
		return nil
	end
	local parts: { ShellPart } = {}
	for _, p in group:GetChildren() do
		if p:IsA("BasePart") then
			local offset = p:GetAttribute("L")
			if typeof(offset) == "CFrame" then
				table.insert(parts, { part = p, offset = offset })
			end
		end
	end
	local want = group:GetAttribute("N")
	if typeof(want) == "number" and #parts < want then
		return nil -- still arriving
	end
	return { group = group, parts = parts }
end

local function placeShell(shell: Shell?, cf: CFrame)
	if not shell then
		return
	end
	for _, entry in shell.parts do
		entry.part.CFrame = cf * entry.offset
	end
end

-- The floor the model rests this car on (T-095): the rig's own `Floor*` points if it has
-- any, else the underside of the body that is drawn -- its shell's lower parts, or the
-- block car's box. Nil leaves the model on the config's stand-in box.
local function floorOf(rig: Rig): { Suspension.FloorPoint }?
	if rig.desc then
		local points = Suspension.floorFromRig(rig.desc.floor)
		if points then
			return points
		end
	end
	local boxes = {}
	if rig.bodyShell then
		for _, entry in rig.bodyShell.parts do
			table.insert(boxes, { cf = entry.offset, size = entry.part.Size })
		end
	elseif rig.body then
		table.insert(boxes, { cf = CFrame.identity, size = rig.body.Size })
	end
	return Suspension.floorFromBoxes(boxes)
end

-- Find the parts, and say whether they are all there yet.
--
-- A car is caught the moment its Model lands in the Cars folder, and a Model replicates
-- before its contents do. With a five-part car that gap was too small to see; with a
-- hundred-part one it is not, and a rig taken inside it holds nothing and draws nothing
-- for the rest of the run. So a rig that is short of parts says so, and is looked up again
-- on the next frame until it is whole. The `Shell` attribute is set by `CarModel` and
-- arrives with the Model itself, so an incomplete rig can tell a block car from a shelled
-- car whose shell has not landed.
local function resolve(rig: Rig)
	local car = rig.car
	local body = car:FindFirstChild(CarModel.BODY_NAME)
	rig.body = if body and body:IsA("BasePart") then body else nil
	rig.bodyShell = shellOf(car, CarModel.BODY_NAME)

	-- A v2 rig draws its wheels through its own groups (on their hubs), not through the
	-- `Wheel*` groups an older body shadows the simulation's wheels with.
	local shellModel = car:FindFirstChild(CarModel.SHELL_NAME)
	local isRig = shellModel ~= nil and CarParts.isRig(shellModel)

	local wheels: { Wheel } = {}
	for name, offset in CarModel.wheelOffsets() do
		local part = car:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(wheels, {
				part = part,
				offset = offset,
				front = CarModel.isFrontWheel(name),
				shell = if isRig then nil else shellOf(car, name),
			})
		end
	end
	rig.wheels = wheels

	rig.desc, rig.groups = nil, nil
	if isRig then
		local desc = CarParts.describe(shellModel :: Instance)
		if desc then
			local list: { RigGroup } = {}
			local all = true
			for _, g in desc.order do
				if g.kind ~= "body" then
					local s = shellOf(car, g.name)
					if not s then
						all = false -- still arriving
						break
					end
					table.insert(list, { name = g.name, shell = s, road = g.road })
				end
			end
			if all then
				rig.desc, rig.groups = desc, list
			end
		end
	end

	local whole = rig.body ~= nil and #wheels == 4
	if whole and isRig then
		whole = rig.bodyShell ~= nil and rig.groups ~= nil
	elseif whole and car:GetAttribute(CarModel.SHELL_NAME) then
		whole = rig.bodyShell ~= nil
		for _, wheel in wheels do
			whole = whole and wheel.shell ~= nil
		end
	end
	rig.complete = whole
	if whole then
		rig.floor = floorOf(rig)
	end
end

function Render.rig(car: Model): Rig
	local rig: Rig = {
		car = car,
		body = nil,
		bodyShell = nil,
		wheels = {},
		complete = false,
		desc = nil,
		groups = nil,
		frames = {},
		lift = {},
		inputs = {},
		floor = nil,
	}
	resolve(rig)
	return rig
end

-- A wheel's vertical offset, in studs up from where the car puts it (0, the default). It
-- moves that wheel's hub, and the wheel and caliper on it, and the simulation's own wheel
-- part with them -- or, on a car with no rig, the wheel part and its `Wheel*` group. `apply`
-- sets all four from the model's suspension; another player's car takes them off the wire
-- (`Suspension.unpack`).
function Render.setWheelLift(rig: Rig, wheel: string, studs: number)
	rig.lift[wheel] = if studs ~= 0 then studs else nil
end

function Render.wheelLift(rig: Rig, wheel: string): number
	return rig.lift[wheel] or 0
end

-- A v2 rig's group by name, for the tests and anything that reads a part back.
function Render.group(rig: Rig, name: string): Shell?
	if name == CarModel.BODY_NAME then
		return rig.bodyShell
	end
	for _, entry in rig.groups or {} do
		if entry.name == name then
			return entry.shell
		end
	end
	return nil
end

-- Place the car from a pose. `wheelAngle` is where the front wheels are DRAWN, in radians,
-- Roblox's sense: positive points them to the car's left. Another player's car is drawn
-- through this too: their CFrame arrives over the wire, their wheels and their lean do not,
-- so both are zero for them.
--
-- `offset` is the body's sprung place on the car's frame (`Suspension.bodyLocal` without
-- the lean): the body rides it, under the lean, and the wheels do not -- they ride the
-- car's frame at their own lifts. Nil, or the identity, is the body where it always was.
function Render.place(
	rig: Rig,
	cf: CFrame,
	wheelAngle: number,
	wheelSpin: number,
	bodyRoll: number?,
	offset: CFrame?
)
	if not rig.complete then
		resolve(rig)
	end

	local bodyCF = if offset then cf * offset else cf
	local roll = bodyRoll or 0
	if roll ~= 0 then
		-- Leaning about the centre of mass rather than about the car's origin, which
		-- is the difference between a car rolling on its springs and a box pivoting
		-- on the road.
		local com = Config.Drift.CenterOfMass
		bodyCF = bodyCF * CFrame.new(com) * CFrame.Angles(0, 0, roll) * CFrame.new(-com)
	end
	if rig.body then
		rig.body.CFrame = bodyCF
	end
	placeShell(rig.bodyShell, bodyCF)

	for _, wheel in rig.wheels do
		local lift = rig.lift[wheel.part.Name]
		local base = cf * CFrame.new(if lift then wheel.offset + Vector3.new(0, lift, 0) else wheel.offset)
		if wheel.front then
			base *= CFrame.Angles(0, wheelAngle, 0)
		end
		local wheelCF = base * CFrame.Angles(wheelSpin, 0, 0)
		wheel.part.CFrame = wheelCF
		placeShell(wheel.shell, wheelCF)
	end

	-- A v2 rig: every group where `CarParts` says it is, from the body (or, for the hubs
	-- and what is on them, from the unleaned car), written absolutely like everything else.
	local groups, desc = rig.groups, rig.desc
	if groups and desc then
		local inputs = rig.inputs
		inputs.steer, inputs.spin, inputs.lift = wheelAngle, wheelSpin, rig.lift
		local frames = CarParts.frames(rig.car, desc, nil, inputs, rig.frames)
		for _, entry in groups do
			placeShell(entry.shell, (if entry.road then cf else bodyCF) * frames[entry.name])
		end
	end
end

-- Where a shell group has actually been put, read back off one of its own parts. Only the
-- tests use this: everything else sets the frame rather than asking for it.
function Render.shellFrame(shell: Shell?): CFrame?
	if not shell or #shell.parts == 0 then
		return nil
	end
	local first = shell.parts[1]
	return first.part.CFrame * first.offset:Inverse()
end

-- ---------------------------------------------------------------- the sub-step
--
-- Where the car is `rem` seconds past the last completed step, with `rem` the leftover in
-- Sim's accumulator (0 .. FixedStep). Position, heading and wheel spin only: those are the
-- three the model integrates at the car's own speed, and they are the three that judder.
--
-- The cosmetic easings (`bodyRoll`, `wheelSteer`) and the surface normal (`up`) are NOT
-- carried forward, because each is an ease toward a target and extrapolating one of those
-- can only overshoot it. Measured on the live playground, the most any of them moves in
-- one step is: body roll 0.19 degrees and drawn wheel angle 2.0 degrees, both in the most
-- violent spin the car can make, which at the camera's 55 studs is hundredths of a stud of
-- movement; and the surface normal 2.35 degrees, on the lip of the ramp -- one or two
-- frames of a car that is genuinely pitching that fast as it launches, and nothing a
-- player meets on the road, where it is 0.0000 degrees a step.
--
-- `rem` is clamped to one step: a caller that hands in a whole frame is asking for a
-- prediction, and this is not one.
function Render.subStep(state: DriftModel.State, rem: number?): (Vector3, number, number)
	local dt = math.clamp(rem or 0, 0, Config.Drift.FixedStep)
	if dt <= 0 then
		return state.position, state.yaw, state.wheelSpin
	end
	local radius = math.max(Config.Drift.WheelDiameter * 0.5, 1e-4)
	-- The height moves at the BODY's own vertical speed (`heave`, T-196): on the ground
	-- `velocity.Y` is the slope's climb, which a body bouncing on its springs is not doing.
	local v = state.velocity
	local heave = (state :: any).heave
	if heave and heave ~= v.Y then
		v = Vector3.new(v.X, heave, v.Z)
	end
	return state.position + v * dt, state.yaw + state.r * dt, state.wheelSpin + (state.u / radius) * dt
end

-- The car's basis from a heading and the surface normal it is following. This mirrors
-- `Model.cframe`, which builds the same matrix from the state's own yaw: the only reason
-- it is written out again is that the drawn heading is the state's PLUS the sub-step, and
-- the model has no business knowing about frames. If `Model.cframe` ever changes shape,
-- this changes with it.
local function poseOf(position: Vector3, yaw: number, up: Vector3): CFrame
	local u = if up.Magnitude > 1e-4 then up.Unit else Vector3.yAxis
	local flat = DriftModel.axes(yaw)
	local right = flat:Cross(u)
	if right.Magnitude < 1e-4 then
		return CFrame.fromMatrix(position, Vector3.new(flat.Z, 0, -flat.X), Vector3.yAxis)
	end
	return CFrame.fromMatrix(position, right.Unit, u)
end

-- The whole pose the car is drawn at, `rem` seconds past the last step: the body's frame,
-- the angle the front wheels are drawn at, how far the wheels have spun, and the lean.
-- Pure, so the tests can measure what a frame WOULD draw without a car in the world
-- (ServerScriptService/Tests/JitterTests).
function Render.pose(state: DriftModel.State, rem: number?): (CFrame, number, number, number)
	local position, yaw, spin = Render.subStep(state, rem)
	return poseOf(position, yaw, state.up), state.wheelSteer, spin, state.bodyRoll
end

-- Place the whole car from one simulation state, drawn `rem` seconds past the last step
-- (Sim's accumulator; see the header). `rem` nil or 0 draws the car at the step itself,
-- which is what it did before T-025 and what a one-off placement -- a spawn, a respawn,
-- a teleport -- still wants.
--
-- The suspension comes with it (T-095): each wheel at the lift the model's step left it at,
-- the body at its sprung offset, and the car's floor handed back to the model for the next
-- step (`floorOf`; the model reads it only when a wheel has run out of travel).
function Render.apply(rig: Rig, state: DriftModel.State, rem: number?)
	local cf, wheelAngle, wheelSpin, bodyRoll = Render.pose(state, rem)
	local lifts = state.wheelLift
	if lifts then
		for i, name in CarModel.WHEEL_NAMES do
			Render.setWheelLift(rig, name, lifts[i] or 0)
		end
	end
	if rig.floor and state.floor ~= rig.floor then
		state.floor = rig.floor
	end
	local body = state.body
	local offset: CFrame? = nil
	if body and not Suspension.bodyAtRest(state) then
		offset = CFrame.new(0, body.z, 0) * CFrame.Angles(body.p, 0, 0) * CFrame.Angles(0, 0, body.q)
	end
	Render.place(rig, cf, wheelAngle, wheelSpin, bodyRoll, offset)
end

return Render
