--!nonstrict
-- T-214: isolated Studio prototype. Nothing starts without the explicit lane flag.
-- No production renderer, collision, config, remote, asset upload or plugin changes.
local RunService=game:GetService("RunService")
local AssetService=game:GetService("AssetService")
local Players=game:GetService("Players")
local Lighting=game:GetService("Lighting")
local RS=game:GetService("ReplicatedStorage")
local Trial -- Loaded only after the Studio + explicit opt-in guard.
local Controller={Priority=-100}

local state={on=false,phase="off",checks={},calls={},resources={editable=0,baked=0},visual="unreviewed"}
local root,gui,original,panelEM,panelLive,panelBaked,terrainBaked,terrainLive
local panelContent,terrainContent
local session
local sky,camera,input
local savedLight,terrainFrame,panelFrame,terrainTarget
local scene="panel"
local mode="baked"
local sun="front"
local lightingConnection
local cameraCF
local streamParts,streamContents={},{}
local savedGuis={}

local function check(name,ok,detail)
	table.insert(state.checks,{name=name,ok=ok,detail=detail})
end
local function part(name,size,cf,parent,colour)
	local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=cf;p.Anchored=true
	p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Color=colour or Color3.fromRGB(220,220,220)
	p.Material=Enum.Material.SmoothPlastic;p.Parent=parent;return p
end
local function label(name,cf,parent)
	local p=part("Label",Vector3.new(48,7,.1),cf,parent,Color3.fromRGB(25,28,34));p.CastShadow=false
	local s=Instance.new("SurfaceGui");s.Face=Enum.NormalId.Back;s.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;s.PixelsPerStud=18;s.Parent=p
	local t=Instance.new("TextLabel");t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.Text=name;t.TextColor3=Color3.new(1,1,1);t.TextScaled=true;t.Font=Enum.Font.GothamBold;t.Parent=s
end
local function destroy(value) value:Destroy() end
local PART,EDITABLE,CONTENT -- native result descriptors are lazy with the trial
local function measured(job,name,fn,returned)
	job:check()
	local frames={};local c=RunService.Heartbeat:Connect(function(dt)table.insert(frames,dt*1000)end)
	local t=os.clock()
	local result=table.pack(pcall(function()return job:await(name,fn,returned)end))
	local elapsed=(os.clock()-t)*1000
	local ok,err=pcall(function()
		job:check()
		if not result[1] then
			table.insert(state.calls,{name=name,wallMs=elapsed,frames=Trial.summary(frames),ok=false})
			error(result[2],0)
		end
		RunService.Heartbeat:Wait();job:check();task.wait();job:check()
		table.insert(state.calls,{name=name,wallMs=elapsed,frames=Trial.summary(frames),ok=true})
	end)
	c:Disconnect()
	if not ok then error(err,0) end
	return table.unpack(result,2,result.n)
end
local function metadata(job,source)
	job:check()
	return {Color=source.Color,Material=source.Material,TextureContent=source.TextureContent,
		DoubleSided=source.DoubleSided,Size=source.Size}
end
local function configure(p,source,cf)
	p.Name="Road";p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=true
	p.Color=source.Color;p.Material=source.Material;p.TextureContent=source.TextureContent
	p.DoubleSided=source.DoubleSided;p.CFrame=cf;p.Size=source.Size
end
local function baked(job,content,source,cf,inject)
	return Trial.bake(job,{
		convert=function(value)return measured(job,"convert",function()return AssetService:CreateDataModelContentAsync(value)end,CONTENT)end,
		valid=function(result,static)return result==Enum.CreateContentResult.Success and static.SourceType==Enum.ContentSourceType.Opaque end,
		create=function(static)return measured(job,"create",function()return AssetService:CreateMeshPartAsync(static,{CollisionFidelity=Enum.CollisionFidelity.Box,RenderFidelity=Enum.RenderFidelity.Precise})end,PART)end,
		configure=function(mp)configure(mp,source,cf)end,
	},content,inject)
