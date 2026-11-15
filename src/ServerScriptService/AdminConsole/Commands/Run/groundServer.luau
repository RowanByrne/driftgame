-- The ground-first trial's switch (features/ground-trial.md, T-218).
local Ops = require(script.Parent.Parent.Parent.Ops)

return function(_context, mode: string?): string
	local road = Ops.need("RoadService")
	local running = road:RunGround()
	if mode == nil then
		local now = if running then ` This road has the {running} ground.` else ""
		return `The next run has the {road:GroundMode()} ground.{now}`
	end
	if road:HasRoad() then
		return `A road is up; the ground changes only between runs (end-run first). Still {road:GroundMode()}.`
	end
	return `The next run has the {road:SetGroundMode(mode)} ground.`
end
