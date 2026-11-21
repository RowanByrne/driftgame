--!strict
--!native
-- Road/GroundSheet: the ground's texture sheet, for the "sheet" ground look (T-340,
-- `Config.GroundLook.Sheet`, docs/game/features/ground-look.md). One image of 2 x 2 squares,
-- grass, rocky grass, rock and snow, each holding its texture `Repeats` times each way;
-- `Drift/GroundMeshView` points each triangle of ground at one square (`writeFaceUVs`), and the
-- vertex colours tint it.
--
-- WHERE THE TEXTURES COME FROM. `Sheet.Image`, the user's picked sheet once uploaded: its four
-- quadrants, each one tile, are read and repeated into the game's sheet (the uploaded master's
-- pixels are never changed; this only lays them out). Until then, placeholder textures made in
-- code: grey value noise shaped as blades, stones, cracked planes and soft drifts.
--
-- Made once a session as an EditableImage (1 024 x 1 024 holds about 32 of the client's ~640
-- tiles of mesh memory while it is made), then made opaque content and let go
-- (`Road/OpaqueBudget`), so it holds none. Where opaque content is refused, the EditableImage
-- itself. nil when this device will not make it: the ground is then drawn as "blend".

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local OpaqueBudget = require(script.Parent.OpaqueBudget)

local GroundSheet = {}

-- PERIODIC VALUE NOISE: a lattice of `cx` by `cy` values that wraps, so a texture made of it
-- tiles. (u, v) in [0, 1).
type Lattice = { cx: number, cy: number, v: { number } }

local function lattice(rng: Random, cx: number, cy: number): Lattice
	local t = table.create(cx * cy)
	for i = 1, cx * cy do
		t[i] = rng:NextNumber() * 2 - 1
	end
	return { cx = cx, cy = cy, v = t }
end

local function sample(l: Lattice, u: number, v: number): number
	local gx, gy = (u % 1) * l.cx, (v % 1) * l.cy
	local x0, y0 = math.floor(gx), math.floor(gy)
	local tx, ty = gx - x0, gy - y0
	tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
	local x1, y1 = (x0 + 1) % l.cx, (y0 + 1) % l.cy
	local t, w = l.v, l.cx
	local a = t[y0 * w + x0 + 1] + (t[y0 * w + x1 + 1] - t[y0 * w + x0 + 1]) * tx
	local b = t[y1 * w + x0 + 1] + (t[y1 * w + x1 + 1] - t[y1 * w + x0 + 1]) * tx
	return a + (b - a) * ty
end

local function fbm(ls: { Lattice }, u: number, v: number): number
	local s, amp, total = 0, 1, 0
	for _, l in ls do
		s += sample(l, u, v) * amp
		total += amp
		amp *= 0.55
	end
	return s / total
end

