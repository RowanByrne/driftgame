--!strict
--!native
-- RoadTexture: the tarmac's own texture (T-268, features/road-surface.md), DRAWN IN CODE from
-- the numbers in `Config.Spline.Tarmac` and the colours and lines in `Config.Road`, and
-- shared by every chunk of the spline road (`Road/SplineMesh`).
--
-- UPLOADED SINCE T-274: an EditableImage of 1 024 x 1 024 holds 32 tiles of the client's
-- mesh memory (`Config.Spline.Mesh.Budget`), so the painted pixels were exported exactly as
-- painted and uploaded (`assets/road/`, `Tarmac.Image`): an uploaded image costs none of it.
-- A device that cannot load it paints the image here as before, and hands it on as opaque
-- content, which costs none of it either (`get`). `Tarmac.ImageHash` is the painted pixels'
-- sum (`pixelHash`): change anything the painting reads and `SplineMeshTests` says the
-- upload no longer matches, so it is exported and uploaded again (`assets/road/MANIFEST.md`).
--
-- WHAT IT DRAWS, after the user's concept art (`assets/reference/environment-mood/`): a cool
-- blue-violet grey with soft painterly grain stretched along the road and a finer aggregate;
-- a dusty, lighter last stud or two at each edge with gravel creeping on; faint ragged
-- patches of newer tarmac; thin cracks, mostly along the edges; and the touge's two white
-- edge lines, faded, worn through and cracked. Nothing down the middle, and no tyre marks
-- (the user's send-backs: "tyre marks are ugly", "get rid of the dashes - it's not
-- realistic"). Wheel tracks can still be painted (`TrackDark`), but are off.
--
-- THE DOUBLE YELLOW of the tight stretches (`centreRuns`) is not in the tarmac's pixels:
-- the texture repeats along the road, and the line must start and stop at the bends. It is
-- two thin strips of the road's mesh (`Road/SplineMesh`), mapped to the image's LINE BAND:
-- columns right of the tarmac holding one weathered yellow line on tarmac (`lineUV`).
--
-- THE GRAVEL (T-270) has a band of its own, right of the line band: softly painted stones
-- on a dusty bed with the asphalt's grain, in the asphalt's colours, blending into the tarmac's
-- edge at one side and grass at the other (`paintGravel`, `gravelUV`). The bevels and the gravel runoff's strips are mapped to it.
--
-- HOW LARGE: 1 024 x 1 024, the largest EditableImage a client will make (measured: 2 048
-- on either side is refused), 4 MB. Painting it is a few hundred ms of work, spread a few ms
-- a frame over many frames.
--
-- HOW IT IS MAPPED. U runs across the tarmac (edge to edge), V along the road over
-- `period()` studs, so the texture repeats every `PeriodStuds`. Each chunk shifts V
-- by whole periods (`base`) so the numbers stay small and the pattern runs on across chunks.
-- Over that, each tarmac vertex is shaded by smooth noise along the road (`tone`), which
-- does not repeat, so the period does not show as a repeat.
--
-- THE PLAIN BAND. The rest of the road's mesh (the gravel bevels, the skirt, a grove's trees)
-- samples UV (0, 0). The image's first and last `PlainPx` columns are plain `Grass.Shade`
-- grey, as the grass tile's corners are (`Road/GrassTexture`), so those keep the brightness
-- they had: a texture on a MeshPart replaces its material's colour map on every face.
--
-- WHEN. A client starts loading the uploaded image as soon as this module is first required,
-- long before a run needs it; a chunk asking before it is ready waits for it. Painting it
-- instead (the fallback) is a few hundred ms of work, a few ms a frame. A device that can
-- neither load nor paint it draws the tarmac as before (flat, with the dashes).

