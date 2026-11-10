--!strict
-- MeshRig: an imported, rigged mesh car built from its data table into a v2 `Shell`
-- (CONTRACTS.md "The car rig", T-111). The data is a module like `Shared/Cars/Liftback`:
-- its surfaces, its moving parts and their pivots, its points and its mesh pieces. Nothing
-- here is any particular car.
--
-- Every piece is a MeshPart made through `AssetService:CreateMeshPartAsync` (a MeshPart
-- cannot be given a mesh after it exists), all of them at once, so it yields: about a
-- second cold for the liftback's 168. `Shared/CarModel` builds one template per body and
-- clones it per car, so this runs once per server.
--
-- A piece `<Part>_<Surface>` goes into the group its part names: the part's own if it
-- moves, the group a static part rides (`into`), or the `Body`. Every wheel gets a hub at
-- its centre, steering if the wheel says so; the calipers ride the hubs. Each piece carries
-- its surface's look and the attributes `Paint` (`body`, `second`, `rim`, `tyre`, `none`),
-- `Surface` and `Part`. `Rig.assemble` anchors it and takes it out of physics.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rig = require(script.Parent.Rig)

local MeshRig = {}

-- How long the meshes get, all together.
MeshRig.MESH_TIMEOUT = 30

-- Every piece is turned half a turn about Y: the importer read the file facing +Z.
local TURN = CFrame.Angles(0, math.pi, 0)

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- The scale the car is built at, and the drop from the ground to the car's frame.
function MeshRig.frame(data: any): (number, number)
	local C = Config.Drift
	return C.Wheelbase / data.measured.wheelbase, C.RideHeight
end

-- A point from the data's ground frame into the car's frame.
function MeshRig.point(data: any, t: { number }): Vector3
	local s, ride = MeshRig.frame(data)
	return v3(t) * s - Vector3.new(0, ride, 0)
end

local function fetch(pieces: any): { [number]: MeshPart }
	local made: { [number]: MeshPart } = {}
	local pending = 0
	for _, d in pieces do
		local id = d[2]
		pending += 1
		task.spawn(function()
			local ok, res = pcall(function()
				return AssetService:CreateMeshPartAsync(`rbxassetid://{id}`, {
					CollisionFidelity = Enum.CollisionFidelity.Box,
					RenderFidelity = Enum.RenderFidelity.Automatic,
				})
			end)
			if ok then
				made[id] = res
			end
			pending -= 1
		end)
	end
	local deadline = os.clock() + MeshRig.MESH_TIMEOUT
	while pending > 0 and os.clock() < deadline do
		task.wait()
	end
	return made
end

-- The group every piece goes in, by its part's name.
function MeshRig.groupOf(data: any, part: string): string
	local g = data.groups[part]
	if not g then
		return "Body"
	end
	return g.into or part
end

-- Build the shell. Returns it (nil if no piece loaded), how many pieces were built, and
-- how many would not load.
function MeshRig.build(data: any): (Model?, number, number)
	local s = MeshRig.frame(data)
	local meshes = fetch(data.pieces)

	local byGroup: { [string]: { BasePart } } = { Body = {} }
	local built, failed = 0, 0
	for _, d in data.pieces do
		local mp = meshes[d[2]]
		if not mp then
			failed += 1
			continue
		end
		local name: string = d[1]
		local partName, surfaceName = string.match(name, "^(%w+)_(%w+)$")
		local surface = data.surfaces[surfaceName or ""] or {}
		mp.Name = name
		mp.Size = Vector3.new(d[3], d[4], d[5]) * s
		mp.CFrame = CFrame.new(MeshRig.point(data, { d[6], d[7], d[8] })) * TURN
		local c = surface.colour or { 163, 162, 165 }
		mp.Color = Color3.fromRGB(c[1], c[2], c[3])
		mp.Material = (Enum.Material :: any)[surface.material or "SmoothPlastic"]
		mp.Reflectance = surface.reflectance or 0
		mp.Transparency = surface.transparency or 0
		mp.DoubleSided = surface.doubleSided == true
		mp.CastShadow = true
		mp:SetAttribute("Paint", surface.paint or "none")
		mp:SetAttribute("Surface", surfaceName)
		mp:SetAttribute("Part", partName)

		local group = MeshRig.groupOf(data, partName or "")
		byGroup[group] = byGroup[group] or {}
		table.insert(byGroup[group], mp)
		built += 1
	end
	if built == 0 then
		return nil, 0, failed
	end

	local names = {}
	for name, g in data.groups do
		if g.kind then
			table.insert(names, name)
		end
	end
	table.sort(names)

	local groups: { Rig.GroupSpec } = {}
	for _, name in names do
		local g = data.groups[name]
		local pivot = MeshRig.point(data, g.pivot)
		if g.kind == "spin" then
			-- the wheel's hub, at its centre: what lifts and steers it (CONTRACTS.md)
			local hub = Rig.hubOf(name)
			table.insert(groups, {
				name = hub,
				kind = "hub",
				pivot = pivot,
				steer = g.steer,
				wheel = name,
				parts = {},
			})
		end
		table.insert(groups, {
			name = name,
			kind = g.kind,
			pivot = pivot,
			axis = if g.axis then v3(g.axis) else nil,
			open = g.open,
			seconds = g.seconds,
			at = g.at,
			on = g.on,
			lamp = g.lamp,
			parts = byGroup[name] or {},
		})
	end

	local floor = {}
	for name, p in data.points.floor do
		floor[name] = MeshRig.point(data, p)
	end
	local shell = Rig.assemble({
		body = byGroup.Body,
		groups = groups,
		seat = CFrame.new(MeshRig.point(data, data.points.seat)),
		exit = CFrame.new(MeshRig.point(data, data.points.exit)),
		floor = floor,
	})
	return shell, built, failed
end

return MeshRig
