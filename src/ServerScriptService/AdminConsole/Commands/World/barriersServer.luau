local Ops = require(script.Parent.Parent.Parent.Ops)

return function(_context, on: boolean?): string
	local playground = Ops.need("PlaygroundService")
	local want = if on == nil then not playground:BarriersOn() else on
	local now = playground:SetBarriers(want)
	return if now then "Barriers up." else "Barriers down: you can drive off the edge."
end