local AssetService = game:GetService("AssetService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local RoadTexture = {}

local texture: Content? = nil
-- the painted fallback's EditableImage, kept only when it could not be made opaque (32 tiles)
local paintedImage: EditableImage? = nil
local source = "none" -- "uploaded", "painted" (opaque), "painted image" (an EditableImage), "none"
local state = "none" -- "none", "making", "done"
local workMs, wallMs, frames = 0, 0, 0
local loadMs = 0
local fetchStatus = "" -- the uploaded image's, as `ContentProvider` reported it

-- Off in config, or in Studio by `workspace.__tarmac_texture = false` (from the next chunk
-- built), to compare with the plain tarmac. (`workspace.__tarmac_painted = true`, set before
-- the first chunk is drawn: the painted image, not the uploaded one, to compare the two.)
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

-- The image's columns, left to right: `PlainPx` plain, the tarmac, the line band
-- (`LineBandPx`), the gravel band (`Gravel.BandPx`, T-270), `PlainPx` plain. Returns the
-- plain width, the tarmac's width, where the line band starts and its width, and where the
-- gravel band starts and its width.
local function columns(): (number, number, number, number, number, number)
	local T = Config.Spline.Tarmac
	local P, Y, G = T.PlainPx, T.LineBandPx, Config.Spline.Gravel.BandPx
	local inner = T.Width - 2 * P - Y - G
	return P, inner, P + inner, Y, P + inner + Y, G
end

-- A tarmac vertex's UV, `d` studs across from the centre line (-half to half), `s` along.
function RoadTexture.uv(s: number, d: number, base: number): Vector2
	local T = Config.Spline.Tarmac
	local half = Config.Road.Width * 0.5
	local P, inner = columns()
	local u = (P + math.clamp((d + half) / (2 * half), 0, 1) * inner) / T.Width
	return Vector2.new(u, (s - base) / RoadTexture.period())
end

-- A centre line strip's vertex UV (send-back 2): `side` 0 for the strip's left edge, 1 for
-- its right, across the image's line band (inset `LineInsetPx` from the band's sides, so
-- nothing next to it bleeds in); line `which` 2 reads half a period on from line 1, so the
-- double line's two halves never wear alike.
function RoadTexture.lineUV(s: number, side: number, base: number, which: number): Vector2
	local T = Config.Spline.Tarmac
	local _, _, x0, Y = columns()
	local inset = T.LineInsetPx
	local u = (x0 + inset + side * (Y - 2 * inset)) / T.Width
	return Vector2.new(u, (s - base) / RoadTexture.period() + (if which == 2 then 0.5 else 0))
end

-- THE GRAVEL (T-270): the bevel at each edge of the tarmac, and the narrow gravel runoff of
-- a tight cliff edge, are mapped to the image's GRAVEL BAND: `Gravel.BandStuds` of gravel
-- across (from the tarmac's edge, where it blends in with the tarmac's dusty edge, out to
-- grass creeping in over its last `GrassFrom` on), repeating every `Gravel.PeriodStuds`
-- along (much shorter than the tarmac's, for the pixels: loose stones have no pattern to see
-- repeat). `e`: studs across the band. The right side reads half a period on from the left.
-- Off in config, or in Studio by `workspace.__gravel_texture = false` (from the next chunk
-- built): the bevels sample the plain band again and no runoff strips are laid.
function RoadTexture.gravelEnabled(): boolean
	if RunService:IsStudio() and workspace:GetAttribute("__gravel_texture") == false then
		return false
	end
	return Config.Spline.Gravel.Enabled
end

function RoadTexture.gravelPeriod(): number
	return Config.Spline.Gravel.PeriodStuds
end

function RoadTexture.gravelBase(s0: number): number
	local p = RoadTexture.gravelPeriod()
	return math.floor(s0 / p) * p
end

function RoadTexture.gravelUV(s: number, e: number, base: number, side: number): Vector2
	local T = Config.Spline.Tarmac
	local Gv = Config.Spline.Gravel
	local _, _, _, _, gx0, G = columns()
	local inset = Gv.InsetPx
	local u = (gx0 + inset + math.clamp(e / Gv.BandStuds, 0, 1) * (G - 2 * inset)) / T.Width
	return Vector2.new(u, (s - base) / RoadTexture.gravelPeriod() + (if side > 0 then 0.5 else 0))
end

