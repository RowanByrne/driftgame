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
local FieldCuts = require(script.Parent.SplineFieldCuts)

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
	fieldPlan: FieldCuts.Plan?,
	captureScenery: boolean?,
	groundOnly: boolean?, -- supported asphalt/lip/banks without new mountain scenery
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
			if o.cancelled and o.cancelled() then batch:Destroy();error("terrain build cancelled") end
		end
	end
	local triangles,skippedHillTriangles=0,0
	if o.fieldPlan and o.fieldPlan.identity~=spline.infields then batch:Destroy();error("field coverage belongs to another road") end
	local fieldContext=if o.fieldPlan then FieldCuts.forBuild(o.fieldPlan,tick) else nil
	local scenery:any=if o.captureScenery or fieldContext then {} else nil
	local fieldCutTriangles=0
	local function tri(name:string,a:Vector3,b:Vector3,c:Vector3,colour:Color3,mat:Enum.Material,surface:string?)
		if (b-a):Cross(c-a).Magnitude<1e-7 then return end
		local side=tonumber(string.match(name,"^Hill_([%-]?%d+)_"))
		if side and (HillCuts.collapsed(a,b,c) or HillCuts.folded(a,b,c,side)) then skippedHillTriangles+=1;return end
		local pieces=nil
		if not surface and (scenery or fieldContext) then
			local points={{a.X,a.Y,a.Z},{b.X,b.Y,b.Z},{c.X,c.Y,c.Z}}
			if scenery then
				if #scenery>=24576 then batch:Destroy();error("field scenery source limit") end
				for _,p in points do table.freeze(p) end
				table.insert(scenery,table.freeze({points=table.freeze(points),material=table.freeze({colour=colour}),kind=name}))
			end
			if fieldContext then
				local changed,why
				pieces,changed,why=FieldCuts.triangle(fieldContext,points[1],points[2],points[3])
				if not pieces then batch:Destroy();error(`field Parts scenery cut failed: {why}`) end
				if changed then fieldCutTriangles+=1 end
			end
		end
		local function emit(points:{{number}}?)
			local made={}
			if points then made=SplineParts.exactTriangle(points,.15,batch,name,colour,mat)
			else Builder.triangleSlab(name,a,b,c,.15,colour,mat,batch,made :: any) end
			for _,p in made do
				p.CanCollide=false;p.CanTouch=false;p.CanQuery=o.queryable==true
				if o.queryable and surface then
					p:AddTag(Config.Drift.SurfaceTag);p:SetAttribute(Config.Drift.SurfaceAttribute,surface)
				end
				table.insert(out,p)
			end
			triangles+=1;tick()
		end
		if pieces then for _,points in pieces do emit(points) end else emit(nil) end
		tick() -- wholly removed faces still consume clipping work and must yield
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
	if o.groundOnly then
		flush();batch:Destroy();worst=math.max(worst,os.clock()-sliceStart)
		return out,{triangles=triangles,groundOnly=true,sliceMs=worst*1000,slices=slices,ms=(os.clock()-started)*1000}
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
	return out,{triangles=triangles,skippedHillTriangles=skippedHillTriangles,hillsOmitted=o.omitHills==true,
		scenery=if scenery then table.freeze(scenery) else nil,fieldCutTriangles=fieldCutTriangles,
		sliceMs=worst*1000,slices=slices,ms=(os.clock()-started)*1000}
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

-- A field's finite perimeter and retirement cut must not inherit the ordinary
-- road slab's outward triangle growth. Split in local coordinates before packing.
local function infieldSlab(t:any,thickness:number,parent:Instance,name:string):{BasePart}
	local a,b,c=t.a.p,t.b.p,t.c.p
	local origin=Vector3.new(a[1],a[2],a[3])
	local U,V,W=Vector3.zero,Vector3.new(b[1]-a[1],b[2]-a[2],b[3]-a[3]),Vector3.new(c[1]-a[1],c[2]-a[2],c[3]-a[3])
	local ab,bc,ca=(V-U).Magnitude,(W-V).Magnitude,(U-W).Magnitude
	if bc>=ab and bc>=ca then U,V,W=V,W,U elseif ca>=ab and ca>=bc then U,V,W=W,U,V end
	local edge=V-U;local length=edge.Magnitude
	if length<.001 then return {} end
	local along=edge/length;local distance=(W-U):Dot(along)
	local foot=U+along*distance;local rise=W-foot;local height=rise.Magnitude
	if height<.001 then return {} end
	local up=rise/height;local normal=along:Cross(up)
	if normal.Y<0 then normal=-normal end
	local out={}
	local function wedge(suffix:string,direction:Vector3,width:number)
		if width<.001 then return end
		local u,pdir,ly,lz
		if direction:Cross(up):Dot(normal)>0 then u,pdir,ly,lz=up,direction,height,width
		else u,pdir,ly,lz=direction,up,width,height end
		local centre=foot+u*(ly*.5)+pdir*(lz*.5)-normal*(thickness*.5)
		local p=Instance.new("WedgePart");p.Name=name..suffix;p.Anchored=true
		p.Size=Vector3.new(thickness,ly,lz);p.CFrame=CFrame.new(origin)*CFrame.fromMatrix(centre,normal,u)
		p.Color=Config.Spline.Terrain.GrassColour;p.Material=Enum.Material.Grass;p.Parent=parent
		table.insert(out,p)
	end
	wedge("a",-along,distance);wedge("b",along,length-distance)
	return out
