--!nonstrict
-- T-214: isolated Studio prototype. Nothing starts without the explicit lane flag.
-- No production renderer, collision, config, remote, asset upload or plugin changes.
local RunService=game:GetService("RunService")
local AssetService=game:GetService("AssetService")
local Players=game:GetService("Players")
local Lighting=game:GetService("Lighting")
local RS=game:GetService("ReplicatedStorage")
local Trial=require(script.Parent.Parent.Drift.BakedShadowTrial)
local Controller={Priority=-100}

local state={on=false,phase="off",checks={},calls={},resources={editable=0,baked=0},visual="unreviewed"}
local root,gui,original,panelEM,panelLive,panelBaked,terrainBaked,terrainLive
local panelContent,terrainContent
local generation=0
local sky,camera,input
local savedLight,terrainFrame,panelFrame,terrainTarget
local scene="panel"
local mode="baked"
local sun="front"
local lightingConnection
local cameraCF
local streamParts,streamContents={},{}
local temporaryMeshes={}
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
local function measured(name,fn)
	local frames={};local c=RunService.Heartbeat:Connect(function(dt)table.insert(frames,dt*1000)end)
	local t=os.clock();local result=table.pack(pcall(fn));local elapsed=(os.clock()-t)*1000
	RunService.Heartbeat:Wait();task.wait();c:Disconnect()
	local entry={name=name,wallMs=elapsed,frames=Trial.summary(frames),ok=result[1]}
	table.insert(state.calls,entry)
	if not result[1] then error(result[2]) end
	return table.unpack(result,2,result.n)
end
local function configure(p,source,cf)
	p.Name="Road";p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=true
	p.Color=source.Color;p.Material=source.Material;p.TextureContent=source.TextureContent
	p.DoubleSided=source.DoubleSided;p.CFrame=cf;p.Size=source.Size
end

-- Cancellation is checked AFTER both native awaits. No late result is published.
local function baked(content,source,cf,token,inject)
	local static,mp
	local ok,err=pcall(function()
		local result
		result,static=measured("convert",function()return AssetService:CreateDataModelContentAsync(content)end)
		assert(result==Enum.CreateContentResult.Success,`conversion result {result}`)
		assert(static.SourceType==Enum.ContentSourceType.Opaque,"not static Opaque Content")
		if inject=="afterConvert" or token~=generation then error("trial cancelled after convert") end
		mp=measured("create",function()return AssetService:CreateMeshPartAsync(static,{CollisionFidelity=Enum.CollisionFidelity.Box,RenderFidelity=Enum.RenderFidelity.Precise})end)
		configure(mp,source,cf)
		if inject=="afterCreate" or token~=generation then error("trial cancelled after create") end
	end)
	if not ok then if mp then mp:Destroy() end;mp=nil;static=nil;return nil,nil,tostring(err) end
	return mp,static
end

local function show()
	if not root then return end
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
		b.Text=choice[1];b.TextSize=14;b.Font=Enum.Font.Gotham;b.BackgroundColor3=Color3.fromRGB(42,52,68);b.TextColor3=Color3.new(1,1,1);b.Parent=gui;b.Activated:Connect(choice[2])
	end
end

