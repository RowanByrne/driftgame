--@localscript
-- TestHud: the two testing buttons, bottom left
-- (docs/game/features/test-hill.md, docs/workflow/UI.md "Programmer art").
--
-- IT IS A TESTING HUD AND IT SAYS SO. The user asked for things they could not do
-- while judging the downhill work: get to the top of a hill without driving up it, and
-- (until T-140) turn the guardrails off. The road has no guardrails any more
-- (features/mountain-road.md), so that button is gone. Nothing here is a game feature
-- and none of it ships, so the panel is labelled `TEST ONLY`, it is a colour nothing
-- else in the game uses, and it is deliberately ugly.
--
-- ONE SCREEN, NOT TWO. Both buttons are the same kind of thing -- "do this to the world
-- so I can look at it" -- and a second `ScreenGui` would be a second `DisplayOrder` to
-- keep in step with the drag pad's.
--
-- WHAT THE CLIENT MAY SAY IS ONE OF THREE STRINGS, and that is the whole of the trust
-- boundary (features/endless-run.md "Server and client", which settles this exact
-- question). It sends `"lift"`, or nil for "what is the state?". IT NEVER
-- SENDS A POSITION: where the top of the hill is, is the server's own number, read off
-- the pieces `PlaygroundService` placed. A client that could name where to put its car
-- would be a client with a teleport.
--
-- WHY IT DOES NOT STEER THE CAR. The whole screen is a drag pad and its horizontal
-- distance IS the car's rate of turn (`Drift/DragControl`), so a thumb on either button
-- would also be a thumb hauling the car round. It is not, because this ScreenGui sits at
-- a higher `DisplayOrder` than the pad's and both buttons are Active GuiObjects: the
-- touch is consumed here and the pad never sees it begin.
--
-- WHY IT IS A LocalScript AND NOT A CONTROLLER, for the same reason `Drift/RoadHud` is:
-- the client loader only loads `Controllers/`, and this talks to one remote and nothing
-- else. As a LocalScript it starts itself and `DriftController` does not grow a line to
-- carry it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local tools = Net.event("TestTools")

--------------------------------------------------------------------------------
-- Art, which is to say: none, and loudly
--------------------------------------------------------------------------------

local TEST = Color3.fromRGB(176, 42, 148) -- a magenta nothing else in the game uses
local LIVE = Color3.fromRGB(150, 54, 48) -- the world is not as it ships
local INK = Color3.fromRGB(240, 242, 248)
local DIM = Color3.fromRGB(222, 196, 226)

-- One size at every layout, for the same reason the start button is
-- (`UI-INVENTORY.md`): 200 px fits inside the narrowest supported screen (390 px, a phone
-- in portrait) with room either side, and the bottom left corner is the one part of the
-- screen nothing else in this game uses -- the readout is top left, the tuner and the DBG
-- button top right, the start button top middle, the handbrake bottom right and the
-- steering slider bottom middle.
local WIDTH, HEIGHT = 200, 40
local GAP = 6
local EDGE = 16
local HEADER = 16

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DriftTest"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true -- bottom left: Roblox's own chrome is nowhere near it
-- `Instance.new("ScreenGui")` still defaults to the legacy `Global` ZIndexBehavior, in
-- which a child does NOT draw above its parent: every ZIndex in the tree is compared
-- against every other, so a label inside a button can be painted over by the button's own
-- background. That bug has already cost this game a day once (`Drift/TunerUI`). `Sibling`
-- is what this file assumes throughout.
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- ABOVE THE DRAG PAD (`DriftControls`, DisplayOrder 5) and below the tuner (20). This one
-- number is what makes a thumb on a button a press and not a steering input. It is above
-- the start button's 15 as well, though the two never share a pixel.
gui.DisplayOrder = 16
gui.Parent = playerGui

