--@localscript
-- RoadHud: the start button, at the top of the screen
-- (docs/game/features/endless-run.md "The button", docs/workflow/UI.md).
--
-- The user asked for exactly this and nothing more: "have it be a button you press at the
-- top of the screen to start the endless mode". So it is one button, plainly styled,
-- programmer art like everything until the UI phase -- no panel, no art, no transition.
--
-- IT IS ALSO THE WAY BACK. The same control ends the run and returns the car to the world
-- it came from, and the button says which of the two it is about to do, because a button
-- that does two things and admits to neither is a button nobody presses twice.
--
-- THE CLIENT DOES NOT KNOW WHETHER IT IS IN A RUN. It is told. Every press fires
-- `RoadRun` with a single boolean -- "start" or "end" -- and the SERVER's answer is what
-- sets the button's state; a refused press (too quick, too many, a run already going)
-- lands back here as the state the server really has, so the button cannot be left
-- showing a run that does not exist. It asks the same question with `nil` the moment it
-- starts up, so a client that joined mid-run shows END and not START.
--
-- NOTHING ON THE WIRE FROM HERE IS A PLACE, A SEED OR A PIECE. The button sends a
-- boolean. The piece number on screen came down from the server, measured there from a
-- position the server had already agreed to (`RoadService`, `CONTRACTS.md`), and this file
-- never sends it back.
--
-- WHY IT DOES NOT STEER THE CAR. The whole screen is a drag pad and its horizontal
-- distance IS the car's rate of turn (`Drift/DragControl`), so a thumb on this button
-- would also be a thumb hauling the car round. It is not, because this ScreenGui sits at
-- a higher `DisplayOrder` than the pad's and the button is an Active GuiObject: the touch
-- is consumed here and the pad never sees it begin. The same trick `Drift/TunerUI` uses,
-- and it is measured (features/endless-run.md "Testing").
--
-- WHY IT IS A LocalScript AND NOT A CONTROLLER. The client loader only loads
-- `Controllers/`, and this talks to one remote and nothing else -- no controller reads it
-- and it reads no controller. As a LocalScript it starts itself and `DriftController` does
-- not grow a line to carry it, exactly as `Drift/TunerUI` does. The day the run has a real
-- HUD -- a score, a multiplier, a distance -- it becomes a controller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local roadRun = Net.event("RoadRun")

--------------------------------------------------------------------------------
-- Art, which is to say: none
--------------------------------------------------------------------------------

local IDLE = Color3.fromRGB(48, 120, 72) -- start: go
local LIVE = Color3.fromRGB(150, 54, 48) -- end: stop
local INK = Color3.fromRGB(240, 242, 248)
local DIM = Color3.fromRGB(190, 196, 210)

-- One size at every layout. The button is 220 x 44 px and centred at the top, which fits
-- inside the narrowest supported screen (390 px, a phone in portrait) with 85 px either
-- side, and sits clear of Roblox's own top-left chrome and top-right chat on every other.
local WIDTH, HEIGHT = 220, 44
local TOP = 8
local LABEL_HEIGHT = 18

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DriftRun"
gui.ResetOnSpawn = false
-- NOT `IgnoreGuiInset`, unlike the drag pad and the tuner. This is the one thing in the
-- game that sits at the TOP MIDDLE, where Roblox puts its own chrome, so it starts below
-- the inset rather than fighting it for the same pixels.
gui.IgnoreGuiInset = false
-- `Instance.new("ScreenGui")` still defaults to the legacy `Global` ZIndexBehavior, in
-- which a child does NOT draw above its parent: every ZIndex in the tree is compared
-- against every other, so a label inside a button can be painted over by the button's own
-- background. That bug has already cost this game a day once (`Drift/TunerUI`). `Sibling`
-- is what this file assumes throughout.
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- ABOVE THE DRAG PAD (`DriftControls`, DisplayOrder 5) and below the tuner (20). This one
-- number is what makes a thumb on the button a press and not a steering input.
gui.DisplayOrder = 15
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "StartRun"
button.AnchorPoint = Vector2.new(0.5, 0)
button.Position = UDim2.new(0.5, 0, 0, TOP)
button.Size = UDim2.fromOffset(WIDTH, HEIGHT)
button.BackgroundColor3 = IDLE
button.BackgroundTransparency = 0.1
button.BorderSizePixel = 0
button.AutoButtonColor = false
button.Active = true -- it eats the touch, so the drag pad never sees it
button.Text = "START ENDLESS RUN"
button.TextColor3 = INK
button.TextSize = 16
button.FontFace = Font.fromEnum(Enum.Font.GothamBold)
button.ZIndex = 2
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = button