local function buildPanels(token)
	local folder=root.Panel
	panelFrame=CFrame.new(0,1000,6000)
	panelEM=AssetService:CreateEditableMesh();assert(panelEM,"panel EditableMesh budget exhausted");state.resources.editable+=1
	local points,triangles=Trial.panel();local ids={}
	for i,p in points do ids[i]=panelEM:AddVertex(p) end
	local normal=panelEM:AddNormal(Vector3.xAxis);local uv=panelEM:AddUV(Vector2.zero);local colour=panelEM:AddColor(Color3.fromRGB(155,173,197),1)
	for _,t in triangles do local f=panelEM:AddTriangle(ids[t[1]],ids[t[2]],ids[t[3]]);panelEM:SetFaceNormals(f,{normal,normal,normal});panelEM:SetFaceUVs(f,{uv,uv,uv});panelEM:SetFaceColors(f,{colour,colour,colour})end
	panelLive=AssetService:CreateMeshPartAsync(Content.fromObject(panelEM),{CollisionFidelity=Enum.CollisionFidelity.Box,RenderFidelity=Enum.RenderFidelity.Precise})
	assert(token==generation,"panel cancelled after create")
	panelLive.Anchored=true;panelLive.CanCollide=false;panelLive.CanTouch=false;panelLive.CanQuery=false;panelLive.CastShadow=true;panelLive.DoubleSided=false;panelLive.Color=Color3.new(1,1,1);panelLive.Material=Enum.Material.SmoothPlastic
	local names={"Live editable · no blockers","Baked · front face to sun","Baked · back face to sun","Ordinary Parts · reference","Empty · lit control"}
	for i,name in names do
		local cf=panelFrame*CFrame.new(0,0,(i-1)*70)
		part("Receiver",Vector3.new(210,1,62),cf*CFrame.new(0,-.5,0),folder)
		label(name,cf*CFrame.new(35,32,0)*CFrame.Angles(0,math.pi*.5,0),folder)
		if i==1 then panelLive.CFrame=cf;panelLive.Parent=folder
		elseif i==2 then local why;panelBaked,panelContent,why=baked(Content.fromObject(panelEM),panelLive,cf,token);assert(panelBaked,why);panelBaked.Name="BakedPanel";panelBaked.Parent=folder;state.resources.baked+=1
		elseif i==3 then local p=panelBaked:Clone();p.Name="BakedBackFacing";p.CFrame=cf*CFrame.Angles(0,math.pi,0);p.Parent=folder
		elseif i==4 then for j,h in {10,25,14,22} do part("ReferenceSlat",Vector3.new(.15,h,10),cf*CFrame.new(0,h*.5,(j-1)*10-15),folder,Color3.fromRGB(155,173,197))end end
	end
	state.panel={faces=#panelEM:GetFaces(),oneSided=true,collision="Box",normal={1,0,0}}
end

local function buildTerrain(token)
	local Mesh=require(RS.Shared.Road.SplineMesh);local Gen=require(RS.Shared.Road.SplineGen)
	local function checkpoint()assert(token==generation,"terrain cancelled");task.wait();assert(token==generation,"terrain cancelled")end
	local gen=Gen.new(101);while gen.spline.length<3000 and not gen.stats.stalled do gen:step();checkpoint() end
	local stats;original,stats=Mesh.build(gen.spline,480,960,Controller.terrainFolder,{sliceMs=3})
	if token~=generation then if original then Mesh.destroy(original);original=nil end;error("terrain cancelled after build")end
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
	local copy=AssetService:CreateEditableMeshAsync(Content.fromObject(em));assert(copy,"copy failed");temporaryMeshes[copy]=true;state.resources.editable+=1
	checkpoint()
	local before=Trial.snapshot(copy,checkpoint)
	local why;terrainBaked,terrainContent,why=baked(Content.fromObject(copy),source,source.CFrame,token);assert(terrainBaked,why)
	copy:Destroy();temporaryMeshes[copy]=nil;copy=nil;state.resources.editable-=1
	state.sourceDestroyed=true;state.staticSourceType=tostring(terrainContent.SourceType);state.resources.baked+=1
	local readback=AssetService:CreateEditableMeshAsync(terrainContent);temporaryMeshes[readback]=true;state.resources.editable+=1
	checkpoint()
	state.readback=Trial.compare(before,Trial.snapshot(readback,checkpoint),checkpoint);readback:Destroy();temporaryMeshes[readback]=nil;state.resources.editable-=1
	check("baked triangles/UV/normals/colours survive source destruction",state.readback.pass,state.readback)
	check("mesh size is stable",(source.MeshSize-terrainBaked.MeshSize).Magnitude<.02,{source=tostring(source.MeshSize),baked=tostring(terrainBaked.MeshSize),size=tostring(terrainBaked.Size)})
	terrainLive=source:Clone();terrainLive.Name="LiveTerrainOnly"
	-- Only the mesh in both standalone modes: no hidden shadow casters, rails or paint Parts.
	terrainBaked.Name="BakedTerrainOnly"
	state.terrain.standaloneParts=1;state.terrain.referenceParts=plain+blockers
	state.bakeFrozenHaze=true;state.textureKept=source.TextureContent==terrainBaked.TextureContent
	-- Backface/DoubleSided controls stay in the real-terrain frame. With the higher
	-- sun their shadows fit on these isolated, raised neutral receivers.
	local controls=Instance.new("Folder");controls.Name="BackfaceControls";controls.Parent=Controller.terrainFolder
	for i,name in {"Back face · single sided","Back face · DoubleSided","Ordinary Parts control"}do
		local cf=CFrame.new(terrainTarget+Vector3.new(110,55,(i-1)*55+5))
		part("ControlReceiver",Vector3.new(70,1,48),cf*CFrame.new(0,-.5,0),controls)
		label(name,cf*CFrame.new(30,30,0)*CFrame.Angles(0,math.pi*.5,0),controls)
		if i<3 then local p=panelBaked:Clone();p.Name=if i==1 then "SingleSidedBack" else "DoubleSidedBack";p.CFrame=cf*CFrame.Angles(0,math.pi,0);p.DoubleSided=i==2;p.Parent=controls
		else for j,h in {10,25,14,22}do part("PartControl",Vector3.new(.15,h,10),cf*CFrame.new(0,h*.5,(j-1)*10-15),controls,Color3.fromRGB(155,173,197))end end
	end
end

function Controller:Init() end
function Controller:Start()
	if not RunService:IsStudio() or workspace:GetAttribute("__baked_shadow_trial")~=true then return end
	generation+=1;local token=generation;state.on=true;state.phase="building"
	sky=require(script.Parent.SkyController);camera=require(script.Parent.CarCameraController);input=require(script.Parent.CarInputController)
	input:DebugSetInput(0,true);sky:DebugHold(60)
	savedLight={latitude=Lighting.GeographicLatitude,ambient=Lighting.Ambient,outdoor=Lighting.OutdoorAmbient,brightness=Lighting.Brightness,exposure=Lighting.ExposureCompensation}
	local atmosphere=Lighting:FindFirstChildOfClass("Atmosphere");if atmosphere then savedLight.density=atmosphere.Density end
	root=Instance.new("Folder");root.Name="__BakedShadowTrial";root.Parent=workspace
	for _,name in {"Panel","Terrain"}do local f=Instance.new("Folder");f.Name=name;f.Parent=root end
	-- Keep folders referenced when a scene is hidden; indexing root would then fail.
	local panelFolder,terrainFolder=root.Panel,root.Terrain
	local ok,err=xpcall(function()
		self.panelFolder=panelFolder;self.terrainFolder=terrainFolder
		buildPanels(token);ui()
		lightingConnection=RunService.RenderStepped:Connect(function()
			Lighting.GeographicLatitude=23.5
			Lighting.Brightness=3;Lighting.Ambient=Color3.fromRGB(45,45,45);Lighting.OutdoorAmbient=Color3.fromRGB(45,45,45);Lighting.ExposureCompensation=0
			if atmosphere then atmosphere.Density=0 end
		end)
		-- Use the existing camera ownership API; never change desktop focus.
		camera:SetView(function()return cameraCF,55 end,"baked-shadow-trial")
		-- show() uses these explicit references after parenting folders out of root.
		self.panelFolder=panelFolder;self.terrainFolder=terrainFolder
		setSun("front");state.phase="ready"
	end,debug.traceback)
	if not ok then self:DebugStop();state.phase="failed";state.error=err;warn("BakedShadowTrial: "..tostring(err)) end
end

function Controller:DebugState()
	if state.on then
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
	assert(state.phase=="ready","trial not ready")
	mode=variant or "baked"
	if original then scene="terrain";show();return {ready=true}end
	state.phase="building terrain";local token=generation
	task.spawn(function()
		local ok,err=xpcall(function()buildTerrain(token)end,debug.traceback)
		if ok and token==generation then state.phase="ready";scene="terrain";show()
		else self:DebugStop();state.phase=if string.find(tostring(err),"cancelled") then "stopped" else "failed";state.error=err end
	end)
	return {scheduled=true}
end

-- One bounded five-resident window, six replacements. No hundreds-of-mesh stress.
function Controller:DebugMeasure()
	assert(state.phase=="ready" and original and not state.measuring,"terrain trial unavailable/busy")
	state.measuring=true;state.measurement={phase="baseline"};local token=generation
	task.spawn(function()
		local ok,err=xpcall(function()
			local baseline={};for _=1,45 do table.insert(baseline,RunService.Heartbeat:Wait()*1000)end
			state.measurement.baseline=Trial.summary(baseline)
			state.measurement.kind="same real terrain snapshot, five published residents, six replacements; not a streaming road run"
			local residents=Instance.new("Folder");residents.Name="WindowCostFixture";residents.Parent=root
			local source=original.Road;local content=source.MeshContent
			local first=#state.calls+1
			for i=1,11 do
				assert(token==generation,"measurement cancelled")
				state.measurement.phase=`window {i}/11`
				if #streamParts==5 then measured("retire",function()local p=table.remove(streamParts,1);p:Destroy();table.remove(streamContents,1)end)end
				local p,c,why=baked(content,source,source.CFrame,token);assert(p,why)
				-- Publish outside the comparison camera to measure lifecycle separately
				-- from visible shadow cost. This is deliberately not a driving benchmark.
				p.CFrame+=Vector3.new((i%5)*1600,2000,3000)
				measured("publish",function()p.Parent=residents end)
				table.insert(streamParts,p);table.insert(streamContents,c);task.wait()
			end
			state.measurement.retained=5
			measured("retireAll",function()for _,p in streamParts do p:Destroy()end;table.clear(streamParts);table.clear(streamContents)end)
			residents:Destroy()
			local settle={};for _=1,120 do table.insert(settle,RunService.Heartbeat:Wait()*1000)end
			state.measurement.afterRelease=Trial.summary(settle)
			for _,stage in {"afterConvert","afterCreate"}do
				local p,c,why=baked(content,source,source.CFrame,token,stage)
				check(`cancellation cleanup {stage}`,p==nil and c==nil and string.find(why,"trial cancelled")~=nil,why)
			end
			local callOk,result,empty=pcall(function()return AssetService:CreateDataModelContentAsync(Content.none)end)
			-- Invalid-input behaviour may throw OR return a non-success result. Do not
			-- manufacture a guaranteed allocation failure on the player's machine.
			check("invalid conversion is rejected",not callOk or result~=Enum.CreateContentResult.Success,{callOk=callOk,result=tostring(result)})
			empty=nil
			state.measurement.callFirst=first;state.measurement.callLast=#state.calls;state.measurement.phase="done"
		end,debug.traceback)
		for _,p in streamParts do p:Destroy()end;table.clear(streamParts);table.clear(streamContents)
		state.measuring=false;if not ok then state.measurement.phase="failed";state.measurement.error=err end
	end)
	return {scheduled=true}
end

function Controller:DebugStop()
	generation+=1
	if lightingConnection then lightingConnection:Disconnect();lightingConnection=nil end
	if camera then camera:SetView(nil) end
	if input then input:DebugClearInput() end
	if gui then gui:Destroy();gui=nil end
	for g,enabled in savedGuis do if g.Parent then g.Enabled=enabled end end;table.clear(savedGuis)
	for _,p in streamParts do p:Destroy()end;table.clear(streamParts);table.clear(streamContents)
	for _,p in {terrainLive,terrainBaked,panelLive,panelBaked}do if p then p:Destroy()end end
	terrainLive=nil;terrainBaked=nil;panelLive=nil;panelBaked=nil;terrainContent=nil;panelContent=nil
	if original then require(RS.Shared.Road.SplineMesh).destroy(original);original=nil end
	if panelEM then panelEM:Destroy();panelEM=nil end
	for em in temporaryMeshes do pcall(function()em:Destroy()end)end;table.clear(temporaryMeshes)
	if self.panelFolder then self.panelFolder:Destroy();self.panelFolder=nil end
	if self.terrainFolder then self.terrainFolder:Destroy();self.terrainFolder=nil end
	if root then root:Destroy();root=nil end
	if savedLight then Lighting.GeographicLatitude=savedLight.latitude end
	if sky then sky:DebugResume()end
	state.on=false;state.phase="stopped";state.resources={editable=0,baked=0}
	return state
end
return Controller