-- THE DOUBLE YELLOW'S STRETCHES (send-back 2: "the double yellow lines that touge has for
-- dangerous 2 lane sections, like switchbacks"): wherever the road is tighter than
-- `CentreLineRadius`, and `CentreLineLead` studs either side of that (a lead-in before the
-- bend and a run-out after it), with a gap shorter than `CentreLineMerge` closed, so a
-- switchback's two bends get one line. Read off the curve on a fixed grid of
-- `CentreLineStep` studs along the whole road, looking `Lead + Merge` past each end, so a
-- chunk anywhere, near or far, finds exactly the same runs, starting and ending on the same
-- grid points. Returns { a1, b1, a2, b2, ... } clipped to [s0, s1].
function RoadTexture.centreRuns(spline: any, s0: number, s1: number): { number }
	local R = Config.Road
	if R.CentreLineStyle ~= "tight" then
		return {}
	end
	local step = R.CentreLineStep
	local kMin = 1 / R.CentreLineRadius
	local nLead = math.round(R.CentreLineLead / step)
	local nMerge = math.round(R.CentreLineMerge / step)
	local i0 = math.floor(s0 / step) - nLead - nMerge - 1
	local i1 = math.ceil(s1 / step) + nLead + nMerge + 1
	local length = spline.length
	local tight = {}
	for i = i0, i1 do
		local s = i * step
		tight[i] = s >= 0 and s <= length and math.abs(spline:curvatureAt(s)) >= kMin
	end
	-- the lead-in and run-out: on wherever a tight point is within `Lead`
	local on = {}
	local lastTight = -math.huge
	for i = i0, i1 do -- forward: a tight point behind, within Lead
		if tight[i] then
			lastTight = i
		end
		on[i] = i - lastTight <= nLead
	end
	local nextTight = math.huge
	for i = i1, i0, -1 do -- backward: one ahead
		if tight[i] then
			nextTight = i
		end
		on[i] = on[i] or nextTight - i <= nLead
	end
	-- close the short gaps (only those with both ends seen)
	local i = i0
	while i <= i1 do
		if on[i] then
			i += 1
		else
			local j = i
			while j <= i1 and not on[j] do
				j += 1
			end
			if i > i0 and j <= i1 and j - i < nMerge then
				for k = i, j - 1 do
					on[k] = true
				end
			end
			i = j
		end
	end
	-- the runs, clipped to the chunk
	local out = {}
	local start: number? = nil
	for k = i0, i1 + 1 do
		local v = k <= i1 and on[k]
		if v and not start then
			start = k
		elseif not v and start then
			local a, b = math.max(start * step, s0), math.min((k - 1) * step, s1)
			if b > a then
				table.insert(out, a)
				table.insert(out, b)
			end
			start = nil
		end
	end
	return out
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

