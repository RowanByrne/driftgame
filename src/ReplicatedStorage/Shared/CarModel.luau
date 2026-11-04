--!strict
-- CarModel: the car, built by code, shared so the server and client agree on it
-- (docs/game/features/drift-model.md "Art and sound").
--
-- There are two bodies and the simulation cannot tell them apart:
--
--   `ae86`  the car the user added to the Main place, read out of it and written down in
--           `Shared/Cars/AE86`. 98 parts of shell and wheels, scaled onto the config.
--   `block` the original: a box and four cylinders, our own shape. Still here because a
--           place whose meshes will not load still has to run, and because the tests need
--           something that cannot fail to build.
--
-- EITHER WAY the car's shape to the rest of the game is identical: a BasePart named `Body`
-- and four named `WheelFL`/`FR`/`RL`/`RR`, at exactly `wheelOffsets()`. The simulation's
-- ground rays, `Render`, the camera and the tests all go through those five parts and
-- never look at the shell. With a shell present the five are simply made invisible and a
-- `Shell` model of matching groups rides along, pivoted by `Render` to the same places.
--
-- HARD RULE (docs/game/DECISIONS.md, 2026-11-03): Roblox physics never moves this car.
-- Every part is anchored, and the model holds no BodyMover, VectorForce, AlignPosition,
-- AlignOrientation, constraint, joint or seat. DriftTests asserts it, because this is the
-- rule most easily broken later -- and the AE86 arrived as a fully scripted A-Chassis
-- vehicle, which is exactly how it gets broken.
--
-- MeshParts cannot be given a mesh after they exist (`MeshId` is not writable from a
-- script), so the shell is built once through `AssetService:CreateMeshPartAsync`, which
-- yields, and cloned per car. The server starts that the moment this module loads, long
-- before anyone can join, so `build()` almost never waits.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local CarModel = {}

CarModel.WHEEL_NAMES = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }
CarModel.BODY_NAME = "Body"
CarModel.SHELL_NAME = "Shell"

-- The bodies this game can build, and the module in `Shared/Cars` each reads.
CarModel.BODIES = { ae86 = "AE86" }

-- Which one a car is built with. `Config.Drift.CarBody` decides it; this is the fallback
-- if that key is ever absent.
--
-- A BODY IS NOT A CAR. Which shape is drawn and which archetype is driven are separate
-- axes on purpose (`Shared/Cars`, docs/game/features/car-archetypes.md): any body may
-- wear any archetype's numbers, which is how an archetype is driven before its art
-- exists. Nothing in here reads the active car except through `Config.Drift`, which is
-- where the geometry the shell is scaled onto comes from.
local DEFAULT_BODY = "ae86"
local bodyOverride: string? = nil

-- How long `build()` will wait for the shell before giving up and handing back a block,
-- and how long the meshes themselves get. Cold, every mesh is a download; measured, the
-- 82 of them take about 15 s one after another and about a second all at once, which is
-- why they are fetched together below.
local SHELL_TIMEOUT = 40
local MESH_TIMEOUT = 30

-- Where each wheel sits, relative to the car's origin. Front is -Z (the look vector).
function CarModel.wheelOffsets(): { [string]: Vector3 }
	local C = Config.Drift
	local halfBase = C.Wheelbase * 0.5
	local halfTrack = C.TrackWidth * 0.5
	local y = C.WheelDiameter * 0.5 - C.RideHeight
	return {
		WheelFL = Vector3.new(-halfTrack, y, -halfBase),
		WheelFR = Vector3.new(halfTrack, y, -halfBase),
		WheelRL = Vector3.new(-halfTrack, y, halfBase),
		WheelRR = Vector3.new(halfTrack, y, halfBase),
	}
end

function CarModel.isFrontWheel(name: string): boolean
	return name == "WheelFL" or name == "WheelFR"
end

-- Which body the next car gets.
function CarModel.bodyName(): string
	if bodyOverride then
		return bodyOverride
	end
	local configured = (Config.Drift :: any).CarBody
	if type(configured) == "string" then
		return configured
	end
	return DEFAULT_BODY
end

