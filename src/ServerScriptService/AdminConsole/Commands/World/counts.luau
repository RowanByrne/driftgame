local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

-- What's in the Workspace, by kind. The road's mesh, the horizon and the sky's pieces are
-- made on each client, so the client's numbers are the ones a player's frame pays for.
local function count(): string
	local parts, meshes, unions, anchoredOff, models = 0, 0, 0, 0, 0
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			if d:IsA("MeshPart") then
				meshes += 1
			elseif d:IsA("UnionOperation") then
				unions += 1
			end
			if not d.Anchored then
				anchoredOff += 1
			end
		elseif d:IsA("Model") then
			models += 1
		end
	end
	return string.format(
		"%d parts (%d mesh parts, %d unions, %d unanchored), %d models; %d instances in all, %d primitives",
		parts,
		meshes,
		unions,
		anchoredOff,
		models,
		Stats.InstanceCount,
		Stats.PrimitivesCount
	)
end

return {
	Name = "counts",
	Description = "Counts the parts, mesh parts and models in the Workspace, on your screen and on the server.",
	Group = "World",
	Args = {},
	ClientRun = function(context)
		context:Reply(`Client: {count()}.`)
		return nil -- and the server's own count
	end,
}
