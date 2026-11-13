--!strict
-- GrassTexture: the grass runoff's own look (T-187), in one of a few STYLES the user picks from
-- (`Config.Spline.Grass.Style`):
--
--   blades   a tile of short blades drawn in code (the first try: read as static in game)
--   mottled  a tile of soft, large, low-contrast patches, no blades, over a big tile
--   soft     fewer, fainter blades, blurred, so a distant tile does not shimmer
--   painted  a painted grass image (the image tool), made grey and evened out offline
--   patches  NO TEXTURE: the grass faces' own colours vary in soft patches (`patch`), so the
--            road's part keeps its Asphalt material, grain and all
--
-- THE TEXTURED STYLES share one EditableImage every chunk uses (`Road/SplineMesh`).
--
-- WHY A TEXTURE, AND WHY ONE IMAGE. The road's mesh is one MeshPart a chunk, so it has one
-- Material: a built-in Grass material would put grass on the tarmac, the rocks and the trees
-- too (measured: a MeshPart's material is projected, it ignores the mesh's UVs). A texture
-- IS mapped by UVs, face by face, so the grass faces get UVs in world studs and tile it, and
-- every other face samples UV (0, 0). A client has no EditableMesh to spare (measured: none
-- free while the road is drawn), so the grass cannot be a mesh of its own.
--
-- WHAT A TEXTURE DOES TO THE REST. With a texture on it, a MeshPart no longer shows its
-- material's colour map (measured: the tarmac went flat and twice as bright). The Asphalt map
-- darkened everything about half (`Shade`), so the image's corners -- where UV (0, 0) samples
-- -- are `Shade` grey: the tarmac, gravel, rock and trees keep their brightness, without
-- Asphalt's grain. The tile averages `Shade` too, so the grass keeps its brightness. Each
-- pixel is a grey the vertex colour multiplies, so the grass stays `GrassColour`.
--
-- A device that will not make the image draws the road as before: no texture, flat grass.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GrassTexture = {}

local CORNER = 2 -- pixels each side of the wrap point held at `Shade`: a 4 x 4 block

export type Style = {
	Texture: boolean,
	TileStuds: number,
	Clump: number,
	Cells: { number }, -- the clumps' octaves: lattice cells a tile, each half the last's weight
	Blades: number,
	BladeLength: { number },
	Blade: number,
	LightShare: number,
	Warm: number,
	Blur: number, -- box-blur passes (radius 1), wrapping
	Image: string?, -- painted: the uploaded grey tile
	PatchStuds: number?, -- patches: across one patch
	PatchShades: { number }?, -- patches: brightness steps either side of `GrassColour`
}

-- The active style, its numbers over the shared defaults.
function GrassTexture.style(): Style
	local G = Config.Spline.Grass
	local out = table.clone(G.Styles.base)
	for k, v in G.Styles[G.Style] or {} do
		out[k] = v
	end
	return out :: any
end

local worstSliceMs = 0

