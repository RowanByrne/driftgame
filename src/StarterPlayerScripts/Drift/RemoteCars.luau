--!nonstrict
-- RemoteCars: draws the other players' cars.
--
-- Only the car a client drives is simulated on that client (features/drift-model.md
-- "Server and client"). Everyone else's arrives as a pose at 20 Hz over `CarStateOther`
-- and is eased toward, so 20 packets a second do not read as 20 jumps a second.
--
-- These cars are anchored too: nothing here hands one to Roblox physics either. Every
-- part is written an ABSOLUTE CFrame through `Render` -- never `Model:PivotTo`, which
-- applies a delta and walks a server-owned shell away from the car it belongs to (T-020).
--
-- THE THING THIS MODULE MUST NEVER STOP DOING IS WRITING. A remote car is drawn only by
-- `Render.place`; the moment there is nothing to write through, that car stands at its
-- spawn for the rest of the session while its packets keep arriving and being applied to
-- nothing. That is T-016 again, on the other side of the wire, and `_ensureRig` below is
-- the same answer `DriftController:_ensureRig` gives for the car this client drives.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Render = require(script.Parent.Render)

local RemoteCars = {}
RemoteCars.__index = RemoteCars

-- Is this rig still holding parts that are in the car?
--
-- A rig is a handful of direct references, taken once. Two things make one useless, and
-- both leave `Render.place` silently writing nothing:
--
--   * it was built from a model whose parts had not replicated yet, so it caught nothing
--     -- which is EVERY remote car, because a car is caught the instant its Model lands in
--     `Workspace.Cars` and a Model replicates before its contents do;
--   * its parts have since left the car (a car rebuilt, a model streamed out).
--
-- `IsDescendantOf` rather than `.Parent ==` on purpose: a car's parts may sit inside a
-- sub-model -- the AE86's `Shell` groups do (Shared/CarModel) -- and a rig built from one
-- is still a rig this module can write through.
--
-- The shell is checked a group at a time, by its first part: a group is replicated,
-- rebuilt and destroyed whole, so one part of it standing in the car stands for all of
-- them, and five checks a frame is what this costs on a hundred-part car. Whether the
-- group is still ARRIVING is `rig.complete`'s business, and `Render.place` re-resolves an
-- incomplete rig itself until the last part lands.
local function shellStands(shell, car: Model): boolean
	if not shell then
		return true -- no shell group is not a missing one: a block car has none
	end
	local first = shell.parts[1]
	return first ~= nil and first.part:IsDescendantOf(car)
end

local function rigIsLive(rig, car: Model?): boolean
	if not rig or not car or rig.car ~= car then
		return false
	end
	if not rig.body or not rig.body:IsDescendantOf(car) then
		return false
	end
	local wheels = rig.wheels
	if not wheels or #wheels ~= 4 then
		return false
	end
	for _, wheel in wheels do
		if not wheel.part or not wheel.part:IsDescendantOf(car) then
			return false
		end
		if not shellStands(wheel.shell, car) then
			return false
		end
	end
	if not shellStands(rig.bodyShell, car) then
		return false
	end
	-- A car v2 rig (Shared/Cars/Rig) draws its wheels and opening parts through groups of
	-- its own, which `Render.place` writes from the body's frame each frame -- so a remote
	-- car's doors, hood and wheels ride with it exactly as the body does, and open wherever
	-- `Shared/CarParts` says. They are replaced with the shell, so one standing is enough:
	-- the first that has a part (a hub may have none).
	for _, entry in rig.groups or {} do
		if #entry.shell.parts > 0 then
			if not shellStands(entry.shell, car) then
				return false
			end
			break
		end
	end
	return true
end

local function rigParts(rig): number
	if not rig then
		return 0
	end
	return (if rig.body then 1 else 0) + #(rig.wheels or {})
end

function RemoteCars.new(carsFolder: Instance, ownCar: Model?)
	local self = setmetatable({}, RemoteCars)
	self.folder = carsFolder
	self.ownCar = ownCar
	self.cars = {} -- userId -> entry
	return self
end

function RemoteCars:SetOwnCar(car: Model?)
	self.ownCar = car
end

-- Is this model somebody else's car, drawn by this module?
--
-- `ownCar` is set when the local car is attached, which is after this module exists and
-- can be behind the server replacing that car, so the local player's UserId is the test
-- that always holds. Drawing our own car here would have this module and the controller
-- writing the same parts from two different poses.
function RemoteCars:_isRemote(car: Instance): boolean
	return car ~= self.ownCar and car:GetAttribute("UserId") ~= Players.LocalPlayer.UserId
end

-- Still the car this entry was made for, and still in the world?
function RemoteCars:_carStands(entry): boolean
	local car = entry.car
	return car.Parent ~= nil and car:IsDescendantOf(self.folder) and self:_isRemote(car)
end

