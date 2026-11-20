--!strict
-- Drift/GroundMeshView: the ground-first trial's option 1, our own mesh (features/ground-trial.md,
-- T-218; step T-220; drawn as tiles that follow the road since T-225). The mountain
-- `Road/Ground` describes, drawn round the car and along the road ahead, on this device only.
-- Purely visual: the car drives on the spline maths.
--
-- TILES. `Drift/GroundTiles` picks a quadtree of square tiles: fine near the car and along
-- the road ahead, coarser further out, as many as the player's "Ground detail" allows
-- (`Drift/GroundDetail`). Each tile is one fixed-size mesh of `TileCells` by `TileCells`
-- cells, copied from a flat one made once: a client holds only so many mesh triangles
-- (`Config.Spline.Ground` "THE BUDGET"), and a fixed-size copy costs only its size. A tile
-- never changes shape, only where its vertices are, so one pool of them serves every spacing.
--
-- A CHANGE IS SHOWN WHOLE. Each change (a tile splitting into four, four merging into one, a
-- new tile, one let go, tiles redrawn for new road) is built into hidden tiles over a few
-- frames, then swapped in within one frame, with its neighbours' edges put right in the same
-- frame.
--
-- NO CRACKS. Two tiles of one spacing share their edge's vertices, worked out the same way
-- (moved or not: each is a function of its own grid point and its neighbours alone).
-- Where a tile meets a coarser one, its edge takes the coarser one's heights (straight lines
-- between the coarser vertices), and a vertex several tiles share takes its height the
-- coarsest one's way (`Clamps`, `Sinks`). So the edges agree exactly.
--
-- ROUND THE ROAD: every vertex sinks its spacing's `Sinks` under the road and its runoff. No
-- triangle may reach over the road from a cutting, so (T-231) a vertex past a runoff's edge
-- with a neighbour on the road is MOVED onto the edge's foot (`SnapFoot`) and held below the
-- edge there: the wall rises from a line along the road, not from a staircase of grid points
-- (a grid point held below the edge up to a cell and a half out, as before T-231, drew each
-- cut wall as a sawtooth wherever the road ran at an angle across the grid). Then each cell
-- is split along the diagonal that fits the ground best, never one joining a vertex on the
-- road to one up a wall; and the face's top edge is pulled onto its line the same way. A
-- vertex that cannot move (road both sides of it, or one on an edge shared with a tile of
-- another spacing, worked out the old way so the two still agree), and every vertex of a
-- tile coarser than `SnapUpTo`, is held below the edge within its spacing's `Clamp`, as
-- before. The road's skirt
-- (`Road/SplineMesh`, a ground run) hides what is left of the gap.
--
-- OPAQUE TILES (T-276), BUILT BUT SWITCHED OFF (`Ground.OpaqueTiles`): a client that makes
-- thousands of opaque contents freezes for seconds at a time (measured: see the config's
-- note), and the ground changes ~30 tiles a second. Only the master is opaque by default; every
-- tile keeps its EditableMesh as before. With the switch on, a tile no longer keeps an
-- EditableMesh, which held one of the client's ~640 tiles of mesh memory each
-- (`Config.Spline.Mesh.Budget`). What a tile draws is
-- kept in its own tables (`heights`, `px`, `pz`, `normals`, `colours`, `flip`), and each time
-- it changes -- built, its edges put right, redrawn -- it is written into a fresh fixed-size
-- copy of the master, made OPAQUE CONTENT (`AssetService:CreateDataModelContentAsync`, which
-- holds none of that memory) and the copy let go, into a new hidden MeshPart. A change is
-- still swapped in within one frame: the new tiles' parts and their neighbours' new parts
-- are made first (off the frame, `OpaqueInFlight` at a time), then shown together while the
-- old ones go. The master is opaque content too, made once a session. WHERE OPAQUE CONTENT
-- IS REFUSED (`CreateContentResult`, or `workspace.__no_opaque` in Studio, as the road's
-- `Road/SplineMesh`), a tile keeps its copy and is edited in place, as every tile was before:
-- never more held than then. Refused, it is not asked again for `REFUSED_WAIT` seconds.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Road.Ground)
local GrassTexture = require(ReplicatedStorage.Shared.Road.GrassTexture)
local GroundLook = require(ReplicatedStorage.Shared.Road.GroundLook)
local DetailTexture = require(ReplicatedStorage.Shared.Road.DetailTexture)
local RoadTexture = require(ReplicatedStorage.Shared.Road.RoadTexture)
local SplineMesh = require(ReplicatedStorage.Shared.Road.SplineMesh)
local OpaqueBudget = require(ReplicatedStorage.Shared.Road.OpaqueBudget)
local GroundDetail = require(script.Parent.GroundDetail)
local MeshBudget = require(script.Parent.MeshBudget)
local RoadAhead = require(script.Parent.RoadAhead)
local RoadBehind = require(script.Parent.RoadBehind)
local GroundTiles = require(script.Parent.GroundTiles)

type Leaf = GroundTiles.Leaf

local GroundMeshView = {}
GroundMeshView.__index = GroundMeshView

