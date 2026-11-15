--!strict
-- SplineParts: a stretch of the spline road laid as ordinary parts (features/spline-road.md,
-- T-134). Not the road the game draws -- that is a mesh (step 3) and the car never asks it
-- anything. This is the same surface cut into triangles the way the piece road cuts its
-- own (`Road/Builder.triangleSlab`), for two jobs:
--
--   * THE YARDSTICK. Built queryable and tagged `DriftSurface`, it is a road the live
--     world's rays and sweeps can drive on, so the spline world's answers can be checked
--     against the answers the game has always trusted, on the very same curve.
--   * A STAND-IN TO LOOK AT. Built with nothing queryable, it is something to see while the
--     car drives on the maths, before the mesh exists.
--
-- Cross-sections every `step` studs of road, each slice two triangles (four wedges), and an
-- upright barrier box per slice either side, inner face at exactly half the width as on the
-- piece road.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Builder = require(script.Parent.Builder)
local Spline = require(script.Parent.Spline)
local SurfaceCuts = require(script.Parent.SplineSurfaceCuts)
local Profile = require(script.Parent.SplineProfile)
local Hill = require(script.Parent.SplineHill)
local HillCuts = require(script.Parent.SplineHillCuts)
local Infield = require(script.Parent.SplineInfield)

local SplineParts = {}

export type Options = {
	step: number?, -- studs between cross-sections (default 4)
	queryable: boolean?, -- solid to rays and sweeps, and tagged as road (default false)
	barriers: boolean?, -- build the side barriers (default true)
	yieldEvery: number?, -- slices between task.wait()s; nil never yields
	terrain: boolean?, -- finite grass, banks and mountains, for the visual fallback
	omitHills: boolean?, -- retain supported ground/capped faces after a hill certification failure
	sliceMs: number?,
	cancelled: (() -> boolean)?,
}

local function point(spline: Spline.Spline, s: number, d: number): Vector3
	return Vector3.new(spline:surfaceXYZ(s, d))
end