-- A tarmac vertex's shade (T-268): darker or lighter by up to `Tone` from smooth noise along
-- the road (over `ToneStuds`, and an octave half that), a little warmer or cooler by
-- `ToneHue`. Never above 1: the image is painted 1 / (1 - Tone) brighter, so the tarmac
-- averages its colours. ALONG ONLY, AND SLOW, on purpose: a chunk drawn coarse far ahead
-- (T-263: one strip across, cuts up to 96 studs apart) has only its edges' vertices, so a
-- tone that differed across the road or changed faster would jump when the chunk is drawn
-- again whole as the car nears it. (`_d` is unused, kept so callers need not change.)
function RoadTexture.tone(s: number, _d: number): Color3
	local T = Config.Spline.Tarmac
	local n = noise1(s / T.ToneStuds, 11) * 0.75 + noise1(s / (T.ToneStuds * 0.5), 12) * 0.25
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
	ix %= L.nD -- across too, so a read past the width (an offset copy of a layer) wraps
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
type Line = { d: number, hw: number, c: Color3, salt: number }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Paint the texture into a pixel buffer, W x H, RGBA. `yield()` is called between rows and
-- hands the frame back when its slice is spent.
function RoadTexture.paint(yield: (() -> ())?): (buffer, number, number)
	local T = Config.Spline.Tarmac
	local R = Config.Road
	local C = R.Colours
	local W, H = T.Width, T.Length
	local P, inner, bx0, Y, gx0 = columns()
	local period = RoadTexture.period()
	local width = R.Width
	local half = width * 0.5
	local pxD = inner / width -- pixels a stud across the tarmac
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
	-- the aggregate: a finer octave of the grain, what the higher resolution is for (T-268)
	local fine = layer(T.FineStuds[1], T.FineStuds[2], period, width, seed + 5)
	local wear = layer(1.2, 6, period, width, seed + 3) -- the paint's wear, and the edge's ragged line
	local wobble = layer(1000, T.TrackWobbleStuds, period, width, seed + 4)
	-- the paint's weathering (send-back 2): a fade that drifts along each line, and holes where
	-- it has worn through to the tarmac
	local lineFade = layer(1000, T.LineFadeStuds, period, width, seed + 6)
	local holes = layer(T.LineHoleStuds[1], T.LineHoleStuds[2], period, width, seed + 7)

	local base = C.Tarmac
	local worn = C.TarmacWorn
	local edge = C.TarmacEdge
	local plain = math.floor(Config.Spline.Grass.Shade * 255 + 0.5)

	-- the patches: rectangles of newer tarmac, ragged and feathered
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

	-- THE PAINTED LINES ON THE TARMAC: the two edge lines, the touge's classic design, and
	-- nothing down the middle (send-back 2: "get rid of the dashes - it's not realistic").
	-- The double yellow centre line of the tight stretches is its own strips in the mesh,
	-- painted from the image's line band (below)
	local lines: { Line } = {}
	local ew = R.EdgeLineWidth
	for i, side in { -1, 1 } do
		table.insert(lines, { d = side * (half - R.EdgeLineInset - ew * 0.5), hw = ew * 0.5, c = C.EdgeLine, salt = i * 3 })
	end
	-- how much of a line's paint is left at (studs across `xs`, along `t`): worn by the wear
	-- noise and the fine grain, and gone where a hole has worn through
	local function weather(xs: number, t: number): number
		local hole = math.clamp((sample(holes, xs, t) - T.LineHoles) / 0.12, 0, 1)
		local wn = sample(wear, xs, t)
		local fn = sample(fine, xs + 5, t)
		return (1 - hole) * math.clamp(1 - T.LineWear * math.max(0, wn + 0.3) - T.LineGrain * math.max(0, fn), 0, 1)
	end
	local function fadeAt(salt: number, t: number): number
		return lerp(T.LineFade[1], T.LineFade[2], (sample(lineFade, salt, t) + 1) * 0.5)
	end

	-- the centre line's band: one yellow line, `CentreLineWidth` studs across `Y - 2 x inset`
	-- pixels, on the tarmac it is painted on (its worn-through paint shows that)
	local yellow = C.CentreLine
	local inset = T.LineInsetPx
	local lineW = R.CentreLineWidth
	local pxB = (Y - 2 * inset) / lineW

	-- the wheel tracks: each lane's two, `TrackGap` apart about its middle (off, `TrackDark` 0)
	local lanes = { -half * 0.5, half * 0.5 }
	local tw = T.TrackWidth * 0.5

	for y = 0, H - 1 do
		local t = (y + 0.5) / pxT
		-- where each lane's tracks are on this row
		local wob1 = sample(wobble, 0, t) * T.TrackWobble
		local wob2 = sample(wobble, 3, t + period * 0.5) * T.TrackWobble
		local fades = { fadeAt(lines[1].salt, t), fadeAt(lines[2].salt, t) }
		local fadeY = fadeAt(9, t)
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
			if x >= gx0 then
				continue -- the gravel band, painted after (`paintGravel`)
			end
			if x >= bx0 then
				-- THE LINE BAND: tarmac with the yellow over it, chipped at its sides, faded
				-- along, worn through in places
				local ub = (x + 0.5 - bx0 - inset) / pxB -- studs across the line
				local xs = ub + 10 -- where its noise is read (any place on the tarmac's)
				local k = 1 + sample(mottle, xs, t) * T.Mottle + sample(grain, xs, t) * T.Grain + sample(fine, xs, t) * T.Fine + (rand() * 2 - 1) * T.Speckle
				local cov = math.clamp(math.min(ub, lineW - ub) * pxB + 0.5 + sample(fine, xs + 20, t) * T.LineChip * pxB, 0, 1)
				local a = cov * fadeY * weather(xs, t)
				local r, g, b = lerp(base.R, yellow.R, a), lerp(base.G, yellow.G, a), lerp(base.B, yellow.B, a)
				k = lerp(k, 1 + (k - 1) * 0.4, a)
				local m = k * lift * 255
				buffer.writeu8(px, o, math.clamp(math.floor(r * m + 0.5), 0, 255))
				buffer.writeu8(px, o + 1, math.clamp(math.floor(g * m + 0.5), 0, 255))
				buffer.writeu8(px, o + 2, math.clamp(math.floor(b * m + 0.5), 0, 255))
				buffer.writeu8(px, o + 3, 255)
				continue
			end
			local xs = (x + 0.5 - P) / pxD -- studs from the left edge
			local d = xs - half
			local e = half - math.abs(d) -- studs to the nearer edge
			local r, g, b = base.R, base.G, base.B

			-- the wheel tracks and the oil strip between them
			local track, oil = 0, 0
			if T.TrackDark > 0 or T.OilDark > 0 then
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
			end

			-- the dusty edge, its inner line ragged
			local wn = sample(wear, xs, t)
			local ed = math.clamp(1 - e / T.EdgeWear + wn * 0.35, 0, 1)
			ed = ed * ed
			r, g, b = lerp(r, edge.R, ed), lerp(g, edge.G, ed), lerp(b, edge.B, ed)

			-- patches: a ragged edge (the wear noise moves it up to `PatchRagged` studs), a faint
			-- darker seam just inside it, and `PatchBlend` of the way to the patch's colour,
			-- feathered over `PatchSoft` studs (send-back: hard flat rectangles read as panels)
			local inPatch = false
			for _, p in patches do
				local dt = (t - p.t0) % period
				local seam = math.min(dt, p.len - dt, d - p.d0, p.d1 - d) + wn * T.PatchRagged
				if seam > 0 then
					inPatch = true
					local k = if seam < T.PatchSeam then 0.92 else 1
					local a = T.PatchBlend * math.clamp(seam / T.PatchSoft, 0, 1)
					r, g, b = lerp(r * k, p.c.R, a), lerp(g * k, p.c.G, a), lerp(b * k, p.c.B, a)
					break
				end
			end

			-- grain: painterly, stretched along; smoother in the polished tracks and patches
			local smoothK = 1 - track * T.TrackSmooth - (if inPatch then 0.4 else 0)
			local k = 1 + sample(mottle, xs, t) * T.Mottle + (sample(grain, xs, t) * T.Grain + sample(fine, xs, t) * T.Fine) * smoothK + (rand() * 2 - 1) * T.Speckle * smoothK

			-- gravel specks on the dusty edge
			if ed > 0.05 and rand() < T.Gravel * ed then
				local v = if rand() < 0.5 then T.GravelLight else T.GravelDark
				r, g, b = r * v, g * v, b * v
			end

			-- the edge lines: chipped sides, a fade drifting along each, worn through in places
			for li, ln in lines do
				local hw = ln.hw + sample(fine, xs + 7, t) * T.LineChip
				local cov = math.clamp((hw - math.abs(d - ln.d)) * pxD + 0.5, 0, 1)
				if cov > 0 then
					local a = cov * fades[li] * weather(xs, t)
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

	-- STROKES on top: blend a pixel toward a colour by `a`, within columns [lo, hi)
	local function blend(x: number, y: number, c: Color3, a: number, lo: number, hi: number)
		if x < lo or x >= hi then
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
		local step = 0.5 / pxT -- half a pixel along, so a crack never skips a row
		local rx, ry = math.max(0, math.floor(T.CrackWidth * 0.5 * pxD)), math.max(0, math.floor(T.CrackWidth * 0.5 * pxT))
		-- the wander and the branching per stud, whatever the step (they were tuned at 0.2)
		local jitter, branch = 0.35 * math.sqrt(step / 0.2), 0.02 * step / 0.2
		for _ = 1, math.floor(len / step) do
			heading += (rand() * 2 - 1) * jitter
			d += math.sin(heading) * step
			t += math.cos(heading) * step
			if math.abs(d) > half - 0.2 then
				break
			end
			local cx, cy = toX(d), math.floor((t % period) * pxT)
			-- `CrackWidth` studs wide, each pixel darkened once per crack
			for y = cy - ry, cy + ry do
				for x = cx - rx, cx + rx do
					local key = (y % H) * W + x
					if not seen[key] then
						seen[key] = true
						blend(x, y, crack, a, P, bx0)
					end
				end
			end
			if depth < 1 and rand() < branch then
				walk(d, t, heading + (if rand() < 0.5 then 1 else -1) * (0.8 + rand() * 0.5), 1 + rand() * 3, a * 0.8, depth + 1)
			end
		end
	end
	for _ = 1, T.Cracks do
		local side = if rand() < 0.5 then -1 else 1
		if rand() < T.CrackAcross then
			-- across: a short one in from an edge
			walk(side * (half - 0.5), rand() * period, -side * (math.pi * 0.5) + (rand() - 0.5) * 0.6, range(T.CrackLength) * 0.25, T.CrackDark, 0)
		else
			-- along, near the edge
			local heading = (rand() - 0.5) * 0.2 + (if rand() < 0.5 then 0 else math.pi)
			walk(side * (half - range(T.CrackEdge)), rand() * period, heading, range(T.CrackLength), T.CrackDark, 0)
		end
	end
	-- cracks across the edge lines, breaking them: short, nearly square to the line
	for _, ln in lines do
		for _ = 1, T.LineCracks do
			walk(ln.d - ln.hw - 0.3, rand() * period, math.pi * 0.5 + (rand() - 0.5) * 0.5, ln.hw * 2 + 0.6, T.CrackDark * (0.7 + rand() * 0.3), 1)
		end
	end
	-- and across the yellow line's band: a pixel row each, wandering a row up or down
	for _ = 1, T.LineCracks do
		local yy = math.floor(rand() * H)
		local a = T.CrackDark * (0.7 + rand() * 0.3)
		for x = bx0, bx0 + Y - 1 do
			if rand() < 0.15 then
				yy += if rand() < 0.5 then -1 else 1
			end
			blend(x, yy, crack, a, bx0, bx0 + Y)
		end
	end
	if yield then
		yield()
	end
	RoadTexture.paintGravel(px, yield)
	return px, W, H
end

-- THE GRAVEL BAND (T-270, the user: "do the same for the gravel on the sides of the road"),
-- into `px`. Three send-backs set it: thousands of tiny faceted stones with per-pixel grain
-- were "too noisy and static-y", flat values and cel-shaded pebbles "too cartoony", and of
-- three looks between them the user picked B (2026-11-16). So it is painted like the
-- approved asphalt: a dusty bed with the asphalt's kind of grain (soft mottling, strokes
-- stretched along, a finer octave; no per-pixel speckle), and a medium density of stones with
-- soft painted shading (no outlines, no cel steps, soft edges a few pixels wide, a faint soft
-- shadow), in the asphalt's own hue and value range ("keep the coloration generally of the
-- road"). Its edges: the tarmac's dusty edge colour taking over in soft ragged shapes at its
-- start, grass in soft shapes over its end. Its own random numbers, so the tarmac's are as
-- they were.
function RoadTexture.paintGravel(px: buffer, yield: (() -> ())?)
	local T = Config.Spline.Tarmac
	local Gv = Config.Spline.Gravel
	local L = Gv -- its look's numbers (look B of three, the user's pick)
	local C = Config.Road.Colours
	local W, H = T.Width, T.Length
	local _, _, _, _, gx0, G = columns()
	local inset = Gv.InsetPx
	local B = Gv.BandStuds
	local period = RoadTexture.gravelPeriod()
	local pxA = (G - 2 * inset) / B -- pixels a stud across the band
	local pxL = H / period -- and along
	local lift = 1 / (1 - T.Tone)
	local rs = (Gv.Seed * 7919) % 2147483646 + 1
	local function rand(): number
		rs = (rs * 16807) % 2147483647
		return rs / 2147483647
	end
	local function range(r: { number }): number
		return r[1] + (r[2] - r[1]) * rand()
	end
	local function smoothstep(a: number, b: number, x: number): number
		local t = math.clamp((x - a) / (b - a), 0, 1)
		return t * t * (3 - 2 * t)
	end
	local width = B + 2 * inset / pxA + 2
	local mottle = layer(L.MottleStuds[1], L.MottleStuds[2], period, width, Gv.Seed + 1)
	local grain = layer(L.GrainStuds[1], L.GrainStuds[2], period, width, Gv.Seed + 2)
	local fine = layer(L.FineStuds[1], L.FineStuds[2], period, width, Gv.Seed + 4)
	local edgeN = layer(Gv.EdgeStuds[1], Gv.EdgeStuds[2], period, width, Gv.Seed + 3)
	local function across(x: number): number
		return (x + 0.5 - gx0 - inset) / pxA
	end
	local m255 = lift * 255
	local function put(x: number, y: number, r: number, g: number, b: number)
		local o = (y * W + x) * 4
		buffer.writeu8(px, o, math.clamp(math.floor(r * m255 + 0.5), 0, 255))
		buffer.writeu8(px, o + 1, math.clamp(math.floor(g * m255 + 0.5), 0, 255))
		buffer.writeu8(px, o + 2, math.clamp(math.floor(b * m255 + 0.5), 0, 255))
		buffer.writeu8(px, o + 3, 255)
	end
	local function get(x: number, y: number): (number, number, number)
		local o = (y * W + x) * 4
		return buffer.readu8(px, o) / m255, buffer.readu8(px, o + 1) / m255, buffer.readu8(px, o + 2) / m255
	end

	-- THE BED: the dust, with the asphalt's kind of grain
	local dust, dark, light = C.GravelDust, C.GravelDark, C.GravelLight
	for y = 0, H - 1 do
		local t = (y + 0.5) / pxL
		for x = gx0, gx0 + G - 1 do
			local ua = math.max(0, across(x) + 1)
			local k = 1 + sample(mottle, ua, t) * L.Mottle + sample(grain, ua, t) * L.Grain + sample(fine, ua, t) * L.Fine
			put(x, y, dust.R * k, dust.G * k, dust.B * k)
		end
		if yield and y % 64 == 63 then
			yield()
		end
	end

	-- THE STONES: each an ellipse with a soft edge `SoftPx` pixels wide, its tone a little
	-- toward `GravelLight` or `GravelDark` (up to `Contrast`), shaded softly across by where it
	-- faces the light (`Lit`), over a faint soft shadow (`ShadowDark`) away from the light.
	-- With `Gap`, kept that far apart; without, they may overlap, as dense gravel does
	local la = math.rad(Gv.LightAngle)
	local lx, ly = math.cos(la), math.sin(la)
	local placed: { { number } } = {}
	local function free(u: number, t: number, r: number): boolean
		for _, p in placed do
			local du = u - p[1]
			local dt = (t - p[2] + period * 0.5) % period - period * 0.5
			local need = r + p[3] + L.Gap
			if du * du + dt * dt < need * need then
				return false
			end
		end
		return true
	end
	local function stone(cu: number, ct: number, r: number)
		local towardLight = rand() < 0.5
		local amt = rand() * L.Contrast
		local tr, tg, tb = lerp(dust.R, (if towardLight then light else dark).R, amt), lerp(dust.G, (if towardLight then light else dark).G, amt), lerp(dust.B, (if towardLight then light else dark).B, amt)
		local rx, ry = r * range(Gv.Aspect) * pxA, r * range(Gv.Aspect) * pxL
		local rot = rand() * math.pi
		local cs, sn = math.cos(rot), math.sin(rot)
		local cx, cy = gx0 + inset + cu * pxA, ct * pxL
		local reach = math.max(rx, ry) + L.SoftPx + 1
		local softQ = L.SoftPx / math.min(rx, ry) -- the edge's width, in radii
		for pass = 1, 2 do
			local ox = if pass == 1 then cx - lx * L.ShadowOffset * rx else cx
			local oy = if pass == 1 then cy - ly * L.ShadowOffset * ry else cy
			if pass == 1 and L.ShadowDark >= 1 then
				continue
			end
			for y = math.floor(oy - reach), math.ceil(oy + reach) do
				for x = math.max(gx0, math.floor(ox - reach)), math.min(gx0 + G - 1, math.ceil(ox + reach)) do
					local dx, dy = x + 0.5 - ox, y + 0.5 - oy
					local ex = (dx * cs + dy * sn) / rx
					local ey = (-dx * sn + dy * cs) / ry
					local q = math.sqrt(ex * ex + ey * ey)
					local cov = smoothstep(1 + softQ * 0.5, 1 - softQ * 0.5, q)
					if cov > 0 then
						local yy = y % H
						local ur, ug, ub = get(x, yy)
						if pass == 1 then
							local a = cov * (1 - L.ShadowDark) * smoothstep(1, 0.2, q)
							put(x, yy, ur * (1 - a), ug * (1 - a), ub * (1 - a))
						else
							-- soft shading: lighter where it faces the light, more so toward its rim
							local toward = (dx / rx) * lx + (dy / ry) * ly
							local s = 1 + L.Lit * math.clamp(toward, -1, 1) * (0.4 + 0.6 * math.min(1, q))
							local a = cov * L.Opacity
							put(x, yy, lerp(ur, tr * s, a), lerp(ug, tg * s, a), lerp(ub, tb * s, a))
						end
					end
				end
			end
		end
	end
	for _, kind in L.Stones do
		local n = math.floor(kind.Density * B * period + 0.5)
		local made, tries = 0, 0
		while made < n and tries < n * 6 do
			tries += 1
			local r = range(kind.Radius)
			local u, t = rand() * B, rand() * period
			if not L.Gap or free(u, t, r) then
				if L.Gap then
					table.insert(placed, { u, t, r })
				end
				stone(u, t, r)
				made += 1
				if yield and made % 100 == 0 then
					yield()
				end
			end
		end
	end
	if yield then
		yield()
	end

	-- THE EDGES, no hard seams: at its start the tarmac's dusty edge (`TarmacEdge`) takes over
	-- in soft ragged shapes over `EdgeSoft`; past `GrassFrom`, grass in soft shapes, more toward
	-- its end
	local te, grass = C.TarmacEdge, C.GravelGrass
	for y = 0, H - 1 do
		local t = (y + 0.5) / pxL
		for x = gx0, gx0 + G - 1 do
			local ua = across(x)
			local n = sample(edgeN, math.max(0, ua + 1), t)
			local a = smoothstep(0.3, 0.7, 1 - ua / Gv.EdgeSoft + n * 0.5)
			local g = smoothstep(0.35, 0.65, (ua - Gv.GrassFrom) / (B - Gv.GrassFrom) + n * 0.45)
			if a > 0 or g > 0 then
				local r0, g0, b0 = get(x, y)
				if a > 0 then
					r0, g0, b0 = lerp(r0, te.R, a), lerp(g0, te.G, a), lerp(b0, te.B, a)
				end
				if g > 0 then
					local k = 1 + sample(fine, math.max(0, ua + 1), t) * L.Fine
					r0, g0, b0 = lerp(r0, grass.R * k, g), lerp(g0, grass.G * k, g), lerp(b0, grass.B * k, g)
				end
				put(x, y, r0, g0, b0)
			end
		end
		if yield and y % 64 == 63 then
			yield()
		end
	end
