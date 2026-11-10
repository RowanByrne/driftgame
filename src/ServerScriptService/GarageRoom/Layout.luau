--!strict
-- GarageRoom/Layout: the garage interior's geometry, written about the room's own origin
-- (docs/game/WORLD.md "Garage", docs/game/features/car-customization.md).
--
-- THE ROOM'S FRAME. The origin is the turntable's centre at floor level; the floor's top is
-- Y = 0. The roller door is in the -X wall and the car comes in heading +X. The back wall
-- (workbench, pegboard, window) is -Z, the parts shelves are on +X, and the front wall,
-- where the wide camera stands, is +Z -- so the wide camera looks the way the picked
-- concept does, with the door on its left. `Config.GarageRoom.Origin` and `Yaw` put this
-- frame in the world; nothing here is a world position.
--
-- Scale: the AE86 is 15.6 studs long and 6.8 wide (`Shared/Cars/AE86`), about 0.28 m to
-- the stud, so the room is about 15 m by 12 m with a 5 m roof -- a small two-car unit.

local Layout = {}

Layout.Room = {
	halfX = 26, -- inside face of the side walls
	halfZ = 22, -- inside face of the back and front walls
	height = 18, -- the underside of the roof
	wall = 1,
	stripeY = 5.5, -- the orange band round the walls, its centre
}

-- In the -X wall, centred on Z.
Layout.Door = {
	width = 18,
	height = 12,
	-- The roller door is rolled most of the way up: its bottom slat stops here, well
	-- over the car's roof (about 4.5 studs).
	slatBottom = 8.2,
	slats = 4,
}

Layout.Turntable = {
	radius = 10, -- the deck: room for the 15.6-stud car with 2 studs at either end
	deckTop = 0.2, -- above the floor; inside the 0.25 kerb the drift model takes
	deckDepth = 1.2, -- the part is buried 1 stud into the floor, so no edge shows daylight
	-- The bevel round the deck: a ring of wedges from the deck's height down to the floor,
	-- coloured in the concept's teal / grey / orange band. It does not spin.
	bevelInner = 9.8, -- overlaps the deck a little, so a ray at the seam finds one or the other
	bevelOuter = 11.5,
	segments = 16,
}

-- The painted bay round the turntable: a rectangle of orange line.
Layout.Bay = { halfX = 14, halfZ = 13, line = 0.6 }

-- Before the door: a street running along Z. The guardrail, the town and the dusk sky that
-- stood beyond it were taken out when the room moved into the yard (2026-11-10); `rail*` and
-- `Backdrop` other than its `seed` are no longer built.
Layout.Street = {
	nearX = -27, -- meets the garage floor here
	farX = -67,
	halfZ = 150,
	railX = -66,
	railHalfZ = 60,
	railPost = 12, -- studs between posts
}

Layout.Backdrop = {
	skyX = -210,
	skyHalfZ = 380,
	-- THE TOWN IS BELOW THE STREET. The street runs along a ridge, the guardrail is its
	-- edge, and the town and the hills sit 20 studs down. That is what lets the dusk show
	-- through the door from inside, as it does in the concept: from the wide camera the
	-- door frames the world only up to about 16 studs at the town's distance, so a town
	-- standing on the street's level would fill the door with walls.
	townBase = -20,
	townLow = 8, -- building heights, from `townBase`
	townHigh = 24,
	hillsX = -185,
	lotFarX = -215,
	-- The sky's colour bands, bottom up, as heights; the first starts just under the town,
	-- and the last carries on to `skyTop` so the view from the street is all sky.
	skyBands = { 26, 6, 6, 8 },
	skyTop = 160,
	seed = 102, -- the silhouette town is laid by a seeded Random, so every build matches
}

-- The named points (WORLD.md "Garage"), as CFrames in the room's frame. Car points are ON
-- the surface the car stands on, facing the way the car faces: add the car's ride height
-- to stand a car there. Camera points are where a camera stands, looking at what it shows.
local function look(from: Vector3, at: Vector3): CFrame
	return CFrame.lookAt(from, at)
end

local deckTop = Layout.Turntable.deckTop

Layout.Points = {
	-- The centre of the turntable's deck, on its top, facing +X (the way the car came in).
	TurntableTop = CFrame.lookAt(Vector3.new(0, deckTop, 0), Vector3.new(1, deckTop, 0)),
	-- On the street outside the door, facing in: where a car arrives from.
	CarEntry = CFrame.lookAt(Vector3.new(-50, 0, 0), Vector3.new(0, 0, 0)),
	-- Just outside the door, facing out: where a car leaving is headed.
	CarExit = CFrame.lookAt(Vector3.new(-40, 0, 0), Vector3.new(-80, 0, 0)),
	-- The concept's angle: high in the front-right corner, the door on the left.
	CamWide = look(Vector3.new(15, 10, 20), Vector3.new(-1, 2.5, -2)),
	-- Low by the front-right wheel (the car faces +X, so its right side is +Z).
	CamWheels = look(Vector3.new(10, 2, 9), Vector3.new(4.5, 1.2, 2.6)),
	-- Down on the floor at the car's side, looking under the sill.
	CamUnderside = look(Vector3.new(1, 0.7, 11), Vector3.new(0, 0.9, 0)),
	-- Over the driver's door, looking in through the side window.
	CamCabin = look(Vector3.new(1, 7, 6.5), Vector3.new(-0.5, 3, 0)),
}

Layout.PointOrder = { "TurntableTop", "CarEntry", "CarExit", "CamWide", "CamWheels", "CamUnderside", "CamCabin" }

return Layout
