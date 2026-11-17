--!strict
-- Drift/MeshBudget: who gives way when this client runs out of EditableMesh memory (T-273,
-- features/ground-trial.md "The mesh budget").
--
-- A client holds about 640 "tiles" of mesh memory in Studio on a PC, a tile being a
-- fixed-size mesh of 128 triangles (`Config.Spline.Mesh.Budget`). Every mesh user shares it:
-- the ground's tiles, the road's chunks, the drift marks, the vista's arc, and EditableImages
-- too (the road's 1 024 x 1 024 texture is 32 tiles). Nothing can ask how much is left: a
-- mesh that does not fit just comes back nil, with an engine warning.
--
-- THE ROAD NEAR THE CAR NEVER GIVES WAY. When the road cannot make a chunk's mesh it asks
-- here first: each giver, cheapest to lose first, lets some of its own go. The ground is the
-- one giver today (`Drift/GroundMeshView`: its hidden spare tiles at once, then fewer tiles
-- far out). Only when nobody can give does the road let its own far chunks go
-- (`Drift/SplineRoadView`), and never the ones near the car.

local MeshBudget = {}

export type Giver = {
	name: string,
	rank: number, -- lower gives first
	give: (units: number) -> (number, number), -- tiles freed now, tiles that will be freed soon
}

local givers: { Giver } = {}
local stats = { asks = 0, freedNow = 0, freeingSoon = 0, refused = 0, byGiver = {} :: { [string]: number } }

-- Register `give(units)`: let go of up to `units` tiles of mesh memory. Returns a function
-- that takes the giver off the list again (call it when the giver is destroyed).
function MeshBudget.giver(name: string, rank: number, give: (number) -> (number, number)): () -> ()
	local g: Giver = { name = name, rank = rank, give = give }
	table.insert(givers, g)
	table.sort(givers, function(a, b)
		return a.rank < b.rank
	end)
	return function()
		local i = table.find(givers, g)
		if i then
			table.remove(givers, i)
		end
	end
end

-- Ask the givers, cheapest first, for `units` tiles. Returns the tiles freed now, and the
-- tiles a giver has promised to free over the next frames (the ground merging tiles).
function MeshBudget.ask(units: number): (number, number)
	stats.asks += 1
	local now, soon = 0, 0
	for _, g in table.clone(givers) do
		if now >= units then
			break
		end
		local ok, a, b = pcall(g.give, units - now)
		if ok then
			local freed, later = tonumber(a) or 0, tonumber(b) or 0
			now += freed
			soon += later
			stats.byGiver[g.name] = (stats.byGiver[g.name] or 0) + freed
		else
			warn(`[MeshBudget] {g.name} failed to give: {a}`)
		end
	end
	stats.freedNow += now
	stats.freeingSoon += soon
	if now <= 0 and soon <= 0 then
		stats.refused += 1
	end
	return now, soon
end

-- Whether a reason a mesh could not be made is this client being out of mesh memory (and not
-- a fault in the code that made it).
function MeshBudget.isShort(reason: any): boolean
	local r = string.lower(tostring(reason))
	return string.find(r, "budget", 1, true) ~= nil or string.find(r, "would not make", 1, true) ~= nil
end

function MeshBudget.DebugState()
	local names = {}
	for _, g in givers do
		table.insert(names, g.name)
	end
	return {
		givers = names,
		asks = stats.asks,
		freedNow = stats.freedNow,
		freeingSoon = stats.freeingSoon,
		refused = stats.refused,
		byGiver = table.clone(stats.byGiver),
	}
end

return MeshBudget