-- The pixels, RGBA, `size` square, from `seed` and `style`: the same on every device. Tiles
-- seamlessly. With `sliceMs` it waits a frame whenever it has worked that long (measured:
-- about 30 ms in one go, too long for one frame), so call it from a thread that may yield.
function GrassTexture.pixels(size: number, seed: number, sliceMs: number?, styleIn: Style?): buffer
	local G = Config.Spline.Grass
	local S = styleIn or GrassTexture.style()
	local n = size * size
	local f = table.create(n, 0) -- each pixel's offset from the mean, in units of `Shade`
	local rng = Random.new(seed)
	local sliceStart = os.clock()
	local function pace()
		if sliceMs then
			local ms = (os.clock() - sliceStart) * 1000
			if ms >= sliceMs then
				worstSliceMs = math.max(worstSliceMs, ms)
				task.wait()
				sliceStart = os.clock()
			end
		end
	end

	-- CLUMPS: tiling value noise, a few octaves, so the grass is patchy rather than even
	local function octave(cells: number, amp: number)
		local lattice = table.create(cells * cells, 0)
		for i = 1, cells * cells do
			lattice[i] = rng:NextNumber() * 2 - 1
		end
		local function at(cx: number, cy: number): number
			return lattice[(cy % cells) * cells + (cx % cells) + 1]
		end
		local scale = cells / size
		for y = 0, size - 1 do
			local gy = y * scale
			local y0 = math.floor(gy)
			local ty = gy - y0
			ty = ty * ty * (3 - 2 * ty)
			for x = 0, size - 1 do
				local gx = x * scale
				local x0 = math.floor(gx)
				local tx = gx - x0
				tx = tx * tx * (3 - 2 * tx)
				local a = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * tx
				local b = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * tx
				local i = y * size + x + 1
				f[i] += (a + (b - a) * ty) * amp
			end
			pace()
		end
	end
	local amp = S.Clump
	for _, cells in S.Cells do
		octave(cells, amp)
		amp *= 0.5
	end

	-- BLADES: short strokes in every direction (it is seen from above), lighter or darker
	-- than the ground, fading toward the tip, wrapping round the tile's edges
	local lenLo, lenHi = S.BladeLength[1], S.BladeLength[2]
	for blade = 1, S.Blades do
		if blade % 256 == 0 then
			pace()
		end
		local x0, y0 = rng:NextNumber() * size, rng:NextNumber() * size
		local angle = rng:NextNumber() * math.pi * 2
		local len = lenLo + (lenHi - lenLo) * rng:NextNumber()
		local tone = (if rng:NextNumber() < S.LightShare then 1 else -1) * S.Blade * (0.5 + 0.5 * rng:NextNumber())
		local dx, dy = math.cos(angle), math.sin(angle)
		local steps = math.max(1, math.floor(len * 2))
		for k = 0, steps do
			local t = k / steps
			local px = math.floor(x0 + dx * len * t) % size
			local py = math.floor(y0 + dy * len * t) % size
			local i = py * size + px + 1
			local w = 0.75 * (1 - 0.6 * t)
			f[i] = f[i] * (1 - w) + tone * w
		end
	end

	-- BLUR: box passes of radius 1, wrapping, so no detail is finer than a few pixels
	for _ = 1, S.Blur do
		local g = table.create(n, 0)
		for y = 0, size - 1 do
			local ym, yp = ((y - 1) % size) * size, ((y + 1) % size) * size
			local y0 = y * size
			for x = 0, size - 1 do
				local xm, xp = (x - 1) % size, (x + 1) % size
				g[y0 + x + 1] = (f[ym + xm + 1] + f[ym + x + 1] + f[ym + xp + 1] + f[y0 + xm + 1] + f[y0 + x + 1] + f[y0 + xp + 1] + f[yp + xm + 1] + f[yp + x + 1] + f[yp + xp + 1]) / 9
			end
			pace()
		end
		f = g
	end

	-- mean zero, so the grass averages `Shade`, as the Asphalt map made it before
	local sum = 0
	for i = 1, n do
		sum += f[i]
	end
	local mean = sum / n

	local shade = G.Shade
	local out = buffer.create(n * 4)
	local function put(i: number, r: number, g: number, b: number)
		local o = (i - 1) * 4
		buffer.writeu8(out, o, math.clamp(math.floor(r * 255 + 0.5), 0, 255))
		buffer.writeu8(out, o + 1, math.clamp(math.floor(g * 255 + 0.5), 0, 255))
		buffer.writeu8(out, o + 2, math.clamp(math.floor(b * 255 + 0.5), 0, 255))
		buffer.writeu8(out, o + 3, 255)
	end
	for i = 1, n do
		local d = f[i] - mean
		local v = shade * (1 + d)
		local warm = math.max(d, 0) * S.Warm
		put(i, v * (1 + warm), v, v * (1 - warm))
		if i % size == 0 then
			pace()
		end
	end
	GrassTexture.plainCorners(out, size)
	return out
end

-- THE CORNERS, where every face that is not grass samples: exactly `Shade`. A block, not one
-- pixel, so a texture a device draws at lower resolution still reads `Shade` there.
function GrassTexture.plainCorners(px: buffer, size: number)
	local v = math.floor(Config.Spline.Grass.Shade * 255 + 0.5)
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			if (x < CORNER or x >= size - CORNER) and (y < CORNER or y >= size - CORNER) then
				local o = (y * size + x) * 4
				buffer.writeu8(px, o, v)
				buffer.writeu8(px, o + 1, v)
				buffer.writeu8(px, o + 2, v)
				buffer.writeu8(px, o + 3, 255)
			end
		end
	end
end

