--!strict
--!native
-- RoadTexture: the tarmac's own texture (T-268, features/road-surface.md), DRAWN IN CODE into
-- one EditableImage every chunk of the spline road shares (`Road/SplineMesh`). Nothing is
-- uploaded: the image is painted here, on each device, from the numbers in
-- `Config.Spline.Tarmac` and the colours and lines in `Config.Road`.
--
-- WHAT IT DRAWS, after the user's concept art (`assets/reference/environment-mood/`): a cool
-- blue-violet grey with soft painterly grain stretched along the road; darker, smoother wheel
-- tracks in each lane and a faint oil strip between them; a dusty, lighter last stud or two
-- at each edge with gravel creeping on; patches of newer and older tarmac; cracks, mostly
-- along the edges; a few long tyre streaks; and the Japanese lines: a solid white edge line
-- just in from each edge, and a centre line (white dashes by default, or solid, or double).
--
-- HOW IT IS MAPPED. U runs across the tarmac (edge to edge), V along the road over
-- `period()` studs, so the texture repeats every `PeriodStuds` and the centre line's dashes
-- (on `MarkInterval`, a whole number of them a period) run on unbroken. Each chunk shifts V
-- by whole periods (`base`) so the numbers stay small and the pattern runs on across chunks.
-- Over that, each tarmac vertex is shaded by smooth noise along the road (`tone`), which
-- does not repeat, so the period does not show as a repeat.
--
-- THE PLAIN BAND. The rest of the road's mesh (the gravel bevels, the skirt, a grove's trees)
-- samples UV (0, 0). The image's first and last `PlainPx` columns are plain `Grass.Shade`
-- grey, as the grass tile's corners are (`Road/GrassTexture`), so those keep the brightness
-- they had: a texture on a MeshPart replaces its material's colour map on every face.
--
-- WHEN. A client starts painting it as soon as this module is first required, a few ms a
-- frame, long before a run needs it; a chunk asking before it is done waits for it.
-- A device that will not make the image draws the tarmac as before (flat, with the dashes).

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local RoadTexture = {}

local image: EditableImage? = nil
local state = "none" -- "none", "making", "done"
local workMs, wallMs, frames = 0, 0, 0

-- Off in config, or in Studio by `workspace.__tarmac_texture = false` (from the next chunk
-- built), to compare with the plain tarmac.
function RoadTexture.enabled(): boolean
	if RunService:IsStudio() then
		local v = workspace:GetAttribute("__tarmac_texture")
		if v == false then
			return false
		end
	end
	return Config.Spline.Tarmac.Enabled
end

-- Studs of road one copy of the texture covers: `PeriodStuds`, rounded to whole dashes.
function RoadTexture.period(): number
	local every = Config.Road.MarkInterval
	return math.max(1, math.round(Config.Spline.Tarmac.PeriodStuds / every)) * every
end

-- The whole periods a chunk shifts its V by, from where it starts.
function RoadTexture.base(s0: number): number
	local p = RoadTexture.period()
	return math.floor(s0 / p) * p
end

-- A tarmac vertex's UV, `d` studs across from the centre line (-half to half), `s` along.
function RoadTexture.uv(s: number, d: number, base: number): Vector2
	local T = Config.Spline.Tarmac
	local half = Config.Road.Width * 0.5
	local inner = T.Width - 2 * T.PlainPx
	local u = (T.PlainPx + math.clamp((d + half) / (2 * half), 0, 1) * inner) / T.Width
	return Vector2.new(u, (s - base) / RoadTexture.period())
end

--------------------------------------------------------------------------------
-- noise: exact integer hashing (bit32), so every device paints the same road
--------------------------------------------------------------------------------