end

-- Visual triangles on a finite cut must not grow back across that cut.
function SplineParts.exactTriangle(points:{{number}},thickness:number,parent:Instance,name:string,colour:Color3,material:Enum.Material):{BasePart}
	local made=infieldSlab({a={p=points[1]},b={p=points[2]},c={p=points[3]}},thickness,parent,name)
	for _,p in made do p.Color=colour;p.Material=material;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false end
	return made
end

function SplineParts.buildInfield(spline:Spline.Spline,x:number,z:number,radius:number,parent:Instance,opts:any?):(Model?,any)
	local o=opts or {}
	local started=os.clock()
	if not spline.infields then return nil,"empty" end
	local first=o.first or spline.firstSample*spline.step
	if o.plan and (o.plan.identity~=spline.infields or o.plan.first~=first) then return nil,"field coverage belongs to another road or retained first" end
	local selected=if o.plan then o.plan.triangles else Infield.near(spline.infields,x,z,radius,o.supportedOnly,first)
	if o.plan and o.supportedOnly then
		local supported={};for _,t in selected do if t.supported then table.insert(supported,t) end end;selected=supported
	end
	local seams=if o.collidable or o.supportedOnly then {} else o.seams or {}
	if #selected==0 then return nil,"empty" end
	if o.maxTriangles and #selected>o.maxTriangles then return nil,"infield warm support exceeds its triangle bound" end
	local model=Instance.new("Model");model.Name="InfieldParts";model:SetAttribute("Infield",true)
	model:SetAttribute("InfieldRevision",if o.plan then o.plan.revision else spline.infieldRevision or 0)
	model:SetAttribute("InfieldCoverage",if o.plan then o.plan.key else "near")
	model:SetAttribute("InfieldFirst",first)
	model:SetAttribute("InfieldX",x);model:SetAttribute("InfieldZ",z);model:SetAttribute("InfieldRadius",radius)
	local batch=Instance.new("Folder");batch.Name="FieldSlices"
	local sliceStart=started
	local paused,worst,slices,count,triangles=0,0,1,0,0
	local budget=(o.sliceMs or Config.Spline.Mesh.SliceMs)/1000
	local function tick()
		if o.cancelled and o.cancelled() then error("infield Parts build cancelled") end
		if o.noYield then return end
		local now=os.clock()
		if now-sliceStart>=budget or #batch:GetChildren()>=192 then
			batch.Parent=model
			batch=Instance.new("Folder");batch.Name="FieldSlices"
			worst=math.max(worst,os.clock()-sliceStart)
			local before=os.clock();task.wait();local after=os.clock()
			paused+=after-before;sliceStart=after;slices+=1
			if o.cancelled and o.cancelled() then error("infield Parts build cancelled") end
		end
	end
	local ok,err=xpcall(function()
		local T=Config.Spline.Terrain
		for i,t in selected do
			if o.supportedOnly and not t.supported then continue end
			tick()
			local made=infieldSlab(t,if o.collidable then Config.Spline.Biomes.Infield.Walking.Thickness else .1,batch,`Infield_{i}`)
			local colour=if t.supported then T.GrassColour else T.RockColour
			for _,p in made do
				p.Color=colour;p.Material=if t.supported then Enum.Material.Grass else Enum.Material.Slate
				p.CanCollide=o.collidable==true and t.supported;p.CanTouch=false;p.CanQuery=o.queryable==true
				p.CastShadow=o.collidable~=true
				if o.collidable then p.Transparency=1 end
				count+=1
			end
			triangles+=1
		end
		for i,seam in seams do
			tick()
			local t={a={p=seam.points[1]},b={p=seam.points[2]},c={p=seam.points[3]}}
			local made=infieldSlab(t,.1,batch,`InfieldSeam_{i}`)
			local material=seam.material
			local colour=if typeof(material)=="Color3" then material elseif type(material)=="table" and typeof(material.colour)=="Color3" then material.colour else T.RockColour
			for _,p in made do
				p.Color=colour;p.Material=Enum.Material.Slate;p.CanCollide=false;p.CanTouch=false;p.CanQuery=o.queryable==true
				p.CastShadow=true;count+=1
			end
			triangles+=1
		end
		tick();batch.Parent=model;model.Parent=parent
	end,debug.traceback)
	if not ok then batch:Destroy();model:Destroy();return nil,tostring(err) end
	worst=math.max(worst,os.clock()-sliceStart)
	model:SetAttribute("InfieldParts",count)
	return model,{triangles=triangles,parts=count,seamTriangles=#seams,ms=(os.clock()-started-paused)*1000,sliceMs=worst*1000,slices=slices}
end

-- Immediate support is about accepted geometry, not just a model's radius.
-- A newer disjoint patch can arrive inside an older model's nominal box.
function SplineParts.warmInfield(spline:any,x:number,z:number,parent:Instance,old:Model?,opts:any?):(Model?,any)
	local o=opts or {};local W=Config.Spline.Biomes.Infield.Walking
	local first=spline.firstSample*spline.step
	local floors={}
	if spline.infields then
		for _,dx in {-W.WarmFootprint,0,W.WarmFootprint} do for _,dz in {-W.WarmFootprint,0,W.WarmFootprint} do
			local floor=Infield.sample(spline.infields,x+dx,z+dz)
			if floor and floor.closingS>=first then table.insert(floors,{x=x+dx,z=z+dz,y=floor.y}) end
		end end
	end
	if #floors==0 then return old,{ready=true,reused=true,needed=false} end
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
	local function supported(model:Model):boolean
		params.FilterDescendantsInstances={model}
		for _,floor in floors do
			local found=false
			for _,offset in {{0,0},{.005,0},{-.005,0},{0,.005},{0,-.005}} do
				local hit=workspace:Raycast(Vector3.new(floor.x+offset[1],floor.y+1,floor.z+offset[2]),Vector3.new(0,-2,0),params)
				-- Adjacent triangles can win a shared crease. A tiny ray whisker
				-- covers packing hairlines, far smaller than an avatar's foot.
				if hit and hit.Normal.Y>.8 and math.abs(hit.Position.Y-floor.y)<=W.SupportTolerance then found=true;break end
			end
			if not found then return false end
		end
		return true
	end
	if old and old:IsDescendantOf(parent) and old:GetAttribute("InfieldFirst")==first
		and old:GetAttribute("InfieldRevision")==spline.infieldRevision then
		local radius=old:GetAttribute("InfieldRadius") :: number
		local margin=W.WarmFootprint+W.WarmMotionMargin
		if math.abs(x-(old:GetAttribute("InfieldX") :: number))<=radius-margin
			and math.abs(z-(old:GetAttribute("InfieldZ") :: number))<=radius-margin and supported(old) then
			return old,{ready=true,reused=true,needed=true,parts=old:GetAttribute("InfieldParts")}
		end
	end
	local radius=W.WarmRadius;local failure="immediate field support is unavailable"
	repeat
		local model,info=SplineParts.buildInfield(spline,x,z,radius,parent,{supportedOnly=true,collidable=true,queryable=true,
			first=first,noYield=true,maxTriangles=o.maxTriangles or W.WarmTriangles,cancelled=o.cancelled})
		if model then
			if info.parts>0 and supported(model) then
				info.ready=true;info.needed=true;info.reused=false;info.radius=radius
				return model,info
			end
			model:Destroy();failure="immediate field wedges do not cover their physical center"
		else failure=tostring(info) end
		if o.cancelled and o.cancelled() then break end
		if radius<=W.WarmMinRadius then break end
		radius=math.max(W.WarmMinRadius,radius*.5)
	until false
	-- A failed attempt does not certify the old radius or the new revision.
	return old,{ready=false,reused=true,needed=true,failure=failure}
end

return SplineParts