local image: EditableImage? = nil
local state = "none" -- "none", "making", "done"
local buildMs = 0

-- The shared image, made the first time it is asked for, over a few frames (it yields: the
-- first chunk to ask waits for it, and so does any chunk asking meanwhile). nil when the
-- style has no texture, when this device will not make one (out of its EditableImage
-- memory), or when the texture is off.
function GrassTexture.get(): EditableImage?
	local G = Config.Spline.Grass
	local S = GrassTexture.style()
	if not G.Enabled or not S.Texture then
		return nil -- read each time, so a test can switch it off and on
	end
	while state == "making" do
		task.wait()
	end
	if state == "done" then
		return image
	end
	state = "making"
	local t0 = os.clock()
	local ok, made = pcall(function()
		if S.Image and S.Image ~= "" then
			-- the painted tile: uploaded grey and evened out to `Shade` already; only its
			-- corners are set here
			local img = AssetService:CreateEditableImageAsync(Content.fromUri(S.Image))
			local size = img.Size.X
			local px = img:ReadPixelsBuffer(Vector2.zero, img.Size)
			GrassTexture.plainCorners(px, size)
			img:WritePixelsBuffer(Vector2.zero, img.Size, px)
			return img
		end
		local img = AssetService:CreateEditableImage({ Size = Vector2.new(G.Size, G.Size) })
		assert(img, "this device would not make an EditableImage")
		local px = GrassTexture.pixels(G.Size, G.Seed, G.SliceMs, S)
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(G.Size, G.Size), px)
		return img
	end)
	buildMs = (os.clock() - t0) * 1000
	if ok then
		image = made
	else
		warn(`[GrassTexture] no grass texture on this device, the grass is drawn flat: {made}`)
	end
	state = "done"
	return image
end

-- A grass vertex's UV: world studs over `TileStuds`, shifted by a whole number of tiles
-- (`base`, from the chunk's centre) so the numbers stay small and the tiling runs on
-- unbroken from chunk to chunk.
function GrassTexture.uv(x: number, z: number, baseU: number, baseV: number): Vector2
	local tile = GrassTexture.style().TileStuds
	return Vector2.new(x / tile - baseU, z / tile - baseV)
end

-- The whole tiles to shift a chunk's UVs by, from its centre.
function GrassTexture.base(centre: Vector3): (number, number)
	local tile = GrassTexture.style().TileStuds
	return math.floor(centre.X / tile), math.floor(centre.Z / tile)
end

-- PATCHES (the untextured style): which of `PatchShades` the grass at world (x, z) takes.
-- Smooth value noise over `PatchStuds` cells, the same on every device; nil in any other
-- style.
local function hash(ix: number, iz: number): number
	-- exact integer maths only (bit32), so every device gets the same patches
	local h = bit32.bxor((ix * 73856093) % 4294967296, (iz * 19349663) % 4294967296)
	for _ = 1, 2 do
		h = bit32.bxor(h, bit32.lshift(h, 13))
		h = bit32.bxor(h, bit32.rshift(h, 17))
		h = bit32.bxor(h, bit32.lshift(h, 5))
	end
	return (h % 10007) / 10007
end
function GrassTexture.patch(x: number, z: number): number?
	local S = GrassTexture.style()
	if S.Texture or not S.PatchStuds or not S.PatchShades then
		return nil
	end
	local gx, gz = x / S.PatchStuds, z / S.PatchStuds
	local x0, z0 = math.floor(gx), math.floor(gz)
	local tx, tz = gx - x0, gz - z0
	tx, tz = tx * tx * (3 - 2 * tx), tz * tz * (3 - 2 * tz)
	local a = hash(x0, z0) + (hash(x0 + 1, z0) - hash(x0, z0)) * tx
	local b = hash(x0, z0 + 1) + (hash(x0 + 1, z0 + 1) - hash(x0, z0 + 1)) * tx
	local v = a + (b - a) * tz -- 0..1
	local k = #S.PatchShades
	return math.clamp(math.floor(v * k) + 1, 1, k)
end

function GrassTexture.DebugState()
	-- `buildMs` is wall time, frames waited included; `worstSliceMs` the most work in a frame
	return { made = image ~= nil, state = state, buildMs = buildMs, worstSliceMs = worstSliceMs, style = Config.Spline.Grass.Style }
end

return GrassTexture
