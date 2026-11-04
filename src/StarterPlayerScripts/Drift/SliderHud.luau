--!nonstrict
-- SliderHud: the steering slider's art, and nothing else
-- (docs/game/features/drift-model.md "The control", "UI").
--
-- The reference draws the slider only while the finger is down, and that is the whole of
-- it: a track at the finger's own height, as wide as the travel the sensitivity setting
-- currently gives, with a knob that eases toward the real steering value. It is feedback,
-- not a widget -- nothing here is ever touched, and nothing here reads an input. The
-- gesture (Drift/DragControl) tells it what to draw, once a frame.
--
-- Programmer art, until the UI phase (docs/workflow/UI.md, docs/game/UI-INVENTORY.md).
-- The two numbers below are art, not tuning, so they are not in Config.Drift: the knob's
-- size is a thumb, and the ease is the reference's own slider speed.

local SliderHud = {}
SliderHud.__index = SliderHud

local TRACK = Color3.fromRGB(30, 32, 38)
local KNOB = Color3.fromRGB(235, 235, 240)
local TICK = Color3.fromRGB(150, 155, 165)

local KNOB_SIZE = 44 -- px
local TRACK_HEIGHT = 12 -- px
local KNOB_RATE = 10 -- per second, how fast the knob eases to the real value

function SliderHud.new(parent: Instance)
	local self = setmetatable({}, SliderHud)

	local track = Instance.new("Frame")
	track.Name = "SteeringTrack"
	track.BackgroundColor3 = TRACK
	track.BackgroundTransparency = 0.4
	track.BorderSizePixel = 0
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Size = UDim2.fromOffset(200, TRACK_HEIGHT)
	track.Position = UDim2.fromScale(0.5, 0.8)
	track.Visible = false
	track.ZIndex = 2
	track.Active = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = track
	track.Parent = parent
	self.track = track

	-- The middle of the travel, so the player can see where centred is.
	local tick = Instance.new("Frame")
	tick.Name = "Centre"
	tick.BackgroundColor3 = TICK
	tick.BackgroundTransparency = 0.3
	tick.BorderSizePixel = 0
	tick.AnchorPoint = Vector2.new(0.5, 0.5)
	tick.Position = UDim2.fromScale(0.5, 0.5)
	tick.Size = UDim2.fromOffset(2, TRACK_HEIGHT + 8)
	tick.ZIndex = 3
	tick.Parent = track

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.BackgroundColor3 = KNOB
	knob.BackgroundTransparency = 0.1
	knob.BorderSizePixel = 0
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.ZIndex = 4
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob
	knob.Parent = track
	self.knob = knob

	self.shown = false
	self.knobX = 0 -- px from the middle of the track, eased
	self.travelPx = 0
	return self
end

-- Once a frame, from the gesture. `centreX`/`centreY` are where the middle of the travel
-- sits on screen in this frame's input mode, `travelPx` is a full finger in pixels, and
-- `steer` is the real value the model is being given, -1 .. 1.
function SliderHud:Update(dt: number, shown: boolean, centreX: number, centreY: number, travelPx: number, steer: number)
	if not shown then
		if self.shown then
			-- The slider does not linger: it exists while the finger is down and not a
			-- frame longer, and the knob starts from the middle next time.
			self.shown = false
			self.knobX = 0
			self.knob.Position = UDim2.fromScale(0.5, 0.5)
			self.track.Visible = false
		end
		return
	end

	self.shown = true
	self.travelPx = travelPx
	self.track.Visible = true
	self.track.Size = UDim2.fromOffset(math.max(travelPx * 2, 1), TRACK_HEIGHT)
	self.track.Position = UDim2.fromOffset(centreX, centreY)

	local target = steer * travelPx
	local alpha = math.clamp(dt * KNOB_RATE, 0, 1)
	self.knobX += (target - self.knobX) * alpha
	self.knob.Position = UDim2.new(0.5, self.knobX, 0.5, 0)
end

function SliderHud:DebugState()
	return {
		shown = self.shown,
		visible = self.track.Visible,
		travelPx = self.travelPx,
		knobPx = self.knobX,
		trackWidth = self.track.AbsoluteSize.X,
		centreX = self.track.Position.X.Offset,
		centreY = self.track.Position.Y.Offset,
	}
end

function SliderHud:Destroy()
	self.track:Destroy()
end

return SliderHud