-- Hold a rig that can actually draw this car, and take it again until it can.
--
-- The rig is NOT something taken once when the car appears. Taken then, it catches
-- nothing: `Workspace.Cars.ChildAdded` fires on a model with zero children. It is taken
-- again every frame until it holds parts that are in the car, and taken again if it ever
-- stops holding them -- a car rebuilt for the same player is the case that happens in
-- normal play.
function RemoteCars:_ensureRig(entry): boolean
	if rigIsLive(entry.rig, entry.car) then
		return true
	end
	entry.rig = Render.rig(entry.car)
	entry.rigAttempts += 1
	-- A rig that had to be retaken is a rig that drew nothing for a while, so the pose it
	-- comes back on is placed outright rather than eased toward from wherever the car was
	-- left standing.
	entry.drawn = false
	if entry.firstParts < 0 then
		entry.firstParts = rigParts(entry.rig)
	end
	if rigIsLive(entry.rig, entry.car) then
		if entry.liveAfter < 0 then
			entry.liveAfter = os.clock() - entry.bornAt
		end
		return true
	end
	-- A car whose parts never arrive is a car this player will never see moving, and
	-- silence is what made this bug cost a day on the local car. Said once per car.
	if not entry.warned and os.clock() - entry.bornAt > Config.Drift.RespawnAnswerWait then
		entry.warned = true
		warn(
			`[RemoteCars] {entry.car.Name} (user {entry.userId}) still has no parts to draw after `
				.. `{entry.rigAttempts} tries; that car will not move`
		)
	end
	return false
end

function RemoteCars:_find(userId: number)
	local entry = self.cars[userId]
	if entry then
		if self:_carStands(entry) then
			return entry
		end
		self.cars[userId] = nil -- gone, or replaced: fall through and look for the new one
	end
	for _, child in self.folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("UserId") == userId and self:_isRemote(child) then
			entry = {
				userId = userId,
				car = child,
				rig = Render.rig(child),
				cf = child:GetPivot(),
				wheelSpin = 0,
				drifting = false,
				drawn = false, -- nothing has been written through this rig yet
				bornAt = os.clock(),
				rigAttempts = 1,
				firstParts = -1,
				liveAfter = -1,
				warned = false,
			}
			entry.firstParts = rigParts(entry.rig)
			if rigIsLive(entry.rig, child) then
				entry.liveAfter = 0
			end
			self.cars[userId] = entry
			return entry
		end
	end
	return nil
end

function RemoteCars:OnState(userId: number, cf: CFrame, velocity: Vector3, drifting: boolean)
	local entry = self:_find(userId)
	if not entry then
		return
	end
	entry.target = cf
	entry.velocity = velocity
	entry.drifting = drifting == true
end

function RemoteCars:Update(dt: number)
	local C = Config.Drift
	local alpha = 1 - math.exp(-dt / math.max(C.RemoteCarSmoothing, 1e-3))
	for userId, entry in self.cars do
		if not self:_carStands(entry) then
			-- The player left, or the server took their car away: the entry goes with it
			-- and nothing of this car is held on to.
			self.cars[userId] = nil
			continue
		end
		if not entry.target then
			continue
		end
		-- The pose is eased whether or not there is anything to draw it on, so a car
		-- whose parts are still arriving is up to date the moment they land rather than
		-- starting its journey from wherever the model's pivot happened to be.
		entry.cf = entry.cf:Lerp(entry.target, alpha)
		local speed = entry.velocity and entry.velocity.Magnitude or 0
		entry.wheelSpin += (speed / math.max(C.WheelDiameter * 0.5, 0.1)) * dt
		if not self:_ensureRig(entry) then
			continue
		end
		if not entry.drawn then
			-- First write on this rig: the car is put where it is reported to be, not
			-- eased toward it from a pose nobody ever saw.
			entry.cf = entry.target
			entry.drawn = true
		end
		Render.place(entry.rig, entry.cf, 0, entry.wheelSpin)
	end
end

-- The other players' cars as this client draws them, for tests and agent playtests. An
-- array: `DriftController:DebugState()` counts it.
--
-- `firstParts = 0` names the race every remote car is born with -- a Model replicates
-- before its parts do -- and `liveAfter` is how long that car took to catch them. `gap`
-- is the studs between where the car is REPORTED to be and where it is DRAWN, which is
-- the smoothing distance at most and `-1` when nothing is drawn.
function RemoteCars:DebugState()
	local list = {}
	for userId, entry in self.cars do
		local body = entry.rig and entry.rig.body
		local drawnAt = if body and body:IsDescendantOf(entry.car) then body.Position else nil
		table.insert(list, {
			userId = userId,
			car = entry.car.Name,
			position = entry.cf.Position,
			reported = entry.target and entry.target.Position or nil,
			drawn = drawnAt,
			gap = if drawnAt and entry.target then (drawnAt - entry.target.Position).Magnitude else -1,
			drifting = entry.drifting,
			live = rigIsLive(entry.rig, entry.car),
			complete = entry.rig ~= nil and entry.rig.complete == true,
			parts = rigParts(entry.rig),
			attempts = entry.rigAttempts,
			firstParts = entry.firstParts,
			liveAfter = entry.liveAfter,
		})
	end
	return list
end

return RemoteCars
