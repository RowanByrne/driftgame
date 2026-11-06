--[[
SourceGate.luau: proves Studio is running the code on disk before you trust a playtest
(docs/workflow/TESTING.md "Every playtest").

Run with execute_luau in the EDIT datamodel. Don't fill CONFIG by hand: tools/ui/source-gate.ps1 hashes
the files on disk and prints this script with CONFIG filled in. For each module it compares Studio's
.Source with the disk file (LF-normalised UTF-8 bytes, BOM dropped, h = (h * 31 + byte) % 2^32) and,
with compile = true, compiles it with loadstring when the plugin context allows that.
Returns { ok, checked, failed, results = { [file] = {...} } } with string keys only.
]]

-- CONFIG BEGIN
local CONFIG = {
	compile = true,
	modules = {
		-- { file = "src/StarterPlayerScripts/UI/Theme.luau", path = { "StarterPlayer", "StarterPlayerScripts", "UI", "Theme" }, bytes = 0, hash = 0 },
	},
}
-- CONFIG END

local function normalise(s: string): string
	if string.sub(s, 1, 3) == "\239\187\191" then
		s = string.sub(s, 4)
	end
	return (string.gsub(s, "\r\n", "\n"))
end

local function hash(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 4294967296
	end
	return h
end

local function find(path: { string }): Instance?
	local ok, node = pcall(function()
		return game:GetService(path[1])
	end)
	if not ok or not node then
		node = game:FindFirstChild(path[1])
	end
	for i = 2, #path do
		if not node then
			return nil
		end
		node = node:FindFirstChild(path[i])
	end
	return node
end

local results = {}
local failed, checked = 0, 0
for _, m in CONFIG.modules do
	checked += 1
	local r: { [string]: any } = { instance = table.concat(m.path, "."), expectBytes = m.bytes, expectHash = m.hash }
	local inst = find(m.path)
	if not inst or not inst:IsA("LuaSourceContainer") then
		r.status = "missing"
	else
		local ok, src = pcall(function()
			return (inst :: any).Source
		end)
		if not ok then
			r.status = "unreadable: " .. tostring(src)
		else
			local s = normalise(src)
			r.bytes, r.hash = #s, hash(s)
			r.status = if r.bytes == m.bytes and r.hash == m.hash then "match" else "MISMATCH"
			if CONFIG.compile and r.status == "match" then
				local ls = (loadstring :: any)
				if typeof(ls) ~= "function" then
					r.compile = "skipped (no loadstring here)"
				else
					local fn, err = ls(s, "=" .. inst.Name)
					r.compile = if fn then "ok" else "ERROR: " .. tostring(err)
					if not fn then
						r.status = "COMPILE ERROR"
					end
				end
			end
		end
	end
	if r.status ~= "match" then
		failed += 1
	end
	results[m.file] = r
	if checked % 20 == 0 then
		task.wait()
	end
end

return { ok = failed == 0 and checked > 0, checked = checked, failed = failed, results = results }