-- Tests and the user's own switch: `setBody("block")` puts the box back, `setBody(nil)`
-- hands the choice back to the config.
function CarModel.setBody(name: string?)
	bodyOverride = name
end

local function newPart(name: string, size: Vector3, colour: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = colour
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true -- never physics
	part.CanCollide = false -- our own sweep handles walls
	part.CanQuery = false -- our own ground rays must not hit the car
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- ---------------------------------------------------------------------- the shell

-- The scales the shell is built at. The config is the truth and the model is not: the
-- AE86 is a real car's proportions and the config's body box is not, so the two cannot
-- both be honoured by one number (T-020, and the report).
--
-- `Wheelbase` sets the body's scale, because the wheel arches have to land on the wheels
-- the simulation actually rays from. `WheelDiameter` sets the wheels' own, so each one
-- touches the road exactly. The two come out within 1.5% of each other, so nothing looks
-- stretched -- but they are kept apart deliberately, so a config change moves the right
-- thing and the gap at each corner stays zero.
local function scales(measured): (number, number)
	local C = Config.Drift
	return C.Wheelbase / measured.wheelbase, C.WheelDiameter / measured.wheelDiameter
end

local function toCFrame(d, scale: number): CFrame
	local p = d.p
	local r = d.r
	if r then
		return CFrame.new(
			p[1] * scale,
			p[2] * scale,
			p[3] * scale,
			r[1],
			r[2],
			r[3],
			r[4],
			r[5],
			r[6],
			r[7],
			r[8],
			r[9]
		)
	end
	return CFrame.new(p[1] * scale, p[2] * scale, p[3] * scale)
end

-- A SurfaceAppearance's maps can only be written by a plugin ("lacking capability
-- Plugin"), so a running game cannot make one -- and this car has 33. What it CAN write is
-- a MeshPart's `TextureID`, and a colour map is exactly that: the albedo, in the mesh's own
-- UVs. So the colour map becomes the texture and the normal, metalness and roughness maps
-- are dropped. The car keeps its paint and its markings and loses its PBR shading, which on
-- a placeholder is nothing. (The alternative is shipping 33 SurfaceAppearance instances in
-- an .rbxmx for Lync to sync and cloning those; it is worth it only if the user wants the
-- extra depth -- see the report.)
-- Asset ids the car carries that Roblox will not serve us: "Asset is not approved for the
-- requester", once per part per join. They are left in `Shared/Cars/AE86` because that
-- file is the record of what the model actually had; they are skipped here because the
-- part looks the same without them and the console should not.
--   1539341292  the brake caliper's texture. The caliper keeps its colour
local DENIED = {
	["rbxassetid://1539341292"] = true,
}

local function colourMap(kids): string?
	if not kids then
		return nil
	end
	for _, k in kids do
		if k.k == "sa" and k.cm ~= "" then
			return k.cm
		end
	end
	return nil
end

local function addKids(part: BasePart, kids)
	if not kids then
		return
	end
	for _, k in kids do
		if k.k == "sa" then
			-- handled by `colourMap`, above: nothing to make here
		elseif (k.k == "tex" or k.k == "dec") and DENIED[k.t] then
			-- skipped, see DENIED
		elseif k.k == "tex" then
			local t = Instance.new("Texture")
			t.Texture = k.t
			t.Face = (Enum.NormalId :: any)[k.f]
			t.Transparency = k.tr
			t.Color3 = Color3.new(k.c[1], k.c[2], k.c[3])
			t.StudsPerTileU = k.su
			t.StudsPerTileV = k.sv
			t.OffsetStudsU = k.ou
			t.OffsetStudsV = k.ov
			t.Parent = part
		elseif k.k == "dec" then
			local dec = Instance.new("Decal")
			dec.Texture = k.t
			dec.Face = (Enum.NormalId :: any)[k.f]
			dec.Transparency = k.tr
			dec.Color3 = Color3.new(k.c[1], k.c[2], k.c[3])
			dec.Parent = part
		elseif k.k == "sm" then
			local sm = Instance.new("SpecialMesh")
			sm.MeshType = (Enum.MeshType :: any)[k.mt]
			sm.MeshId = k.id
			sm.TextureId = k.tid
			sm.Scale = Vector3.new(k.sc[1], k.sc[2], k.sc[3])
			sm.Offset = Vector3.new(k.off[1], k.off[2], k.off[3])
			sm.VertexColor = Vector3.new(k.vc[1], k.vc[2], k.vc[3])
			sm.Parent = part
		elseif k.k == "mesh" then
			local mesh = Instance.new(k.cls) :: any
			mesh.Scale = Vector3.new(k.sc[1], k.sc[2], k.sc[3])
			mesh.Offset = Vector3.new(k.off[1], k.off[2], k.off[3])
			mesh.Parent = part
		end
	end
end

-- Every distinct mesh the body needs, fetched all at once. A MeshPart cannot be given a
-- mesh after it exists, so each id is turned into one prototype part here and cloned
-- wherever the body uses it. Serially this is the slowest thing in the build by far; in
-- parallel it is about a second, cold.
local function fetchMeshes(data): { [string]: MeshPart }
	local wanted: { [string]: boolean } = {}
	local function collect(list)
		for _, d in list do
			if d.c == "MeshPart" then
				wanted[d.mesh] = true
			end
		end
	end
	collect(data.shell)
	for _, name in CarModel.WHEEL_NAMES do
		collect(data.wheels[string.sub(name, 6)])
	end

	local made: { [string]: MeshPart } = {}
	local pending = 0
	for id in wanted do
		pending += 1
		task.spawn(function()
			local ok, res = pcall(function()
				return AssetService:CreateMeshPartAsync(id, {
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
	local deadline = os.clock() + MESH_TIMEOUT
	while pending > 0 and os.clock() < deadline do
		task.wait()
	end
	return made
end

-- One shell part. `at` is the frame the part's recorded place is relative to, already in
-- the group's own coordinates. Returns nil only when a mesh will not load.
local function shellPart(d, scale: number, at: CFrame, meshes: { [string]: MeshPart }): BasePart?
	local part: BasePart
	if d.c == "MeshPart" then
		local prototype = meshes[d.mesh]
		if not prototype then
			return nil
		end
		local mp = prototype:Clone()
		local texture = d.tex or colourMap(d.kids)
		if texture and not DENIED[texture] then
			mp.TextureID = texture
		end
		mp.DoubleSided = d.ds == true
		part = mp
	else
		local p = Instance.new("Part")
		if d.shape then
			p.Shape = (Enum.PartType :: any)[d.shape]
		end
		part = p
	end

	part.Name = d.n
	part.Size = Vector3.new(d.s[1], d.s[2], d.s[3]) * scale
	local offset = at * toCFrame(d, scale)
	part.CFrame = offset
	-- Where this part sits in its group, written down rather than inferred. `Render` reads
	-- it once and then writes every shell part an ABSOLUTE CFrame each frame, the same way
	-- it already writes the five simulation parts.
	--
	-- Moving the group with `Model:PivotTo` instead looks right and is wrong: a shell part
	-- belongs to the server, the server re-asserts its CFrame, and a pivot is a DELTA, so
	-- each re-assertion is applied again and the shell walks away from the car. Measured,
	-- it was 2 500 studs out inside a minute. An absolute write cannot drift.
	part:SetAttribute("L", offset)
	part.Color = Color3.new(d.col[1], d.col[2], d.col[3])
	part.Material = (Enum.Material :: any)[d.m]
	part.Transparency = d.tr or 0
	part.Reflectance = d.rf or 0
	part.CastShadow = d.sh ~= false

	-- The five rules that keep a 98-part car out of Roblox's hands entirely.
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- the ground rays must not hit the car
	part.CanTouch = false
	part.Locked = true

	addKids(part, d.kids)
	return part
end

-- A group of shell parts, built about its own origin. Its pivot is set there too, which
-- `Render` does not use (it writes each part absolutely) but `car:PivotTo()` and Studio
-- both do, so the group moves sensibly with the car it is parented into.
local function shellGroup(
	name: string,
	parts,
	scale: number,
	at: CFrame,
	meshes: { [string]: MeshPart }
): (Model, number, number)
	local group = Instance.new("Model")
	group.Name = name
	local built, failed = 0, 0
	for _, d in parts do
		local part = shellPart(d, scale, at, meshes)
		if part then
			part.Parent = group
			built += 1
		else
			failed += 1
		end
	end
	group.WorldPivot = CFrame.identity
	-- How many parts to expect. A Model replicates before its contents, so a client has to
	-- know when it has all of them (Drift/Render, `resolve`).
	group:SetAttribute("N", built)
	return group, built, failed
end

local template: Model? = nil
local templateFor: string? = nil
local templateState = "none" -- none | building | ready | failed

-- Build the shell once. Yields: every mesh goes through `CreateMeshPartAsync`.
local function buildShell(name: string)
	local moduleName = CarModel.BODIES[name]
	local cars = ReplicatedStorage.Shared:FindFirstChild("Cars")
	local module = if moduleName and cars then cars:FindFirstChild(moduleName) else nil
	if not module or not module:IsA("ModuleScript") then
		warn(`[CarModel] no body '{name}' in Shared/Cars; the car is a block`)
		templateState = "failed"
		return
	end

	local okRequire, data = pcall(require, module)
	if not okRequire then
		warn(`[CarModel] body '{name}' would not load: {data}; the car is a block`)
		templateState = "failed"
		return
	end

	local meshes = fetchMeshes(data)
	local bodyScale, wheelScale = scales(data.measured)
	local shell = Instance.new("Model")
	shell.Name = CarModel.SHELL_NAME

	-- The shell's own origin is the centre of the four hubs, on the hub plane; the car's
	-- is `RideHeight` above the road. This is the one offset between them, and it is the
	-- same number the wheels are drawn at.
	local hubPlane = CFrame.new(0, Config.Drift.WheelDiameter * 0.5 - Config.Drift.RideHeight, 0)

	local built, failed = 0, 0
	local body, b, f = shellGroup(CarModel.BODY_NAME, data.shell, bodyScale, hubPlane, meshes)
	body.Parent = shell
	built += b
	failed += f
	task.wait()

	for _, wheelName in CarModel.WHEEL_NAMES do
		local key = string.sub(wheelName, 6) -- WheelFL -> FL
		local group, wb, wf = shellGroup(wheelName, data.wheels[key], wheelScale, CFrame.identity, meshes)
		group.Parent = shell
		built += wb
		failed += wf
		task.wait()
	end

	for _, prototype in meshes do
		prototype:Destroy()
	end
	shell.WorldPivot = CFrame.identity

	if failed > 0 then
		-- A third party's uploads: one of them being taken down is a real way for this to
		-- break (docs/workflow/PLATFORM-RISKS.md, "Copyright and trademarks").
		warn(`[CarModel] body '{name}': {failed} of {built + failed} meshes would not load`)
	end
	if built == 0 then
		shell:Destroy()
		templateState = "failed"
		return
	end

	template = shell
	templateState = "ready"
end

-- Anything that goes wrong in there has to end the wait, not outlive it: a thread that
-- dies half way leaves `build()` waiting the whole timeout for a shell that is never
-- coming, and every car after it too.
local function buildTemplate(name: string)
	templateState = "building"
	templateFor = name
	local ok, err = pcall(buildShell, name)
	if not ok then
		warn(`[CarModel] body '{name}' would not build: {err}; the car is a block`)
		templateState = "failed"
	elseif templateState == "building" then
		templateState = "failed"
	end
end

-- Start the build without waiting for it. The server calls this as soon as this module
-- loads, so the template is there before the first player is.
function CarModel.preload()
	if templateState == "none" or templateFor ~= CarModel.bodyName() then
		local name = CarModel.bodyName()
		if name ~= "block" then
			task.spawn(buildTemplate, name)
		end
	end
end

-- A shell for one car, or nil for a block car. Waits for the template only if the preload
-- has not finished.
function CarModel.shell(): Model?
	local name = CarModel.bodyName()
	if name == "block" then
		return nil
	end
	if templateFor ~= name then
		templateState = "none"
		template = nil
	end
	if templateState == "none" then
		task.spawn(buildTemplate, name)
	end
	local deadline = os.clock() + SHELL_TIMEOUT
	while templateState == "building" and os.clock() < deadline do
		task.wait()
	end
	if templateState ~= "ready" or not template then
		if templateState == "building" then
			warn(`[CarModel] body '{name}' took longer than {SHELL_TIMEOUT}s; this car is a block`)
		end
		return nil
	end
	return (template :: Model):Clone()
end

-- ---------------------------------------------------------------------- the car

-- A fresh car model at the origin. The caller parents it and pivots it into place.
function CarModel.build(): Model
	local C = Config.Drift

	local model = Instance.new("Model")
	model.Name = "Car"

	local body = newPart("Body", Vector3.new(C.BodyWidth, C.BodyHeight, C.BodyLength), Color3.fromRGB(196, 62, 54))
	body.Parent = model
	model.PrimaryPart = body

	-- A Roblox cylinder's axis runs along its local X, which is the car's right, so a wheel
	-- needs no extra rotation to sit the right way round.
	local wheelSize = Vector3.new(C.WheelWidth, C.WheelDiameter, C.WheelDiameter)
	for name, offset in CarModel.wheelOffsets() do
		local wheel = newPart(name, wheelSize, Color3.fromRGB(28, 28, 32))
		wheel.Shape = Enum.PartType.Cylinder
		wheel.CFrame = CFrame.new(offset)
		wheel.Parent = model
	end

	local shell = CarModel.shell()
	if shell then
		-- The five simulation parts stay, exactly where they were: everything else in the
		-- game still finds the car through them. They just stop being what you see.
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				part.Transparency = 1
				part.CastShadow = false
			end
		end
		shell.Parent = model
		-- An attribute arrives with the Model itself, ahead of its hundred parts, so a
		-- client that catches the car mid-replication knows to wait for a shell rather
		-- than deciding there is not one (Drift/Render, `resolve`).
		model:SetAttribute(CarModel.SHELL_NAME, true)
	end

	model:PivotTo(CFrame.identity)
	return model
end

-- ---------------------------------------------------------------------- the rules

-- Everything in a car model that would hand it back to Roblox physics. Empty is the rule.
function CarModel.physicsOffenders(model: Instance): { string }
	local offenders = {}
	for _, d in model:GetDescendants() do
		if
			d:IsA("BodyMover")
			or d:IsA("Constraint")
			or d:IsA("JointInstance")
			or d:IsA("Motor")
			or d:IsA("WeldConstraint")
			or d:IsA("NoCollisionConstraint")
		then
			table.insert(offenders, `{d:GetFullName()} is a {d.ClassName}`)
		elseif d:IsA("Seat") or d:IsA("VehicleSeat") then
			-- A seat drives itself and carries a player: both are physics by another name,
			-- and the AE86 arrived with one.
			table.insert(offenders, `{d:GetFullName()} is a {d.ClassName}`)
		elseif d:IsA("BasePart") and not d.Anchored then
			table.insert(offenders, `{d:GetFullName()} is not anchored`)
		end
	end
	return offenders
end

-- Everything that is not physics but has no business in a car either: the scripts, sounds,
-- lights and emitters the user asked to be rid of ("ditch all the scripts attached to
-- it"). Kept apart from `physicsOffenders` because breaking this one is untidy, not fatal.
function CarModel.strayOffenders(model: Instance): { string }
	local offenders = {}
	for _, d in model:GetDescendants() do
		if
			d:IsA("LuaSourceContainer")
			or d:IsA("Sound")
			or d:IsA("ParticleEmitter")
			or d:IsA("Light")
			or d:IsA("Smoke")
			or d:IsA("Fire")
			or d:IsA("Trail")
			or d:IsA("Beam")
			or d:IsA("ClickDetector")
			or d:IsA("ProximityPrompt")
			or d:IsA("LayerCollector")
			or d:IsA("RemoteEvent")
			or d:IsA("RemoteFunction")
			or d:IsA("BindableEvent")
			or d:IsA("BindableFunction")
			or d:IsA("Attachment")
		then
			table.insert(offenders, `{d:GetFullName()} is a {d.ClassName}`)
		end
	end
	return offenders
end

-- The server owns every car, so it is the one that pays for the shell, once, at boot.
if RunService:IsServer() then
	CarModel.preload()
end

return CarModel