local function terrain(spline:Spline.Spline,s0:number,s1:number,parent:Instance,o:Options):({BasePart},any)
	local R,T=Config.Road,Config.Spline.Terrain
	local out:{BasePart}={}
	local budget=(o.sliceMs or Config.Spline.Mesh.SliceMs)/1000
	local started=os.clock()
	local sliceStart,worst,slices=started,0,1
	local batch=Instance.new("Folder");batch.Name="TerrainSlices"
	local function flush()
		if #batch:GetChildren()>0 then batch.Parent=parent else batch:Destroy() end
		batch=Instance.new("Folder");batch.Name="TerrainSlices"
	end
	local function tick()
		if o.cancelled and o.cancelled() then batch:Destroy();error("terrain build cancelled") end
		local now=os.clock()
		if now-sliceStart>=budget or #batch:GetChildren()>=192 then
			flush()
			worst=math.max(worst,os.clock()-sliceStart)
			task.wait();sliceStart=os.clock();slices+=1
		end
	end
	local triangles,skippedHillTriangles=0,0
	local function tri(name:string,a:Vector3,b:Vector3,c:Vector3,colour:Color3,mat:Enum.Material,surface:string?)
		if (b-a):Cross(c-a).Magnitude<1e-7 then return end
		local side=tonumber(string.match(name,"^Hill_([%-]?%d+)_"))
		if side and (HillCuts.collapsed(a,b,c) or HillCuts.folded(a,b,c,side)) then skippedHillTriangles+=1;return end
		local made={}
		Builder.triangleSlab(name,a,b,c,.15,colour,mat,batch,made :: any)
		for _,p in made do
			p.CanCollide=false;p.CanTouch=false;p.CanQuery=o.queryable==true
			if o.queryable and surface then
				p:AddTag(Config.Drift.SurfaceTag);p:SetAttribute(Config.Drift.SurfaceAttribute,surface)
			end
			table.insert(out,p)
		end
		triangles+=1;tick()
	end
	local function quad(name:string,a:Vector3,b:Vector3,c:Vector3,d:Vector3,colour:Color3,mat:Enum.Material,surface:string?)
		tri(name.."a",a,b,c,colour,mat,surface)
		tri(name.."b",a,c,d,colour,mat,surface)
	end
	local across,grass=4,10
	local cuts=SurfaceCuts.sections(spline,s0,s1,.12,12,1,across,grass,tick)
	local prev,prevD=nil,nil
	for k,s in cuts do
		local ds=SurfaceCuts.offsets(spline,s,across,grass)
		local pts={}
		for j,d in ds do pts[j]=Vector3.new(spline:terrainXYZ(s,d)) end
		if prev and prevD then
			for j=1,#ds-1 do
				local tarmac=j>grass+1 and j<=grass+1+across
				local bevel=j==grass+1 or j==grass+across+2
				local side=if j<grass+2 then -1 else 1
				local gravel=bevel or (not tarmac and spline:gravelAt((s+cuts[k-1])*.5,side))
				local colour=if tarmac then R.Colours.Road elseif gravel then T.GravelColour else T.GrassColour
				local mat=if tarmac then R.RoadMaterial elseif gravel then Enum.Material.Pebble else Enum.Material.Grass
				quad(`Ground_{k}_{j}`,prev[j],prev[j+1],pts[j+1],pts[j],colour,mat,if tarmac then R.SurfaceTarmac else "grass")
			end
		end
		prev,prevD=pts,ds;tick()
	end
	-- Far scenery is coarser; its joins and face caps remain the existing hill's.
	local faces=cuts -- face feet share the supported ground's exact polyline
	local hill=Hill.context(spline,s0,s1,Profile.draw,tick,true)
	for k=1,#faces-1 do
		local a,b=faces[k],faces[k+1]
		if b-a<1e-5 then continue end
		for _,side in {-1,1} do
			local kind=spline:edgeAt((a+b)*.5,side)
			local ra,rb=Hill.ray(hill,a,side),Hill.ray(hill,b,side)
			local pa=Profile.draw(spline,a,side,kind,Hill.cap(ra))
			local pb=Profile.draw(spline,b,side,kind,Hill.cap(rb))
			for j=1,(if kind==Spline.ROCK then #pa-2 else #pa-1) do
				quad(`Face_{side}_{k}_{j}`,pa[j],pa[j+1],pb[j+1],pb[j],if kind==Spline.ROCK then T.RockColour else T.CliffColour,Enum.Material.Slate)
			end
			if o.omitHills then continue end
			Hill.finish(hill,ra);Hill.finish(hill,rb)
			local A,B=Hill.drawRings(spline,ra),Hill.drawRings(spline,rb)
			quad(`Hill_{side}_{k}_foot`,pa[5],A[1],B[1],pb[5],Config.Spline.Hill.Colour,Enum.Material.Grass)
			for j=1,#A-1 do
				if j==#A-1 and ra.free and rb.free then continue end
				quad(`Hill_{side}_{k}_{j}`,A[j],A[j+1],B[j+1],B[j],Config.Spline.Hill.Colour,Enum.Material.Grass)
			end
		end
	end
	flush();batch:Destroy()
	worst=math.max(worst,os.clock()-sliceStart)
	return out,{triangles=triangles,skippedHillTriangles=skippedHillTriangles,hillsOmitted=o.omitHills==true,sliceMs=worst*1000,slices=slices,ms=(os.clock()-started)*1000}
end

-- Lay road from s0 to s1 under `parent`. Returns the parts made.
function SplineParts.build(spline: Spline.Spline, s0: number, s1: number, parent: Instance, opts: Options?): ({ BasePart },any)
	local o: Options = opts or {}
	if o.terrain then return terrain(spline,s0,s1,parent,o) end
	local R = Config.Road
	local D = Config.Drift
	local step = o.step or 4
	local queryable = o.queryable == true
	local half = R.Width * 0.5
	local out: { BasePart } = {}
	local slices = math.max(1, math.ceil((s1 - s0) / step))
	local ds = (s1 - s0) / slices

	local folder = Instance.new("Folder")
	folder.Name = "Slices"
	local made = 0
	for i = 0, slices - 1 do
		local sa, sb = s0 + i * ds, s0 + (i + 1) * ds
		local la, ra = point(spline, sa, -half), point(spline, sa, half)
		local lb, rb = point(spline, sb, -half), point(spline, sb, half)
		local tris: { BasePart } = {}
		-- the diagonal alternates, as on the piece road, so no one edge carries the error
		if i % 2 == 0 then
			Builder.triangleSlab(`Road_{i}_1`, la, ra, rb, R.Thickness, R.Colours.Road, R.RoadMaterial, folder, tris :: any)
			Builder.triangleSlab(`Road_{i}_2`, la, rb, lb, R.Thickness, R.Colours.Road, R.RoadMaterial, folder, tris :: any)
		else
			Builder.triangleSlab(`Road_{i}_1`, la, ra, lb, R.Thickness, R.Colours.Road, R.RoadMaterial, folder, tris :: any)
			Builder.triangleSlab(`Road_{i}_2`, ra, rb, lb, R.Thickness, R.Colours.Road, R.RoadMaterial, folder, tris :: any)
		end
		for _, p in tris do
			p.CanQuery = queryable
			p.CanCollide = false
			p.CanTouch = false
			p.CastShadow = true -- T-178, as the mesh road
			if queryable then
				p:AddTag(D.SurfaceTag)
				p:SetAttribute(D.SurfaceAttribute, R.SurfaceTarmac)
			end
			table.insert(out, p)
		end
		if o.barriers ~= false then
			for _, side in { -1, 1 } do
				local off = side * (half + R.BarrierThickness * 0.5)
				local a = point(spline, sa, off)
				local b = point(spline, sb, off)
				-- upright, along the chord, standing from the road edge's height
				local ea = spline:heightAt(sa) + side * half * math.tan(spline:bankAt(sa))
				local eb = spline:heightAt(sb) + side * half * math.tan(spline:bankAt(sb))
				local base = (ea + eb) * 0.5
				local mid = Vector3.new((a.X + b.X) * 0.5, base + (R.BarrierHeight - R.BarrierSink) * 0.5, (a.Z + b.Z) * 0.5)
				local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
				local len = flat.Magnitude
				local cf = CFrame.lookAt(mid, mid + flat, Vector3.yAxis)
				local wall = Instance.new("Part")
				wall.Name = `Barrier_{if side < 0 then "L" else "R"}_{i}`
				wall.Anchored = true
				wall.CanCollide = false
				wall.CanTouch = false
				wall.CanQuery = queryable
				wall.CastShadow = true -- T-178, as the mesh road's barriers
				wall.Material = R.BarrierMaterial
				wall.Color = R.Colours.Barrier
				-- a little long, so neighbouring slices overlap rather than leave a slot
				wall.Size = Vector3.new(R.BarrierThickness, R.BarrierHeight + R.BarrierSink + math.abs(eb - ea), len + 0.3)
				wall.CFrame = cf
				wall.Parent = folder
				table.insert(out, wall)
			end
		end
		made += 1
		if o.yieldEvery and made % o.yieldEvery == 0 then
			folder.Parent = parent
			folder = Instance.new("Folder")
			folder.Name = "Slices"
			task.wait()
		end
	end
	folder.Parent = parent
	return out
end

function SplineParts.buildInfield(spline:Spline.Spline,x:number,z:number,radius:number,parent:Instance,opts:any?):(Model?,any)
	local o=opts or {}
	local started=os.clock()
	if not spline.infields then return nil,"empty" end
	local selected=Infield.near(spline.infields,x,z,radius,o.supportedOnly)
	if #selected==0 then return nil,"empty" end
	local model=Instance.new("Model");model.Name="InfieldParts";model:SetAttribute("Infield",true)
	model:SetAttribute("InfieldRevision",spline.infieldRevision or 0)
	local batch=Instance.new("Folder");batch.Name="FieldSlices"
	local sliceStart=started
	local paused,worst,slices,count,triangles=0,0,1,0,0
	local budget=(o.sliceMs or Config.Spline.Mesh.SliceMs)/1000
	local function tick()
		if o.cancelled and o.cancelled() then error("infield Parts build cancelled") end
		local now=os.clock()
		if now-sliceStart>=budget or #batch:GetChildren()>=192 then
			batch.Parent=model
			batch=Instance.new("Folder");batch.Name="FieldSlices"
			worst=math.max(worst,os.clock()-sliceStart)
			local before=os.clock();task.wait();local after=os.clock()
			paused+=after-before;sliceStart=after;slices+=1
		end
	end
	local ok,err=xpcall(function()
		local T=Config.Spline.Terrain
		for i,t in selected do
			tick()
			local a,b,c=t.a.p,t.b.p,t.c.p
			local made={}
			local colour=if t.supported then T.GrassColour else T.RockColour
			Builder.triangleSlab(`Infield_{i}`,Vector3.new(a[1],a[2],a[3]),Vector3.new(b[1],b[2],b[3]),Vector3.new(c[1],c[2],c[3]),
				.1,colour,if t.supported then Enum.Material.Grass else Enum.Material.Slate,batch,made :: any)
			for _,p in made do
				p.CanCollide=o.collidable==true and t.supported;p.CanTouch=false;p.CanQuery=o.queryable==true
				p.CastShadow=o.collidable~=true
				if o.collidable then p.Transparency=1 end
				count+=1
			end
			triangles+=1
		end
		tick();batch.Parent=model;model.Parent=parent
	end,debug.traceback)
	if not ok then batch:Destroy();model:Destroy();return nil,tostring(err) end
	worst=math.max(worst,os.clock()-sliceStart)
	return model,{triangles=triangles,parts=count,ms=(os.clock()-started-paused)*1000,sliceMs=worst*1000,slices=slices}
end

return SplineParts