end

-- The painted pixels' sum (T-274): what `Tarmac.ImageHash` records for the uploaded image.
-- An FNV-style running sum over the RGBA words, in doubles as Luau does it (so it is not
-- FNV's own value; `assets/road/MANIFEST.md` has the same sum in Python, to check a file).
function RoadTexture.pixelHash(px: buffer): number
	local h = 2166136261
	for i = 0, buffer.len(px) - 1, 4 do
		h = bit32.bxor(h, buffer.readu32(px, i))
		h = (h * 16777619) % 4294967296
	end
	return h
end

-- Whether this device has the uploaded image (T-274). Yields while it loads.
local function loadUploaded(uri: string): boolean
	local probe = Instance.new("ImageLabel")
	probe.Image = uri
	local status: Enum.AssetFetchStatus? = nil
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync({ probe }, function(_, s)
			status = s
		end)
	end)
	probe:Destroy()
	fetchStatus = if ok then tostring(status) else tostring(err)
	return ok and status == Enum.AssetFetchStatus.Success
end

-- The fallback: the image painted here, a few ms a frame (`SliceMs`), then handed on as
-- OPAQUE CONTENT and its EditableImage let go, so it costs none of the client's mesh memory
-- (T-274; kept as the EditableImage, 32 tiles, only if that fails).
local function paintIt(): Content?
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
	if not ok then
		warn(`[RoadTexture] no tarmac texture on this device, the tarmac is drawn flat: {made}`)
		return nil
	end
	local img = made :: EditableImage
	local okC, result, content = pcall(function()
		return AssetService:CreateDataModelContentAsync(Content.fromObject(img))
	end)
	if okC and result == Enum.CreateContentResult.Success then
		img:Destroy()
		source = "painted"
		return content
	end
	paintedImage = img
	source = "painted image"
	return Content.fromObject(img)
