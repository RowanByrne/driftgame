local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

return function(): string
	local parts, meshes, models = 0, 0, 0
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			if d:IsA("MeshPart") then
				meshes += 1
			end
		elseif d:IsA("Model") then
			models += 1
		end
	end
	local folders = {}
	for _, child in Workspace:GetChildren() do
		if child:IsA("Folder") or child:IsA("Model") then
			local n = 0
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
				end
			end
			if n > 0 then
				table.insert(folders, { name = child.Name, n = n })
			end
		end
	end
	table.sort(folders, function(a, b)
		return a.n > b.n
	end)
	local top = {}
	for i = 1, math.min(5, #folders) do
		table.insert(top, `{folders[i].name} {folders[i].n}`)
	end
	return string.format(
		"Server: %d parts (%d mesh parts), %d models; %d instances in all. Most parts: %s.",
		parts,
		meshes,
		models,
		Stats.InstanceCount,
		if #top > 0 then table.concat(top, ", ") else "none"
	)
end