-- What state it is in, said in words under it rather than only in a colour: a colour is
-- not a state anyone can read out loud, and this is a test build.
local label = Instance.new("TextLabel")
label.Name = "RunState"
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, TOP + HEIGHT + 4)
label.Size = UDim2.fromOffset(WIDTH + 80, LABEL_HEIGHT)
label.BackgroundTransparency = 1
label.Text = "not in a run"
label.TextColor3 = DIM
label.TextSize = 13
label.FontFace = Font.fromEnum(Enum.Font.Gotham)
-- It sits over the SKY, not over a plate, and light grey on a bright sky is the "i can't
-- see the text" bug this game has already had twice (T-040). A black stroke reads on
-- anything the camera can be pointing at, and costs no layout.
label.TextStrokeColor3 = Color3.new(0, 0, 0)
label.TextStrokeTransparency = 0.35
label.ZIndex = 2
label.Parent = gui

--------------------------------------------------------------------------------
-- What the server says
--------------------------------------------------------------------------------

-- The last thing the SERVER said, and the only thing the button reads. Never written by a
-- press: a press is a request, and the answer is what moves this.
local state = { running = false, inRun = false, players = 0, n = 0, furthestN = 0 }
local asked = 0 -- presses sent, for the tests
local told = 0 -- answers taken

local function paint()
	if state.inRun then
		button.Text = "END RUN"
		button.BackgroundColor3 = LIVE
		local others = math.max(state.players - 1, 0)
		local who = if others == 0
			then "alone"
			elseif others == 1 then "1 other driver"
			else `{others} other drivers`
		label.Text = `on the road -- piece {state.n}, {who}`
	else
		button.Text = "START ENDLESS RUN"
		button.BackgroundColor3 = IDLE
		label.Text = if state.running
			then `a run is going ({state.players} driving) -- press to join`
			else "not in a run"
	end
end

local function ask(want: boolean?)
	asked += 1
	roadRun:FireServer(want)
end

button.Activated:Connect(function()
	-- What to ask for follows the SERVER's state, not a local toggle: two presses in the
	-- same tick ask the same thing twice rather than cancelling each other out, and the
	-- second is refused by the server's cooldown.
	ask(not state.inRun)
end)

roadRun.OnClientEvent:Connect(function(answer)
	if type(answer) ~= "table" then
		return
	end
	told += 1
	state = {
		running = answer.running == true,
		inRun = answer.inRun == true,
		players = tonumber(answer.players) or 0,
		n = tonumber(answer.n) or 0,
		furthestN = tonumber(answer.furthestN) or 0,
	}
	paint()
end)

paint()
-- The question, asked once: a client that joined while a run was going, or that missed the
-- answer to its last press, is put in step by the reply.
ask(nil)

--------------------------------------------------------------------------------
-- The bridge
--------------------------------------------------------------------------------

-- Studio only, and the same shape as `Drift/TunerUI`'s: the client loader's own
-- `DebugBridge` resolves loaded Controllers, and this is a LocalScript, so it carries its
-- own. `Invoke("DebugState")`, `Invoke("DebugPress")`.
if RunService:IsStudio() then
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "RoadHudBridge"
	bridge.OnInvoke = function(member: string, ...)
		if member == "DebugState" then
			return {
				running = state.running,
				inRun = state.inRun,
				players = state.players,
				n = state.n,
				furthestN = state.furthestN,
				asked = asked,
				told = told,
				text = button.Text,
				labelText = label.Text,
				visible = gui.Enabled and button.Visible,
				position = button.AbsolutePosition,
				size = button.AbsoluteSize,
				displayOrder = gui.DisplayOrder,
				zIndexBehavior = gui.ZIndexBehavior.Name,
				colour = button.BackgroundColor3,
			}
		elseif member == "DebugPress" then
			-- Through the real handler, not past it: what a tap does.
			ask(not state.inRun)
			return { asked = asked, wanted = not state.inRun }
		end
		error(`RoadHudBridge: no member '{tostring(member)}'. Try DebugState or DebugPress.`)
	end
	bridge.Parent = Players.LocalPlayer:WaitForChild("PlayerScripts")
end
