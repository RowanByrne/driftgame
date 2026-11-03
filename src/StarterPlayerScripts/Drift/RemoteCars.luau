--!nonstrict
-- RemoteCars: draws the other players' cars.
--
-- Only the car a client drives is simulated on that client (features/drift-model.md
-- "Server and client"). Everyone else's arrives as a pose at 20 Hz over `CarStateOther`
-- and is eased toward, so 20 packets a second do not read as 20 jumps a second.
--
-- These cars are anchored too: nothing here hands one to Roblox physics either.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Render = require(script.Parent.Render)

local RemoteCars = {}
RemoteCars.__index = RemoteCars

function RemoteCars.new(carsFolder: Instance, ownCar: Model?)
	local self = setmetatable({}, RemoteCars)
	self.folder = carsFolder
	self.ownCar = ownCar
	self.cars = {} -- userId -> { rig, cf, wheelSpin, drifting }
	return self
end

function RemoteCars:SetOwnCar(car: Model?)
	self.ownCar = car
end

function RemoteCars:_find(userId: number)
	local entry = self.cars[userId]
	if entry and entry.rig.car.Parent then
		return entry
	end
	for _, child in self.folder:GetChildren() do
		if child:IsA("Model") and child ~= self.ownCar and child:GetAttribute("UserId") == userId then
			entry = { rig = Render.rig(child), cf = child:GetPivot(), wheelSpin = 0, drifting = false }
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
		if not entry.rig.car.Parent then
			self.cars[userId] = nil
			continue
		end
		if entry.target then
			entry.cf = entry.cf:Lerp(entry.target, alpha)
			local speed = entry.velocity and entry.velocity.Magnitude or 0
			entry.wheelSpin += (speed / math.max(C.WheelDiameter * 0.5, 0.1)) * dt
			Render.place(entry.rig, entry.cf, 0, entry.wheelSpin)
		end
	end
end

function RemoteCars:DebugState()
	local list = {}
	for userId, entry in self.cars do
		table.insert(list, { userId = userId, position = entry.cf.Position, drifting = entry.drifting })
	end
	return list
end

return RemoteCars