local function newButton(name: string, text: string, y: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.new(0, EDGE, 1, -y)
	button.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	button.BackgroundColor3 = TEST
	button.BackgroundTransparency = 0.1
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Active = true -- it eats the touch, so the drag pad never sees it
	button.Text = text
	button.TextColor3 = INK
	button.TextSize = 15
	button.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	button.ZIndex = 2
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = button
	return button
end

local lift = newButton("LiftToTop", "LIFT TO HILL TOP", EDGE)

-- What this panel is, said in words. A colour is not a warning anyone can read out loud,
-- and the one thing that must never happen is this going out with the game.
local header = Instance.new("TextLabel")
header.Name = "TestOnly"
header.AnchorPoint = Vector2.new(0, 1)
header.Position = UDim2.new(0, EDGE, 1, -(EDGE + (HEIGHT + GAP) * 1))
header.Size = UDim2.fromOffset(WIDTH, HEADER)
header.BackgroundTransparency = 1
header.Text = "TEST ONLY -- NOT SHIPPING"
header.TextColor3 = DIM
header.TextXAlignment = Enum.TextXAlignment.Left
header.TextSize = 13
header.FontFace = Font.fromEnum(Enum.Font.Gotham)
-- It sits over the world, not over a panel, and light text on a bright sky is the "i
-- can't see the text" bug this game has already had twice (T-040).
header.TextStrokeColor3 = Color3.new(0, 0, 0)
header.TextStrokeTransparency = 0.35
header.ZIndex = 2
header.Parent = gui

--------------------------------------------------------------------------------
-- What the server says
--------------------------------------------------------------------------------

-- The last thing the SERVER said, and the only thing the buttons read. Never written by a
-- press: a press is a request, and the answer is what moves this.
local state = { hill = false }
local asked = 0 -- presses sent, for the tests
local told = 0 -- answers taken

local function paint()
	lift.Text = if state.hill then "LIFT TO HILL TOP" else "NO HILL HERE"
	lift.BackgroundColor3 = if state.hill then TEST else Color3.fromRGB(86, 86, 94)
end

local function ask(what: string?)
	asked += 1
	tools:FireServer(what)
end

lift.Activated:Connect(function()
	ask("lift")
end)

tools.OnClientEvent:Connect(function(answer)
	if type(answer) ~= "table" then
		return
	end
	told += 1
	state = { hill = answer.hill == true }
	paint()
end)

paint()
-- The question, asked once, so the button shows whether there is a hill here.
ask(nil)

--------------------------------------------------------------------------------
-- The spline test road (Studio only, T-134)
--------------------------------------------------------------------------------
-- A third button: lay a spline road far from everything and drive it, before the run
-- uses one (`SplineTestService`, features/spline-road.md). The server chooses the road
-- and sends its sections; this replays them into the client's own copy of the curve and
-- hands it to `DriftController`, whose car then stands on the maths.
local splineOn = false
local splineButton: TextButton? = nil
local runModeButton: TextButton? = nil
local runMode = "spline"
if RunService:IsStudio() then
	local DriftController = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers"):WaitForChild("DriftController"))
	local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
	local splineRemote = Net.event("SplineTest")
	local button = newButton("SplineRoad", "SPLINE TEST ROAD", EDGE + (HEIGHT + GAP) * 1)
	splineButton = button
	-- WHICH ROAD THE NEXT ENDLESS RUN LAYS (T-136): the spline road, as shipped since
	-- T-140, or the old piece road. Refused while a run is going; the start button then
	-- lays whichever this says.
	local modeButton = newButton("RunRoad", "RUN ROAD: SPLINE", EDGE + (HEIGHT + GAP) * 2)
	runModeButton = modeButton
	header.Position = UDim2.new(0, EDGE, 1, -(EDGE + (HEIGHT + GAP) * 3))

	local function paintSpline()
		button.Text = if splineOn then "LEAVE SPLINE ROAD" else "SPLINE TEST ROAD"
		button.BackgroundColor3 = if splineOn then LIVE else TEST
		modeButton.Text = if runMode == "spline" then "RUN ROAD: SPLINE" else "RUN ROAD: PIECES"
		modeButton.BackgroundColor3 = if runMode == "spline" then TEST else LIVE
	end

	modeButton.Activated:Connect(function()
		splineRemote:FireServer("mode")
	end)

	button.Activated:Connect(function()
		splineRemote:FireServer("toggle")
	end)

	splineRemote.OnClientEvent:Connect(function(answer)
		if type(answer) ~= "table" then
			return
		end
		if answer.runMode == "spline" or answer.runMode == "pieces" then
			runMode = answer.runMode
		end
		local o = answer.origin
		if answer.on == true and type(answer.sections) == "table" and type(o) == "table" and not splineOn then
			local fall = if type(answer.fall) == "number" then answer.fall else nil
			local ok, spline = pcall(SplineGen.replay, answer.sections, { x = o.x, y = o.y, z = o.z, yaw = o.yaw }, fall)
			if ok then
				splineOn = true
				DriftController:UseSpline(spline)
			else
				warn(`[TestHud] the spline road's sections would not replay: {spline}`)
			end
		elseif answer.on ~= true and splineOn then
			splineOn = false
			DriftController:UseSpline(nil)
		end
		paintSpline()
	end)

	paintSpline()
	splineRemote:FireServer(nil)
end

--------------------------------------------------------------------------------
-- The bridge
--------------------------------------------------------------------------------

-- Studio only, and the same shape as `Drift/RoadHud`'s: the client loader's own
-- `DebugBridge` resolves loaded Controllers, and this is a LocalScript, so it carries its
-- own. `Invoke("DebugState")`, `Invoke("DebugPress", "lift" | "spline" | "mode")`.
if RunService:IsStudio() then
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "TestHudBridge"
	bridge.OnInvoke = function(member: string, ...)
		if member == "DebugState" then
			return {
				hill = state.hill,
				asked = asked,
				told = told,
				liftText = lift.Text,
				visible = gui.Enabled and lift.Visible,
				liftPosition = lift.AbsolutePosition,
				liftSize = lift.AbsoluteSize,
				displayOrder = gui.DisplayOrder,
				zIndexBehavior = gui.ZIndexBehavior.Name,
				splineOn = splineOn,
				splineText = splineButton and splineButton.Text or nil,
				runMode = runMode,
				runModeText = runModeButton and runModeButton.Text or nil,
			}
		elseif member == "DebugPress" then
			-- Through the real handler, not past it: what a tap does.
			local what = ...
			if what == "spline" and splineButton then
				Net.event("SplineTest"):FireServer("toggle")
				return { wanted = what }
			end
			if what == "mode" and runModeButton then
				Net.event("SplineTest"):FireServer("mode")
				return { wanted = what }
			end
			ask(what)
			return { asked = asked, wanted = what }
		end
		error(`TestHudBridge: no member '{tostring(member)}'. Try DebugState or DebugPress.`)
	end
	bridge.Parent = Players.LocalPlayer:WaitForChild("PlayerScripts")
end
