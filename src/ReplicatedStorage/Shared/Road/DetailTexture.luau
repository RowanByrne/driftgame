--!strict
--!native
-- Road/DetailTexture: the ground's one shared detail texture, for the "detail" ground look
-- (T-338 step 1, `Config.GroundLook.Detail`, docs/game/features/ground-look.md). Grey noise
-- made in code, nothing uploaded: the vertex colours multiply it, so the one image gives
-- grass and rock alike grain up close, as the grass runoff's texture does (`Road/GrassTexture`).
--
-- It tiles exactly: lattice noise whose lattice wraps at the image's edge, four octaves.
-- Made once a session as an EditableImage (a 256 x 256 one holds about 2 of the client's
-- ~640 tiles of mesh memory), then made opaque content and let go (`Road/OpaqueBudget`), so it
-- holds none. Where opaque content is refused, the EditableImage itself. nil when this device
-- will not make it: the ground is then drawn as "blend".

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local OpaqueBudget = require(script.Parent.OpaqueBudget)

local DetailTexture = {}

-- One octave's lattice of values, -1 to 1, `cells` each way.
local function lattice(rng: Random, cells: number): { number }
	local t = table.create(cells * cells)
	for i = 1, cells * cells do
		t[i] = rng:NextNumber() * 2 - 1
	end
	return t
end

-- The grey of each pixel, 0 to 1, by y * size + x + 1: tiling at the edges.
function DetailTexture.pixels(size: number): { number }
	local D = Config.GroundLook.Detail
	local rng = Random.new(33811)
	local octaves = {}
	local total = 0
	for o = 0, D.Octaves - 1 do
		local cells = D.Cells * 2 ^ o
		local amp = 0.55 ^ o
		total += amp
		table.insert(octaves, { cells = cells, amp = amp, v = lattice(rng, cells) })
	end
	local out = table.create(size * size)
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local sum = 0
			for _, oc in octaves do
				local c = oc.cells
				local gx, gy = x / size * c, y / size * c
				local x0, y0 = math.floor(gx), math.floor(gy)
				local tx, ty = gx - x0, gy - y0
				tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
				local x1, y1 = (x0 + 1) % c, (y0 + 1) % c
				local v = oc.v
				local a = v[y0 * c + x0 + 1] + (v[y0 * c + x1 + 1] - v[y0 * c + x0 + 1]) * tx
				local b = v[y1 * c + x0 + 1] + (v[y1 * c + x1 + 1] - v[y1 * c + x0 + 1]) * tx
				sum += (a + (b - a) * ty) * oc.amp
			end
			-- (lattice noise rarely reaches its full height: half of it is most of the spread)
			local g = D.Mean + math.clamp(sum / total * 2, -1, 1) * D.Contrast
			out[y * size + x + 1] = math.clamp(g, 0, 1)
		end
	end
	return out
end

local content: Content? = nil
local image: EditableImage? = nil
local state = "none" -- "none", "making", "opaque", "image" (opaque refused), "off"
local buildMs = 0

-- The texture, made the first time it is asked for (it yields; a caller asking meanwhile
-- waits). nil when this device will not make it.
function DetailTexture.content(): Content?
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
	local size = Config.GroundLook.Detail.Size
	local ok, made = pcall(function()
		local img = AssetService:CreateEditableImage({ Size = Vector2.new(size, size) })
		local g = DetailTexture.pixels(size)
		local px = buffer.create(size * size * 4)
		for i = 1, size * size do
			local v = math.floor(g[i] * 255 + 0.5)
			local o = (i - 1) * 4
			buffer.writeu8(px, o, v)
			buffer.writeu8(px, o + 1, v)
			buffer.writeu8(px, o + 2, v)
			buffer.writeu8(px, o + 3, 255)
		end
		img:WritePixelsBuffer(Vector2.zero, img.Size, px)
		return img
	end)
	buildMs = (os.clock() - t0) * 1000
	if not ok or not made then
		warn(`[DetailTexture] no detail texture on this device: {made}`)
		state = "off"
		return nil
	end
	local img = made :: EditableImage
	local okO, opaque = OpaqueBudget.make("detail", Content.fromObject(img))
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

function DetailTexture.DebugState()
	return { state = state, buildMs = buildMs, size = Config.GroundLook.Detail.Size }
end

return DetailTexture