type Tile = {
	-- the tile's own fixed-size mesh, edited in place: only where opaque content was refused
	-- (T-276); nil for an opaque tile, which draws a new part each time it changes
	em: EditableMesh?,
	part: MeshPart?, -- what it draws (an opaque tile hidden in the pool has none)
	origin: Vector3, -- the world point its vertices are written relative to (the part's place)
	-- by grid index i * (n + 1) + j + 1 (i along x, j along z): the vertex and its own
	-- normal, colour and UV ids
	v: { number },
	nrm: { number },
	col: { number },
	uv: { number },
	leaf: Leaf?,
	heights: { number }, -- what is drawn, world y, by grid index
	px: { number }, -- and where, world x and z (a vertex can be moved off its grid point)
	pz: { number },
	normals: { Vector3 }, -- the normal each vertex is drawn with
	colours: { Color3 }, -- and its colour
	borrowed: { boolean }, -- shaded a coarser neighbour's way (`shadeAt`), by grid index
	cls: { number }, -- ROAD, HELD or OPEN (below), by grid index
	-- by cell index i * C + j + 1: its two faces' ids, and whether it is split along a-d
	-- (its corners a (i, j), b (i + 1, j), c (i, j + 1), d (i + 1, j + 1); b-c otherwise)
	faces: { number },
	flip: { boolean },
	cy: number, -- the part's height (vertices are written relative to it)
	stale: boolean,
	-- THE ROCK MESH (T-339, the "rock" ground look): a second copy of the master over a tile
	-- with rock in it, in the Rock material (`writeRock`); only on a tile that keeps its own
	-- mesh. Let go when the tile is next drawn without rock
	rockEm: EditableMesh?,
	rockPart: MeshPart?,
	rockMap: any, -- its ids (`IdMap`)
	hasRock: boolean,
}

type Op = {
	kind: string, -- "fill" | "split" | "merge" | "drop" | "stale"
	old: { Leaf },
	new: { Leaf },
	region: { Leaf },
}

-- the flat tile every tile is copied from: opaque content (T-276), or where that was refused
-- a fixed-size mesh, as before
type Master = { em: EditableMesh?, content: Content? }

-- A tile's mesh being made (T-276, `_render`): its part once done, the copy it keeps where
-- opaque content was refused, and the point its vertices are relative to.
type Job = {
	done: boolean,
	part: MeshPart?,
	held: EditableMesh?,
	origin: Vector3?,
	map: any, -- the kept copy's ids (`IdMap`)
	err: string?,
}

export type View = typeof(setmetatable(
	{} :: {
		spline: any,
		field: Ground.Field,
		folder: Folder,
		dead: boolean,
		failed: string?,
		paused: boolean, -- Studio checks only: build nothing
		running: boolean,
		carX: number,
		carZ: number,
		along: number?,
		checkedTo: number,
		master: Master?,
		pool: { Tile },
		free: { Tile },
		cap: number, -- tiles at most, shown and hidden
		failCap: number?, -- the device would make no more than this
		shown: { [number]: Leaf },
		tiles: { [number]: Tile }, -- by leaf key
		detail: number,
		dirty: boolean, -- the setting changed
		desired: { [number]: Leaf }?,
		desiredAt: Vector3?,
		desiredDetail: number,
		pending: { Op }, -- the changes still to make towards `desired`
		lastStale: boolean,
		sliceStart: number,
		work: number,
		changedConn: any,
		behindConn: any, -- the player's "Road behind" (T-230)
		aheadConn: any, -- the player's "Road ahead" (T-263)
		unGive: (() -> ())?, -- off `Drift/MeshBudget`'s givers (T-273)
		yields: number, -- times the ground gave way to the road (T-273)
		yielded: number, -- tiles it let go at once doing so
		-- measured
		ops: { [string]: number },
		tilesBuilt: number,
		rimWrites: number,
		shades: { [number]: { [number]: { any } } }, -- grid points shaded, by spacing (`shadeAt`)
		shadesFor: { number }, -- the road's first and last s they were worked out for
		wall: { [string]: number }, -- vertices moved onto a wall's foot, held, cells split a-d, cells left inverted
		lastMs: number,
		worstMs: number,
		worstSliceMs: number,
		lastSlices: number,
		worstCommitMs: number,
		selectMs: number,
		totalWorkMs: number, -- all building and choosing, for the per-frame cost
		events: { { number } },
		slices: { number },
		inflight: number, -- tile meshes being made now (T-276)
		opaque: { [string]: number }, -- how tiles' meshes were made (`_render`)
		retryAt: number, -- (os.clock) a change that could not get a mesh is not tried before this
	},
	GroundMeshView
))

local HALF_SPAN = 400 -- studs: the template's height either way, so its box covers the mountain

local function cells(): number
	return Config.Spline.Ground.TileCells
end

-- WHEN THE GROUND DRAWS THE RUNOFF (T-251, `Ground.RunoffBy = "ground"`): the road's mesh
-- stops at its bevels' feet, and the ground under the road and runoff is the runoff's own
-- surface (`Spline:underY`), worked out exactly from the curve, not from the stations'
-- carried-on estimate (`Ground.at`), sunk only `RunoffSinks` (none on the finest tiles):
-- what is drawn is what the car stands on. Its edge is the exact edge too, and a vertex past
-- it beside the road moves onto its foot over a drop as well as under a wall, so the drop
-- starts at the edge, where the car goes over, not a cell out.
-- (`Ground.runoffBy`, read when a view is made: one view at a time)
local groundRunoff = false

local clampOf: { [number]: number } = {}
local sinkOf: { [number]: number } = {}
local function setRunoffBy()
	groundRunoff = Ground.runoffBy() == "ground"
	for k, s in Config.Spline.Ground.Spacings do
		clampOf[s] = Config.Spline.Ground.Clamps[k]
		sinkOf[s] = if groundRunoff then Config.Spline.Ground.RunoffSinks[k] else Config.Spline.Ground.Sinks[k]
	end
end
setRunoffBy()

-- THE GROUND'S LOOK (T-339, `Road/GroundLook`, `Config.GroundLook`): read when a view is
-- made, and again by `Restyle` (the `ground-look` command), one view at a time as above.
-- `detailContent`: the "detail" look's texture, once made (`Road/DetailTexture`)
local lookNow = "old"
local detailContent: Content? = nil
local rockStats = { made = 0, fails = 0, writes = 0, writeMs = 0, dropped = 0 }

-- A tile's part dressed for the look: the detail texture on it, or none.
local function stylePart(part: MeshPart)
	local want = if lookNow == "detail" and detailContent then detailContent else Content.none
	if part.TextureContent ~= want then
		part.TextureContent = want
	end
end

local function scaleColour(c: Color3, k: number): Color3
	return Color3.new(math.min(1, c.R * k), math.min(1, c.G * k), math.min(1, c.B * k))
end

-- Let a tile's rock mesh go.
local function dropRock(t: Tile)
	if t.rockPart then
		t.rockPart:Destroy()
	end
	if t.rockEm then
		t.rockEm:Destroy()
		rockStats.dropped += 1
	end
	t.rockPart, t.rockEm, t.rockMap, t.hasRock = nil, nil, nil, false
end

function GroundMeshView.new(spline: any, parent: Instance?): View
	setRunoffBy()
	local folder = Instance.new("Folder")
	folder.Name = "GroundMesh"
	folder.Parent = parent or Workspace
	local self = setmetatable({
		spline = spline,
		field = spline.mountain,
		folder = folder,
		dead = false,
		failed = nil,
		paused = false,
		running = false,
		carX = spline.origin.x,
		carZ = spline.origin.z,
		along = nil,
		checkedTo = spline.length,
		master = nil,
		pool = {},
		free = {},
		cap = 0,
		failCap = nil,
		shown = {},
		tiles = {},
		detail = GroundDetail.get(),
		dirty = false,
		desired = nil,
		desiredAt = nil,
		desiredDetail = 0,
		pending = {},
		lastStale = false,
		sliceStart = 0,
		work = 0,
		changedConn = nil,
		behindConn = nil,
		aheadConn = nil,
		unGive = nil,
		yields = 0,
		yielded = 0,
		ops = { fill = 0, split = 0, merge = 0, drop = 0, stale = 0 },
		tilesBuilt = 0,
		rimWrites = 0,
		shades = {},
		shadesFor = { 0, 0 },
		wall = { moved = 0, held = 0, flipped = 0, inverted = 0 },
		lastMs = 0,
		worstMs = 0,
		worstSliceMs = 0,
		lastSlices = 0,
		worstCommitMs = 0,
		selectMs = 0,
		totalWorkMs = 0,
		events = {},
		slices = {},
		inflight = 0,
		-- renders: meshes made; opaque: made opaque; kept: refused, the copy kept (the fallback);
		-- copyFails / partFails: no room for a copy, or no part; waitMs: a change waiting on
		-- them, off the frame; worstWaitMs; inflightMost; drops: changes given up for want of one
		opaque = { renders = 0, opaque = 0, kept = 0, copyFails = 0, partFails = 0, waitMs = 0, worstWaitMs = 0, inflightMost = 0, drops = 0 },
		retryAt = 0,
	}, GroundMeshView)
	self:_setCap()
	self.changedConn = GroundDetail.Changed:Connect(function(value: number)
		self.detail = value
		self.dirty = true
		self:_setCap()
	end)
	-- the road drawn behind the car changed: so does the corridor the ground follows
	self.behindConn = RoadBehind.Changed:Connect(function()
		self.dirty = true
		self:_setCap()
	end)
	-- and the road drawn ahead of it (T-263): the corridor reaches as far as the road does
	self.aheadConn = RoadAhead.Changed:Connect(function()
		self.dirty = true
		self:_setCap()
	end)
	-- THE ROAD COMES FIRST (T-273, `Drift/MeshBudget`): out of mesh memory, the road asks the
	-- ground to give way before it lets any of its own go
	self.unGive = MeshBudget.giver("ground", 1, function(units: number)
		return self:Yield(units)
	end)
	lookNow = GroundLook.current()
	if lookNow == "detail" and not detailContent then
		self:Restyle() -- (drawn again once its texture is made)
	end
	return self
end

-- THE LOOK CHANGED (T-339, the `ground-look` command): read it again and redraw every tile in
-- it, as any redraw is done (stale tiles, nearest first, `Spare` at a time), over a second or
-- two. The "detail" texture is made first, the first time it is wanted.
function GroundMeshView.Restyle(self: View)
	local look = GroundLook.current()
	task.spawn(function()
		if look == "detail" and not detailContent then
			detailContent = DetailTexture.content()
		end
		if self.dead then
			return
		end
		lookNow = look
		for _, tile in self.tiles do
			tile.stale = true
		end
		self.dirty = true
	end)
end

-- Studio checks (T-339): switch the look on this device, as the `ground-look` command does.
function GroundMeshView.DebugRestyle(self: View, look: string?)
	Workspace:SetAttribute("__ground_look", look)
	self:Restyle()
	return { look = GroundLook.current() }
end

-- Studio checks (T-339): what the shown ground is, for tuning the bands. Its open vertices'
-- steepness (by 10 degrees) and height above the mountain's zero, the share of them past half
-- rocky, rock, alpine and snow; and along the road every `step` studs, its height and how
-- many rock vertices are within 300 studs of it (where to look at the rock).
function GroundMeshView.DebugLookSurvey(self: View, step: number?)
	local oy = self.field.oy
	local byAngle = table.create(10, 0)
	local n, rocky, rock, alpine, snow = 0, 0, 0, 0, 0
	local lo, hi = math.huge, -math.huge
	local rockPts = {}
	for _, tile in self.tiles do
		for k = 1, #tile.heights do
			if tile.cls[k] == OPEN then
				local nv = tile.normals[k]
				local alt = tile.heights[k] - oy
				local w = GroundLook.weights(tile.px[k], tile.pz[k], alt, nv.Y)
				n += 1
				local b = math.clamp(math.floor(w.angle / 10) + 1, 1, 10)
				byAngle[b] += 1
				lo, hi = math.min(lo, alt), math.max(hi, alt)
				rocky += if w.rocky > 0.5 then 1 else 0
				alpine += if w.alpine > 0.5 then 1 else 0
				snow += if w.snow > 0.5 then 1 else 0
				if w.rock > 0.5 then
					rock += 1
					table.insert(rockPts, { tile.px[k], tile.pz[k] })
				end
			end
		end
	end
	local road = {}
	local sp = self.spline
	for s = 0, sp.length, step or 250 do
		local x, z = sp:planAt(s)
		local near = 0
		for _, p in rockPts do
			local dx, dz = p[1] - x, p[2] - z
			if dx * dx + dz * dz < 90000 then
				near += 1
			end
		end
		table.insert(road, { s = s, x = math.round(x), z = math.round(z), alt = math.round(sp:heightAt(s) - oy), yaw = math.round(math.deg(sp:yawAt(s))), rockNear = near })
	end
	local share = function(c: number): number
		return if n > 0 then math.round(c / n * 1000) / 10 else 0
	end
	return {
		vertices = n,
		byAngle = byAngle,
		alt = { math.round(lo), math.round(hi) },
		percent = { rocky = share(rocky), rock = share(rock), alpine = share(alpine), snow = share(snow) },
		car = { math.round(self.carX), math.round(self.carZ) },
		road = road,
	}
end

-- What the look costs (T-339): the look, the tiles shown and held, how many shown tiles carry
-- a rock mesh, and the rock meshes made, failed, let go and written (and their time).
function GroundMeshView.DebugLook(self: View)
	local shown, rock = 0, 0
	for _, tile in self.tiles do
		shown += 1
		if tile.hasRock and tile.rockPart and tile.rockPart.Parent then
			rock += 1
		end
	end
	local held = 0
	for _, t in self.pool do
		if t.rockEm then
			held += 1
		end
	end
	return {
		look = lookNow,
		tiles = shown,
		pool = #self.pool,
		rockShown = rock,
		rockHeld = held,
		rock = table.clone(rockStats),
		detail = DetailTexture.DebugState(),
		workMs = self.totalWorkMs,
		built = self.tilesBuilt,
	}
end

-- Give way to the road (T-273): let go of up to `units` tiles. The hidden ones go at once;
-- past those the ground holds fewer from now on (`failCap`), so it merges far tiles over the
-- next frames: coarser far out, never under `Ground.YieldFloor` tiles. Returns the tiles let
-- go now, and the ones still to go.
-- OPAQUE TILES (T-276) hold none of the mesh memory, so letting them go frees nothing: the
-- ground gives way only while it holds tiles of its own (where opaque content was refused),
-- and counts only those.
function GroundMeshView.Yield(self: View, units: number): (number, number)
	if self.dead or units <= 0 then
		return 0, 0
	end
	local held = self:_held()
	if held <= 0 then
		return 0, 0 -- nothing held: nothing to give
	end
	local G = Config.Spline.Ground
	local floor = G.YieldFloor + G.Spare
	local before = #self.pool
	local target = math.max(floor, math.min(self.cap, before) - math.ceil(units))
	if target >= math.min(self.cap, before) then
		return 0, 0 -- at the floor already
	end
	self.failCap = math.min(self.failCap or math.huge, target)
	self.yields += 1
	self:_setCap()
	self.desired = nil
	self:_trim()
	local now = held - self:_held()
	local soon = 0
	for _, t in self.pool do
		if t.em then
			soon += 1
		end
	end
	soon = math.min(soon, math.max(0, #self.pool - self.cap))
	self.yielded += now
	return now, soon
end

-- The tiles of mesh memory the ground holds now (T-276): its tiles that keep their own mesh
-- (none where opaque content is made), and the master where it is not opaque. (Not the copies
-- being made opaque at this moment, `inflight`: those are let go within a frame or two.)
function GroundMeshView._held(self: View): number
	local held = 0
	for _, t in self.pool do
		if t.em then
			held += 1
		end
	end
	if self.master and self.master.em then
		held += 1
	end
	return held
end

-- The tiles the settings allow: the Ground detail's, and the Road behind's and Road ahead's
-- for the corridor beside the road behind the car (T-230) and past the default reach ahead
-- (T-263), so a longer road does not cost sharp ground nearer the car. Never more than
-- `Ground.CorridorMost` past the most any Ground detail holds (Ultra's): with Ultra and both
-- settings at Longest, that fits the budget beside the road (far chunks drawn at `Mesh.Far`).
-- AND NEVER MORE THAN THE MESH MEMORY HAS ROOM FOR (T-273, `SplineMesh.groundRoom`): what is
-- left beside the road those settings draw, the other mesh users and some spare. Past that
-- the far ground is coarser, and the road never runs out.
function GroundMeshView._tiles(self: View): number
	local G = Config.Spline.Ground
	local detail = G.Detail
	local own = GroundDetail.preset(self.detail).Tiles
	local more = (RoadBehind.preset().GroundTiles or 0) + (RoadAhead.preset().GroundTiles or 0)
	local wanted = math.max(own, math.min(own + more, detail[#detail].Tiles + G.CorridorMost))
	local room = SplineMesh.groundRoom(RoadAhead.studs(), RoadBehind.studs()) - G.Spare
	return math.max(G.YieldFloor, math.min(wanted, room))
end

function GroundMeshView._setCap(self: View)
	local G = Config.Spline.Ground
	local cap = self:_tiles() + G.Spare
	if self.failCap then
		cap = math.min(cap, self.failCap)
	end
	self.cap = cap
end

-- How many tiles may show: the setting's, or fewer if this device would not make that many.
function GroundMeshView._leafBudget(self: View): number
	return math.max(4, math.min(self:_tiles(), self.cap - Config.Spline.Ground.Spare))
end

--------------------------------------------------------------------------------
-- Building, a few ms a frame
--------------------------------------------------------------------------------

function GroundMeshView._slice(self: View)
	local G = Config.Spline.Ground
	local now = os.clock()
	local budget = (if next(self.shown) == nil then G.FirstSliceMs else G.MeshSliceMs) / 1000
	if now - self.sliceStart > budget then
		local ms = (now - self.sliceStart) * 1000
		self.work += now - self.sliceStart
		self.worstSliceMs = math.max(self.worstSliceMs, ms)
		if #self.slices < 4000 then
			table.insert(self.slices, ms)
		end
		self.lastSlices += 1
		task.wait()
		self.sliceStart = os.clock()
	end
end

--------------------------------------------------------------------------------
-- Where each vertex goes, and how each cell is split (T-231)
--------------------------------------------------------------------------------

-- `Ground.at`, counted: points of ground worked out to build tiles (the build's main cost).
local groundEvals = 0
local function groundAt(ctx: Ground.Context, x: number, z: number): (number, number, number, number)
	groundEvals += 1
	return Ground.at(ctx, x, z)
end

-- THE RUNOFF'S OWN SURFACE at (x, z) (T-251): its height, and where on the road it is (s, d);
-- nil where no road is near. Past the runoff's edge, level with the edge. Of two stretches of
-- road near the point (two legs, the far side of a hairpin), the one whose edge it is least
-- far past: the nearest centre line can be the other leg's, beyond a narrow runoff.
local underEvals = 0
local clusterS: { number } = {}
local clusterD: { number } = {}
local function underAt(ctx: Ground.Context, x: number, z: number): (number?, number?, number?, number?)
	local spline = ctx.spline
	local T = Config.Spline.Terrain
	local half = Config.Road.Width * 0.5
	local reach = half + math.max(T.RunoffMax, T.GroveRunoff[2]) + 24
	underEvals += 1
	local cell = spline.cell
	local first = spline.firstSample * spline.step
	local r2 = reach * reach
	-- the nearest filed point of each stretch of road in reach (points more than `apart`
	-- along the road from a stretch's nearest so far are another stretch)
	local apart = 2 * reach
	local nc = 0
	for cx = math.floor((x - reach) / cell), math.floor((x + reach) / cell) do
		for cz = math.floor((z - reach) / cell), math.floor((z + reach) / cell) do
			local list = spline.hash[(cx + 1048576) * 2097152 + (cz + 1048576)] -- `Spline`'s own key
			if list then
				for j = 1, #list, 3 do
					local s = list[j]
					if s >= first then
						local dx, dz = list[j + 1] - x, list[j + 2] - z
						local dd = dx * dx + dz * dz
						if dd <= r2 then
							local found = false
							for c = 1, nc do
								if math.abs(clusterS[c] - s) < apart then
									if dd < clusterD[c] then
										clusterS[c], clusterD[c] = s, dd
									end
									found = true
									break
								end
							end
							if not found then
								nc += 1
								clusterS[nc], clusterD[nc] = s, dd
							end
						end
					end
				end
			end
		end
	end
	local bestE, bestS, bestD = math.huge, nil :: number?, nil :: number?
	for c = 1, nc do
		local s, d = spline:projectFrom(x, z, clusterS[c])
		if s and d then
			local side = if d < 0 then -1 else 1
			local e = math.abs(d) - half - spline:runoffAt(s, side)
			if e < bestE then
				bestE, bestS, bestD = e, s, d
			end
		end
	end
	if not bestS or not bestD or bestE > 24 then
		return nil, nil, nil, nil
	end
	return spline:underY(bestS, bestD), bestS, bestD, bestE
end

-- How near a runoff's edge (`Ground.at`'s reckoning) a point has to be for the exact one to
-- be worked out: `Ground.at`'s edge, from the stations' straight stretches and widths eased
-- between them, can be a stud or so off the true one, and the vertices moved onto the foot
-- are placed by it (T-251)
local EXACT_NEAR = 40 -- studs

-- The height the road holds the ground at, `T` as `Ground.at` has it (the edge's, less
-- `Under`), or, when the ground draws the runoff, the runoff's own surface there.
local function edgeY(ctx: Ground.Context, x: number, z: number, T: number): number
	if groundRunoff then
		local y = underAt(ctx, x, z)
		if y then
			return y
		end
	end
	return T
end

-- What a vertex is, for how its cell may be split: on the road (or the flat foot just past
-- its edge), held below the edge, or open ground. A triangle joining ROAD to OPEN would
-- reach up from the road over it.
local ROAD, HELD, OPEN = 0, 1, 2

-- The grid indices of a cell's two triangles, as drawn: split along b-c, or a-d if flipped.
-- Both wound as the template winds them, to face up.
local function cellTriangles(n: number, i: number, j: number, flip: boolean): ({ number }, { number })
	local a, b, c, d = i * n + j + 1, (i + 1) * n + j + 1, i * n + j + 2, (i + 1) * n + j + 2
	if flip then
		return { a, d, b }, { a, c, d }
	end
	return { a, c, b }, { b, c, d }
end

-- OPAQUE CONTENT (T-276), as `Road/SplineMesh` makes it: (true, content), or false where it is
-- refused. In Studio, `workspace.__no_opaque = true` refuses it, to try the fallback. Once
-- refused, nothing is made opaque for `REFUSED_WAIT` seconds (each try costs a copy).
local REFUSED_WAIT = 30 -- seconds
local refusedUntil = 0

-- WHETHER TILES ARE MADE OPAQUE AT ALL (`Ground.OpaqueTiles`, off: see its note; in Studio
-- `workspace.__opaque_ground = true` turns it on, to measure). The master is opaque either way.
local function opaqueTiles(): boolean
	return Config.Spline.Ground.OpaqueTiles == true or (RunService:IsStudio() and Workspace:GetAttribute("__opaque_ground") == true)
end

local function opaqueOk(): boolean
	if RunService:IsStudio() and Workspace:GetAttribute("__no_opaque") == true then
		return false
	end
	-- (T-288) and the session's cap of opaque content (`Road/OpaqueBudget`)
	return os.clock() >= refusedUntil and OpaqueBudget.allows()
end

local function toOpaque(em: EditableMesh): (boolean, Content?)
	if not opaqueOk() then
		return false, nil
	end
	local made, content = OpaqueBudget.make("ground", Content.fromObject(em))
	if not made then
		refusedUntil = os.clock() + REFUSED_WAIT
		return false, nil
	end
	return true, content
end

-- Where grid point (i, j) of the master is (i along x, j along z): flat, `sp` apart, but for
-- two corners `HALF_SPAN` up and down, so a part made from a copy as it comes has a box that
-- holds anything a tile draws.
local function masterPosition(C: number, sp: number, i: number, j: number): Vector3
	local y = 0
	if i == 0 and j == 0 then
		y = HALF_SPAN
	elseif i == C and j == C then
		y = -HALF_SPAN
	end
	return Vector3.new((i - C / 2) * sp, y, (j - C / 2) * sp)
end

-- the master's opaque content, made once a session and shared by every view (it holds none of
-- the mesh memory), for this many cells and this spacing
local masterContent: Content? = nil
local masterKey = ""

-- The flat tile every tile is copied from: never shown, never moved. It spans the coarsest
-- tile, so every tile's bounds hold whatever it draws. Opaque content (T-276); where that is
-- refused, a fixed-size mesh, as before.
local function makeMaster(): Master?
	local G = Config.Spline.Ground
	local C = cells()
	local n = C + 1
	local sp = G.Spacings[#G.Spacings]
	local key = `{C}:{sp}`
	if masterContent and masterKey == key then
		return { em = nil, content = masterContent }
	end
	local okT, made = pcall(function()
		return AssetService:CreateEditableMesh({ FixedSize = false })
	end)
	if not okT or not made then
		return nil
	end
	local template = made :: EditableMesh
	local ids = table.create(n * n)
	for i = 0, C do
		for j = 0, C do
			ids[i * n + j + 1] = template:AddVertex(masterPosition(C, sp, i, j))
		end
	end
	local nrm, col, uv = table.create(n * n), table.create(n * n), table.create(n * n)
	for k = 1, n * n do
		nrm[k] = template:AddNormal(Vector3.yAxis)
		col[k] = template:AddColor(Color3.new(1, 1, 1), 1)
		uv[k] = template:AddUV(Vector2.zero)
	end
	for i = 0, C - 1 do
		for j = 0, C - 1 do
			local a, b, c, d = i * n + j + 1, (i + 1) * n + j + 1, i * n + j + 2, (i + 1) * n + j + 2
			-- two triangles a cell, wound to face up, split along b-c
			for _, t in { { a, c, b }, { b, c, d } } do
				local f = template:AddTriangle(ids[t[1]], ids[t[2]], ids[t[3]])
				template:SetFaceNormals(f, { nrm[t[1]], nrm[t[2]], nrm[t[3]] })
				template:SetFaceColors(f, { col[t[1]], col[t[2]], col[t[3]] })
				template:SetFaceUVs(f, { uv[t[1]], uv[t[2]], uv[t[3]] })
			end
		end
	end
	local opaque, content = toOpaque(template)
	if opaque and content then
		template:Destroy()
		masterContent, masterKey = content, key
		return { em = nil, content = content }
	end
	local ok, em = pcall(function()
		return AssetService:CreateEditableMeshAsync(Content.fromObject(template), { FixedSize = true })
	end)
	template:Destroy()
	if not ok or not em then
		return nil
	end
	return { em = em :: EditableMesh, content = nil }
end

local function masterSource(master: Master): Content
	return if master.content then master.content else Content.fromObject(master.em :: EditableMesh)
end

-- A COPY'S IDS: each grid point's vertex, normal, colour and UV ids, and each cell's two faces
-- (its first holds corner a, as the master has it). Found by where each vertex is and what its
-- faces name, and kept: a copy of the same master gets the same ids (`Road/SplineMesh` measured
-- it for its templates); a copy whose faces or corners differ is mapped again.
type IdMap = {
	v: { number },
	nrm: { number },
	col: { number },
	uv: { number },
	faces: { number },
	count: number,
	f1: number,
	fN: number,
}
local idMapCache: IdMap? = nil
local idMaps = 0 -- times a copy was mapped afresh

local function idMapOf(copy: EditableMesh): IdMap
	local G = Config.Spline.Ground
	local C = cells()
	local n = C + 1
	local sp = G.Spacings[#G.Spacings]
	local all = copy:GetFaces()
	local m = idMapCache
	if m and #all == m.count and all[1] == m.f1 and all[#all] == m.fN then
		-- (and three corners where the master has them)
		local same = true
		for _, ij in { { 0, 0 }, { C, C }, { C, 0 } } do
			local k = ij[1] * n + ij[2] + 1
			local okP, p = pcall(copy.GetPosition, copy, m.v[k])
			if not okP or (p - masterPosition(C, sp, ij[1], ij[2])).Magnitude > 1e-3 then
				same = false
			end
		end
		if same then
			return m
		end
	end
	idMaps += 1
	local v, cn, cc, cu = table.create(n * n), table.create(n * n), table.create(n * n), table.create(n * n)
	local faces = table.create(2 * C * C)
	for _, f in all do
		local vs = copy:GetFaceVertices(f)
		local ns = copy:GetFaceNormals(f)
		local cs = copy:GetFaceColors(f)
		local us = copy:GetFaceUVs(f)
		local mi, mj, hasA = math.huge, math.huge, false
		local ks = {}
		for q = 1, 3 do
			local p = copy:GetPosition(vs[q])
			local i, j = math.round(p.X / sp + C / 2), math.round(p.Z / sp + C / 2)
			local k = i * n + j + 1
			v[k], cn[k], cc[k], cu[k] = vs[q], ns[q], cs[q], us[q]
			mi, mj = math.min(mi, i), math.min(mj, j)
			ks[q] = { i, j }
		end
		for q = 1, 3 do
			if ks[q][1] == mi and ks[q][2] == mj then
				hasA = true
			end
		end
		-- a cell's first face holds its corner a, its second does not
		faces[2 * (mi * C + mj) + (if hasA then 1 else 2)] = f
	end
	m = { v = v, nrm = cn, col = cc, uv = cu, faces = faces, count = #all, f1 = all[1], fN = all[#all] }
	idMapCache = m
	return m
end

local function dress(mp: MeshPart)
	mp.Name = "GroundTile"
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.CastShadow = false
	mp.Material = Enum.Material.Grass
	mp.Color = Color3.new(1, 1, 1)
end

local function partFrom(content: Content): MeshPart?
	local ok, part = pcall(function()
		return AssetService:CreateMeshPartAsync(content, {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
		})
	end)
	if not ok or not part then
		return nil
	end
	local mp = part :: MeshPart
	dress(mp)
	return mp
end

-- A tile's own tables, drawing nothing yet.
local function blankTile(): Tile
	local C = cells()
	local n = C + 1
	return {
		em = nil,
		part = nil,
		origin = Vector3.zero,
		v = {},
		nrm = {},
		col = {},
		uv = {},
		leaf = nil,
		heights = table.create(n * n, 0),
		px = table.create(n * n, 0),
		pz = table.create(n * n, 0),
		normals = table.create(n * n, Vector3.yAxis),
		colours = table.create(n * n, Color3.new(1, 1, 1)),
		borrowed = table.create(n * n, false),
		cls = table.create(n * n, 2),
		faces = {},
		flip = table.create(C * C, false),
		cy = 0,
		stale = false,
		rockEm = nil,
		rockPart = nil,
		rockMap = nil,
		hasRock = false,
	}
end

-- A tile that keeps its own fixed-size mesh, edited in place (as every tile was before T-276):
-- where opaque content is refused. nil when the device will not make it.
local function makeTile(master: Master): Tile?
	local ok, em = pcall(function()
		return AssetService:CreateEditableMeshAsync(masterSource(master), { FixedSize = true })
	end)
	if not ok or not em then
		return nil
	end
	local copy = em :: EditableMesh
	local m = idMapOf(copy)
	local mp = partFrom(Content.fromObject(copy))
	if not mp then
		copy:Destroy()
		return nil
	end
	local tile = blankTile()
	tile.em, tile.part = copy, mp
	tile.v, tile.nrm, tile.col, tile.uv, tile.faces = m.v, m.nrm, m.col, m.uv, m.faces
	return tile
end

-- Write a tile's ground into `copy` (fresh from the master: every cell split b-c), each vertex
-- relative to `origin`.
local function writeTile(copy: EditableMesh, m: IdMap, origin: Vector3, px: { number }, pz: { number }, heights: { number }, normals: { Vector3 }, colours: { Color3 }, flip: { boolean })
	local C = cells()
	local n = C + 1
	local uvStuds = Config.Spline.Ground.UVStuds
	local ox, oy, oz = origin.X, origin.Y, origin.Z
	for k = 1, n * n do
		local x, z = px[k], pz[k]
		copy:SetPosition(m.v[k], Vector3.new(x - ox, heights[k] - oy, z - oz))
		copy:SetNormal(m.nrm[k], normals[k])
		copy:SetColor(m.col[k], colours[k])
		copy:SetUV(m.uv[k], Vector2.new(x / uvStuds, z / uvStuds))
	end
	for i = 0, C - 1 do
		for j = 0, C - 1 do
			local c = i * C + j + 1
			if flip[c] then
				local t1, t2 = cellTriangles(n, i, j, true)
				for q, t in { t1, t2 } do
					local f = m.faces[2 * (c - 1) + q]
					copy:SetFaceVertices(f, { m.v[t[1]], m.v[t[2]], m.v[t[3]] })
					copy:SetFaceNormals(f, { m.nrm[t[1]], m.nrm[t[2]], m.nrm[t[3]] })
					copy:SetFaceColors(f, { m.col[t[1]], m.col[t[2]], m.col[t[3]] })
					copy:SetFaceUVs(f, { m.uv[t[1]], m.uv[t[2]], m.uv[t[3]] })
				end
			end
		end
	end
end

-- A TILE'S MESH AS OPAQUE CONTENT (T-276): `leaf`'s ground as these tables have it, written
-- into a fresh copy of the master, centred on its own box (a part is culled by its box, and
-- keeps its vertices where they were written: `Road/SplineMesh`), made opaque and the copy let
-- go, into a new MeshPart, hidden. Where opaque content is refused, the copy is kept and the
-- part drawn from it, edited in place from then on, as before: its vertices then relative to
-- the tile's centre at `cy`, and its box the master's. Returns the part, the copy kept (if
-- any) with its ids, and the point its vertices are relative to; nil when the device has no
-- room for a copy.
local function render(master: Master, leaf: Leaf, cy: number, px: { number }, pz: { number }, heights: { number }, normals: { Vector3 }, colours: { Color3 }, flip: { boolean }, stats: { [string]: number }): (MeshPart?, EditableMesh?, Vector3?, IdMap?)
	local C = cells()
	local n = C + 1
	local sp = Config.Spline.Ground.Spacings[#Config.Spline.Ground.Spacings]
	local centre = Vector3.new(leaf.x0 + leaf.side * 0.5, cy, leaf.z0 + leaf.side * 0.5)
	local ok, em = pcall(function()
		return AssetService:CreateEditableMeshAsync(masterSource(master), { FixedSize = true })
	end)
	if not ok or not em then
		stats.copyFails += 1
		return nil, nil, nil
	end
	local copy = em :: EditableMesh
	local m = idMapOf(copy)
	if opaqueOk() then
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		for k = 1, n * n do
			local p = Vector3.new(px[k], heights[k], pz[k])
			lo, hi = lo:Min(p), hi:Max(p)
		end
		local origin = (lo + hi) * 0.5
		writeTile(copy, m, origin, px, pz, heights, normals, colours, flip)
		local made, content = toOpaque(copy)
		if made and content then
			copy:Destroy()
			local part = partFrom(content)
			if not part then
				stats.partFails += 1
				return nil, nil, nil
			end
			part.CFrame = CFrame.new(origin)
			stats.opaque += 1
			return part, nil, origin
		end
		-- refused: the copy as the master has it again, so its part gets the master's box
		for i = 0, C do
			for j = 0, C do
				copy:SetPosition(m.v[i * n + j + 1], masterPosition(C, sp, i, j))
			end
		end
		for c = 1, C * C do
			if flip[c] then
				local i, j = (c - 1) // C, (c - 1) % C
				local t1, t2 = cellTriangles(n, i, j, false)
				for q, t in { t1, t2 } do
					copy:SetFaceVertices(m.faces[2 * (c - 1) + q], { m.v[t[1]], m.v[t[2]], m.v[t[3]] })
				end
			end
		end
	end
	-- kept, edited in place (the fallback)
	local part = partFrom(Content.fromObject(copy))
	if not part then
		copy:Destroy()
		stats.partFails += 1
		return nil, nil, nil
	end
	writeTile(copy, m, centre, px, pz, heights, normals, colours, flip)
	part.CFrame = CFrame.new(centre)
	stats.kept += 1
	return part, copy, centre, m
end

-- Where (x, z) is in a triangle, in plan: its three weights (all -1 for no triangle at all).
local function bary(x1: number, z1: number, x2: number, z2: number, x3: number, z3: number, x: number, z: number): (number, number, number)
	local det = (z2 - z3) * (x1 - x3) + (x3 - x2) * (z1 - z3)
	if math.abs(det) < 1e-9 then
		return -1, -1, -1
	end
	local l1 = ((z2 - z3) * (x - x3) + (x3 - x2) * (z - z3)) / det
	local l2 = ((z3 - z1) * (x - x3) + (x1 - x3) * (z - z3)) / det
	return l1, l2, 1 - l1 - l2
end

-- Twice a triangle's area in plan: negative wound the template's way, so positive is folded over.
local function orient(x1: number, z1: number, x2: number, z2: number, x3: number, z3: number): number
	return (x2 - x1) * (z3 - z1) - (z2 - z1) * (x3 - x1)
end

-- The height a vertex takes at (x, z), done the way tiles of spacing `s` did it before T-231:
-- the ground, sunk under the road, and held below the edge within that spacing's clamp of it.
-- Still how a vertex shared with a tile of another spacing is done, so both agree on it.
local function vertexHeight(ctx: Ground.Context, s: number, x: number, z: number): number
	local y, a, e, T = groundAt(ctx, x, z)
	local sink = sinkOf[s]
	y -= sink * a
	if groundRunoff and e < EXACT_NEAR then
		local uy, _, _, ue = underAt(ctx, x, z)
		if uy and ue then
			if ue <= 0 then
				return uy - sink
			elseif ue < clampOf[s] then
				return math.min(y, uy - sink)
			end
			return y
		end
	end
	if e < clampOf[s] then
		y = math.min(y, edgeY(ctx, x, z, T) - sink)
	end
	return y
end

-- THE GROUND ON ONE SPACING'S GRID: the world's grid points `s` apart (point (I, J) at
-- x = I * s, z = J * s), each worked out once a fill and kept.
type Lattice = {
	ctx: Ground.Context,
	s: number,
	at: { [number]: { number } }, -- by point: y, a, e, T, from `Ground.at`
	placed: { [number]: { number } }, -- by point: x, z, y, class (`place`)
}

local function latKey(I: number, J: number): number
	return (I + 1048576) * 2097152 + (J + 1048576)
end

local function newLattice(ctx: Ground.Context, s: number): Lattice
	return { ctx = ctx, s = s, at = {}, placed = {} }
end

local function latAt(L: Lattice, I: number, J: number): { number }
	local k = latKey(I, J)
	local r = L.at[k]
	if not r then
		local y, a, e, T = groundAt(L.ctx, I * L.s, J * L.s)
		if groundRunoff and e < EXACT_NEAR then
			-- (the exact edge: how far past it, and the runoff's surface level with it, T-251)
			local uy, _, _, ue = underAt(L.ctx, I * L.s, J * L.s)
			if uy and ue then
				e, T = ue, uy
			end
		end
		r = { y, a, e, T }
		L.at[k] = r
	end
	return r
end

-- The way (x, z)'s distance past the nearest runoff's edge grows fastest, as a unit vector
-- and its rate (about 1); nil where it is too flat to tell.
local function edgeGradient(L: Lattice, x: number, z: number, e: number): (number?, number?, number?)
	local h = 0.25
	local _, _, ex = groundAt(L.ctx, x + h, z)
	local _, _, ez = groundAt(L.ctx, x, z + h)
	if groundRunoff then
		local _, _, _, ux = underAt(L.ctx, x + h, z)
		local _, _, _, uz = underAt(L.ctx, x, z + h)
		if ux and uz then
			ex, ez = ux, uz
		end
	end
	local gx, gz = (ex - e) / h, (ez - e) / h
	local g = math.sqrt(gx * gx + gz * gz)
	if g ~= g or g < 0.3 or g == math.huge then
		return nil, nil, nil
	end
	return gx / g, gz / g, g
end

-- Where the vertex of grid point (I, J) goes, its height and its class: {x, z, y, class}. The
-- same in every tile of this spacing, since it reads only the point and its four neighbours.
-- THE FOOT: a point past a runoff's edge with a neighbour on the road, and above the edge,
-- would make a triangle from the road up to it, reaching over the road: it moves onto the
-- edge's foot (`SnapFoot` past it), square to the edge, and is held below the edge there.
-- Where it cannot (road both sides of it, or further than `SnapMax` of a cell to go) it stays,
-- held below the edge. One already below the edge (a drop) stays where it is.
-- THE TOP: a point just past the end of a cut or fill, with a neighbour on its face, moves
-- back onto the face's end, so the wall's top edge is a line along the road too.
-- Everything else stays on its grid point.
local function place(L: Lattice, I: number, J: number): { number }
	local key = latKey(I, J)
	local p = L.placed[key]
	if p then
		return p
	end
	local G = Config.Spline.Ground
	local s = L.s
	local x, z = I * s, J * s
	local r = latAt(L, I, J)
	local y, a, e, T = r[1], r[2], r[3], r[4]
	local sink = sinkOf[s]
	local foot = G.SnapFoot
	local reach = G.SnapMax * s
	local open = y - sink * a
	p = { x, z, open, OPEN }
	if e <= foot then
		p = { x, z, if groundRunoff then T - sink else open, ROAD }
	elseif s > G.SnapUpTo then
		-- a coarse tile, far ahead: held below the edge within its clamp, as before T-231
		-- (moved, a 32-stud tile's ground stood 5.8 studs over a runoff's edge, measured)
		if e < clampOf[s] then
			p = { x, z, math.min(open, T - sink), HELD }
		end
	elseif e <= s + foot or (groundRunoff and e <= 2 * s + foot) then
		-- (a stud along the road is not always a stud past the edge: round the inside of a
		-- bend the runoff narrows fast, and a point a cell from the road can be more than a
		-- cell past its edge, measured; so when the ground draws the runoff, two cells)
		local west = latAt(L, I - 1, J)[3] <= foot
		local east = latAt(L, I + 1, J)[3] <= foot
		local south = latAt(L, I, J - 1)[3] <= foot
		local north = latAt(L, I, J + 1)[3] <= foot
		if west or east or south or north then
			local edge = T - sink
			if open <= edge and not groundRunoff then
				p = { x, z, open, HELD } -- below the edge already: safe where it is
			else
				-- (when the ground draws the runoff, a vertex over a drop is moved too, and
				-- one that cannot move is held level with the edge: never under the runoff)
				p = { x, z, edge, HELD }
				if not (west and east) and not (south and north) then
					local ux, uz, g = edgeGradient(L, x, z, e)
					if ux and uz and g then
						local move = (e - foot) / g
						if move <= reach * 1.15 then
							move = math.min(move, reach) -- (a little short of the foot at worst)
							local nx, nz = x - ux * move, z - uz * move
							local y2, a2, _, T2 = groundAt(L.ctx, nx, nz)
							local e2 = edgeY(L.ctx, nx, nz, T2) - sink
							p = { nx, nz, if groundRunoff then e2 else math.min(y2 - sink * a2, e2), HELD }
						end
					end
				end
			end
		end
	end
	if p[4] == OPEN and a <= 0 and s <= G.SnapUpTo and e < G.BlendMax + G.BlendFoot + s then
		-- past the end of a cut or fill: how wide its face is, read off a neighbour on it
		-- (`Road/Ground`: the face eases over `bw` studs from `BlendFoot` past the edge)
		local topE = math.huge
		for _, o in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
			local q = latAt(L, I + o[1], J + o[2])
			local aq, eq = q[2], q[3]
			if aq > 0.02 and aq < 0.95 and eq < e then
				-- 1 - a = smoothstep(t): t back from it
				local t = 0.5 - math.sin(math.asin(math.clamp(1 - 2 * (1 - aq), -1, 1)) / 3)
				if t > 0.05 then
					topE = math.min(topE, G.BlendFoot + (eq - G.BlendFoot) / t)
				end
			end
		end
		if topE < e then
			local ux, uz, g = edgeGradient(L, x, z, e)
			if ux and uz and g then
				local move = (e - topE) / g
				if move <= reach then
					local nx, nz = x - ux * move, z - uz * move
					local y2, a2, e2 = groundAt(L.ctx, nx, nz)
					-- only if it landed by the face's end, never down by the road
					if a2 < 0.3 and e2 > foot + 1 then
						p = { nx, nz, y2 - sink * a2, OPEN }
					end
				end
			end
		end
	end
	L.placed[key] = p
	return p
end

-- A tile's rim, given the tiles round it (`map`): {grid index -> {x, z, y, class}}. A vertex
-- only tiles of this spacing touch is placed like any other (`place`), and they all agree on
-- it. One a tile of another spacing touches stays on its grid point and takes its height the
-- old way (`vertexHeight`), the coarsest touching tile's: along an edge that meets a coarser
-- tile, straight between that tile's vertices. So both sides of every edge agree exactly.
local function rimPlace(L: Lattice, leaf: Leaf, map: { [number]: Leaf }): { [number]: { number } }
	local ctx = L.ctx
	local C = cells()
	local n = C + 1
	local s, x0, z0, side = leaf.s, leaf.x0, leaf.z0, leaf.side
	local I0, J0 = math.round(x0 / s), math.round(z0 / s)
	local foot = Config.Spline.Ground.SnapFoot
	local e = 0.5
	local mid = side * 0.5
	-- the spacing across each edge, if coarser than this tile's
	local function across(px: number, pz: number): number
		local l = GroundTiles.leafAt(map, px, pz)
		return if l and l.s > s then l.s else 0
	end
	local west, east = across(x0 - e, z0 + mid), across(x0 + side + e, z0 + mid)
	local south, north = across(x0 + mid, z0 - e), across(x0 + mid, z0 + side + e)
	local cache: { [number]: number } = {}
	local function H(x: number, z: number): number
		local key = math.round(x * 2) * 4194304 + math.round(z * 2)
		local y = cache[key]
		if y then
			return y
		end
		local sm = GroundTiles.spacingAround(map, x, z)
		if sm < s then
			sm = s
		end
		y = vertexHeight(ctx, sm, x, z)
		cache[key] = y
		return y
	end
	local out: { [number]: { number } } = {}
	local function vertex(i: number, j: number)
		local x, z = x0 + i * s, z0 + j * s
		local lo, hi = GroundTiles.spacingRange(map, x, z)
		if lo >= s and hi <= s then
			out[i * n + j + 1] = place(L, I0 + i, J0 + j)
			return
		end
		local S = 0
		local along, alongStart = 0, 0
		if i == 0 then
			S, along, alongStart = west, j * s, z0
		elseif i == C then
			S, along, alongStart = east, j * s, z0
		elseif j == 0 then
			S, along, alongStart = south, i * s, x0
		else
			S, along, alongStart = north, i * s, x0
		end
		local y
		local r = if S > 0 then along % S else 0
		if S > 0 and r > 1e-6 and (i ~= 0 and i ~= C or j ~= 0 and j ~= C) then
			local a0 = alongStart + along - r
			local f = r / S
			if i == 0 or i == C then
				y = H(x, a0) * (1 - f) + H(x, a0 + S) * f
			else
				y = H(a0, z) * (1 - f) + H(a0 + S, z) * f
			end
		else
			y = H(x, z)
		end
		local r = latAt(L, I0 + i, J0 + j)
		local cls = if r[3] <= foot then ROAD elseif y <= r[4] - sinkOf[s] + 1e-3 then HELD else OPEN
		out[i * n + j + 1] = { x, z, y, cls }
	end
	for t = 0, C do
		vertex(0, t)
		vertex(C, t)
		if t > 0 and t < C then
			vertex(t, 0)
			vertex(t, C)
		end
	end
	return out
end

-- How cell (i, j) is best split, given every vertex as placed (`P`: {x, z, y, class} by grid
-- index): true for a-d. Never along a diagonal joining a vertex on the road to open ground.
-- A cell with a corner on the road (on a coarse tile, or held below it) takes the lower
-- diagonal; any other the
-- one that puts the cell's middle nearer the ground there, when the two differ there by
-- `FitGap` or more (b-c, the template's, when they do not); and never one that folds a
-- triangle over, if the other does not. Also whether it still folds.
local function chooseSplit(ctx: Ground.Context, s: number, P: { { number } }, n: number, i: number, j: number): (boolean, boolean)
	local a, b, c, d = i * n + j + 1, (i + 1) * n + j + 1, i * n + j + 2, (i + 1) * n + j + 2
	local A, B, Cc, D = P[a], P[b], P[c], P[d]
	local function joins(p: { number }, q: { number }): boolean
		return (p[4] == ROAD and q[4] == OPEN) or (p[4] == OPEN and q[4] == ROAD)
	end
	local function folds(flip: boolean): boolean
		local t1, t2 = cellTriangles(n, i, j, flip)
		for _, t in { t1, t2 } do
			local p, q, r = P[t[1]], P[t[2]], P[t[3]]
			if orient(p[1], p[2], q[1], q[2], r[1], r[2]) > -1e-6 * s * s then
				return true
			end
		end
		return false
	end
	local function heightAt(flip: boolean, x: number, z: number): number?
		local t1, t2 = cellTriangles(n, i, j, flip)
		for _, t in { t1, t2 } do
			local p, q, r = P[t[1]], P[t[2]], P[t[3]]
			local l1, l2, l3 = bary(p[1], p[2], q[1], q[2], r[1], r[2], x, z)
			if l1 >= -1e-9 and l2 >= -1e-9 and l3 >= -1e-9 then
				return l1 * p[3] + l2 * q[3] + l3 * r[3]
			end
		end
		return nil
	end
	local canAD, canBC = not joins(A, D), not joins(B, Cc)
	local flip = false
	if canAD and not canBC then
		flip = true
	elseif canAD == canBC then
		local mx, mz = (A[1] + B[1] + Cc[1] + D[1]) * 0.25, (A[2] + B[2] + Cc[2] + D[2]) * 0.25
		local yBC, yAD = heightAt(false, mx, mz), heightAt(true, mx, mz)
		-- on the road (or, on a coarse tile, beside it, where nothing is moved): the lower,
		-- which lies under the other everywhere in the cell
		local byRoad = false
		local coarse = s > Config.Spline.Ground.SnapUpTo
		for _, p in { A, B, Cc, D } do
			if p[4] == ROAD or (coarse and p[4] == HELD) then
				byRoad = true
			end
		end
		if yBC and yAD and byRoad then
			flip = yAD < yBC
		elseif yBC and yAD and math.abs(yBC - yAD) >= Config.Spline.Ground.FitGap then
			local y, w = groundAt(ctx, mx, mz)
			local want = y - sinkOf[s] * w
			flip = math.abs(yAD - want) < math.abs(yBC - want)
		end
	end
	if folds(flip) and (if flip then canBC else canAD) and not folds(not flip) then
		flip = not flip
	end
	return flip, folds(flip)
end

-- Split a tile's cell (i, j) along a-d (`flip`) or b-c, if it is not already.
local function setSplit(tile: Tile, i: number, j: number, flip: boolean)
	local C = cells()
	local c = i * C + j + 1
	if tile.flip[c] == flip then
		return
	end
	tile.flip[c] = flip
	local em = tile.em
	if not em then
		return -- an opaque tile: written whole when its mesh is made (`render`)
	end
	local t1, t2 = cellTriangles(C + 1, i, j, flip)
	local v, nrm, col, uv = tile.v, tile.nrm, tile.col, tile.uv
	for q, t in { t1, t2 } do
		local f = tile.faces[2 * (c - 1) + q]
		em:SetFaceVertices(f, { v[t[1]], v[t[2]], v[t[3]] })
		em:SetFaceNormals(f, { nrm[t[1]], nrm[t[2]], nrm[t[3]] })
		em:SetFaceColors(f, { col[t[1]], col[t[2]], col[t[3]] })
		em:SetFaceUVs(f, { uv[t[1]], uv[t[2]], uv[t[3]] })
	end
end

-- HOW A VERTEX IS SHADED: its normal from the four round it, as placed, and its colour by
-- slope (rock past `RockAngle`), blotched by where its grid point is; when the ground draws
-- the runoff, a vertex on the road or held at its edge in the runoff's own colour, and one on
-- the road with the road's true normal (T-251).
local function shadeFrom(spline: any, ctx: Ground.Context, p: { number }, x: number, z: number, xp: { number }, xm: { number }, zp: { number }, zm: { number }): (Vector3, Color3)
	local G = Config.Spline.Ground
	local across = Vector3.new(zp[1] - zm[1], zp[3] - zm[3], zp[2] - zm[2])
	local along = Vector3.new(xp[1] - xm[1], xp[3] - xm[3], xp[2] - xm[2])
	local nv = across:Cross(along)
	nv = if nv.Magnitude > 1e-9 then nv.Unit else Vector3.yAxis
	local colour
	if lookNow ~= "old" then
		-- by steepness and height (T-339, `Road/GroundLook`)
		colour = GroundLook.colour(x, p[3], z, p[3] - spline.mountain.oy, nv.Y)
	elseif nv.Y < math.cos(math.rad(G.RockAngle)) then
		colour = G.GroundRockColour
	else
		local blotch = math.clamp(0.5 + 1.6 * math.noise(x / 70, z / 70, 3.37), 0, 1)
		colour = G.GrassColours[1]:Lerp(G.GrassColours[2], blotch)
	end
	if groundRunoff and (p[4] == ROAD or p[4] == HELD) then
		-- THE RUNOFF (T-251): its own grass, blotched as the road's runoff was, or gravel
		-- in a gravel run; on the road, its true normal, so it shades as it did
		local TT = Config.Spline.Terrain
		local g = TT.GrassColour
		local _, rs, rd = underAt(ctx, p[1], p[2])
		-- (T-270: with the gravel textured, the road's mesh lays a gravel strip over a gravel
		-- run's runoff; the ground under it stays grass, or its gravel colour smeared out a
		-- whole cell across the grass beside it, 8 studs and more)
		if rs and rd and math.abs(rd) > Config.Road.Width * 0.5 and spline:gravelAt(rs, if rd < 0 then -1 else 1) and not RoadTexture.gravelEnabled() then
			colour = TT.GravelColour
		else
			local b = GrassTexture.blotch(p[1], p[2])
			colour = Color3.new(math.min(1, g.R * b), math.min(1, g.G * b), math.min(1, g.B * b))
		end
		if p[4] == ROAD and rs and rd then
			nv = spline:terrainNormal(rs, rd)
		end
	end
	return nv, GroundLook.forTexture(lookNow, colour)
end

-- THE ROCK MESH (T-339, the "rock" look): every vertex of the tile again, out along its
-- normal where it is rock and in where it is not (`Config.GroundLook.RockMesh`), so the Rock
-- material shows through the grass on the steep faces; its faces split as the tile's are.
-- Written whole each time the tile is drawn or its edges change.
local function writeRock(tile: Tile, oy: number)
	local em, m = tile.rockEm, tile.rockMap
	if not em or not m then
		return
	end
	local t0 = os.clock()
	local R = Config.GroundLook.RockMesh
	local C = cells()
	local n = C + 1
	local o = tile.origin
	for k = 1, n * n do
		local nv = tile.normals[k]
		local x, z, y = tile.px[k], tile.pz[k], tile.heights[k]
		local w = if tile.cls[k] == OPEN then GroundLook.rockWeight(x, z, y - oy, nv.Y) else 0
		local off = -R.Sink + (R.Lift + R.Sink) * w
		em:SetPosition(m.v[k], Vector3.new(x - o.X, y - o.Y, z - o.Z) + nv * off)
		em:SetNormal(m.nrm[k], nv)
		em:SetColor(m.col[k], scaleColour(tile.colours[k], R.Tint))
	end
	for i = 0, C - 1 do
		for j = 0, C - 1 do
			local c = i * C + j + 1
			local t1, t2 = cellTriangles(n, i, j, tile.flip[c])
			for q, t in { t1, t2 } do
				local f = m.faces[2 * (c - 1) + q]
				em:SetFaceVertices(f, { m.v[t[1]], m.v[t[2]], m.v[t[3]] })
				em:SetFaceNormals(f, { m.nrm[t[1]], m.nrm[t[2]], m.nrm[t[3]] })
				em:SetFaceColors(f, { m.col[t[1]], m.col[t[2]], m.col[t[3]] })
			end
		end
	end
	rockStats.writes += 1
	rockStats.writeMs += (os.clock() - t0) * 1000
end

-- Whether any of a tile's vertices is rock enough for the rock mesh to show.
local function tileHasRock(tile: Tile, oy: number): boolean
	local from = Config.GroundLook.RockMesh.From
	for k = 1, #tile.heights do
		if tile.cls[k] == OPEN and GroundLook.rockWeight(tile.px[k], tile.pz[k], tile.heights[k] - oy, tile.normals[k].Y) >= from then
			return true
		end
	end
	return false
end

-- A grid point of a spacing's lattice, shaded the way a tile of that spacing shades it when
-- every tile round the point has that spacing.
local function latticeShade(spline: any, L: Lattice, I: number, J: number): (Vector3, Color3)
	return shadeFrom(spline, L.ctx, place(L, I, J), I * L.s, J * L.s, place(L, I + 1, J), place(L, I - 1, J), place(L, I, J + 1), place(L, I, J - 1))
end

-- NO LINES WHERE TILES MEET (T-251 send-back): a vertex on an edge it shares with a coarser
-- tile is shaded as the coarser tile shades that edge, as its height already is: at a grid
-- point of the coarsest tile touching it, that spacing's way; between two, straight between
-- them (the coarser tile blends its normals and colours along the edge just so). Before this,
-- each tile shaded its edge from its own grid, so the two sides of an edge met at a
-- different normal and colour: a light or dark line along every edge between two spacings
-- (measured: up to 13 degrees and 12 of 255 apart). `lats`: lattices made so far, by spacing.
local function onGrid(v: number, sp: number): boolean
	local q = v / sp
	return math.abs(q - math.round(q)) < 1e-6
end

local function shadeAt(self: View, map: { [number]: Leaf }, lats: { [number]: { any } }, s: number, x: number, z: number): (Vector3, Color3)
	local sm = GroundTiles.spacingAround(map, x, z)
	if sm < s then
		sm = s
	end
	if onGrid(x, sm) and onGrid(z, sm) then
		-- (kept: a grid point is shaded the same while the road near it does not change)
		local I, J = math.round(x / sm), math.round(z / sm)
		local spline = self.spline
		local span = self.shadesFor
		if span[1] ~= spline.firstSample or span[2] ~= spline.length then
			self.shades = {}
			self.shadesFor = { spline.firstSample, spline.length }
		end
		local bySpacing = self.shades[sm]
		if not bySpacing then
			bySpacing = {}
			self.shades[sm] = bySpacing
		end
		local kept = bySpacing[latKey(I, J)]
		if kept then
			return kept[1], kept[2]
		end
		-- a lattice of that spacing made round a point near enough (`place` and its neighbours
		-- reach two grid points out), or a new one round this point
		local held = lats[sm]
		if not held or math.abs(x - held[2]) > 2 * sm or math.abs(z - held[3]) > 2 * sm then
			local r = 5 * sm + 1
			held = { newLattice(Ground.context(self.field, self.spline, x - r, z - r, x + r, z + r), sm), x, z }
			lats[sm] = held
		end
		local nv, colour = latticeShade(self.spline, held[1] :: Lattice, I, J)
		bySpacing[latKey(I, J)] = { nv, colour }
		return nv, colour
	end
	local ax, az, bx, bz, f
	if onGrid(x, sm) then
		local z0 = math.floor(z / sm) * sm
		ax, az, bx, bz, f = x, z0, x, z0 + sm, (z - z0) / sm
	else
		local x0 = math.floor(x / sm) * sm
		ax, az, bx, bz, f = x0, z, x0 + sm, z, (x - x0) / sm
	end
	local na, ca = shadeAt(self, map, lats, sm, ax, az)
	local nb, cb = shadeAt(self, map, lats, sm, bx, bz)
	local nv = na * (1 - f) + nb * f
	return if nv.Magnitude > 1e-9 then nv.Unit else Vector3.yAxis, ca:Lerp(cb, f)
end

-- Fill a hidden tile with `leaf`'s ground, given the tiles it will sit among (`map`).
function GroundMeshView._fill(self: View, tile: Tile, leaf: Leaf, map: { [number]: Leaf }): boolean
	local G = Config.Spline.Ground
	local C = cells()
	local n = C + 1
	local m = n + 2 -- with a row of apron each side, for the normals
	local s, x0, z0 = leaf.s, leaf.x0, leaf.z0
	-- (two cells round: the apron's neighbours, and where a vertex moves to, must be inside it)
	local margin = 2 * s + 1
	local ctx = Ground.context(self.field, self.spline, x0 - margin, z0 - margin, x0 + leaf.side + margin, z0 + leaf.side + margin)
	local L = newLattice(ctx, s)
	local I0, J0 = math.round(x0 / s), math.round(z0 / s)
	self:_slice()
	-- every vertex and the apron, placed this spacing's way (the apron for the normals)
	local V = table.create(m * m)
	for i = -1, C + 1 do
		if self.dead then
			return false
		end
		for j = -1, C + 1 do
			V[(i + 1) * m + (j + 1) + 1] = place(L, I0 + i, J0 + j)
			if groundRunoff then
				self:_slice() -- (a point by the road works out the exact edge several times)
			end
		end
		self:_slice()
	end
	local P = table.create(n * n)
	for i = 0, C do
		for j = 0, C do
			P[i * n + j + 1] = V[(i + 1) * m + (j + 1) + 1]
		end
	end
	for k, p in rimPlace(L, leaf, map) do
		P[k] = p
	end
	self:_slice()
	local flips = table.create(C * C, false)
	for i = 0, C - 1 do
		for j = 0, C - 1 do
			local f, folded = chooseSplit(ctx, s, P, n, i, j)
			flips[i * C + j + 1] = f
			if f then
				self.wall.flipped += 1
			end
			if folded then
				self.wall.inverted += 1
			end
		end
	end
	self:_slice()
	-- normals from the vertices round each one, as placed (the apron gives the edge ones),
	-- colours by slope
	local cx, cz = x0 + leaf.side * 0.5, z0 + leaf.side * 0.5
	local cy = Ground.base(self.field, cx, cz)
	local uvStuds = G.UVStuds
	local em = tile.em
	local heights = tile.heights
	local lats: { [number]: { any } } = {}
	for i = 0, C do
		local x = x0 + i * s
		for j = 0, C do
			local k = i * n + j + 1
			local z = z0 + j * s
			local q = (i + 1) * m + (j + 1) + 1
			local p = P[k]
			local nv, colour
			local _, hi = GroundTiles.spacingRange(map, x, z)
			local borrow = (i == 0 or i == C or j == 0 or j == C) and hi > s
			if borrow then
				nv, colour = shadeAt(self, map, lats, s, x, z) -- shared with a coarser tile
			else
				nv, colour = shadeFrom(self.spline, ctx, V[q], x, z, V[q + m], V[q - m], V[q + 1], V[q - 1])
			end
			tile.borrowed[k] = borrow
			if groundRunoff then
				self:_slice()
			end
			if p[4] == HELD then
				if p[1] ~= x or p[2] ~= z then
					self.wall.moved += 1
				else
					self.wall.held += 1
				end
			end
			tile.px[k], tile.pz[k], heights[k], tile.cls[k], tile.normals[k], tile.colours[k] = p[1], p[2], p[3], p[4], nv, colour
			if em then
				-- a tile that keeps its own mesh (opaque content refused): written in place
				em:SetPosition(tile.v[k], Vector3.new(p[1] - cx, p[3] - cy, p[2] - cz))
				em:SetNormal(tile.nrm[k], nv)
				em:SetColor(tile.col[k], colour)
				em:SetUV(tile.uv[k], Vector2.new(p[1] / uvStuds, p[2] / uvStuds))
			end
		end
		self:_slice()
	end
	for i = 0, C - 1 do
		for j = 0, C - 1 do
			setSplit(tile, i, j, flips[i * C + j + 1])
		end
	end
	if em and tile.part then
		tile.part.CFrame = CFrame.new(cx, cy, cz)
		tile.origin = Vector3.new(cx, cy, cz)
	end
	-- the rock mesh (T-339, "rock" only, a tile that keeps its own mesh): made if this tile
	-- has rock and has none yet, let go if it has none
	local oy = self.field.oy
	if lookNow == "rock" and em and tile.part and tileHasRock(tile, oy) then
		if not tile.rockEm and self.master then
			local ok, made = pcall(function()
				return AssetService:CreateEditableMeshAsync(masterSource(self.master :: Master), { FixedSize = true })
			end)
			local part = if ok and made then partFrom(Content.fromObject(made :: EditableMesh)) else nil
			if ok and made and part then
				part.Name = "GroundRock"
				part.Material = Config.GroundLook.RockMesh.Material
				tile.rockEm, tile.rockPart, tile.rockMap = made :: EditableMesh, part, idMapOf(made :: EditableMesh)
				rockStats.made += 1
			else
				if ok and made then
					(made :: EditableMesh):Destroy()
				end
				rockStats.fails += 1
			end
			if self.dead then
				return false
			end
		end
		if tile.rockEm and tile.rockPart then
			tile.hasRock = true
			tile.rockPart.CFrame = tile.part.CFrame
			writeRock(tile, oy)
		end
	elseif tile.rockEm then
		dropRock(tile)
	end
	-- (an opaque tile's mesh is made from these tables next, `_render`)
	tile.leaf = leaf
	tile.cy = cy
	tile.stale = false
	self.tilesBuilt += 1
	return true
end

-- A shown tile's rim, worked out again among `map`: the vertices that would move or shade
-- differently ({k, x, z, y, class, normal, colour}), and the cells beside them whose split
-- would change ({i, j, flip}).
function GroundMeshView._rimChanges(self: View, tile: Tile, map: { [number]: Leaf }): ({ { any } }, { { any } })
	local leaf = tile.leaf :: Leaf
	local s = leaf.s
	local C = cells()
	local n = C + 1
	local margin = 2 * s + 1
	local ctx = Ground.context(self.field, self.spline, leaf.x0 - margin, leaf.z0 - margin, leaf.x0 + leaf.side + margin, leaf.z0 + leaf.side + margin)
	local L = newLattice(ctx, s)
	self:_slice()
	local changes = {}
	local changed: { [number]: { number } } = {}
	local I0, J0 = math.round(leaf.x0 / s), math.round(leaf.z0 / s)
	local lats: { [number]: { any } } = {}
	for k, p in rimPlace(L, leaf, map) do
		local moved = math.abs(p[1] - tile.px[k]) > 1e-4
			or math.abs(p[2] - tile.pz[k]) > 1e-4
			or math.abs(p[3] - tile.heights[k]) > 1e-4
			or p[4] ~= tile.cls[k]
		-- and how it is shaded, as `_fill` would shade it among these tiles
		local i, j = (k - 1) // n, (k - 1) % n
		local x, z = leaf.x0 + i * s, leaf.z0 + j * s
		local _, hi = GroundTiles.spacingRange(map, x, z)
		local borrow = hi > s
		local nv, colour = tile.normals[k], tile.colours[k]
		local reshaded = false
		-- (a vertex shaded its own tile's way stays so while no coarser tile touches it)
		if borrow or tile.borrowed[k] then
			if borrow then
				nv, colour = shadeAt(self, map, lats, s, x, z)
			else
				nv, colour = latticeShade(self.spline, L, I0 + i, J0 + j)
			end
			local was, wasC = tile.normals[k], tile.colours[k]
			reshaded = nv:Dot(was) < 0.99999
				or math.abs(colour.R - wasC.R) + math.abs(colour.G - wasC.G) + math.abs(colour.B - wasC.B) > 1e-4
		end
		if moved or reshaded or borrow ~= tile.borrowed[k] then
			table.insert(changes, { k, p[1], p[2], p[3], p[4], nv, colour, borrow })
		end
		if moved then
			changed[k] = p
		end
		if groundRunoff then
			self:_slice()
		end
	end
	self:_slice()
	local splits = {}
	if #changes > 0 then
		local P = table.create(n * n)
		for k = 1, n * n do
			P[k] = changed[k] or { tile.px[k], tile.pz[k], tile.heights[k], tile.cls[k] }
		end
		for i = 0, C - 1 do
			for j = 0, C - 1 do
				local a, b, c, d = i * n + j + 1, (i + 1) * n + j + 1, i * n + j + 2, (i + 1) * n + j + 2
				if changed[a] or changed[b] or changed[c] or changed[d] then
					local f = chooseSplit(ctx, s, P, n, i, j)
					if f ~= tile.flip[i * C + j + 1] then
						table.insert(splits, { i, j, f })
					end
				end
			end
		end
		self:_slice()
	end
	return changes, splits
end

-- A tile from the pool, or a new one; nil if the device will make no more. `over`: a change
-- that lets go of more tiles than it takes may go past the cap for a moment (a lower
-- setting turns the pool into merges, each needing one tile before it frees four).
function GroundMeshView._take(self: View, over: boolean?): Tile?
	if not self.master then
		self.master = makeMaster()
		if not self.master then
			self.failed = "this device would not make the ground's mesh"
			return nil
		end
	end
	local master = self.master :: Master
	if master.em and not master.content and opaqueOk() then
		-- opaque content refused when the master was made, served now: the master as content,
		-- and its own mesh let go (T-276)
		local made, content = toOpaque(master.em)
		if made and content then
			master.em:Destroy()
			master.em, master.content = nil, content
		end
	end
	local opaque = opaqueTiles() and opaqueOk() and master.content ~= nil
	local t = table.remove(self.free)
	if t and not t.em and not opaque then
		-- an opaque tile while tiles are not made opaque (switched off since): a tile that
		-- keeps its own mesh instead
		local i = table.find(self.pool, t)
		if i then
			table.remove(self.pool, i)
		end
		if t.part then
			t.part:Destroy()
		end
		t = nil
	end
	if t then
		if t.em and opaque then
			-- a tile that kept its own mesh, while opaque content was refused: let it go
			if t.part then
				t.part:Destroy()
			end
			t.em:Destroy()
			t.em, t.part = nil, nil
			dropRock(t)
		end
		return t
	end
	if #self.pool >= self.cap and not over then
		return nil
	end
	local tile
	if opaque then
		-- (holds no mesh memory: its mesh is made opaque once it is filled, `_render`)
		tile = blankTile()
	else
		tile = makeTile(master)
	end
	if not tile then
		-- the budget is full: hold what there is, less a few for the road
		local G = Config.Spline.Ground
		self.failCap = math.min(self.failCap or math.huge, math.max(G.Spare + 4, #self.pool - G.ReleaseOnFail))
		self:_setCap()
		return nil
	end
	table.insert(self.pool, tile)
	return tile
end

-- Let a tile's drawing go: an opaque tile's part (made again when it is next filled); one that
-- keeps its own mesh only leaves the world, ready to be written again, as before T-276.
local function stow(t: Tile)
	if t.rockPart then
		t.rockPart.Parent = nil
	end
	if t.em then
		if t.part then
			t.part.Parent = nil
		end
	elseif t.part then
		t.part:Destroy()
		t.part = nil
	end
end

-- Let go of hidden tiles past the cap (a lower setting, or a full budget), for the road; and
-- past `Spare` (T-273): merges left up to 60 hidden, every one held in the mesh memory.
function GroundMeshView._trim(self: View)
	local spare = Config.Spline.Ground.Spare
	while #self.free > 0 and (#self.pool > self.cap or #self.free > spare) do
		local t = table.remove(self.free) :: Tile
		local i = table.find(self.pool, t)
		if i then
			table.remove(self.pool, i)
		end
		if t.part then
			t.part:Destroy()
		end
		if t.em then
			t.em:Destroy()
		end
		dropRock(t)
	end
end

-- Make a tile's mesh from these tables, off the frame (T-276, `render`): at most
-- `Ground.OpaqueInFlight` at once. The job is done once `job.done`.
function GroundMeshView._render(self: View, leaf: Leaf, cy: number, px: { number }, pz: { number }, heights: { number }, normals: { Vector3 }, colours: { Color3 }, flip: { boolean }): Job
	local most = Config.Spline.Ground.OpaqueInFlight
	while self.inflight >= most and not self.dead do
		self:_pause()
	end
	local job: Job = { done = false, part = nil, held = nil, origin = nil, map = nil, err = nil }
	local master = self.master :: Master
	local stats = self.opaque
	self.inflight += 1
	stats.inflightMost = math.max(stats.inflightMost, self.inflight)
	stats.renders += 1
	task.spawn(function()
		local ok, part, held, origin, map = pcall(render, master, leaf, cy, px, pz, heights, normals, colours, flip, stats)
		self.inflight -= 1
		if ok then
			job.part, job.held, job.origin, job.map = part, held, origin, map
		else
			job.err = tostring(part)
		end
		job.done = true
	end)
	return job
end

-- Hand the frame back while waiting on the engine: not counted as building (`Road/SplineMesh`
-- measured the waits run off the frame).
function GroundMeshView._pause(self: View)
	local now = os.clock()
	local ms = (now - self.sliceStart) * 1000
	self.work += now - self.sliceStart
	self.worstSliceMs = math.max(self.worstSliceMs, ms)
	task.wait()
	self.sliceStart = os.clock()
end

-- Wait for `jobs` to be done. Returns whether every one made its part.
function GroundMeshView._await(self: View, jobs: { Job }): boolean
	local t0 = os.clock()
	local all = true
	for _, job in jobs do
		while not job.done do
			self:_pause()
		end
		if not job.part then
			all = false
			if job.err then
				warn(`[GroundMeshView] a tile's mesh: {job.err}`)
			end
		end
	end
	local ms = (os.clock() - t0) * 1000
	self.opaque.waitMs += ms
	self.opaque.worstWaitMs = math.max(self.opaque.worstWaitMs, ms)
	return all
end

-- Let go of what `jobs` made (a change given up).
local function scrap(jobs: { Job })
	for _, job in jobs do
		if job.part then
			job.part:Destroy()
			job.part = nil
		end
		if job.held then
			job.held:Destroy()
			job.held = nil
		end
	end
end

--------------------------------------------------------------------------------
-- What to change next
--------------------------------------------------------------------------------

-- The car's place along the road, followed from frame to frame.
function GroundMeshView._locate(self: View)
	local spline = self.spline
	local s
	if self.along then
		s = spline:projectFrom(self.carX, self.carZ, self.along)
	end
	if not s then
		s = spline:project(self.carX, self.carZ, 200)
	end
	if s then
		self.along = s
	end
end

function GroundMeshView._want(self: View): GroundTiles.Want
	local P = GroundDetail.preset(self.detail)
	local road = {}
	local along = self.along
	local spline = self.spline
	if along then
		-- as far as the road is drawn: 8 studs out to `Fine` along it, then coarser. Behind the
		-- car, from where the drawn road starts (the player's "Road behind", T-230, chunk-
		-- aligned as `Drift/SplineRoadView` draws it), so no coarse tile ever lies beside drawn
		-- road; but past `Mesh.BehindSharp` (300) studs back it asks only for `RoadCoarsest`, so a longer
		-- road behind costs the corridor's few coarse tiles, not the sharp ground ahead. Ahead,
		-- to the player's "Road ahead" (T-263). (`GroundTiles.roadPoints`, T-281, so the tests
		-- ask for the same)
		local first = spline.firstSample * spline.step
		local s0 = math.max(first, RoadBehind.from(along))
		local s1 = math.min(spline.length, along + RoadAhead.studs())
		road = GroundTiles.roadPoints(spline, along, s0, s1, P.Fine)
	end
	local split: { [number]: boolean } = {}
	for _, leaf in self.shown do
		local p = GroundTiles.parent(leaf)
		while p and not split[p.key] do
			split[p.key] = true
			p = GroundTiles.parent(p)
		end
	end
	return {
		x = self.carX,
		z = self.carZ,
		road = road,
		tiles = self:_leafBudget(),
		ratio = P.Ratio,
		reach = P.Reach,
		split = split,
		limit = GroundTiles.limit(), -- inside the painted vista (T-281)
	}
end

function GroundMeshView._desired(self: View): { [number]: Leaf }
	local at = Vector3.new(self.carX, 0, self.carZ)
	local G = Config.Spline.Ground
	if not self.desired or self.dirty or self.desiredDetail ~= self.detail or not self.desiredAt or (at - self.desiredAt).Magnitude > G.Reselect then
		local t0 = os.clock()
		local _, map = GroundTiles.select(self:_want())
		self.selectMs = (os.clock() - t0) * 1000
		self.totalWorkMs += self.selectMs
		self.desired = map
		self.desiredAt = at
		self.desiredDetail = self.detail
		self.dirty = false
		self.pending = {}
	end
	return self.desired :: { [number]: Leaf }
end

-- A big split a step at a time: `root`'s children that hold wanted tiles, each one taken
-- further down where it would reach past the ground's limit round where the wanted tiles
-- were chosen (T-281), so no step ever shows a tile the vista would cut.
function GroundMeshView._step(self: View, root: Leaf, desired: { [number]: Leaf }): { Leaf }
	local limit = GroundTiles.limit()
	local at = self.desiredAt or Vector3.new(self.carX, 0, self.carZ)
	local out: { Leaf } = {}
	local function walk(nd: Leaf)
		for _, c in GroundTiles.children(nd) do
			local holds = desired[c.key] ~= nil
			if not holds then
				for _, l in desired do
					if GroundTiles.within(c, l) then
						holds = true
						break
					end
				end
			end
			if holds then
				if not desired[c.key] and c.level > 1 and GroundTiles.farCorner(c.x0, c.z0, c.side, at.X, at.Z) > limit then
					walk(c)
				else
					table.insert(out, c)
				end
			end
		end
	end
	walk(root)
	return out
end

-- Every place the shown tiles differ from the wanted ones, as one change each (the coarsest
-- tile round it), nearest the car first. They never overlap, so they can be done in turn.
function GroundMeshView._diff(self: View, desired: { [number]: Leaf }): { Op }
	local G = Config.Spline.Ground
	local shown = self.shown
	local roots: { [number]: Leaf } = {}
	for k, leaf in desired do
		if not shown[k] then
			local r = GroundTiles.above(shown, leaf) or leaf
			roots[r.key] = r
		end
	end
	for k, leaf in shown do
		if not desired[k] then
			local r = GroundTiles.above(desired, leaf) or leaf
			roots[r.key] = r
		end
	end
	local list: { Op } = {}
	for _, root in roots do
		local old, new = {}, {}
		for _, l in shown do
			if GroundTiles.within(root, l) then
				table.insert(old, l)
			end
		end
		for _, l in desired do
			if GroundTiles.within(root, l) then
				table.insert(new, l)
			end
		end
		local kind = if #old == 0 then "fill" elseif #new == 0 then "drop" elseif shown[root.key] then "split" else "merge"
		if kind == "split" and #new > G.Spare then
			new = self:_step(root, desired) -- a step at a time
		end
		table.insert(list, { kind = kind, old = old, new = new, region = { root } })
	end
	local cx, cz = self.carX, self.carZ
	local function dist(l: Leaf): number
		return GroundTiles.distTo(l.x0, l.z0, l.side, cx, cz)
	end
	table.sort(list, function(a, b)
		return dist(a.region[1]) < dist(b.region[1])
	end)
	return list
end

function GroundMeshView._nextOp(self: View): Op?
	local G = Config.Spline.Ground
	local desired = self:_desired()
	local room = #self.free + math.max(0, self.cap - #self.pool)
	-- tiles to redraw for new road, between the changes
	local stale = {}
	for k, tile in self.tiles do
		if tile.stale and desired[k] then
			table.insert(stale, tile.leaf :: Leaf)
		end
	end
	if #self.pending == 0 then
		self.pending = self:_diff(desired)
	end
	local list = self.pending
	if #stale > 0 and (self.lastStale == false or #list == 0) and room >= 1 then
		local cx, cz = self.carX, self.carZ
		table.sort(stale, function(a, b)
			return GroundTiles.distTo(a.x0, a.z0, a.side, cx, cz) < GroundTiles.distTo(b.x0, b.z0, b.side, cx, cz)
		end)
		local batch = {}
		for i = 1, math.min(#stale, room, G.Spare) do
			batch[i] = stale[i]
		end
		self.lastStale = true
		return { kind = "stale", old = batch, new = batch, region = batch }
	end
	self.lastStale = false
	for i, op in list do
		if #op.new <= room then
			table.remove(list, i)
			return op
		end
	end
	-- nothing that adds tiles fits: free some first
	for i, op in list do
		if #op.new <= 1 and #op.old >= #op.new then
			table.remove(list, i)
			return op
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Doing it
--------------------------------------------------------------------------------

function GroundMeshView._do(self: View, op: Op): boolean
	local t0 = os.clock()
	self.work = 0
	self.lastSlices = 1
	self.sliceStart = t0
	local length = self.spline.length
	-- what will show once it is done
	local future: { [number]: Leaf } = table.clone(self.shown)
	for _, l in op.old do
		future[l.key] = nil
	end
	local newKeys: { [number]: boolean } = {}
	for _, l in op.new do
		future[l.key] = l
		newKeys[l.key] = true
	end
	-- the new tiles, hidden; an opaque tile's mesh made from its tables as soon as it is filled
	-- (T-276), while the next one is worked out
	local built: { Tile } = {}
	local jobs: { Job } = {}
	local builtJobs: { [Tile]: Job } = {}
	local function giveUp(): boolean
		self:_await(jobs)
		scrap(jobs)
		for _, t in built do
			stow(t)
			table.insert(self.free, t)
		end
		return false
	end
	for _, leaf in op.new do
		local tile = self:_take(#op.old > #op.new)
		if not tile then
			return giveUp()
		end
		table.insert(built, tile)
		if not self:_fill(tile, leaf, future) then
			return giveUp()
		end
		if not tile.em then
			local job = self:_render(leaf, tile.cy, tile.px, tile.pz, tile.heights, tile.normals, tile.colours, tile.flip)
			table.insert(jobs, job)
			builtJobs[tile] = job
		end
	end
	-- the tiles round it whose edges change: one that keeps its own mesh is written in place at
	-- the swap, as before; an opaque one gets a new mesh from its tables with the changes in
	local pending: { { any } } = {}
	for k, leaf in future do
		if not newKeys[k] then
			local touching = false
			for _, r in op.region do
				if GroundTiles.touches(leaf, r) then
					touching = true
					break
				end
			end
			local tile = self.tiles[k]
			if touching and tile then
				local changes, splits = self:_rimChanges(tile, future)
				if #changes > 0 or #splits > 0 then
					local job: Job? = nil
					if not tile.em then
						local px, pz, h = table.clone(tile.px), table.clone(tile.pz), table.clone(tile.heights)
						local nm, cl, fl = table.clone(tile.normals), table.clone(tile.colours), table.clone(tile.flip)
						for _, ch in changes do
							local kk = ch[1]
							px[kk], pz[kk], h[kk] = ch[2], ch[3], ch[4]
							if ch[6] and ch[7] then
								nm[kk], cl[kk] = ch[6], ch[7]
							end
						end
						local C = cells()
						for _, sp in splits do
							fl[sp[1] * C + sp[2] + 1] = sp[3]
						end
						job = self:_render(tile.leaf :: Leaf, tile.cy, px, pz, h, nm, cl, fl)
						table.insert(jobs, job :: Job)
					end
					table.insert(pending, { tile, changes, splits, job })
				end
			end
		end
		if self.dead then
			return giveUp()
		end
	end
	if self.dead then
		return giveUp()
	end
	-- every mesh made, or none of it is shown
	if not self:_await(jobs) or self.dead then
		self.opaque.drops += 1
		-- (out of room for a copy: not tried again for a moment)
		self.retryAt = os.clock() + 0.25
		return giveUp()
	end
	-- swap it in, all in this frame
	local c0 = os.clock()
	local oldTiles: { Tile } = {}
	for _, l in op.old do
		local t = self.tiles[l.key]
		if t then
			table.insert(oldTiles, t)
			self.tiles[l.key] = nil
		end
	end
	for _, tile in built do
		local leaf = tile.leaf :: Leaf
		local job = builtJobs[tile]
		if job then
			tile.part, tile.em, tile.origin = job.part, job.held, job.origin :: Vector3
			if job.held then
				-- (opaque content refused: it keeps its copy, written in place from now on)
				local m = job.map :: IdMap
				tile.v, tile.nrm, tile.col, tile.uv, tile.faces = m.v, m.nrm, m.col, m.uv, m.faces
			end
		end
		self.tiles[leaf.key] = tile
		stylePart(tile.part :: MeshPart)
		;(tile.part :: MeshPart).Parent = self.folder
		if tile.hasRock and tile.rockPart then
			tile.rockPart.Parent = self.folder
		end
		if self.spline.length ~= length then
			tile.stale = true -- road arrived while it was built
		end
	end
	for _, t in oldTiles do
		stow(t)
		t.leaf = nil
		t.stale = false
		table.insert(self.free, t)
	end
	local uvStuds = Config.Spline.Ground.UVStuds
	for _, p in pending do
		local tile, changes, splits, job = p[1] :: Tile, p[2] :: { { any } }, p[3] :: { { any } }, p[4] :: Job?
		local em = tile.em
		local o = tile.origin
		for _, ch in changes do
			local k, x, z, y, cls, nv, colour = ch[1], ch[2], ch[3], ch[4], ch[5], ch[6], ch[7]
			tile.heights[k], tile.px[k], tile.pz[k], tile.cls[k] = y, x, z, cls
			if em then
				em:SetPosition(tile.v[k], Vector3.new(x - o.X, y - o.Y, z - o.Z))
				em:SetUV(tile.uv[k], Vector2.new(x / uvStuds, z / uvStuds))
			end
			if nv and colour then
				tile.normals[k], tile.colours[k], tile.borrowed[k] = nv, colour, ch[8] == true
				if em then
					em:SetNormal(tile.nrm[k], nv)
					em:SetColor(tile.col[k], colour)
				end
			end
			self.rimWrites += 1
		end
		for _, sp in splits do
			setSplit(tile, sp[1], sp[2], sp[3])
		end
		if tile.hasRock and (#changes > 0 or #splits > 0) then
			writeRock(tile, self.field.oy) -- (T-339: its edges follow the tile's)
		end
		if job then
			-- its new mesh in, its old one out, in this frame
			local old = tile.part
			local part = job.part :: MeshPart
			stylePart(part)
			part.Parent = self.folder
			tile.part, tile.origin = part, job.origin :: Vector3
			if job.held then
				tile.em = job.held
				local m = job.map :: IdMap
				tile.v, tile.nrm, tile.col, tile.uv, tile.faces = m.v, m.nrm, m.col, m.uv, m.faces
			end
			if old then
				old:Destroy()
			end
		end
	end
	self.shown = future
	self.worstCommitMs = math.max(self.worstCommitMs, (os.clock() - c0) * 1000)
	self.work += os.clock() - self.sliceStart
	self.lastMs = self.work * 1000
	self.totalWorkMs += self.lastMs
	self.worstMs = math.max(self.worstMs, self.lastMs)
	self.ops[op.kind] += 1
	if #self.events < 4000 then
		table.insert(self.events, { os.clock(), #op.new, #op.old })
	end
	return true
end

-- New road laid since the last look: the shown tiles it comes near are redrawn.
function GroundMeshView._checkNewRoad(self: View)
	local spline = self.spline
	local from, to = self.checkedTo, spline.length
	if to <= from + 1e-6 then
		return
	end
	self.checkedTo = to
	local reach = Ground.reach()
	for s = math.max(0, from - 16), to, 16 do
		local x, z = spline:planAt(s)
		for _, tile in self.tiles do
			local l = tile.leaf
			if l and not tile.stale and GroundTiles.distTo(l.x0, l.z0, l.side, x, z) < reach then
				tile.stale = true
			end
		end
	end
	self.desired = nil -- the road ahead may reach further now
end

function GroundMeshView._run(self: View)
	self.running = true
	while not self.dead and not self.paused do
		self:_checkNewRoad()
		local op = self:_nextOp()
		if not op then
			break
		end
		if not self:_do(op) then
			if self.failed then
				break
			end
			-- no tile to be had: settle for fewer, and try again next frame (or, out of room for
			-- a tile's copy, in a moment, T-276)
			self.desired = nil
			while os.clock() < self.retryAt and not self.dead do
				task.wait()
			end
		end
		self:_trim()
		task.wait()
	end
	self:_trim()
	self.running = false
end

-- Each frame, with the car's position.
function GroundMeshView.Update(self: View, x: number, z: number)
	if self.dead or self.failed or self.paused then
		return
	end
	self.carX, self.carZ = x, z
	self:_locate()
	if not self.running then
		self:_checkNewRoad()
		local at = self.desiredAt
		local moved = not at or (Vector3.new(x, 0, z) - at).Magnitude > 8
		local stale = false
		for _, tile in self.tiles do
			if tile.stale then
				stale = true
				break
			end
		end
		if moved or stale or self.dirty or self.desired == nil or #self.pool > self.cap then
			self.running = true
			task.spawn(function()
				local ok, err = pcall(self._run, self)
				if not ok then
					self.failed = tostring(err)
					self.running = false
					warn(`[GroundMeshView] {err}`)
				end
			end)
		end
	end
end

function GroundMeshView.Destroy(self: View)
	self.dead = true
	if self.changedConn then
		self.changedConn:Disconnect()
	end
	if self.behindConn then
		self.behindConn:Disconnect()
	end
	if self.aheadConn then
		self.aheadConn:Disconnect()
	end
	if self.unGive then
		self.unGive()
		self.unGive = nil
	end
	for _, tile in self.pool do
		if tile.part then
			tile.part:Destroy()
		end
		if tile.em then
			tile.em:Destroy()
		end
		dropRock(tile)
	end
	self.pool, self.free, self.tiles, self.shown = {}, {}, {}, {}
	if self.master then
		-- (its opaque content is kept for the next view: it holds no mesh memory)
		if self.master.em then
			self.master.em:Destroy()
		end
		self.master = nil
	end
	self.folder:Destroy()
end

--------------------------------------------------------------------------------
-- Checks
--------------------------------------------------------------------------------

-- The drawn ground at (x, z) in a tile, as its triangles have it: its height, the triangle's
-- own normal and the normal the renderer blends there; nil if no triangle of the tile holds
-- it (its vertices can be moved off their grid points, up to a cell).
local function facetAt(tile: Tile, x: number, z: number): (number?, Vector3?, Vector3?, Color3?)
	local leaf = tile.leaf :: Leaf
	local C = cells()
	local n = C + 1
	local s = leaf.s
	local gi = math.floor((x - leaf.x0) / s)
	local gj = math.floor((z - leaf.z0) / s)
	local px, pz, h = tile.px, tile.pz, tile.heights
	local best, bestY, bestN, bestS, bestC = -math.huge, nil, nil, nil, nil
	for i = math.max(gi - 1, 0), math.min(gi + 1, C - 1) do
		for j = math.max(gj - 1, 0), math.min(gj + 1, C - 1) do
			local t1, t2 = cellTriangles(n, i, j, tile.flip[i * C + j + 1])
			for _, t in { t1, t2 } do
				local p, q, r = t[1], t[2], t[3]
				local x1, z1, x2, z2, x3, z3 = px[p], pz[p], px[q], pz[q], px[r], pz[r]
				local l1, l2, l3 = bary(x1, z1, x2, z2, x3, z3, x, z)
				do
					local worst = math.min(l1, l2, l3) -- the most inside wins, for points on an edge
					if worst > best and worst > -1e-6 then
						best = worst
						bestY = l1 * h[p] + l2 * h[q] + l3 * h[r]
						local A = Vector3.new(x1, h[p], z1)
						local B = Vector3.new(x2, h[q], z2)
						local Cv = Vector3.new(x3, h[r], z3)
						local fn = (B - A):Cross(Cv - A)
						if fn.Y < 0 then
							fn = -fn
						end
						bestN = if fn.Magnitude > 1e-9 then fn.Unit else Vector3.yAxis
						local nm = tile.normals
						local sn = nm[p] * l1 + nm[q] * l2 + nm[r] * l3
						bestS = if sn.Magnitude > 1e-9 then sn.Unit else Vector3.yAxis
						local cl = tile.colours
						local ca, cb, cc = cl[p], cl[q], cl[r]
						bestC = Color3.new(ca.R * l1 + cb.R * l2 + cc.R * l3, ca.G * l1 + cb.G * l2 + cc.G * l3, ca.B * l1 + cb.B * l2 + cc.B * l3)
					end
				end
			end
		end
	end
	return bestY, bestN, bestS, bestC
end

local function surfaceAt(tile: Tile, x: number, z: number): number?
	return (facetAt(tile, x, z))
end

function GroundMeshView._tileAt(self: View, x: number, z: number): Tile?
	local l = GroundTiles.leafAt(self.shown, x, z)
	return if l then self.tiles[l.key] else nil
end

-- The drawn ground at (x, z) (`facetAt`) and the tile drawing it: the tile whose square holds
-- the point first, then any tile beside it (a vertex moved onto a wall's foot can carry a
-- tile's triangles a little past its square).
function GroundMeshView._drawnAt(self: View, x: number, z: number): (number?, Tile?, Vector3?, Vector3?)
	local t = self:_tileAt(x, z)
	if t then
		local y, fn, sn = facetAt(t, x, z)
		if y then
			return y, t, fn, sn
		end
	end
	for _, o in self.tiles do
		local l = o.leaf
		if l and o ~= t and x >= l.x0 - l.s and x <= l.x0 + l.side + l.s and z >= l.z0 - l.s and z <= l.z0 + l.side + l.s then
			local y, fn, sn = facetAt(o, x, z)
			if y then
				return y, o, fn, sn
			end
		end
	end
	return nil, nil, nil, nil
end

-- How far along the road ahead of the car its middle (and points `side` studs either way of
-- it) lie in tiles of `level` or finer.
function GroundMeshView.DebugReach(self: View, level: number, side: number?): number
	local spline = self.spline
	local along = self.along
	if not along then
		return 0
	end
	local s = along
	while s < spline.length do
		local x, z = spline:planAt(s)
		local yaw = spline:yawAt(s)
		for _, d in { 0, side or 0, -(side or 0) } do
			local l = GroundTiles.leafAt(self.shown, x + d * math.cos(yaw), z - d * math.sin(yaw))
			if not l or l.level > level then
				return s - along
			end
		end
		s += 8
	end
	return s - along
end

-- Sorted numbers in brief: how many, mean, p50, p90, p99, min and max.
local function brief(list: { number })
	if #list == 0 then
		return { n = 0 }
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	local sum = 0
	for _, v in sorted do
		sum += v
	end
	local function pct(p: number): number
		return sorted[math.clamp(math.ceil(#sorted * p), 1, #sorted)]
	end
	local function r(v: number): number
		return math.round(v * 1000) / 1000
	end
	return { n = #sorted, mean = r(sum / #sorted), p50 = r(pct(0.5)), p90 = r(pct(0.9)), p99 = r(pct(0.99)), min = r(sorted[1]), max = r(sorted[#sorted]) }
end

-- Where two shown tiles meet: the biggest height difference along their shared edges, sampled
-- every stud; and the drawn ground's highest point above the road or runoff, sampled along it.
function GroundMeshView.DebugSeams(self: View, roadAhead: number?)
	local list = {}
	for _, tile in self.tiles do
		if tile.leaf then
			table.insert(list, tile)
		end
	end
	local worst, edgePairs, samples, missing = 0, 0, 0, 0
	local rimVertices, rimMismatch = 0, 0
	local shadeSame = { angle = {}, colour = {} }
	local shadeMixed = { angle = {}, colour = {} }
	local worstAt = nil
	for a = 1, #list do
		local A = list[a]
		local la = A.leaf :: Leaf
		for b = a + 1, #list do
			local B = list[b]
			local lb = B.leaf :: Leaf
			-- a shared vertical edge (x) or horizontal (z), with some length in common
			local shared = nil
			if math.abs(la.x0 + la.side - lb.x0) < 1e-6 or math.abs(lb.x0 + lb.side - la.x0) < 1e-6 then
				local x = if math.abs(la.x0 + la.side - lb.x0) < 1e-6 then lb.x0 else la.x0
				local z0, z1 = math.max(la.z0, lb.z0), math.min(la.z0 + la.side, lb.z0 + lb.side)
				if z1 > z0 then
					shared = { x, z0, x, z1 }
				end
			elseif math.abs(la.z0 + la.side - lb.z0) < 1e-6 or math.abs(lb.z0 + lb.side - la.z0) < 1e-6 then
				local z = if math.abs(la.z0 + la.side - lb.z0) < 1e-6 then lb.z0 else la.z0
				local x0, x1 = math.max(la.x0, lb.x0), math.min(la.x0 + la.side, lb.x0 + lb.side)
				if x1 > x0 then
					shared = { x0, z, x1, z }
				end
			end
			if shared then
				edgePairs += 1
				local len = math.max(math.abs(shared[3] - shared[1]), math.abs(shared[4] - shared[2]))
				if la.s == lb.s then
					-- one spacing: the very same vertices, wherever they were moved to
					local s, n = la.s, cells() + 1
					for t = 0, len, s do
						local f = t / len
						local x = shared[1] + (shared[3] - shared[1]) * f
						local z = shared[2] + (shared[4] - shared[2]) * f
						local ka = math.round((x - la.x0) / s) * n + math.round((z - la.z0) / s) + 1
						local kb = math.round((x - lb.x0) / s) * n + math.round((z - lb.z0) / s) + 1
						local dd = math.max(math.abs(A.px[ka] - B.px[kb]), math.abs(A.pz[ka] - B.pz[kb]), math.abs(A.heights[ka] - B.heights[kb]))
						rimVertices += 1
						rimMismatch = math.max(rimMismatch, dd)
					end
				end
				local mixed = la.s ~= lb.s
				for t = 0, len do
					local f = t / len
					local x = shared[1] + (shared[3] - shared[1]) * f
					local z = shared[2] + (shared[4] - shared[2]) * f
					local ya, _, sa, ca = facetAt(A, x, z)
					local yb, _, sb, cb = facetAt(B, x, z)
					if sa and sb and ca and cb then
						-- (T-251 send-back: how the two sides shade and colour the same point)
						local ang = math.deg(math.acos(math.clamp(sa:Dot(sb), -1, 1)))
						local col = math.max(math.abs(ca.R - cb.R), math.abs(ca.G - cb.G), math.abs(ca.B - cb.B)) * 255
						local bucket = if mixed then shadeMixed else shadeSame
						table.insert(bucket.angle, ang)
						table.insert(bucket.colour, col)
					end
					local d = if ya and yb then math.abs(ya - yb) else 0
					if not ya or not yb then
						missing += 1
					end
					samples += 1
					if d > worst then
						worst = d
						worstAt = { x, z, la.s, lb.s }
					end
				end
			end
		end
	end
	-- the road: centre line, tarmac edges and runoff edges, every 4 studs ahead
	local spline = self.spline
	local half = Config.Road.Width * 0.5
	local above, roadSamples = -math.huge, 0
	local aboveBySpacing: { [string]: number } = {}
	local aboveAt = nil
	if self.along then
		local s = math.max(RoadBehind.from(self.along), spline.firstSample * spline.step)
		local s1 = math.min(spline.length, self.along + (roadAhead or RoadAhead.studs()))
		while s <= s1 do
			for _, side in { -1, 1 } do
				local w = spline:runoffAt(s, side)
				for _, d in { 0, half, half + w * 0.5, half + w - 1, half + w - 0.05 } do
					local x, y, z = spline:terrainXYZ(s, side * d)
					local g, tile = self:_drawnAt(x, z)
					if tile and g then
						local sk = tostring((tile.leaf :: Leaf).s)
						aboveBySpacing[sk] = math.max(aboveBySpacing[sk] or -math.huge, g - y)
						roadSamples += 1
						if g - y > above then
							above = g - y
							aboveAt = { s - self.along, side * d, (tile.leaf :: Leaf).s }
						end
					end
				end
			end
			s += 4
		end
	end
	return {
		tilePairs = edgePairs,
		edgeSamples = samples,
		edgeMissing = missing, -- points on a shared edge a tile did not hold (its vertices moved)
		rimVertices = rimVertices, -- vertices two tiles of one spacing share
		rimMismatch = rimMismatch, -- studs: the most two copies of one of them differ
		worstStep = worst,
		worstAt = worstAt,
		roadSamples = roadSamples,
		highestAboveRoad = above,
		highestAboveRoadBySpacing = aboveBySpacing,
		highestAt = aboveAt,
		-- across every shared edge, every stud: the angle between the normals the two sides
		-- shade it with (degrees), and the most a colour channel differs (of 255); between tiles
		-- of one spacing, and of two
		shadeSame = { angle = brief(shadeSame.angle), colour = brief(shadeSame.colour) },
		shadeMixed = { angle = brief(shadeMixed.angle), colour = brief(shadeMixed.colour) },
	}
end

-- How well the drawn ground follows the cut walls and drops beside the road (T-231). Every
-- `step` studs of road from `behind` back to `ahead` on from the car, a line square across each
-- side from the runoff's edge, 40 studs out, every half stud: the drawn ground against what
-- the tile means to draw there (`Ground.at`, sunk). A profile counts as a wall where the
-- ground 40 studs out is over 4 studs above the edge (a cut) or below it (a fill). Per wall:
-- the worst height difference along it; how far from the true wall's middle the drawn
-- one's is (its wander, and how much that changes from one profile to the next: a sawtooth
-- changes a lot); and at the true middle, how far the drawn triangle's own normal, and the
-- normal the renderer blends there, are from the true ground's.
function GroundMeshView.DebugWalls(self: View, ahead: number?, step: number?, behind: number?)
	local spline = self.spline
	local along = self.along
	if not along then
		return { on = false }
	end
	local half = Config.Road.Width * 0.5
	local OUT, DS = 40, 0.5
	local s0 = math.max(spline.firstSample * spline.step, along - (behind or 0))
	local s1 = math.min(spline.length, along + (ahead or 400))
	local dsStep = step or 2
	local function agg()
		return { n = 0, dev = {}, wander = {}, jitter = {}, facet = {}, shade = {}, facetStep = {}, bySpacing = {}, worst = 0, worstAt = nil :: any, worstList = {} :: { any } }
	end
	local out = { cut = agg(), fill = agg() }
	local prev: { [number]: any } = {}
	local s = s0
	while s <= s1 do
		local cx, cz = spline:planAt(s)
		local yaw = spline:yawAt(s)
		local rx, rz = math.cos(yaw), -math.sin(yaw)
		for _, side in { -1, 1 } do
			local D = half + spline:runoffAt(s, side)
			local ux, uz = rx * side, rz * side
			local ex, ez = cx + ux * D, cz + uz * D
			local ctx = Ground.context(self.field, spline, ex - OUT - 2, ez - OUT - 2, ex + OUT + 2, ez + OUT + 2)
			local trueY, drawnY, T0 = {}, {}, nil
			local ok = true
			local tileS = 0
			for q = 0, OUT / DS do
				local d = q * DS
				local x, z = ex + ux * d, ez + uz * d
				local y, a, _, T = Ground.at(ctx, x, z)
				if q == 0 then
					T0 = T
				end
				local g, tile = self:_drawnAt(x, z)
				if not tile or not g then
					ok = false
					break
				end
				local sp = (tile.leaf :: Leaf).s
				tileS = math.max(tileS, sp)
				trueY[q] = y - sinkOf[sp] * a
				drawnY[q] = g
			end
			local kind = nil
			if ok and T0 then
				local rise = trueY[OUT / DS] - T0
				kind = if rise > 4 then "cut" elseif rise < -4 then "fill" else nil
			end
			if kind then
				local A = out[kind]
				local sign = if kind == "cut" then 1 else -1
				local mid = (T0 + trueY[OUT / DS]) * 0.5
				local dev, qT, qD = 0, nil, nil
				for q = 0, OUT / DS do
					dev = math.max(dev, math.abs(drawnY[q] - trueY[q]))
					if not qT and (trueY[q] - mid) * sign >= 0 then
						qT = q
					end
					if not qD and (drawnY[q] - mid) * sign >= 0 then
						qD = q
					end
				end
				A.n += 1
				table.insert(A.dev, dev)
				-- the worst few, drawn against true every 2 studs out, to see what is off
				if #A.worstList < 6 or dev > A.worstList[#A.worstList].dev then
					local line = {}
					for q = 0, OUT / DS, 4 do
						table.insert(line, string.format("%g:%.1f/%.1f", q * DS, trueY[q] - T0, drawnY[q] - T0))
					end
					table.insert(A.worstList, { dev = math.round(dev * 100) / 100, at = math.round(s - along), side = side, edge = { math.round(ex), math.round(T0), math.round(ez) }, line = table.concat(line, " ") })
					table.sort(A.worstList, function(p, q)
						return p.dev > q.dev
					end)
					A.worstList[7] = nil
				end
				local key = tostring(tileS)
				A.bySpacing[key] = (A.bySpacing[key] or 0) + 1
				if dev > A.worst then
					A.worst = dev
					A.worstAt = { s - along, side, tileS }
				end
				if qT and qD then
					local wander = (qD - qT) * DS
					table.insert(A.wander, math.abs(wander))
					local p = prev[side]
					if p and p.kind == kind and p.s == s - dsStep then
						table.insert(A.jitter, math.abs(wander - p.wander))
					end
					-- normals at the true wall's middle
					local d = qT * DS
					local x, z = ex + ux * d, ez + uz * d
					local _, _, fn, sn = self:_drawnAt(x, z)
					local h = 0.5
					local yx1 = Ground.at(ctx, x + h, z)
					local yx0 = Ground.at(ctx, x - h, z)
					local yz1 = Ground.at(ctx, x, z + h)
					local yz0 = Ground.at(ctx, x, z - h)
					local tn = Vector3.new(-(yx1 - yx0) / (2 * h), 1, -(yz1 - yz0) / (2 * h)).Unit
					if fn and sn then
						table.insert(A.facet, math.deg(math.acos(math.clamp(fn:Dot(tn), -1, 1))))
						table.insert(A.shade, math.deg(math.acos(math.clamp(sn:Dot(tn), -1, 1))))
						if p and p.kind == kind and p.s == s - dsStep and p.fn then
							table.insert(A.facetStep, math.deg(math.acos(math.clamp(fn:Dot(p.fn), -1, 1))))
						end
					end
					prev[side] = { kind = kind, s = s, wander = wander, fn = fn }
				else
					prev[side] = nil
				end
			else
				prev[side] = nil
			end
		end
		s += dsStep
	end
	local function summary(list: { number })
		if #list == 0 then
			return { n = 0 }
		end
		local sorted = table.clone(list)
		table.sort(sorted)
		local sum = 0
		for _, v in sorted do
			sum += v
		end
		local function pct(p: number): number
			return sorted[math.clamp(math.ceil(#sorted * p), 1, #sorted)]
		end
		local r = function(v: number): number
			return math.round(v * 100) / 100
		end
		return { n = #sorted, mean = r(sum / #sorted), p50 = r(pct(0.5)), p90 = r(pct(0.9)), max = r(sorted[#sorted]) }
	end
	local result = { on = true, from = s0 - along, to = s1 - along, step = dsStep }
	for kind, A in out do
		result[kind] = {
			profiles = A.n,
			bySpacing = A.bySpacing,
			deviation = summary(A.dev), -- studs, worst along each profile
			wander = summary(A.wander), -- studs, drawn wall's middle from the true one's
			jitter = summary(A.jitter), -- studs, how much the wander changes profile to profile
			facetAngle = summary(A.facet), -- degrees, drawn triangle's normal from the true one
			shadeAngle = summary(A.shade), -- degrees, the blended normal from the true one
			facetStep = summary(A.facetStep), -- degrees, triangle normal from the last profile's
			worstAt = A.worstAt,
			worstProfiles = A.worstList, -- "studs out: true/drawn", heights above the edge
		}
	end
	return result
end

-- THE GROUND UNDER THE CAR WHERE IT CARRIES THE RUNOFF (T-251): every `step` studs of road
-- from `behind` back to `ahead` on from the car, across each side from the bevel's foot to the
-- runoff's edge every half stud, the drawn ground less what the car stands on there
-- (`Spline:terrainY`): positive, a wheel there would sink into the drawn ground; negative, it
-- would float over it. By tile spacing. And across the tarmac and the bevel, how far the
-- drawn ground is below the road's surface (it must never show through), and at the edge's
-- flat foot, half a stud past it.
function GroundMeshView.DebugRunoffGap(self: View, ahead: number?, behind: number?, step: number?)
	local spline = self.spline
	local along = self.along
	if not along then
		return { on = false }
	end
	local half = Config.Road.Width * 0.5
	local s0 = math.max(spline.firstSample * spline.step, along - (behind or 100))
	local s1 = math.min(spline.length, along + (ahead or 100))
	local gaps: { [string]: { number } } = {}
	local under: { [string]: { number } } = {}
	local foot: { [string]: { number } } = {}
	local missing = 0
	local worst, worstAt = 0, nil :: any
	local trace = {}
	local s = s0
	while s <= s1 do
		for _, side in { -1, 1 } do
			local w = spline:runoffAt(s, side)
			local lw = spline:lipWidthAt(s, side)
			-- the road: drawn ground under the tarmac and bevel
			for d = 0, half + lw, 2 do
				local x, y, z = spline:terrainXYZ(s, side * math.min(d, half + lw))
				local g, tile = self:_drawnAt(x, z)
				if g and tile then
					local k = tostring((tile.leaf :: Leaf).s)
					under[k] = under[k] or {}
					table.insert(under[k], y - g)
				end
			end
			-- the runoff: from the bevel's foot to the edge
			local d = half + lw
			while d <= half + w + 1e-6 do
				local x, y, z = spline:terrainXYZ(s, side * d)
				local g, tile = self:_drawnAt(x, z)
				if g and tile then
					local k = tostring((tile.leaf :: Leaf).s)
					gaps[k] = gaps[k] or {}
					table.insert(gaps[k], g - y)
					if math.abs(g - y) > 0.25 and #trace < 40 then
						local dbg = {}
						local leaf = tile.leaf :: Leaf
						-- the cell's corners, as placed: x, z, height less the runoff's there, class
						local ci, cj = math.floor((x - leaf.x0) / leaf.s), math.floor((z - leaf.z0) / leaf.s)
						local nn = cells() + 1
						for _, o in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
							local kk = (ci + o[1]) * nn + (cj + o[2]) + 1
							if tile.px[kk] then
								table.insert(dbg, string.format("%.1f,%.1f:%.2f/%d", tile.px[kk] - x, tile.pz[kk] - z, tile.heights[kk] - y, tile.cls[kk]))
							end
						end
						table.insert(trace, { math.round((s - along) * 10) / 10, math.round((d - half) * 10) / 10, side, math.round((g - y) * 100) / 100, leaf.s, math.round(w * 10) / 10, table.concat(dbg, " "), math.round(x * 10) / 10, math.round(z * 10) / 10 })
					end
					if math.abs(g - y) > math.abs(worst) then
						worst, worstAt = g - y, { math.round((s - along) * 10) / 10, math.round((d - half) * 10) / 10, side, (tile.leaf :: Leaf).s, math.round(w * 10) / 10 }
					end
				else
					missing += 1
				end
				d += 0.5
			end
			do
				local x, y, z = spline:terrainXYZ(s, side * (half + w + 0.5))
				local g, tile = self:_drawnAt(x, z)
				if g and tile then
					local k = tostring((tile.leaf :: Leaf).s)
					foot[k] = foot[k] or {}
					table.insert(foot[k], g - y)
				end
			end
		end
		s += step or 2
	end
	local out = { on = true, runoffBy = Ground.runoffBy(), from = s0 - along, to = s1 - along, missing = missing, worst = worst, worstAt = worstAt, trace = trace, runoff = {}, belowRoad = {}, edgeFoot = {} }
	for k, l in gaps do
		out.runoff[k] = brief(l)
		local abs = table.create(#l)
		local o1, o2, o3 = 0, 0, 0
		for i, v in l do
			abs[i] = math.abs(v)
			if abs[i] > 0.1 then
				o1 += 1
			end
			if abs[i] > 0.2 then
				o2 += 1
			end
			if abs[i] > 0.3 then
				o3 += 1
			end
		end
		out.runoff[k].abs = brief(abs)
		out.runoff[k].over = { o1, o2, o3 } -- points off by more than 0.1, 0.2, 0.3 studs
	end
	for k, l in under do
		out.belowRoad[k] = brief(l)
	end
	for k, l in foot do
		out.edgeFoot[k] = brief(l)
	end
	return out
end

-- One drawn vertex near (x, z), and how it was placed (T-251): the shown tile's vertex nearest
-- the point, and the same grid point worked out afresh (`Ground.at`, the exact edge, its four
-- neighbours' distances past the edge, which spacings meet there, and where `place` puts it).
function GroundMeshView.DebugVertexAt(self: View, x: number, z: number)
	local tile = self:_tileAt(x, z)
	if not tile or not tile.leaf then
		return { found = false }
	end
	local leaf = tile.leaf :: Leaf
	local s = leaf.s
	local n = cells() + 1
	local i, j = math.round((x - leaf.x0) / s), math.round((z - leaf.z0) / s)
	local k = i * n + j + 1
	local gx, gz = leaf.x0 + i * s, leaf.z0 + j * s
	local margin = 2 * s + 1
	local ctx = Ground.context(self.field, self.spline, gx - margin, gz - margin, gx + margin, gz + margin)
	local L = newLattice(ctx, s)
	local I, J = math.round(gx / s), math.round(gz / s)
	local y, a, e, T = Ground.at(ctx, gx, gz)
	local r = latAt(L, I, J)
	local p = place(L, I, J)
	local lo, hi = GroundTiles.spacingRange(self.shown, gx, gz)
	local uy, us, ud, ue = underAt(ctx, gx, gz)
	return {
		found = true,
		spacing = s,
		grid = { gx, gz },
		shown = { tile.px[k], tile.pz[k], tile.heights[k], tile.cls[k] },
		placedNow = p,
		groundAt = { y, a, e, T },
		lattice = r,
		under = { uy, us, ud, ue },
		neighbours = { latAt(L, I - 1, J)[3], latAt(L, I + 1, J)[3], latAt(L, I, J - 1)[3], latAt(L, I, J + 1)[3] },
		spacings = { lo, hi },
		stale = tile.stale,
	}
end

-- A DRIVE OVER THE RUNOFF (T-251): the car's own model, on the road's own world
-- (`Drift/SplineWorld`, as the car drives it), from `start` at `speed` studs a second, the
-- finger held as `inputs` (`Sim.Keyframe`s), for `seconds`. Every step, each wheel's contact
-- (where its tyre touches, raised by its drawn lift): the ground the car reads there, and the
-- drawn ground under it. What the wheel stands on less what is drawn, so positive is a wheel
-- floating over the drawn ground and negative one sunk into it; by what the wheel is on. And
-- what stopped the car (`SplineWorld` stats). Only where tiles are drawn: put the car there
-- first, and let the ground build round it.
function GroundMeshView.DebugDriveGap(self: View, start: CFrame, speed: number, inputs: { any }, seconds: number)
	local Sim = require(script.Parent.Sim)
	local SplineWorld = require(script.Parent.SplineWorld)
	local Model = require(script.Parent.Model)
	local Suspension = require(script.Parent.Suspension)
	local world = SplineWorld.new(self.spline)
	local runner = Sim.newRunner(start)
	runner.state.velocity = start.LookVector * speed
	local by: { [string]: { number } } = {}
	local spacing: { [string]: number } = {}
	local air, undrawn, steps = 0, 0, 0
	local worst, worstAt = 0, nil :: any
	local path = {}
	local dt = Config.Drift.FixedStep
	local t = 0
	while t < seconds do
		Sim.advance(runner, dt, function(time: number)
			return Sim.inputAt(inputs, time)
		end, world, function(st: any)
			steps += 1
			local cf = Model.cframe(st)
			for i = 1, 4 do
				local at = cf * (Suspension.wheelContact(i) + Vector3.new(0, st.wheelLift[i], 0))
				local hit = world.probe(at)
				if not hit then
					air += 1
					continue
				end
				local g, tile = self:_drawnAt(at.X, at.Z)
				if not g or not tile then
					undrawn += 1
					continue
				end
				local k = hit.surface or "?"
				by[k] = by[k] or {}
				table.insert(by[k], hit.y - g)
				local sk = tostring((tile.leaf :: Leaf).s)
				spacing[sk] = (spacing[sk] or 0) + 1
				if math.abs(hit.y - g) > math.abs(worst) then
					local sa, da = self.spline:project(at.X, at.Z, 200)
					worst, worstAt = hit.y - g, { t = math.round(st.time * 100) / 100, wheel = i, surface = k, s = sa, d = da }
				end
			end
			if steps % 60 == 0 then
				local sa, da = self.spline:project(st.position.X, st.position.Z, 200)
				table.insert(path, { math.round(st.time * 10) / 10, sa and math.round(sa) or false, da and math.round(da * 10) / 10 or false, math.round(Model.speed(st)) })
			end
		end)
		t += dt
	end
	local out = { steps = steps, wheelsInAir = air, wheelsOverNoTile = undrawn, bySpacing = spacing, worst = worst, worstAt = worstAt, path = path, stats = table.clone(world.stats), surfaces = {} }
	for k, l in by do
		local abs = table.create(#l)
		for i, v in l do
			abs[i] = math.abs(v)
		end
		out.surfaces[k] = { signed = brief(l), abs = brief(abs) }
	end
	return out
end

-- The tiles it holds and why, cheaply, for watching the mesh budget while driving (T-273):
-- `DebugState` also checks the seams, about half a second over a long road.
function GroundMeshView.DebugBudget(self: View)
	local count = 0
	for _ in self.shown do
		count += 1
	end
	return {
		shown = count,
		pool = #self.pool,
		free = #self.free,
		cap = self.cap,
		failCap = self.failCap,
		master = self.master ~= nil,
		masterOpaque = self.master ~= nil and self.master.content ~= nil,
		yields = self.yields,
		yielded = self.yielded,
		failed = self.failed,
		-- mesh budget tiles held (T-276: only tiles that keep their own mesh, and a master that is
		-- not opaque), and the copies being made opaque at this moment
		tileUnits = self:_held(),
		inflight = self.inflight,
		opaque = table.clone(self.opaque),
		opaqueOk = opaqueOk(),
		opaqueTiles = opaqueTiles(),
	}
end

-- WHAT IS DRAWN IS WHAT THE TABLES SAY (T-276): up to `count` shown tiles' meshes read back
-- (an opaque part's content opened as a mesh again) and matched to their tables: each drawn
-- vertex, placed by its part, against the nearest vertex the tables have, and each drawn
-- triangle against the tables' triangles. The seams and over-the-road checks
-- (`DebugSeams`) read the tables, so this is what carries them over to what is drawn.
function GroundMeshView.DebugDrawnMatches(self: View, count: number?)
	local C = cells()
	local n = C + 1
	local out = { tiles = 0, opaque = 0, kept = 0, vertices = 0, worstOff = 0, triangles = 0, trianglesMissing = 0, failed = 0, boxOff = 0 }
	for _, tile in self.tiles do
		if out.tiles >= (count or 20) then
			break
		end
		local part = tile.part
		if not part or not tile.leaf then
			continue
		end
		out.tiles += 1
		local mesh: EditableMesh? = tile.em
		local own = false
		if not mesh then
			out.opaque += 1
			local ok, em = pcall(function()
				return AssetService:CreateEditableMeshAsync(part.MeshContent, { FixedSize = true })
			end)
			if not ok or not em then
				out.failed += 1
				continue
			end
			mesh, own = em, true
		else
			out.kept += 1
		end
		local em = mesh :: EditableMesh
		local o = part.Position
		-- the tables' vertices, and their triangles as sorted grid indices
		local want = {}
		for i = 0, C - 1 do
			for j = 0, C - 1 do
				local t1, t2 = cellTriangles(n, i, j, tile.flip[i * C + j + 1])
				for _, t in { t1, t2 } do
					local k = { t[1], t[2], t[3] }
					table.sort(k)
					want[`{k[1]},{k[2]},{k[3]}`] = true
				end
			end
		end
		local function nearest(p: Vector3): (number, number)
			local best, bk = math.huge, 0
			for k = 1, n * n do
				local d = (Vector3.new(tile.px[k], tile.heights[k], tile.pz[k]) - p).Magnitude
				if d < best then
					best, bk = d, k
				end
			end
			return bk, best
		end
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, f in em:GetFaces() do
			local vs = em:GetFaceVertices(f)
			local ks = {}
			for q = 1, 3 do
				local p = em:GetPosition(vs[q]) + o
				lo, hi = lo:Min(p), hi:Max(p)
				local k, d = nearest(p)
				ks[q] = k
				out.vertices += 1
				out.worstOff = math.max(out.worstOff, d)
			end
			table.sort(ks)
			out.triangles += 1
			if not want[`{ks[1]},{ks[2]},{ks[3]}`] then
				out.trianglesMissing += 1
			end
		end
		if own then
			-- an opaque part's box is its mesh's own (it is culled by it)
			local box = hi - lo
			out.boxOff = math.max(out.boxOff, (box - part.Size).Magnitude, ((lo + hi) * 0.5 - o).Magnitude)
			em:Destroy()
		end
		task.wait()
	end
	return out
end

-- The shown tile whose furthest corner is furthest from the flat point (x, z) (the camera),
-- and how far; with the ground's limit from the car (T-281).
function GroundMeshView.DebugFarthest(self: View, x: number, z: number)
	local most, at = 0, nil
	local count = 0
	for _, l in self.shown do
		count += 1
		local d = GroundTiles.farCorner(l.x0, l.z0, l.side, x, z)
		if d > most then
			most, at = d, l
		end
	end
	return {
		farthest = most,
		side = at and at.side,
		shown = count,
		limit = GroundTiles.limit(),
		car = Vector3.new(self.carX, 0, self.carZ),
	}
end

function GroundMeshView.DebugState(self: View)
	local byLevel = {}
	local count = 0
	for _, l in self.shown do
		byLevel[l.s] = (byLevel[l.s] or 0) + 1
		count += 1
	end
	local perTile = cells() * cells() * 2
	local nv = (cells() + 1) ^ 2
	return {
		detail = self.detail,
		detailName = GroundDetail.name(self.detail),
		shown = count,
		bySpacing = byLevel,
		pool = #self.pool,
		free = #self.free,
		cap = self.cap,
		failCap = self.failCap,
		yields = self.yields, -- gave way to the road (T-273)
		yielded = self.yielded,
		trianglesShown = count * perTile,
		trianglesHeld = #self.pool * perTile,
		verticesShown = count * nv,
		verticesHeld = #self.pool * nv,
		along = self.along,
		fineAhead = self:DebugReach(1, 0),
		fineAheadCorridor = self:DebugReach(1, 40),
		mediumAhead = self:DebugReach(2, 40),
		coarseAhead = self:DebugReach(3, 100),
		seams = self:DebugSeams(Config.Spline.Mesh.Near.Ahead), -- (to the whole road only: over 9 600 studs it takes about half a second)
		failed = self.failed,
		running = self.running,
		paused = self.paused,
		ops = self.ops,
		tilesBuilt = self.tilesBuilt,
		rimWrites = self.rimWrites,
		wall = self.wall,
		groundPoints = groundEvals, -- `Ground.at` calls building tiles, every view this session
		runoffBy = Ground.runoffBy(),
		underPoints = underEvals, -- `underAt` calls (T-251), every view this session
		lastMs = self.lastMs,
		worstMs = self.worstMs,
		worstSliceMs = self.worstSliceMs,
		lastSlices = self.lastSlices,
		worstCommitMs = self.worstCommitMs,
		selectMs = self.selectMs,
		totalWorkMs = self.totalWorkMs,
		events = self.events,
		slices = self.slices,
		-- T-276
		held = self:_held(),
		opaque = table.clone(self.opaque),
		opaqueOk = opaqueOk(),
		opaqueTiles = opaqueTiles(),
		idMaps = idMaps,
	}
end

return GroundMeshView
