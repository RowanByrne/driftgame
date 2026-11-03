--!nonstrict
-- CarCameraController: the chase camera.
--
-- A camera that sits behind the car's nose is useless in a drift: at 40 degrees of slip
-- the nose points at the inside of the corner and the player cannot see where the car is
-- actually going. So the camera follows a direction blended between the car's heading and
-- its velocity (`CamVelocityLead`), and looks ahead along the velocity. Holding a slide
-- then keeps the corner exit on screen.
--
-- Field of view opens with speed, so top speed reads as fast rather than as a number.
-- Every number is in Config.Drift; none is in here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = script.Parent.Parent:WaitForChild("Drift")
local DriftModel = require(DriftFolder.Model)

local DriftController = require(script.Parent.DriftController)

local CarCameraController = {}

CarCameraController.Priority = 5 -- after DriftController, so a state exists to follow

local STEP_NAME = "DriftCamera"

function CarCameraController:Init()
	self.yaw = 0
	self.position = Vector3.zero
	self.started = false
	self.standstill = 0
end

function CarCameraController:Start()
	local camera = workspace.CurrentCamera
	if not camera then
		warn("[CarCameraController] there is no CurrentCamera")
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
	self.camera = camera

	-- A new camera arrives on respawn and on some Studio actions; take it over again.
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Scriptable
			self.camera = cam
			self.started = false
		end
	end)

	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value, function(dt)
		self:_frame(dt)
	end)
end

-- The direction the camera sits behind: the car's heading, leaned toward where the car is
-- really travelling. At a standstill there is no velocity to lean toward, so it holds the
-- heading rather than snapping about.
function CarCameraController:_leadYaw(state, dt: number): number
	local C = Config.Drift
	local speed = DriftModel.speed(state)
	if speed < C.MinSlipSpeed then
		self.standstill += dt
	else
		self.standstill = 0
	end
	if self.standstill > C.CamStandstillSeconds then
		return state.yaw
	end
	local fwd, right = DriftModel.axes(state.yaw)
	local velocity = fwd * state.u + right * state.v
	if velocity.Magnitude < 1e-3 or state.u < 0 then
		return state.yaw
	end
	local velDir = velocity.Unit
	local velYaw = math.atan2(-velDir.X, -velDir.Z)
	-- Blend the two headings the short way round.
	local diff = (velYaw - state.yaw + math.pi) % (2 * math.pi) - math.pi
	return state.yaw + diff * C.CamVelocityLead
end

function CarCameraController:_frame(dt: number)
	local camera = self.camera
	if not camera then
		return
	end
	local state = DriftController:CurrentState()
	if not state then
		return
	end
	local C = Config.Drift

	local wantedYaw = self:_leadYaw(state, dt)
	if not self.started then
		self.yaw = wantedYaw
		self.started = true
		self.position = state.position
	end

	local diff = (wantedYaw - self.yaw + math.pi) % (2 * math.pi) - math.pi
	self.yaw += diff * (1 - math.exp(-dt * C.CamYawStiffness))

	local back = Vector3.new(math.sin(self.yaw), 0, math.cos(self.yaw)) -- behind the look direction
	local wantedPosition = state.position + back * C.CamDistance + Vector3.yAxis * C.CamHeight
	self.position = self.position:Lerp(wantedPosition, 1 - math.exp(-dt * C.CamStiffness))

	local fwd, right = DriftModel.axes(state.yaw)
	local velocity = fwd * state.u + right * state.v
	local lookDir = if velocity.Magnitude > C.MinSlipSpeed then velocity.Unit else fwd
	local focus = state.position + lookDir * C.CamLookAhead + Vector3.yAxis * C.CamLookHeight

	-- Never let the camera stare at its own feet when the car is right below it.
	local toFocus = focus - self.position
	local flat = Vector3.new(toFocus.X, 0, toFocus.Z)
	if flat.Magnitude > 1e-3 then
		local maxDrop = flat.Magnitude * math.tan(math.rad(-C.CamMinPitch))
		if -toFocus.Y > maxDrop then
			focus = Vector3.new(focus.X, self.position.Y - maxDrop, focus.Z)
		end
	end

	camera.CFrame = CFrame.lookAt(self.position, focus)
	local speedFrac = math.clamp(DriftModel.speed(state) / C.TopSpeed, 0, 1)
	camera.FieldOfView = C.CamFovBase + (C.CamFovTop - C.CamFovBase) * speedFrac
end

function CarCameraController:DebugState()
	local state = DriftController:CurrentState()
	return {
		hasCamera = self.camera ~= nil,
		cameraType = self.camera and self.camera.CameraType.Name or "none",
		position = self.camera and self.camera.CFrame.Position or Vector3.zero,
		fieldOfView = self.camera and self.camera.FieldOfView or 0,
		followYawDeg = math.deg(self.yaw) % 360,
		carYawDeg = state and math.deg(state.yaw) % 360 or nil,
		leadDeg = if state then math.deg((self.yaw - state.yaw + math.pi) % (2 * math.pi) - math.pi) else nil,
		distanceToCar = if state and self.camera then (self.camera.CFrame.Position - state.position).Magnitude else nil,
	}
end

return CarCameraController