local function ease(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- THE PLACEHOLDERS: one tile of each texture, `t` pixels each way, grey 0 to 1 by
-- y * t + x + 1, averaging about `Sheet.Mean`.
function GroundSheet.placeholder(kind: string, t: number): { number }
	local mean = Config.GroundLook.Sheet.Mean
	local rng = Random.new(if kind == "grass" then 101 elseif kind == "rocky" then 202 elseif kind == "rock" then 303 else 404)
	local soft = { lattice(rng, 3, 3), lattice(rng, 6, 6), lattice(rng, 12, 12) }
	local blades = lattice(rng, 56, 7) -- streaks: fine across, long along
	local fine = lattice(rng, 64, 64)
	local stones = { lattice(rng, 9, 9), lattice(rng, 18, 18) }
	local planes = lattice(rng, 5, 5)
	local cracks = { lattice(rng, 4, 4), lattice(rng, 8, 8), lattice(rng, 16, 16) }
	local out = table.create(t * t)
	for y = 0, t - 1 do
		for x = 0, t - 1 do
			local u, v = x / t, y / t
			local g
			if kind == "grass" or kind == "rocky" then
				g = mean + fbm(soft, u, v) * 0.12 + sample(blades, u, v) * 0.1 + sample(fine, u, v) * 0.05
				if kind == "rocky" then
					local n = fbm(stones, u, v)
					local stone = ease(0.12, 0.2, n)
					local rim = ease(0.06, 0.12, n) - stone
					g = g * (1 - stone) + (mean + 0.12 + sample(fine, u * 2, v * 2) * 0.05) * stone - rim * 0.16
				end
			elseif kind == "rock" then
				local level = math.floor((sample(planes, u, v) + 1) * 2.5) / 5 -- flat planes, five greys
				local c = math.abs(fbm(cracks, u, v))
				local crack = 1 - ease(0, 0.07, c)
				g = mean - 0.08 + level * 0.18 + sample(fine, u, v) * 0.04 - crack * 0.3
			else
				g = mean + 0.05 + fbm(soft, u, v) * 0.07
			end
			out[y * t + x + 1] = math.clamp(g, 0, 1)
		end
	end
	return out
end

-- The uploaded sheet's quadrants (`Sheet.Image`), each resampled to one tile of `t` pixels,
-- in `Sheet.Order`; nil if it will not load.
local function fromImage(id: string, t: number): { { number } }?
	local ok, img = pcall(function()
		return AssetService:CreateEditableImageAsync(Content.fromUri(id))
	end)
	if not ok or not img then
		warn(`[GroundSheet] the sheet {id} would not load: {img}`)
		return nil
	end
	local image = img :: EditableImage
	local size = image.Size
	local px = image:ReadPixelsBuffer(Vector2.zero, size)
	image:Destroy()
	local w, h = size.X, size.Y
	local qw, qh = w // 2, h // 2
	local tiles = {}
	for q = 0, 3 do
		local ox, oy = (q % 2) * qw, (q // 2) * qh
		local out = table.create(t * t)
		for y = 0, t - 1 do
			for x = 0, t - 1 do
				-- bilinear, wrapping within the quadrant (it tiles)
				local fx, fy = (x + 0.5) / t * qw - 0.5, (y + 0.5) / t * qh - 0.5
				local x0, y0 = math.floor(fx), math.floor(fy)
				local tx, ty = fx - x0, fy - y0
				local function at(ix: number, iy: number): number
					local o = ((oy + iy % qh) * w + ox + ix % qw) * 4
					-- (luminance: the sheet is meant grey; any colour in it is the vertex colour's job)
					return (buffer.readu8(px, o) * 0.299 + buffer.readu8(px, o + 1) * 0.587 + buffer.readu8(px, o + 2) * 0.114) / 255
				end
				local a = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * tx
				local b = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * tx
				out[y * t + x + 1] = a + (b - a) * ty
			end
		end
		tiles[q + 1] = out
	end
	return tiles
end

-- The game's sheet's pixels, grey 0 to 1 by y * size + x + 1: each square its tile repeated
-- `Repeats` times each way. `tiles` in `Sheet.Order`, each `t` pixels each way.
function GroundSheet.lay(tiles: { { number } }, t: number, size: number, reps: number): { number }
	local out = table.create(size * size)
	local half = size // 2
	for y = 0, size - 1 do
		local row = y // half
		local ty = math.floor(((y % half) / half * reps) % 1 * t)
		for x = 0, size - 1 do
			local col = x // half
			local tx = math.floor(((x % half) / half * reps) % 1 * t)
			out[y * size + x + 1] = tiles[row * 2 + col + 1][ty * t + tx + 1]
		end
	end
	return out
end

local content: Content? = nil
local image: EditableImage? = nil
local state = "none" -- "none", "making", "opaque", "image" (opaque refused), "off"
local source = "none" -- "placeholder" or the uploaded id
local buildMs = 0

-- The sheet, made the first time it is asked for (it yields; a caller asking meanwhile waits).
-- nil when this device will not make it.
function GroundSheet.content(): Content?
	while state == "making" do
		task.wait()
	end
	if state == "opaque" then
		return content
	elseif state == "image" then
		return if image then Content.fromObject(image) else nil
	elseif state == "off" then
		return nil
	end
	state = "making"
	local t0 = os.clock()
	local S = Config.GroundLook.Sheet
	local size, reps = S.Size, S.Repeats
	local t = math.max(8, math.round(size / 2 / reps))
	local ok, made = pcall(function()
		local tiles = if S.Image then fromImage(S.Image, t) else nil
		if tiles then
			source = S.Image :: string
		else
			tiles = {}
			for i, kind in S.Order do
				(tiles :: any)[i] = GroundSheet.placeholder(kind, t)
				task.wait()
			end
			source = "placeholder"
		end
		local g = GroundSheet.lay(tiles :: { { number } }, t, size, reps)
		task.wait()
		local px = buffer.create(size * size * 4)
		for i = 1, size * size do
			local v = math.floor(math.clamp(g[i], 0, 1) * 255 + 0.5)
			local o = (i - 1) * 4
			buffer.writeu8(px, o, v)
			buffer.writeu8(px, o + 1, v)
			buffer.writeu8(px, o + 2, v)
			buffer.writeu8(px, o + 3, 255)
		end
		local img = AssetService:CreateEditableImage({ Size = Vector2.new(size, size) })
		img:WritePixelsBuffer(Vector2.zero, img.Size, px)
		return img
	end)
	buildMs = (os.clock() - t0) * 1000
	if not ok or not made then
		warn(`[GroundSheet] no texture sheet on this device: {made}`)
		state = "off"
		return nil
	end
	local img = made :: EditableImage
	local okO, opaque = OpaqueBudget.make("sheet", Content.fromObject(img))
	if okO and opaque then
		img:Destroy()
		content = opaque
		state = "opaque"
		return content
	end
	image = img
	state = "image"
	return Content.fromObject(img)
end

function GroundSheet.DebugState()
	-- `buildMs` is wall time, its waits included
	return { state = state, source = source, buildMs = buildMs, size = Config.GroundLook.Sheet.Size }
end

return GroundSheet