end

-- The shared texture, ready the first time it is asked for (a client starts it on require,
-- below): the uploaded image, or where it will not load, the image painted here. It yields.
-- nil when it is off, or when this device can do neither.
function RoadTexture.get(): Content?
	if not RoadTexture.enabled() then
		return nil
	end
	while state == "making" do
		task.wait()
	end
	if state == "done" then
		return texture
	end
	state = "making"
	local T = Config.Spline.Tarmac
	local painted = RunService:IsStudio() and workspace:GetAttribute("__tarmac_painted") == true
	if T.Image ~= "" and not painted then
		local t0 = os.clock()
		-- (a server draws nothing: it only builds chunks in Studio tests, so it trusts the id)
		if RunService:IsServer() or loadUploaded(T.Image) then
			texture = Content.fromUri(T.Image)
			source = "uploaded"
		end
		loadMs = (os.clock() - t0) * 1000
	end
	if not texture then
		if T.Image ~= "" and not painted then
			warn(`[RoadTexture] the uploaded tarmac texture did not load ({fetchStatus}), painting it instead`)
		end
		texture = paintIt()
	end
	state = "done"
	return texture
end

-- Start loading it now, in the background (a client, as soon as the road's code loads).
function RoadTexture.prepare()
	if state == "none" and RoadTexture.enabled() then
		task.spawn(RoadTexture.get)
	end
end

function RoadTexture.DebugState()
	return {
		made = texture ~= nil,
		source = source, -- "uploaded", "painted" (opaque), "painted image", "none"
		state = state,
		fetchStatus = fetchStatus,
		loadMs = loadMs, -- loading the uploaded image
		-- tiles of the client's mesh memory it holds: only a painted EditableImage holds any
		tiles = if paintedImage then paintedImage.Size.X * paintedImage.Size.Y / (1024 * 1024) * Config.Spline.Mesh.Budget.Image1024 else 0,
		workMs = workMs, -- painting (the fallback), without the frames it waited
		wallMs = wallMs,
		frames = frames,
		period = RoadTexture.period(),
	}
end

if RunService:IsClient() then
	task.defer(RoadTexture.prepare)
end

return RoadTexture