end

local function show()
	if not state.on or not root then return end
	local pf,tf=Controller.panelFolder,Controller.terrainFolder
	pf.Parent=if scene=="panel" then root else nil
	tf.Parent=if scene=="terrain" then root else nil
	if original then original.Parent=if scene=="terrain" and mode=="reference" then tf else nil end
	if terrainLive then terrainLive.Parent=if scene=="terrain" and mode=="live" then tf else nil end
	if terrainBaked then terrainBaked.Parent=if scene=="terrain" and mode=="baked" then tf else nil end
	if scene=="panel" then
		cameraCF=panelFrame*CFrame.lookAt(Vector3.new(180,220,440),Vector3.new(0,3,140))
	else
		cameraCF=CFrame.lookAt(terrainTarget+Vector3.new(220,180,270),terrainTarget+Vector3.new(30,40,30))
	end
	state.scene=scene;state.mode=mode;state.sun=sun
end
local function setSun(which)
	if not state.on then return end
	sun=which
	-- Use the sky's own hold so its Heartbeat cannot overwrite the trial clock.
	local goal=if which=="front" then 7 else if which=="back" then 17 else 10
	local lo,hi=0,120
	for _=1,20 do local mid=(lo+hi)*.5;if sky:DebugLook(mid).Clock<goal then lo=mid else hi=mid end end
	sky:DebugHold((lo+hi)*.5)
	show()
