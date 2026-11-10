--!nonstrict
-- Driver: the avatar in the driver's seat (docs/game/features/car-v2.md, T-096).
--
-- There is no Seat, weld, joint or constraint in a car (DECISIONS.md, 2026-11-03;
-- `CarModel.physicsOffenders`). A seated avatar is held by nothing at all: the server
-- anchors its root, and every client writes that root's CFrame each frame from the car it
-- has JUST drawn -- `DriftController` for the car this client drives, `RemoteCars` for
-- everyone else's -- so the driver is never a frame behind the car, at any speed. An anchored
-- part's CFrame written on a client stays on that client, which is exactly right: each
-- client draws every car itself, and puts each driver in the car it drew.
--
-- WHO is in a car is the car's `Driver` attribute (a UserId; `Config.CarEntry.
-- DriverAttribute`), which only the server writes. WHERE comes off the car's rig -- its
-- `Seat` (hips) and `Exit` (feet) points -- and from `Config.CarEntry` for a car with no rig,
-- which is every car today.
--
-- Pure enough for the server: `CarService` and `CarEntryTests` require it for the same
-- points, so the server and the clients cannot disagree about where the seat is. The sit
-- animation (`newSitter`) is the only part that only means anything on a client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarParts = require(ReplicatedStorage.Shared.CarParts)
local Config = require(ReplicatedStorage.Shared.Config)

local Driver = {}

-- Studio tests only: stand-in drivers by UserId, looked up before `Players`. A solo
-- playtest has one player, so the remote view of a driver is proven on a dummy avatar in a
-- dummy car; this is how `RemoteCars` finds it without a second client.
Driver.debugCharacters = {} :: { [number]: Model }

-- The seat (hips) and exit (feet) points in the car's frame, and whether they came off a
-- rig. A rig's points win; a car without one, or a rig without them, has the fallbacks.
function Driver.points(car: Instance?): (CFrame, CFrame, boolean)
	local E = Config.CarEntry
	local seat, exit, fromRig = E.SeatFallback, E.ExitFallback, false
	if car and CarParts.isRig(car) then
		local desc = CarParts.describe(car)
		if desc then
			if desc.seat then
				seat, fromRig = desc.seat, true
			end
			if desc.exit then
				exit = desc.exit
			end
		end
	end
	return seat, exit, fromRig
end

function Driver.rootOf(character: Instance?): BasePart?
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = (humanoid and humanoid.RootPart) or character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- How far above its feet an avatar's root is when it stands. R15 says so itself
-- (`HipHeight` is from the ground to the bottom of the root); R6 has no hip height to read.
function Driver.rootAboveFeet(character: Instance?): number
	local E = Config.CarEntry
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = Driver.rootOf(character)
	if not humanoid or not root or humanoid.RigType == Enum.HumanoidRigType.R6 then
		return E.R6RootAboveFeet
	end
	return humanoid.HipHeight + root.Size.Y * 0.5
end

-- Where the root goes when the car's BODY is drawn at `bodyCF`. The body, not the car's
-- road frame: the seat is in the body, and the body leans.
function Driver.seatRoot(bodyCF: CFrame, car: Instance?): CFrame
	local seat = Driver.points(car)
	return bodyCF * seat * CFrame.new(0, Config.CarEntry.RootAboveSeat, 0)
end

-- Where the root goes when the avatar has got out of a car parked at `carCF`.
function Driver.exitRoot(carCF: CFrame, car: Instance?, character: Instance?): CFrame
	local _, exit = Driver.points(car)
	return carCF * exit * CFrame.new(0, Driver.rootAboveFeet(character), 0)
end

-- The driver's door, in the world: where the Get in prompt hangs and what the server
-- measures a request against. The exit point at hip height, beside the door.
function Driver.doorPoint(carCF: CFrame, car: Instance?): Vector3
	local _, exit = Driver.points(car)
	return (carCF * exit * CFrame.new(0, Config.CarEntry.DoorPromptHeight, 0)).Position
end

-- Who the server has in this car's driver's seat, or nil.
function Driver.driverOf(car: Instance?): number?
	if not car then
		return nil
	end
	local id = car:GetAttribute(Config.CarEntry.DriverAttribute)
	return if type(id) == "number" then id else nil
end

function Driver.characterOf(userId: number?): Model?
	if not userId then
		return nil
	end
	local stand = Driver.debugCharacters[userId]
	if stand and stand.Parent then
		return stand
	end
	local player = Players:GetPlayerByUserId(userId)
	return player and player.Character or nil
end

-- Put this car's driver in its seat, the car's body having just been drawn at `bodyCF`.
-- Writes only a root the server has anchored: an avatar on its way out is the physics'
-- again, and a write then would fight it. Returns the root and where it was put.
function Driver.placeIn(car: Instance, bodyCF: CFrame): (BasePart?, CFrame?)
	local root = Driver.rootOf(Driver.characterOf(Driver.driverOf(car)))
	if not root or not root.Anchored then
		return nil, nil
	end
	local target = Driver.seatRoot(bodyCF, car)
	root.CFrame = target
	return root, target
end

-- ---------------------------------------------------------------- the sit pose (client)
--
-- Roblox's own sit animation, played on the avatar's own Animator: an animation the owning
-- client plays replicates to everyone, so other players see the pose with no remote. The
-- avatar's `Animate.sit` is used when it has one, so a player with a custom sit keeps it.
-- `Action` priority so it holds over whatever the Animate script thinks an anchored
-- humanoid is doing.

local Sitter = {}
Sitter.__index = Sitter

function Driver.newSitter()
	return setmetatable({ character = nil, track = nil }, Sitter)
end

local function sitAnimation(character: Model): Animation
	local animate = character:FindFirstChild("Animate")
	local sit = animate and animate:FindFirstChild("sit")
	local own = sit and sit:FindFirstChildOfClass("Animation")
	if own and own.AnimationId ~= "" then
		return own
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local anim = Instance.new("Animation")
	anim.AnimationId = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6
		then Config.CarEntry.SitAnimationR6
		else Config.CarEntry.SitAnimationR15
	return anim
end

function Sitter:Sit(character: Model?): boolean
	if not character then
		return false
	end
	if self.character == character and self.track and self.track.IsPlaying then
		return true
	end
	self:Stand()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(sitAnimation(character))
	end)
	if not ok or not track then
		return false
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(Config.CarEntry.SitFadeSeconds)
	self.character, self.track = character, track
	return true
end

function Sitter:Stand()
	local track = self.track
	if track then
		local fade = Config.CarEntry.SitFadeSeconds
		track:Stop(fade)
		task.delay(fade + 0.1, function()
			track:Destroy()
		end)
	end
	self.character, self.track = nil, nil
end

function Sitter:IsSitting(): boolean
	return self.track ~= nil and self.track.IsPlaying
end

return Driver
