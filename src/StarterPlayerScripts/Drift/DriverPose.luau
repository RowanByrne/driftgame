--!nonstrict
-- DriverPose: the seated driver's hands on the steering wheel (docs/game/features/car-v2.md
-- "The driver's pose", T-116).
--
-- Roblox's sit animation (`Driver.newSitter`) holds the arms out wide, about 4 studs across
-- at the elbows, and in a right-hand-drive car the right one comes out through the door.
-- This keeps the sit pose for the legs and the body and puts the hands on the wheel's rim,
-- the elbows down and in: on every client, for every seated driver -- this client's own and
-- everyone else's -- with nothing uploaded and nothing sent over the wire.
--
-- HOW: a two-bone solve per arm (upper arm and forearm, the wrist held straight), written
-- straight into the arm joints' `Transform` each frame after the Animator has written the
-- sit pose. Roblox's `IKControl` was tried first and left the hand 0.15 to 0.45 studs off
-- its target on an avatar with `AnimationConstraint` joints, even with the target at the
-- hand's own rest place and every joint limit off (measured in DR-Lane3), so the solve is
-- ours. It works the same on `Motor6D` and `AnimationConstraint` joints. An R6 avatar has
-- no elbow: its arms are pointed at the grips, straight.
--
-- WHERE THE GRIPS ARE: on the rim of the car's `SteeringWheel` hinge (the rig's), at
-- `GripAngle` either side of the top, turned with the wheel, so the hands follow it. A car
-- with no rig, or no wheel, gets a wheel where the liftback's is from the seat
-- (`FallbackWheel`). Everything is solved in the avatar's ROOT frame, and the grips are
-- fixed in the car's body, so it does not matter which of the car, the root and this runs
-- first in a frame: the car and the root move together.
--
-- WHO: a car's `Driver` attribute names its driver (`Driver.driverOf`), and a driver is
-- seated while the server holds its root anchored -- the same test `Driver.placeIn` uses.
-- On getting out the pose fades back to the animation over `PoseFadeSeconds` and the
-- avatar is let go: from then on nothing here writes to it.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarParts = require(ReplicatedStorage.Shared.CarParts)
local Config = require(ReplicatedStorage.Shared.Config)
local Driver = require(script.Parent.Driver)

local DriverPose = {}

local WHEEL = "SteeringWheel"
local SIDES = { Left = -1, Right = 1 } -- which way is out, in the avatar's root frame

-- Every avatar being posed: character -> poser.
local posers: { [Model]: any } = {}
DriverPose.posers = posers

-- ---------------------------------------------------------------- joints

-- A joint's two parts and its two frames, `Motor6D` or `AnimationConstraint`. For both,
-- Part1.CFrame * C1 == Part0.CFrame * C0 * Transform.
local function jointFrames(joint: Instance)
	if joint:IsA("Motor6D") then
		return joint.Part0, joint.Part1, joint.C0, joint.C1
	end
	if joint:IsA("AnimationConstraint") then
		local a0, a1 = joint.Attachment0, joint.Attachment1
		if a0 and a1 then
			return a0.Parent, a1.Parent, a0.CFrame, a1.CFrame
		end
	end
	return nil
end

-- part1 -> joint, for the avatar's own body (not its accessories).
local function jointMap(character: Model)
	local map = {}
	for _, d in character:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and not d:FindFirstAncestorOfClass("Accessory") then
			local _, p1 = jointFrames(d)
			if p1 and p1:IsA("BasePart") and not map[p1] then
				map[p1] = d
			end
		end
	end
	return map
end

-- ---------------------------------------------------------------- the solve

