--!strict
-- Config.CarEntry: getting in and out of the car (docs/game/features/car-v2.md, T-096).
--
-- The player spawns in the driver's seat, with their own avatar sitting in it. Below
-- `ExitSpeed` they can get out: the door opens, the avatar stands beside it and walks with
-- Roblox's own controls. A `ProximityPrompt` at the driver's door puts them back in.
--
-- The seated avatar is NOT held by a Seat, a weld or any joint (DECISIONS.md, 2026-11-03):
-- its root is anchored and written every frame by the same code that draws the car. The
-- points below are where; the rig's own `Seat` and `Exit` replace the two fallbacks for any
-- car built on it (CONTRACTS.md "The car rig").
--
-- A plain table with no write guard, like `Config.Road`, so a Studio session can move the
-- seat around and see it on the next frame.

return {
	-- Characters exist. Off puts back the old "the player is the car" (no avatar at all).
	Characters = true,

	-- The attribute on a car Model naming who sits in its driver's seat (a UserId). Absent
	-- is nobody: the car is parked and its owner is walking.
	DriverAttribute = "Driver",

	-- GETTING OUT ------------------------------------------------------------------------

	ExitSpeed = 8, -- studs/s across the ground: the Get out button shows below this
	-- The server checks the last speed it agreed to against `ExitSpeed` times this. A packet
	-- is 50 ms old by the time the press arrives, and a car slowing through 8 was honestly
	-- under it when the finger went down.
	ExitSpeedTolerance = 1.25,
	AnswerWait = 3, -- seconds the client holds the car waiting for an answer before driving on

	-- GETTING IN -------------------------------------------------------------------------

	PromptDistance = 8, -- studs: the Get in prompt shows within this of the driver's door
	-- What the server allows on top of `PromptDistance`: the character's position reaches it
	-- a few frames late, and a player walking past the door as they press is honest.
	EnterDistanceSlack = 4,
	PromptText = "Get in",
	WalkFieldOfView = 70, -- Roblox's own, for the walking camera: the drift camera widens it

	-- Requests a second per UserId, getting in and out together; the rest are refused.
	RateLimit = 4,

	-- THE DOOR ---------------------------------------------------------------------------

	DoorName = "DoorR", -- right-hand drive: the driver's door is on the right (CONTRACTS.md)
	-- A car with no rig has no door to open (today's cars). The steps still happen in
	-- order -- stand or sit, then hand the controls over -- with this pause in place of
	-- each door move. Zero: there is nothing to watch.
	NoDoorSeconds = 0,

	-- THE POINTS -------------------------------------------------------------------------
	-- In the CAR'S FRAME (CONTRACTS.md "The car rig"): origin `RideHeight` (2.4) above the
	-- road, front -Z, right +X. Used when a car has no rig, or its rig has no `Seat`/`Exit`.

	-- Where the seated avatar's HIPS go: the driver's cushion, right-hand drive, a little
	-- behind the middle of today's 14-stud block, low so the head stays under the roof.
	-- Only 1.05 to the right: a Roblox avatar sits 4 studs across at the elbows, and the
	-- shell's side at the door is 3.2 out (2.95 at the window), so any further and the right
	-- arm comes through the door (measured in DR-Lane2: 3.46 out at 1.35).
	SeatFallback = CFrame.new(1.05, -1.05, 0.9),
	-- Where the avatar's FEET go: on the road beside the driver's door, clear of it open.
	ExitFallback = CFrame.new(5.6, -2.4, 0.9),
	-- Where the Get in prompt hangs, above the exit point: about a standing avatar's chest.
	DoorPromptHeight = 2.5,

	-- The avatar's root above its hips while sitting, and above its feet while standing.
	-- Measured on an R15 avatar in DR-Lane2 (T-096): Roblox's sit pose holds the
	-- LowerTorso's centre 0.80 below the root, so the hips land on `Seat`. An R6 one stands
	-- on `R6RootAboveFeet`. Standing R15 is worked out from the avatar's own `HipHeight`, so
	-- a tall avatar's feet are on the road too.
	RootAboveSeat = 0.8,
	R6RootAboveFeet = 3,

	-- The sit pose: the avatar's own `Animate.sit` when it has one, else Roblox's default.
	SitAnimationR15 = "rbxassetid://2506281703",
	SitAnimationR6 = "rbxassetid://178130996",
	SitFadeSeconds = 0.15,

	-- THE BUTTON -------------------------------------------------------------------------
	-- Bottom right, stacked above the STOP button (Drift/DragControl: 96 x 96, 28 in from the
	-- corner), so the left of the screen and the middle stay the steering finger's. Above
	-- the drag pad's DisplayOrder 5, which is what makes a thumb on it a press.
	ButtonSize = Vector2.new(96, 48),
	ButtonMargin = 28, -- from the right edge, matching the STOP button
	ButtonAbove = 28 + 96 + 12, -- from the bottom: the STOP button and a gap
	DisplayOrder = 14,
	ButtonText = "GET OUT",
}