local function hash(a: number, b: number, salt: number): number -- [0, 1)
	local h = bit32.bxor((a * 73856093) % 4294967296, (b * 19349663) % 4294967296, (salt * 83492791) % 4294967296)
	for _ = 1, 2 do
		h = bit32.bxor(h, bit32.lshift(h, 13))
		h = bit32.bxor(h, bit32.rshift(h, 17))
		h = bit32.bxor(h, bit32.lshift(h, 5))
	end
	return (h % 65521) / 65521
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- smooth value noise in -1..1, unbounded (for the vertices' tone)
local function noise1(x: number, salt: number): number
	local i = math.floor(x)
	local t = smooth(x - i)
	local a, b = hash(i, 0, salt), hash(i + 1, 0, salt)
	return (a + (b - a) * t) * 2 - 1
end
local function noise2(x: number, y: number, salt: number): number
	local ix, iy = math.floor(x), math.floor(y)
	local tx, ty = smooth(x - ix), smooth(y - iy)
	local a = hash(ix, iy, salt) + (hash(ix + 1, iy, salt) - hash(ix, iy, salt)) * tx
	local b = hash(ix, iy + 1, salt) + (hash(ix + 1, iy + 1, salt) - hash(ix, iy + 1, salt)) * tx
	return (a + (b - a) * ty) * 2 - 1
end

-- A tarmac vertex's shade (T-268): darker or lighter by up to `Tone` from smooth noise along
-- the road (over `ToneStuds`, and a finer octave that differs lane to lane), a little warmer
-- or cooler by `ToneHue`. Never above 1: the image is painted 1 / (1 - Tone) brighter, so
-- the tarmac averages its colours.
function RoadTexture.tone(s: number, d: number): Color3
	local T = Config.Spline.Tarmac
	local n = noise1(s / T.ToneStuds, 11) * 0.65 + noise2(s / (T.ToneStuds * 0.4), d / 20, 12) * 0.35
	local k = 1 - T.Tone + T.Tone * math.clamp(n, -1, 1)
	local h = T.ToneHue * noise1(s / (T.ToneStuds * 1.7), 13)
	return Color3.new(math.min(1, k * (1 + h)), k, math.min(1, k * (1 - h)))
end

-- Periodic value noise over the tarmac in studs: `cellD` across, `cellT` along, wrapping
-- along every `period` studs so the texture tiles.
type Layer = { nD: number, nT: number, cellD: number, cellT: number, v: { number } }
local function layer(cellD: number, cellT: number, period: number, width: number, salt: number): Layer
	local nT = math.max(1, math.round(period / cellT))
	local nD = math.ceil(width / cellD) + 2
	local v = table.create((nD + 1) * nT)
	for iy = 0, nT - 1 do
		for ix = 0, nD do
			v[iy * (nD + 1) + ix + 1] = hash(ix, iy, salt) * 2 - 1
		end
	end
	return { nD = nD, nT = nT, cellD = cellD, cellT = period / nT, v = v }
end
-- `x` studs from the left edge, `t` studs along (0..period)
local function sample(L: Layer, x: number, t: number): number
	local fx, fy = x / L.cellD, t / L.cellT
	local ix, iy = math.floor(fx), math.floor(fy)
	local tx, ty = smooth(fx - ix), smooth(fy - iy)
	local w = L.nD + 1
	local r0 = (iy % L.nT) * w + ix + 1
	local r1 = ((iy + 1) % L.nT) * w + ix + 1
	local v = L.v
	local a = v[r0] + (v[r0 + 1] - v[r0]) * tx
	local b = v[r1] + (v[r1 + 1] - v[r1]) * tx
	return a + (b - a) * ty
end

--------------------------------------------------------------------------------
-- painting
--------------------------------------------------------------------------------

type Patch = { t0: number, len: number, d0: number, d1: number, c: Color3 }
type Line = { d: number, hw: number, c: Color3, dashed: boolean }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Paint the texture into a pixel buffer, W x H, RGBA. `yield()` is called between rows and
-- hands the frame back when its slice is spent.
function RoadTexture.paint(yield: (() -> ())?): (buffer, number, number)
	local T = Config.Spline.Tarmac
	local R = Config.Road
	local C = R.Colours
	local W, H, P = T.Width, T.Length, T.PlainPx
	local period = RoadTexture.period()
	local width = R.Width
	local half = width * 0.5
	local inner = W - 2 * P
	local pxD = inner / width -- pixels a stud across
	local pxT = H / period -- pixels a stud along
	local px = buffer.create(W * H * 4)
	local lift = 1 / (1 - T.Tone) -- the vertices' tone darkens by Tone on average
	local seed = T.Seed

	-- Park-Miller: exact in doubles, the same on every device
	local rs = (seed * 7919) % 2147483646 + 1
	local function rand(): number
		rs = (rs * 16807) % 2147483647
		return rs / 2147483647
	end
	local function range(r: { number }): number
		return r[1] + (r[2] - r[1]) * rand()
	end

	local mottle = layer(T.MottleStuds, T.MottleStuds * 1.6, period, width, seed + 1)
	local grain = layer(T.GrainStuds[1], T.GrainStuds[2], period, width, seed + 2)
	local wear = layer(1.2, 6, period, width, seed + 3) -- the paint's wear, and the edge's ragged line
	local wobble = layer(1000, T.TrackWobbleStuds, period, width, seed + 4)

	local base = C.Tarmac
	local worn = C.TarmacWorn
	local edge = C.TarmacEdge
	local plain = math.floor(Config.Spline.Grass.Shade * 255 + 0.5)

	-- the patches: rectangles of newer (darker) or older (lighter) tarmac
	local patches: { Patch } = {}
	for i = 1, T.Patches do
		local len, w = range(T.PatchLength), range(T.PatchWidth)
		local dc = (rand() * 2 - 1) * (half - w * 0.5 - 0.5)
		table.insert(patches, {
			t0 = rand() * period,
			len = len,
			d0 = dc - w * 0.5,
			d1 = dc + w * 0.5,
			c = C.TarmacPatch[(i - 1) % #C.TarmacPatch + 1],
		})
	end

	-- the lines: each { centre d, half width, colour, dashed }
	local lines: { Line } = {}
	local ew = R.EdgeLineWidth
	for _, side in { -1, 1 } do
		table.insert(lines, { d = side * (half - R.EdgeLineInset - ew * 0.5), hw = ew * 0.5, c = C.EdgeLine, dashed = false })
	end
	local cw = R.MarkWidth
	if R.CentreLineStyle == "double" then
		for _, side in { -1, 1 } do
			table.insert(lines, { d = side * (R.CentreLineGap + cw) * 0.5, hw = cw * 0.5, c = C.CentreLine, dashed = false })
		end
	elseif R.CentreLineStyle ~= "none" then
		table.insert(lines, { d = 0, hw = cw * 0.5, c = C.CentreLine, dashed = R.CentreLineStyle == "dashed" })
	end
	local interval, dash = R.MarkInterval, R.MarkDashLength

	-- the wheel tracks: each lane's two, `TrackGap` apart about its middle
	local lanes = { -half * 0.5, half * 0.5 }
	local tw = T.TrackWidth * 0.5

	for y = 0, H - 1 do
		local t = (y + 0.5) / pxT
		-- where each lane's tracks are on this row
		local wob1 = sample(wobble, 0, t) * T.TrackWobble
		local wob2 = sample(wobble, 3, t + period * 0.5) * T.TrackWobble
		-- the dashes' coverage along, antialiased
		local inDash = 1
		do
			local into = t % interval
			inDash = math.clamp(math.min(into, dash - into) * pxT + 0.5, 0, 1)
		end
		local row = y * W * 4
		for x = 0, W - 1 do
			local o = row + x * 4
			if x < P or x >= W - P then
				buffer.writeu8(px, o, plain)
				buffer.writeu8(px, o + 1, plain)
				buffer.writeu8(px, o + 2, plain)
				buffer.writeu8(px, o + 3, 255)
				continue
			end
			local xs = (x + 0.5 - P) / pxD -- studs from the left edge
			local d = xs - half
			local e = half - math.abs(d) -- studs to the nearer edge
			local r, g, b = base.R, base.G, base.B

			-- the wheel tracks and the oil strip between them
			local track, oil = 0, 0
			for li = 1, 2 do
				local c = lanes[li] + (if li == 1 then wob1 else wob2)
				local u = d - c
				local a1 = (u - T.TrackGap * 0.5) / tw
				local a2 = (u + T.TrackGap * 0.5) / tw
				track = math.max(track, math.exp(-a1 * a1), math.exp(-a2 * a2))
				local a3 = u / T.OilWidth
				oil = math.max(oil, math.exp(-a3 * a3))
			end
			local tk = track * T.TrackDark + oil * T.OilDark
			r, g, b = lerp(r, worn.R, tk), lerp(g, worn.G, tk), lerp(b, worn.B, tk)

			-- the dusty edge, its inner line ragged
			local wn = sample(wear, xs, t)
			local ed = math.clamp(1 - e / T.EdgeWear + wn * 0.35, 0, 1)
			ed = ed * ed
			r, g, b = lerp(r, edge.R, ed), lerp(g, edge.G, ed), lerp(b, edge.B, ed)

			-- patches
			local inPatch = false
			for _, p in patches do
				local dt = (t - p.t0) % period
				if dt < p.len and d > p.d0 and d < p.d1 then
					inPatch = true
					-- a darker seam round it
					local seam = math.min(dt, p.len - dt, d - p.d0, p.d1 - d)
					local k = if seam < T.PatchSeam then 0.8 else 1
					r, g, b = lerp(r, p.c.R * k, 0.85), lerp(g, p.c.G * k, 0.85), lerp(b, p.c.B * k, 0.85)
					break
				end
			end

			-- grain: painterly, stretched along; smoother in the polished tracks and patches
			local smoothK = 1 - track * 0.6 - (if inPatch then 0.4 else 0)
			local k = 1 + sample(mottle, xs, t) * T.Mottle + sample(grain, xs, t) * T.Grain * smoothK + (rand() * 2 - 1) * T.Speckle

			-- gravel specks on the dusty edge
			if ed > 0.05 and rand() < T.Gravel * ed then
				local v = if rand() < 0.5 then T.GravelLight else T.GravelDark
				r, g, b = r * v, g * v, b * v
			end

			-- the painted lines, worn where the noise says
			for _, ln in lines do
				local cov = math.clamp((ln.hw - math.abs(d - ln.d)) * pxD + 0.5, 0, 1)
				if cov > 0 then
					if ln.dashed then
						cov *= inDash
					end
					local a = cov * math.clamp(1 - T.LineWear * math.max(0, wn + 0.3), 0, 1)
					r, g, b = lerp(r, ln.c.R, a), lerp(g, ln.c.G, a), lerp(b, ln.c.B, a)
					k = lerp(k, 1 + (k - 1) * 0.4, a)
				end
			end

			local m = k * lift * 255
			buffer.writeu8(px, o, math.clamp(math.floor(r * m + 0.5), 0, 255))
			buffer.writeu8(px, o + 1, math.clamp(math.floor(g * m + 0.5), 0, 255))
			buffer.writeu8(px, o + 2, math.clamp(math.floor(b * m + 0.5), 0, 255))
			buffer.writeu8(px, o + 3, 255)
		end
		if yield then
			yield()
		end
	end

	-- STROKES on top: blend a pixel toward a colour by `a`
	local function blend(x: number, y: number, c: Color3, a: number)
		if x < P or x >= W - P then
			return
		end
		y %= H
		local o = (y * W + x) * 4
		local m = lift * 255
		buffer.writeu8(px, o, math.floor(lerp(buffer.readu8(px, o), c.R * m, a) + 0.5))
		buffer.writeu8(px, o + 1, math.floor(lerp(buffer.readu8(px, o + 1), c.G * m, a) + 0.5))
		buffer.writeu8(px, o + 2, math.floor(lerp(buffer.readu8(px, o + 2), c.B * m, a) + 0.5))
	end
	local function toX(d: number): number
		return math.floor(P + (d + half) * pxD)
	end

	-- CRACKS: a random walk a step at a time, mostly along the road near an edge, some across;
	-- each pixel darkened once per crack, with a branch now and then
	local crack = C.Crack
	local function walk(d: number, t: number, heading: number, len: number, a: number, depth: number)
		local seen = {}
		local step = 0.2
		for _ = 1, math.floor(len / step) do
			heading += (rand() * 2 - 1) * 0.35
			d += math.sin(heading) * step
			t += math.cos(heading) * step
			if math.abs(d) > half - 0.2 then
				break
			end
			local x, y = toX(d), math.floor((t % period) * pxT)
			local key = y * W + x
			if not seen[key] then
				seen[key] = true
				blend(x, y, crack, a)
			end
			if depth < 1 and rand() < 0.02 then
				walk(d, t, heading + (if rand() < 0.5 then 1 else -1) * (0.8 + rand() * 0.5), 1 + rand() * 3, a * 0.8, depth + 1)
			end
		end
	end
	for _ = 1, T.Cracks do
		local side = if rand() < 0.5 then -1 else 1
		if rand() < T.CrackAcross then
			-- across: in from an edge, over part of a lane
			walk(side * (half - 0.5), rand() * period, -side * (math.pi * 0.5) + (rand() - 0.5) * 0.6, range(T.CrackLength) * 0.5, T.CrackDark, 0)
		else
			-- along, near the edge
			local heading = (rand() - 0.5) * 0.2 + (if rand() < 0.5 then 0 else math.pi)
			walk(side * (half - range(T.CrackEdge)), rand() * period, heading, range(T.CrackLength), T.CrackDark, 0)
		end
	end
	if yield then
		yield()
	end

	-- TYRE STREAKS: a pair of long arcs through a lane, a car's two rear tyres, darkest in
	-- the middle and fading at both ends, rasterised a row at a time
	local rubber = C.TyreStreak
	local sw = T.StreakWidth * 0.5 * pxD
	for _ = 1, T.Streaks do
		local lane = lanes[if rand() < 0.5 then 1 else 2]
		local t0, len = rand() * period, range(T.StreakLength)
		local amp = (rand() * 2 - 1) * T.StreakSwing
		local dark = T.StreakDark * (0.6 + rand() * 0.4)
		local rows = math.floor(len * pxT)
		for i = 0, rows do
			local u = i / rows
			local dMid = lane + amp * (math.sin(math.pi * u) - 0.5)
			local a = dark * math.sin(math.pi * u) ^ 0.7
			local y = math.floor(t0 * pxT) + i
			for _, off in { -T.TrackGap * 0.5, T.TrackGap * 0.5 } do
				local cx = P + (dMid + off + half) * pxD
				for x = math.floor(cx - sw), math.ceil(cx + sw) do
					local cov = math.clamp(sw + 0.5 - math.abs(x + 0.5 - cx), 0, 1)
					if cov > 0 then
						blend(x, y, rubber, a * cov)
					end
				end
			end
		end
	end
	return px, W, H
end

-- The shared image, painted the first time it is asked for (a client starts it on require,
-- below). It yields: a few ms a frame (`SliceMs`). nil when it is off, or when this device
-- will not make an EditableImage.
function RoadTexture.get(): EditableImage?
	if not RoadTexture.enabled() then
		return nil
	end
	while state == "making" do
		task.wait()
	end
	if state == "done" then
		return image
	end
	state = "making"
	local T = Config.Spline.Tarmac
	local t0 = os.clock()
	local budget = T.SliceMs / 1000
	local sliceStart = t0
	local paused = 0
	frames = 1
	local ok, made = pcall(function()
		local px, W, H = RoadTexture.paint(function()
			if os.clock() - sliceStart >= budget then
				local now = os.clock()
				task.wait()
				sliceStart = os.clock()
				paused += sliceStart - now
				frames += 1
			end
		end)
		local img = AssetService:CreateEditableImage({ Size = Vector2.new(W, H) })
		assert(img, "this device would not make an EditableImage")
		img:WritePixelsBuffer(Vector2.zero, img.Size, px)
		return img
	end)
	wallMs = (os.clock() - t0) * 1000
	workMs = wallMs - paused * 1000
	if ok then
		image = made
	else
		warn(`[RoadTexture] no tarmac texture on this device, the tarmac is drawn flat: {made}`)
	end
	state = "done"
	return image
end

-- Start painting now, in the background (a client, as soon as the road's code loads).
function RoadTexture.prepare()
	if state == "none" and RoadTexture.enabled() then
		task.spawn(RoadTexture.get)
	end
end

function RoadTexture.DebugState()
	return {
		made = image ~= nil,
		state = state,
		workMs = workMs, -- painting, without the frames it waited
		wallMs = wallMs,
		frames = frames,
		width = if image then image.Size.X else 0,
		height = if image then image.Size.Y else 0,
		period = RoadTexture.period(),
	}
end

if RunService:IsClient() then
	task.defer(RoadTexture.prepare)
end

return RoadTexture