-- The rotation that takes local direction `la` onto `wa`, turning local `lb` as near to
-- `wb` as it can go.
local function basis(a: Vector3, b: Vector3): CFrame?
	if a.Magnitude < 1e-6 then
		return nil
	end
	local x = a.Unit
	local perp = b - x * b:Dot(x)
	if perp.Magnitude < 1e-6 then
		perp = (if math.abs(x.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis)
		perp -= x * perp:Dot(x)
	end
	local y = perp.Unit
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end

local function align(la: Vector3, lb: Vector3, wa: Vector3, wb: Vector3): CFrame
	local l, w = basis(la, lb), basis(wa, wb)
	if not l or not w then
		return CFrame.identity
	end
	return w * l:Inverse()
end

-- A config direction given for the RIGHT arm, for `side`: the left arm's is its mirror.
local function sided(v: Vector3, side: number): Vector3
	return Vector3.new(v.X * side, v.Y, v.Z)
end

-- Where a part is in the root's frame this frame: down the joints from the root, with the
-- Transforms the Animator has just written.
local function inRoot(p, part: BasePart): CFrame
	local cached = p.frameCache[part]
	if cached then
		return cached
	end
	local cf = CFrame.identity
	if part ~= p.root then
		local joint = p.joints[part]
		local p0, c0, c1
		if joint then
			local a, _, b, c = jointFrames(joint)
			p0, c0, c1 = a, b, c
		end
		if p0 and c0 and c1 then
			cf = inRoot(p, p0) * c0 * joint.Transform * c1:Inverse()
		end
	end
	p.frameCache[part] = cf
	return cf
end

local function write(joint: Instance, transform: CFrame, weight: number)
	if weight >= 1 then
		joint.Transform = transform
	else
		joint.Transform = joint.Transform:Lerp(transform, weight)
	end
end

-- One R15 arm: the shoulder, the elbow and the wrist. The hand's grip point goes to `target`
-- (root frame), the elbow bends toward `pole`. Returns how far the grip falls short.
local function solveR15(p, arm, target: Vector3, weight: number): number
	local E = Config.CarEntry
	local _, _, c0s, c1s = jointFrames(arm.shoulder)
	local _, _, c0e, c1e = jointFrames(arm.elbow)
	local _, _, c0w, c1w = jointFrames(arm.wrist)
	if not (c0s and c0e and c0w) then
		return math.huge
	end
	local side = arm.side
	local shoulderFrame = inRoot(p, arm.torso) * c0s
	local S = shoulderFrame.Position

	-- The two bones, in their own parts' frames. The grip is in the forearm's frame with the
	-- wrist straight, so the forearm's bone runs from the elbow to the grip.
	local sU, eU = c1s.Position, c0e.Position
	local eL = c1e.Position
	local gL = (c0w * c1w:Inverse()):PointToWorldSpace(arm.gripLocal)
	local L1, L2 = (eU - sU).Magnitude, (gL - eL).Magnitude

	local toT = target - S
	local d = math.clamp(toT.Magnitude, math.abs(L1 - L2) + 1e-3, L1 + L2 - 1e-3)
	local dir = if toT.Magnitude > 1e-6 then toT.Unit else Vector3.new(0, 0, -1)
	local pole = sided(E.PoseElbowPole, side)
	pole -= dir * pole:Dot(dir)
	if pole.Magnitude < 1e-6 then
		pole = Vector3.new(0, -1, 0) - dir * (-dir.Y)
	end
	local a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
	local h = math.sqrt(math.max(L1 * L1 - a * a, 0))
	local elbow = S + dir * a + pole.Unit * h
	local reached = S + dir * d

	-- The upper arm: its bone onto shoulder->elbow, its outside (the way the part sits off its
	-- shoulder joint) turned toward `PoseUpperArmOutside`.
	local outU = -sU
	if (outU - (eU - sU).Unit * outU:Dot((eU - sU).Unit)).Magnitude < 0.05 then
		outU = Vector3.xAxis * side
	end
	local rotU = align(eU - sU, outU, elbow - S, sided(E.PoseUpperArmOutside, side))
	local U = CFrame.new(S - rotU:VectorToWorldSpace(sU)) * rotU

	-- The forearm: its bone onto elbow->grip, its outside toward `PoseForearmOutside`.
	local elbowAt = U:PointToWorldSpace(eU)
	local rotL = align(gL - eL, Vector3.xAxis * side, reached - elbowAt, sided(E.PoseForearmOutside, side))
	local L = CFrame.new(elbowAt - rotL:VectorToWorldSpace(eL)) * rotL

	write(arm.shoulder, shoulderFrame:Inverse() * U * c1s, weight)
	write(arm.elbow, (U * c0e):Inverse() * L * c1e, weight)
	write(arm.wrist, CFrame.identity, weight)
	return (L:PointToWorldSpace(gL) - target).Magnitude
end

-- One R6 arm: a single bone, pointed from the shoulder at the grip.
local function solveR6(p, arm, target: Vector3, weight: number): number
	local E = Config.CarEntry
	local _, _, c0s, c1s = jointFrames(arm.shoulder)
	if not c0s then
		return math.huge
	end
	local side = arm.side
	local shoulderFrame = inRoot(p, arm.torso) * c0s
	local S = shoulderFrame.Position
	local sU = c1s.Position
	-- Hung off its shoulder by half its width, like an R15 upper arm: its outside turned the
	-- same way keeps it inside the door.
	local rot = align(arm.gripLocal - sU, -sU, target - S, sided(E.PoseUpperArmOutside, side))
	local U = CFrame.new(S - rot:VectorToWorldSpace(sU)) * rot
	write(arm.shoulder, shoulderFrame:Inverse() * U * c1s, weight)
	return (U:PointToWorldSpace(arm.gripLocal) - target).Magnitude
end

-- ---------------------------------------------------------------- the wheel

-- The steering wheel in the car's body frame (pivot turned by the wheel's angle) and its
-- column axis; for a car with no rig or no wheel, the stand-in wheel off the seat.
function DriverPose.wheel(car: Instance): (CFrame, Vector3, boolean)
	local desc = CarParts.isRig(car) and CarParts.describe(car) or nil
	local g = desc and desc.byName[WHEEL]
	if g and g.kind == "hinge" then
		local frame
		if g.on then
			frame = CarParts.frames(car, desc)[WHEEL]
		else
			frame = g.link * CFrame.fromAxisAngle(g.axis, math.rad(CarParts.angle(car, WHEEL)))
		end
		return frame, g.axis, true
	end
	local E = Config.CarEntry
	local seat = Driver.points(car)
	return CFrame.new(seat:PointToWorldSpace(E.FallbackWheel)), seat:VectorToWorldSpace(E.FallbackWheelAxis).Unit, false
