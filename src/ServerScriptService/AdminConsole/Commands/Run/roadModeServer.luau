local Ops = require(script.Parent.Parent.Parent.Ops)

return function(_context, mode: string?): string
	local road = Ops.need("RoadService")
	if mode == nil then
		return `The next run lays the {road:Mode()} road.`
	end
	if road:HasRoad() then
		return `A road is up; the mode changes only between runs. Still {road:Mode()}.`
	end
	return `The next run lays the {road:SetMode(mode)} road.`
end
