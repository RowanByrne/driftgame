--!strict
-- The approved drive records steering at five-stud intervals. The original 300-stud
-- boundaries also matter: the grade fitter looks ahead from the end of each section.
local Config = require(game.ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)

local Drive = {}
local STEP = 5
local SECTION_SAMPLES = 60
local curvature: buffer? = nil

function Drive.section(s0: number, bank0: number): Spline.Section?
	if not curvature then
		local encoded = require(script.Parent.Seed7Curvature)
		curvature = game:GetService("EncodingService"):Base64Decode(buffer.fromstring((encoded:gsub("%s", ""))))
	end
	local samples = curvature :: buffer
	local first = s0 / STEP
	local count = math.min(SECTION_SAMPLES, buffer.len(samples) / 4 - 1 - first)
	if count <= 0 then
		return nil
	end
	local C = Config.Spline
	local k = table.create(count * 2)
	local bank = {}
	local lastU, lastBank = 0, bank0
	local sharpest = math.abs(buffer.readf32(samples, first * 4))
	for i = 1, count do
		local u = i * STEP
		local steering = buffer.readf32(samples, (first + i) * 4)
		k[2 * i - 1], k[2 * i] = u, steering
		sharpest = math.max(sharpest, math.abs(steering))
		if i % 5 == 0 or i == count then
			-- Same radius-to-bank curve and eased rate limit as a generated turn.
			local target = math.rad(C.MaxBank) * math.clamp(steering * C.FullBankRadius, -1, 1)
			local limit = (u - lastU) * math.rad(C.MaxBankRate) / 1.5
			lastBank += math.clamp(target - lastBank, -limit, limit)
			table.insert(bank, u)
			table.insert(bank, lastBank)
			lastU = u
		end
	end
	local tag = if s0 == 0 then "Start" else "Straight"
	if s0 > 0 then
		for _, bend in C.Bends do
			if sharpest >= 1 / bend.radius[2] then
				tag = bend.name
				break
			end
		end
	end
	return { len = count * STEP, k = k, b = bank, g = {}, tag = tag }
end

return Drive