end

-- A point on the rim, in the car's body frame: `degrees` round from the top of the wheel
-- (toward the driver's right), in the wheel's own frame, so it turns with the wheel.
local function rimPoint(frame: CFrame, axis: Vector3, degrees: number): Vector3
	local E = Config.CarEntry
	local up = Vector3.yAxis - axis * axis.Y
	up = if up.Magnitude > 1e-4 then up.Unit else Vector3.new(0, 0, -1)
	local right = up:Cross(axis)
	local t = math.rad(degrees)
	return frame:PointToWorldSpace((right * math.sin(t) + up * math.cos(t)) * E.GripRadius + axis * E.GripLift)
end

-- The two grip points on the rim, in the car's body frame: `GripAngle` degrees either side
-- of the top of the wheel, turned with it.
function DriverPose.grips(car: Instance): { [string]: Vector3 }
	local E = Config.CarEntry
	local frame, axis = DriverPose.wheel(car)
	local out = {}
	for name, side in SIDES do
		out[name] = rimPoint(frame, axis, E.GripAngle * side)
	end
	return out
end

-- ---------------------------------------------------------------- posers

local function newPoser(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = Driver.rootOf(character)
	if not humanoid or not root then
		return nil
	end
	local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
	local joints = jointMap(character)
	local arms = {}
	for name, side in SIDES do
		local arm
		if r6 then
			local limb = character:FindFirstChild(name .. " Arm")
			local shoulder = limb and joints[limb]
			if shoulder then
				local grip = limb:FindFirstChild(name .. "GripAttachment")
				arm = {
					side = side,
					shoulder = shoulder,
					torso = (jointFrames(shoulder)),
					gripLocal = if grip and grip:IsA("Attachment") then grip.Position else Vector3.new(0, -limb.Size.Y * 0.5, 0),
				}
			end
		else
			local upper = character:FindFirstChild(name .. "UpperArm")
			local lower = character:FindFirstChild(name .. "LowerArm")
			local hand = character:FindFirstChild(name .. "Hand")
			local shoulder, elbow, wrist = upper and joints[upper], lower and joints[lower], hand and joints[hand]
			if shoulder and elbow and wrist then
				local grip = hand:FindFirstChild(name .. "GripAttachment")
				arm = {
					side = side,
					shoulder = shoulder,
					elbow = elbow,
					wrist = wrist,
					torso = (jointFrames(shoulder)),
					gripLocal = if grip and grip:IsA("Attachment") then grip.Position else Vector3.new(0, -hand.Size.Y * 0.5, 0),
				}
			end
		end
		if arm and arm.torso then
			arms[name] = arm
		end
	end
	if next(arms) == nil then
		return nil
	end
	return {
		character = character,
		root = root,
		r6 = r6,
		joints = joints,
		arms = arms,
		weight = 0,
		goal = 1,
		car = nil,
		frameCache = {},
		gaps = {},
		targets = {}, -- root frame
	}
end

-- An R15 arm's shoulder (root frame) and how far its grip reaches from it, the arm straight.
-- Nil for R6: a straight arm only points.
local function shoulderReach(p, arm): (Vector3?, number)
	if p.r6 then
		return nil, 0
	end
	local _, _, c0s, c1s = jointFrames(arm.shoulder)
	local _, _, c0e, c1e = jointFrames(arm.elbow)
	local _, _, c0w, c1w = jointFrames(arm.wrist)
	if not (c0s and c0e and c0w) then
		return nil, 0
	end
	local gL = (c0w * c1w:Inverse()):PointToWorldSpace(arm.gripLocal)
	local reach = (c0e.Position - c1s.Position).Magnitude + (gL - c1e.Position).Magnitude
	return (inRoot(p, arm.torso) * c0s).Position, reach
end

local function pose(p, weight: number)
	table.clear(p.frameCache)
	local E = Config.CarEntry
	-- A car gone mid-fade still answers for where its wheel was: its attributes stay.
	local car = p.car
	if not car then
		return
	end
	local seat = Driver.points(car)
	local rootInBody = seat * CFrame.new(0, E.RootAboveSeat, 0)
	local frame, axis = DriverPose.wheel(car)
	local still = CFrame.new(frame.Position)
	local function toRoot(v: Vector3): Vector3
		return rootInBody:PointToObjectSpace(v)
	end
	for name, arm in p.arms do
		local base = E.GripAngle * arm.side
		local target = toRoot(rimPoint(frame, axis, base))
		-- A wheel turned far enough takes a grip out of an arm's reach: that hand slides
		-- round the rim to the nearest place it can hold, nearest to where it started.
		local S, reach = shoulderReach(p, arm)
		if S and (target - S).Magnitude > reach * E.GripReach then
			local home = toRoot(rimPoint(still, axis, base))
			local best = nil
			for k = E.GripSlideStep, 180, E.GripSlideStep do
				for _, sign in { 1, -1 } do
					local t = toRoot(rimPoint(frame, axis, base + k * sign))
					if (t - S).Magnitude <= reach * E.GripReach and (not best or (t - home).Magnitude < (best - home).Magnitude) then
						best = t
					end
				end
				if best then
					break
				end
			end
			target = best or target
		end
		p.targets[name] = target
		local ok, gap = pcall(if p.r6 then solveR6 else solveR15, p, arm, target, weight)
		p.gaps[name] = if ok then gap else math.huge
		if not ok and p.error ~= gap then
			p.error = gap
			warn(`[DriverPose] {p.character.Name}'s {name} arm: {gap}`)
		end
	end
end

-- Let an avatar go: forget it. Nothing was added to it, and from the next frame the
-- Animator alone writes its joints.
local function release(character: Model)
	posers[character] = nil
end

-- One frame: find every seated driver, ease each pose toward on or off, and write it.
function DriverPose.step(folder: Instance?, dt: number)
	local E = Config.CarEntry
	local seated = {}
	if folder and E.DriverPose then
		for _, car in folder:GetChildren() do
			local character = Driver.characterOf(Driver.driverOf(car))
			local root = Driver.rootOf(character)
			if character and root and root.Anchored then
				local p = posers[character]
				if not p or p.root ~= root then
					p = newPoser(character)
					posers[character] = p
				end
				if p then
					p.car = car
					seated[character] = true
				end
			end
		end
	end
	local rate = dt / math.max(E.PoseFadeSeconds, 1e-3)
	for character, p in posers do
		p.goal = if seated[character] then 1 else 0
		if not character.Parent or not p.root.Parent then
			release(character)
			continue
		end
		p.weight = math.clamp(p.weight + (if p.goal > 0 then rate else -rate), 0, 1)
		if p.weight <= 0 and p.goal == 0 then
			release(character)
			continue
		end
		pose(p, p.weight)
	end
end

-- Run it: after the Animator has written the frame's pose, before it is simulated and drawn.
function DriverPose.start(folder: Instance)
	if DriverPose._conn then
		DriverPose._conn:Disconnect()
	end
	DriverPose._conn = RunService.PreSimulation:Connect(function(dt)
		DriverPose.step(folder, dt)
	end)
end

-- For the tests: pose `character` in `car` once, fully, now, without keeping it. Returns
-- each hand's target on the rim in the world (the avatar's root standing where it sits)
-- and how far the solve left each grip from it; nil if the avatar has no arms to pose.
function DriverPose.poseNow(character: Model, car: Instance): ({ [string]: Vector3 }?, { [string]: number }?)
	local p = newPoser(character)
	if not p then
		return nil, nil
	end
	p.car = car
	pose(p, 1)
	local targets = {}
	for name, t in p.targets do
		targets[name] = p.root.CFrame:PointToWorldSpace(t)
	end
	return targets, p.gaps
end

function DriverPose.isPosing(character: Model?): boolean
	return character ~= nil and posers[character] ~= nil
end

-- Every posed avatar: who, how far into the pose, and how far each hand's grip ended up
-- from its target in the solve.
function DriverPose.debugState()
	local list = {}
	for character, p in posers do
		table.insert(list, {
			character = character.Name,
			r6 = p.r6,
			weight = p.weight,
			goal = p.goal,
			car = p.car and p.car.Name or nil,
			gaps = table.clone(p.gaps),
		})
	end
	return list
end

-- Where each hand's grip should be, in the world, for a posed avatar: for measuring.
function DriverPose.worldTargets(character: Model): { [string]: Vector3 }?
	local p = posers[character]
	if not p then
		return nil
	end
	local out = {}
	for name, t in p.targets do
		out[name] = p.root.CFrame:PointToWorldSpace(t)
	end
	return out
end

return DriverPose