end
local function ui()
	for _,g in Players.LocalPlayer.PlayerGui:GetChildren()do if g:IsA("ScreenGui") then savedGuis[g]=g.Enabled;g.Enabled=false end end
	gui=Instance.new("ScreenGui");gui.Name="BakedShadowTrial";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=200;gui.Parent=Players.LocalPlayer.PlayerGui
	local header=Instance.new("TextLabel");header.Size=UDim2.new(1,0,0,42);header.BackgroundColor3=Color3.fromRGB(20,23,30);header.TextColor3=Color3.new(1,1,1);header.TextSize=16;header.Font=Enum.Font.GothamBold
	header.Text="STUDIO TRIAL · native baked shadows · same mesh, Box collision · colours frozen at bake";header.Parent=gui
	local choices={
		{"Low front",function()setSun("front")end},{"Low back",function()setSun("back")end},{"Higher sun",function()setSun("high")end},
		{"Panel controls",function()scene="panel";show()end},
		{"Terrain: live",function()Controller:DebugTerrain("live")end},
		{"Terrain: baked",function()Controller:DebugTerrain("baked")end},
		{"Terrain: boxes",function()Controller:DebugTerrain("reference")end},
	}
	for i,choice in choices do
		local b=Instance.new("TextButton");b.Size=UDim2.new(1/#choices,-4,0,38);b.Position=UDim2.new((i-1)/#choices,2,0,44)
		b.Text=choice[1];b.TextSize=14;b.Font=Enum.Font.Gotham;b.BackgroundColor3=Color3.fromRGB(42,52,68);b.TextColor3=Color3.new(1,1,1);b.Parent=gui;b.Activated:Connect(function()if state.on and state.phase=="ready" and not state.measuring then choice[2]()end end)
	end
end

local function buildPanels(job)
	local folder=root.Panel
	panelFrame=CFrame.new(0,1000,6000)
	panelEM=job:await("panelMesh",function()return AssetService:CreateEditableMesh()end,EDITABLE);assert(panelEM,"panel EditableMesh budget exhausted");state.resources.editable+=1
	local points,triangles=Trial.panel();local ids={}
	for i,p in points do ids[i]=panelEM:AddVertex(p) end
	local normal=panelEM:AddNormal(Vector3.xAxis);local uv=panelEM:AddUV(Vector2.zero);local colour=panelEM:AddColor(Color3.fromRGB(155,173,197),1)
	for _,t in triangles do local f=panelEM:AddTriangle(ids[t[1]],ids[t[2]],ids[t[3]]);panelEM:SetFaceNormals(f,{normal,normal,normal});panelEM:SetFaceUVs(f,{uv,uv,uv});panelEM:SetFaceColors(f,{colour,colour,colour})end
	panelLive=measured(job,"panelPart",function()return AssetService:CreateMeshPartAsync(Content.fromObject(panelEM),{CollisionFidelity=Enum.CollisionFidelity.Box,RenderFidelity=Enum.RenderFidelity.Precise})end,PART)
	panelLive.Anchored=true;panelLive.CanCollide=false;panelLive.CanTouch=false;panelLive.CanQuery=false;panelLive.CastShadow=true;panelLive.DoubleSided=false;panelLive.Color=Color3.new(1,1,1);panelLive.Material=Enum.Material.SmoothPlastic
	local names={"Live editable · no blockers","Baked · front face to sun","Baked · back face to sun","Ordinary Parts · reference","Empty · lit control"}
	for i,name in names do
		local cf=panelFrame*CFrame.new(0,0,(i-1)*70)
		part("Receiver",Vector3.new(210,1,62),cf*CFrame.new(0,-.5,0),folder)
		label(name,cf*CFrame.new(35,32,0)*CFrame.Angles(0,math.pi*.5,0),folder)
		if i==1 then panelLive.CFrame=cf;panelLive.Parent=folder
		elseif i==2 then local why;panelBaked,panelContent,why=baked(job,Content.fromObject(panelEM),metadata(job,panelLive),cf);assert(panelBaked,why);panelBaked.Name="BakedPanel";panelBaked.Parent=folder;state.resources.baked+=1
		elseif i==3 then local p=session:own(panelBaked:Clone(),"part",destroy,0);p.Name="BakedBackFacing";p.CFrame=cf*CFrame.Angles(0,math.pi,0);p.Parent=folder
		elseif i==4 then for j,h in {10,25,14,22} do part("ReferenceSlat",Vector3.new(.15,h,10),cf*CFrame.new(0,h*.5,(j-1)*10-15),folder,Color3.fromRGB(155,173,197))end end
	end
	state.panel={faces=#panelEM:GetFaces(),oneSided=true,collision="Box",normal={1,0,0}}
end

local function buildTerrain(job)
	local Mesh=require(RS.Shared.Road.SplineMesh);local Gen=require(RS.Shared.Road.SplineGen)
	local function checkpoint()job:check();task.wait();job:check()end
	local gen=Gen.new(101);while gen.spline.length<3000 and not gen.stats.stalled do gen:step();checkpoint() end
	local stats;original,stats=job:await("sourceBuild",function()return Mesh.build(gen.spline,480,960,Controller.terrainFolder,{sliceMs=3,cancelled=function()return job.scope.closed end})end,
		{index=1,kind="source",dispose=Mesh.destroy,order=1})
	assert(original,`source mesh build failed: {stats}`);state.resources.editable+=1
	local source=original.Road;local em=source.MeshContent.Object
	local cx,cy,cz=gen.spline:surfaceXYZ(625,0)
	local shift=Vector3.new(0,1000,9000)-Vector3.new(cx,cy,cz)
	original:PivotTo(original:GetPivot()+shift)
	terrainTarget=Vector3.new(0,1000,9000);terrainFrame=source.CFrame
	local blockers,plain=0,0
	for _,p in original:GetDescendants() do if p:IsA("BasePart") then if string.find(p.Name,"Shade") then blockers+=1 else plain+=1 end end end
	state.terrain={seed=101,s0=480,s1=960,focus=625,triangles=stats.triangles,sourceSliceMs=stats.sliceMs,sourceWorkMs=stats.ms,blockers=blockers,nonBlockerParts=plain}
	-- Bake an exact editable copy, then destroy that source before displaying the
	-- static result. The original remains only to provide the live/reference modes.
	local copy=measured(job,"clone",function()return AssetService:CreateEditableMeshAsync(Content.fromObject(em))end,EDITABLE);assert(copy,"copy failed");state.resources.editable+=1
	checkpoint()
	local before=Trial.snapshot(copy,checkpoint)
	local why;terrainBaked,terrainContent,why=baked(job,Content.fromObject(copy),metadata(job,source),source.CFrame);assert(terrainBaked,why)
	session:drop(copy);copy=nil;state.resources.editable-=1
	state.sourceDestroyed=true;state.staticSourceType=tostring(terrainContent.SourceType);state.resources.baked+=1
	local readback=measured(job,"readback",function()return AssetService:CreateEditableMeshAsync(terrainContent)end,EDITABLE);assert(readback,"readback failed");state.resources.editable+=1
	checkpoint()
	state.readback=Trial.compare(before,Trial.snapshot(readback,checkpoint),checkpoint);session:drop(readback);state.resources.editable-=1
	check("baked triangles/UV/normals/colours survive source destruction",state.readback.pass,state.readback)
	check("mesh size is stable",(source.MeshSize-terrainBaked.MeshSize).Magnitude<.02,{source=tostring(source.MeshSize),baked=tostring(terrainBaked.MeshSize),size=tostring(terrainBaked.Size)})
	terrainLive=session:own(source:Clone(),"part",destroy,0);terrainLive.Name="LiveTerrainOnly"
	-- Only the mesh in both standalone modes: no hidden shadow casters, rails or paint Parts.
	terrainBaked.Name="BakedTerrainOnly"
	terrainBaked.DoubleSided=true -- the tested backface shadow needs this
	state.terrain.doubleSided=true
	state.terrain.standaloneParts=1;state.terrain.referenceParts=plain+blockers
	state.bakeFrozenHaze=true;state.textureKept=source.TextureContent==terrainBaked.TextureContent
	-- Backface/DoubleSided controls stay in the real-terrain frame. With the higher
	-- sun their shadows fit on these isolated, raised neutral receivers.
	local controls=Instance.new("Folder");controls.Name="BackfaceControls";controls.Parent=Controller.terrainFolder
	for i,name in {"Back face · single sided","Back face · DoubleSided","Ordinary Parts control"}do
		local cf=CFrame.new(terrainTarget+Vector3.new(110,55,(i-1)*55+5))
		part("ControlReceiver",Vector3.new(70,1,48),cf*CFrame.new(0,-.5,0),controls)
		label(name,cf*CFrame.new(30,30,0)*CFrame.Angles(0,math.pi*.5,0),controls)
		if i<3 then local p=session:own(panelBaked:Clone(),"part",destroy,0);p.Name=if i==1 then "SingleSidedBack" else "DoubleSidedBack";p.CFrame=cf*CFrame.Angles(0,math.pi,0);p.DoubleSided=i==2;p.Parent=controls
		else for j,h in {10,25,14,22}do part("PartControl",Vector3.new(.15,h,10),cf*CFrame.new(0,h*.5,(j-1)*10-15),controls,Color3.fromRGB(155,173,197))end end
	end
end

local function clearReferences()
	root=nil;original=nil;panelEM=nil;panelLive=nil;panelBaked=nil;terrainBaked=nil;terrainLive=nil
	panelContent=nil;terrainContent=nil;Controller.panelFolder=nil;Controller.terrainFolder=nil
	table.clear(streamParts);table.clear(streamContents)
	state.resources={editable=0,baked=0}
end
local function fail(owner,err)
	if owner.closed then return end -- a stopped generation never becomes ready/failed later
	Controller:DebugStop();state.phase="failed";state.error=tostring(err)
	warn("BakedShadowTrial: "..tostring(err))
end
function Controller:Init() end
function Controller:Start()
	if not RunService:IsStudio() or workspace:GetAttribute("__baked_shadow_trial")~=true then return end
	if state.phase~="off" then return end -- another comparison requires a fresh Play
	state.on=true;state.phase="building"
	local loaded,helper=pcall(require,script.Parent.Parent.Drift.BakedShadowTrial)
	if not loaded then state.on=false;state.phase="failed";state.error=tostring(helper);return end
	Trial=helper
	if not state.on then return end -- require may yield before resources exist
	PART={index=1,kind="part",dispose=destroy,order=0}
	EDITABLE={index=1,kind="editable",dispose=destroy,order=2}
	CONTENT={index=2,kind="content",order=3}
	local owner=Trial.lifetime(clearReferences);session=owner
	local job=owner:begin()
	local ok,err=Trial.runJob(job,function()
		sky=require(script.Parent.SkyController);job:check()
		camera=require(script.Parent.CarCameraController);job:check()
		input=require(script.Parent.CarInputController);job:check()
		savedLight={latitude=Lighting.GeographicLatitude}
		input:DebugSetInput(0,true);sky:DebugHold(60)
		local atmosphere=Lighting:FindFirstChildOfClass("Atmosphere")
		root=owner:own(Instance.new("Folder"),"folder",destroy,4);root.Name="__BakedShadowTrial";root.Parent=workspace
		for _,name in {"Panel","Terrain"}do local f=owner:own(Instance.new("Folder"),"folder",destroy,4);f.Name=name;f.Parent=root end
		self.panelFolder=root.Panel;self.terrainFolder=root.Terrain
		buildPanels(job);job:check();ui()
		lightingConnection=RunService.RenderStepped:Connect(function()
			Lighting.GeographicLatitude=23.5
			Lighting.Brightness=3;Lighting.Ambient=Color3.fromRGB(45,45,45);Lighting.OutdoorAmbient=Color3.fromRGB(45,45,45);Lighting.ExposureCompensation=0
			if atmosphere then atmosphere.Density=0 end
		end)
		camera:SetView(function()return cameraCF,55 end,"baked-shadow-trial")
		setSun("front");state.phase="ready"
	end)
	if not ok then fail(owner,err) end
end

function Controller:DebugState()
	if session then state.lifetime=session:describe() end
	if state.on and panelFrame then
		state.light={sun=tostring(Lighting:GetSunDirection()),elevation=math.deg(math.asin(Lighting:GetSunDirection().Y)),panelNormalDot=Lighting:GetSunDirection():Dot(panelFrame.XVector),clock=Lighting.ClockTime}
		state.memoryMb=game:GetService("Stats"):GetTotalMemoryUsageMb()
		state.resources.windowParts=#streamParts;state.resources.windowContents=#streamContents
	end
	return state
end
function Controller:DebugSelect(which,variant,light)
	assert(state.on and state.phase=="ready","trial not ready")
	if which=="terrain" and not original then return self:DebugTerrain(variant)end
	if which then assert(which=="panel" or which=="terrain");scene=which end
	if variant then assert(variant=="live" or variant=="baked" or variant=="reference");mode=variant end
	if light then assert(light=="front" or light=="back" or light=="high");setSun(light) end
	show();return self:DebugState()
end

function Controller:DebugTerrain(variant)
	assert(state.on and state.phase=="ready" and session and not session.closed and not state.measuring,"trial not ready/busy")
	assert(variant==nil or variant=="live" or variant=="baked" or variant=="reference","invalid terrain mode")
	mode=variant or "baked"
	if original then scene="terrain";show();return {ready=true}end
	state.phase="building terrain"
	local owner=session;local job=owner:begin() -- protect sources before task.spawn can yield
	task.spawn(function()
		local ok,err=Trial.runJob(job,function()buildTerrain(job)end)
		if owner.closed then return end
		if ok then state.phase="ready";scene="terrain";show() else fail(owner,err) end
	end)
	return {scheduled=true}
end

-- One bounded five-resident window, six replacements. No hundreds-of-mesh stress.
function Controller:DebugMeasure()
	assert(state.on and state.phase=="ready" and original and not state.measuring and session and not session.closed,"terrain trial unavailable/busy")
	state.measuring=true;state.measurement={phase="baseline"}
	local owner=session;local job=owner:begin()
	task.spawn(function()
		local residents
		local ok,err=Trial.runJob(job,function()
			local function waitFrame()job:check();local dt=RunService.Heartbeat:Wait();job:check();return dt*1000 end
			local baseline={};for _=1,45 do table.insert(baseline,waitFrame())end
			state.measurement.baseline=Trial.summary(baseline)
			state.measurement.kind="same real terrain snapshot, five published residents, six replacements; not a streaming road run"
			residents=owner:own(Instance.new("Folder"),"folder",destroy,4);residents.Name="WindowCostFixture";residents.Parent=root
			local source=original.Road;local content=source.MeshContent;local info=metadata(job,source);local cf=source.CFrame
			local first=#state.calls+1
			for i=1,11 do
				job:check();state.measurement.phase=`window {i}/11`
				if #streamParts==5 then measured(job,"retire",function()owner:drop(table.remove(streamParts,1));owner:drop(table.remove(streamContents,1))end)end
				local p,c,why=baked(job,content,info,cf);assert(p,why)
				p.CFrame+=Vector3.new((i%5)*1600,2000,3000)
				measured(job,"publish",function()p.Parent=residents end)
				table.insert(streamParts,p);table.insert(streamContents,c);task.wait();job:check()
			end
			state.measurement.retained=5
			measured(job,"retireAll",function()for _,p in streamParts do owner:drop(p)end;for _,c in streamContents do owner:drop(c)end;table.clear(streamParts);table.clear(streamContents)end)
			owner:drop(residents);residents=nil
			local settle={};for _=1,120 do table.insert(settle,waitFrame())end
			state.measurement.afterRelease=Trial.summary(settle)
			for _,stage in {"afterConvert","afterCreate"}do
				local p,c,why=baked(job,content,info,cf,stage)
				check(`cancellation cleanup {stage}`,p==nil and c==nil and string.find(why,"trial cancelled")~=nil,why)
			end
			local callOk,result=pcall(function()return measured(job,"invalid",function()return AssetService:CreateDataModelContentAsync(Content.none)end,CONTENT)end)
			job:check()
			check("invalid conversion is rejected",not callOk or result~=Enum.CreateContentResult.Success,{callOk=callOk,result=tostring(result)})
			state.measurement.callFirst=first;state.measurement.callLast=#state.calls;state.measurement.phase="done"
		end)
		-- These are this job's outputs. No replacement session can start in this Play.
		for _,p in streamParts do owner:drop(p)end;for _,c in streamContents do owner:drop(c)end
		table.clear(streamParts);table.clear(streamContents);if residents then owner:drop(residents)end
		state.measuring=false
		if not owner.closed and not ok then state.measurement.phase="failed";state.measurement.error=err end
	end)
	return {scheduled=true}
end

function Controller:DebugStop()
	local wasOn=state.on
	state.on=false;state.phase="stopped" -- invalidate/hide BEFORE any deferred disposal
	if lightingConnection then lightingConnection:Disconnect();lightingConnection=nil end
	if wasOn and camera then camera:SetView(nil) end
	if wasOn and input then input:DebugClearInput() end
	if gui then gui:Destroy();gui=nil end
	for g,enabled in savedGuis do if g.Parent then g.Enabled=enabled end end;table.clear(savedGuis)
	if root then root.Parent=nil end
	if self.panelFolder then self.panelFolder.Parent=nil end
	if self.terrainFolder then self.terrainFolder.Parent=nil end
	if wasOn and savedLight then Lighting.GeographicLatitude=savedLight.latitude end
	if wasOn and sky then sky:DebugResume()end
	if session then session:cancel() end -- pending jobs retain all source/metadata refs
	return self:DebugState()
end
return Controller
