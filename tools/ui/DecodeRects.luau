--[[
DecodeRects.luau: measures what Roblox actually decoded for uploaded images (docs/workflow/ART-PIPELINE.md "Images", step 5).

Run with execute_luau in the EDIT datamodel after upload_image. Roblox rescales uploads to about 1024 px
on the long side, so ImageRectOffset / ImageRectSize and the aspect used by the 20% rule must come from
here, never from the source PNG. For each id it loads the decoded image with
AssetService:CreateEditableImageAsync, reads its pixels with ReadPixelsBuffer, and finds the box of
pixels with alpha >= alphaThreshold, grown by margin px and clamped to the image (or to each cell).

Edit CONFIG, then send the whole file as the execute_luau code. Returns string-keyed tables only:
{ [id] = { decodedSize, rectOffset = {x, y}, rectSize = {x, y}, aspect, cells?, error? } }
EditableImage needs the asset to be one the signed-in Studio user may edit (their own uploads).
]]

local CONFIG = {
	ids = {
		-- "rbxassetid://123456789", 123456789,
	},
	alphaThreshold = 8,
	margin = 1,
	-- Atlases: bounds per cell instead of (as well as) the whole image.
	-- grid = { cell = 128 }                                  -> cells keyed "row_col" (0-based)
	-- cells = { anchor = { x = 0, y = 0, w = 128, h = 128 } } -> named sub-rects in decoded px
	grid = nil,
	cells = nil,
}

local AssetService = game:GetService("AssetService")

local function uri(id: any): string
	if type(id) == "number" or string.match(tostring(id), "^%d+$") then
		return "rbxassetid://" .. tostring(id)
	end
	return tostring(id)
end

local function load(u: string): (boolean, any)
	local ok, img = pcall(function()
		return AssetService:CreateEditableImageAsync(Content.fromUri(u))
	end)
	if not ok then -- older engines took the content id string directly
		local ok2, img2 = pcall(function()
			return (AssetService :: any):CreateEditableImageAsync(u)
		end)
		if ok2 then
			return ok2, img2
		end
	end
	return ok, img
end

-- Alpha bounds inside the region (x0, y0, w, h) of an RGBA8 buffer that is imgW pixels wide.
local function bounds(buf: buffer, imgW: number, x0: number, y0: number, w: number, h: number)
	local threshold, margin = CONFIG.alphaThreshold, CONFIG.margin
	local minX, minY, maxX, maxY = math.huge, math.huge, -1, -1
	for y = y0, y0 + h - 1 do
		local row = y * imgW
		for x = x0, x0 + w - 1 do
			if buffer.readu8(buf, (row + x) * 4 + 3) >= threshold then
				if x < minX then minX = x end
				if x > maxX then maxX = x end
				if y < minY then minY = y end
				if y > maxY then maxY = y end
			end
		end
		if (y - y0) % 128 == 127 then
			task.wait() -- keep Studio responsive on big images
		end
	end
	if maxX < 0 then
		return { empty = true }
	end
	minX, minY = math.max(x0, minX - margin), math.max(y0, minY - margin)
	maxX, maxY = math.min(x0 + w - 1, maxX + margin), math.min(y0 + h - 1, maxY + margin)
	local rw, rh = maxX - minX + 1, maxY - minY + 1
	return {
		rectOffset = { x = minX, y = minY },
		rectSize = { x = rw, y = rh },
		aspect = math.floor(rw / rh * 1000 + 0.5) / 1000,
	}
end

local out = {}
for _, id in CONFIG.ids do
	local u = uri(id)
	local ok, img = load(u)
	if not ok or not img then
		out[u] = { error = tostring(img) }
		continue
	end
	local size: Vector2 = img.Size
	local w, h = size.X, size.Y
	local okRead, buf = pcall(function()
		return img:ReadPixelsBuffer(Vector2.zero, size)
	end)
	if not okRead then
		img:Destroy()
		out[u] = { error = "ReadPixelsBuffer: " .. tostring(buf) }
		continue
	end
	local r = bounds(buf, w, 0, 0, w, h)
	r.decodedSize = string.format("%dx%d", w, h)
	if CONFIG.grid then
		local c = CONFIG.grid.cell
		local cells = {}
		for cy = 0, math.floor(h / c) - 1 do
			for cx = 0, math.floor(w / c) - 1 do
				local b = bounds(buf, w, cx * c, cy * c, c, c)
				if not b.empty then
					cells[string.format("%d_%d", cy, cx)] = b
				end
			end
		end
		r.cells = cells
	elseif CONFIG.cells then
		local cells = {}
		for name, rect in CONFIG.cells do
			local x, y = math.max(0, rect.x), math.max(0, rect.y)
			cells[tostring(name)] = bounds(buf, w, x, y, math.min(rect.w, w - x), math.min(rect.h, h - y))
		end
		r.cells = cells
	end
	img:Destroy()
	out[u] = r
end
return out
