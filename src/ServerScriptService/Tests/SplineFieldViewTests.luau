--!nonstrict
assert(game:GetService("RunService"):IsStudio(),"SplineFieldViewTests is Studio only")
local Tests={}

function Tests.run(_self,subjects)
	local root=game.ReplicatedStorage.Shared.Road
	local Field=subjects and subjects.Field or require(game.StarterPlayer.StarterPlayerScripts.Drift.SplineFieldView)
	local Infield=subjects and subjects.Infield or require(root.SplineInfield)
	local Cuts=subjects and subjects.Cuts or require(root.SplineFieldCuts)
	local cfg=require(game.ReplicatedStorage.Shared.Config)
	local C=cfg.Spline.Biomes.Infield.View;local saved=C.MaxPatches
	local holder=Instance.new("Folder")
	local ok,result=xpcall(function()
		local checks={};local function check(name,pass,detail)table.insert(checks,{name=name,ok=not not pass,detail=detail})end
		local function rectangle(index,id,x0,x1,z0,z1,arc)
			Infield.add(index,Infield.patch(id,{
				{sa=arc,sb=arc+400,sideA=1,sideB=-1,a={x0,0,z1},b={x1,0,z1},weight=1},
				{sa=arc+20,sb=arc+380,sideA=1,sideB=-1,a={x0,0,z0},b={x1,0,z0},weight=1},
			}))
		end
		local index=Infield.new(32)
		rectangle(index,"one",2,22,-20,0,100)
		rectangle(index,"two",32,52,-20,0,600)
		rectangle(index,"far",2400,2420,-20,0,1200)
		local sp={infields=index,firstSample=0,step=2,infieldRevision=3}
		local field=Field.new(sp,holder);local ticks=0;local function tick()ticks+=1 end
		local nearTicks=0
		local candidates=Infield.nearPatches(index,12,-10,80,0,function()nearTicks+=1 end)
		check("field selection gathers bounded patch identities with slice callbacks",candidates.one~=nil and candidates.two~=nil and candidates.far==nil and nearTicks>0,
			"triangle gathering and sorting do not precede the patch-count bound")
		local retiredCandidates=Infield.nearPatches(index,12,-10,80,1000,tick)
		check("patch selection skips fully retired fields and freezes its cached bounds",next(retiredCandidates)==nil
			and not pcall(function()index.patchBounds.one[1]+=1 end),"retired triangle history does not become candidate display work")
		C.MaxPatches=1
		field:Request(100,Vector3.new(12,0,-10));local firstKey=field.request.key
		local one=field:Select(tick)
		check("the actor's containing field takes priority over other nearby coverage",one and one.selection.one and not one.selection.two,
			"bounded patch selection starts with the actual containing field")
		field:Request(600,Vector3.new(42,0,-10));local two=field:Select(tick)
		check("entering another field invalidates selection within the same spatial cell",field.request.key~=firstKey and two and two.selection.two and not two.selection.one,
			"physical patch identity is part of the request key")
		local cached=field:Select(function()error("unchanged selection recomputed")end)
		check("unchanged field requests reuse immutable geometry",cached==two,"a drawing frame does not rebuild an unchanged plan")
		local old=Cuts.plan(index,{one=true},100,1)
		local target=Cuts.plan(index,{two=true},650,2)
		local records={[0]={serial=1,mask=old,s0=100,s1=110,scenery={}},[1]={serial=2,mask=target,s0=990,s1=1000,scenery={}}}
		local chosen,cover,draining=field:Coverage(records,target,tick)
		check("rolling coverage retains every old and new road mask",Field.equal(chosen,target) and not draining and cover.selection.one and cover.selection.two and cover.first==100,
			"union coverage uses the oldest retained distance until its road mask is replaced")
		local distant=Cuts.plan(index,{far=true},0,3)
		local oldOnly={[0]=records[0]}
		local empty,oldCover,mustDrain=field:Coverage(oldOnly,distant,tick)
		check("distant coverage drains old masks before exceeding the mesh bounds",empty==nil and mustDrain and oldCover.selection.one and not oldCover.selection.far,
			"the desired far field remains queued while old clipped ground stays covered")
		local entered,newCover,stillDraining=field:Coverage({},distant,tick)
		check("a completed drain enters the queued complete field",Field.equal(entered,distant) and newCover.selection.far and not stillDraining,
			"no extra field mesh is needed for a third coverage generation")
		field.live={plan=cover,sources={[0]=1,[1]=2}}
		check("companion fields identify their exact published source map",not field:NeedsField(cover,records),"matching chunk serials reuse the current field")
		local changed=table.clone(records);changed[1]=table.clone(records[1]);changed[1].serial=3
		check("a source change invalidates seams without a coverage change",field:NeedsField(cover,changed),"a new cap or fallback source must receive a new companion")
		check("source removal invalidates companion seams",field:NeedsField(cover,oldOnly),"a retired chunk cannot leave its source seam behind")
		local peerRecords={[0]={s0=100,s1=110},[1]={s0=490,s1=500}}
		local peers=Field.PeerIntervals(Cuts.plan(index,{one=true},0,1),peerRecords)
		check("opposite-road intervals exclude only published main coverage",#peers==2 and peers[1][1]==110 and peers[1][2]==120 and peers[2][1]==480 and peers[2][2]==490,
			"both attached arms are retained beyond the contiguous main window")
		local retainedPeers=Field.PeerIntervals(Cuts.plan(index,{one=true},300,2),{})
		check("retired approach asphalt is never rebuilt as a peer strip",#retainedPeers==1 and retainedPeers[1][1]==480 and retainedPeers[1][2]==500,
			"the later live arm remains visible after its early partner retires")
		local transitionalPeers=Field.PeerIntervals(old,{},300)
		check("transitional union floors cannot reconstruct newly retired peer asphalt",#transitionalPeers==1 and transitionalPeers[1][1]==480 and transitionalPeers[1][2]==500,
			"peer visibility uses the current first even while older road masks still need an older floor union")
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	C.MaxPatches=saved;holder:Destroy()
	if not ok then return {passed=0,total=1,checks={{name="field-view pure fixture completes",ok=false,detail=result}}} end
	return result
end

function Tests.runtime(_self,options)
	local o=options or {};local root=game.ReplicatedStorage.Shared.Road
	local Spline,Planner,Infield=require(root.Spline),require(root.SplineInfieldPlanner),require(root.SplineInfield)
	local Mesh,Profile=require(root.SplineMesh),require(root.SplineProfile)
	local View=require(game.StarterPlayer.StarterPlayerScripts.Drift.SplineRoadView)
	local Field=require(game.StarterPlayer.StarterPlayerScripts.Drift.SplineFieldView)
	local cfg=require(game.ReplicatedStorage.Shared.Config)
	local run=game:GetService("RunService")
	local marker=if o.marker then game.ServerStorage:FindFirstChild(o.marker) else nil
	local saved=cfg.Spline.Biomes.GroundEnabled;cfg.Spline.Biomes.GroundEnabled=true
	local savedMesh,savedProfile=Mesh.drawProfile,Profile.draw
	local folder=Instance.new("Folder");folder.Name="__T212FieldViewRuntime";folder.Parent=workspace
	local view=nil
	local ok,result=xpcall(function()
		local checks={};local function check(name,pass,detail)table.insert(checks,{name=name,ok=not not pass,detail=detail})end
		assert(Mesh.liveMeshCount()==0,"runtime fixture needs a fresh play with no other server-view meshes")
		local sp=Spline.new({x=30000,y=50,z=-20000,yaw=0});sp.fall=math.pi*.5
		local function section(length,knots,left,right,bank)
			return {len=length,k=knots,g={length,0},b={length,0},rl={length,16},rr={length,16},el={length,left},er={length,right},hl={length,bank},hr={length,0}}
		end
		local a=section(1800,{1800,0},Spline.ROCK,Spline.CLIFF,20);a.bm={0,1,0};sp:append(a)
		local turn=math.pi*100+20
		sp:append(section(turn,{20,.01,turn-20,.01,turn,0},Spline.ROCK,Spline.CLIFF,0))
		local b0=sp.length;sp:append(section(1600,{1600,0},Spline.CLIFF,Spline.ROCK,0))
		local patches=Planner.plan(sp,800,1760,b0,sp.length);assert(#patches>0,"runtime fixture has no accepted field");sp:addInfields(patches)
		local row=patches[1].rows[math.max(2,math.floor(#patches[1].rows*.15))]
		local p=Infield.columns(row)[6];local position=Vector3.new(p[1],p[2],p[3]);local at=row.sa
		view=View.new(sp,folder);view.forceFallback=o.forceFallback==true
		local frames,maxMeshes,maxPublish,invalid,early=0,0,0,0,0
		local frameMs={};local examples={}
		local function note(text)invalid+=1;if #examples<6 then table.insert(examples,text) end end
		local function inspect()
			frames+=1;local state=view:DebugState()
			maxMeshes=math.max(maxMeshes,state.peakMeshes,state.liveMeshes);maxPublish=math.max(maxPublish,state.worstPublishMs)
			if state.chunks>5 or state.liveMeshes>8 then note(`road/mesh budget {state.chunks}/{state.liveMeshes}`) end
			local live=view.fields.live;local published={}
			for id,record in view.records do
				published[record.model]=true
				if record.model.Parent~=view.folder then note(`unparented published road {id}`) end
				if live and live.sources[id]~=record.serial then note(`source serial mismatch {id}`) end
			end
			if live then for id in live.sources do if not view.records[id] then note(`retired seam source {id}`) end end end
			local function exposed(root)
				if not root then return false end
				for _,p in root:GetDescendants() do if p:IsA("BasePart") and p.Transparency<1 then return true end end
				return false
			end
			for _,child in view.folder:GetChildren() do
				if child:GetAttribute("Fallback") and not published[child] then
					if exposed(child:FindFirstChild("Scenery")) then early+=1 end
					for _,batch in child:GetChildren() do
						if batch.Name=="TerrainSlices" then
							local first=batch:FindFirstChildWhichIsA("BasePart")
							if first and first.Transparency<1 and not string.find(first.Name,"Ground",1,true) then early+=1 end
						end
					end
				elseif child:GetAttribute("Infield") and (not live or child~=live.model) then
					if exposed(child:FindFirstChild("FieldSeams")) then early+=1 end
					for _,batch in child:GetChildren() do
						local first=batch:FindFirstChildWhichIsA("BasePart")
						if first and first.Transparency<1 and string.find(first.Name,"InfieldSeam",1,true) then early+=1 end
					end
				end
			end
		end
		local function settled()
			if view.building or view.fieldBuilding or view.captureWanted then return false end
			local desired=view.fieldTarget;local live=view.fields.live
			if not desired or not live or not Field.equal(live.plan,desired) then return false end
			if view.fields.cachedKey~=view.fields.request.key then return false end
			for i=view.windowLo,view.windowHi do
				local record=view.records[i]
				if not record or not Field.equal(record.mask,desired) then return false end
				if view.stale[i] and i*cfg.Spline.Mesh.ChunkLength<=at+cfg.Spline.Mesh.RedrawWithin then return false end
			end
			return true
		end
		local function settle(stage)
			if marker then marker:SetAttribute("stage",stage) end
			local deadline=os.clock()+(o.timeout or 90);local stable=0
			repeat
				view:Update(at,position)
				local dt=run.Heartbeat:Wait();table.insert(frameMs,dt*1000);inspect()
				stable=if settled() then stable+1 else 0
			until stable>=3 or os.clock()>=deadline
			assert(stable>=3,`{stage} timed out: {game:GetService("HttpService"):JSONEncode(view:DebugState())}`)
		end
		settle("initial linked-field visibility")
		local peers,peerParts=0,0
		for _,peer in view.fields.peers do peers+=1;peerParts+=peer.parts end
		check("both road arms are visible beyond the main arc window",peers>0 and peerParts>0,
			`{peers} opposite-arm strips, {peerParts} ordinary supported Parts; owner{row.sa}, peer{row.sb}`)
		local function top(model)
			local maximum=-math.huge
			for _,part in model:GetDescendants() do if part:IsA("BasePart") then
				local cf,h=part.CFrame,part.Size*.5
				maximum=math.max(maximum,cf.Position.Y+math.abs(cf.RightVector.Y)*h.X+math.abs(cf.UpVector.Y)*h.Y+math.abs(cf.LookVector.Y)*h.Z)
			end end
			return maximum
		end
		local oldTop=top(view.fields.live.model);local oldBuilt=view.fields.built
		local function raised(base)
			return function(spline,s,side,kind,cap)
				local points=base(spline,s,side,kind,cap)
				if spline==sp and kind==Spline.ROCK then for i=2,#points do points[i]+=Vector3.yAxis*(80*(i-1)/(#points-1)) end end
				return points
			end
		end
		Mesh.drawProfile=raised(savedMesh);Profile.draw=raised(savedProfile)
		for i in view.chunks do view.stale[i]=true end
		settle("large actual source-height change")
		local newTop=top(view.fields.live.model)
		check("field seams replace with a large real source change",view.fields.built>oldBuilt and newTop>oldTop+10,
			`source-only change kept the same spline length; field top{oldTop}→{newTop}, paired fields{view.fields.built-oldBuilt}`)
		check("every observed frame retains exact published source ownership",invalid==0,
			`{frames} real Heartbeat frames; mismatches{invalid}; {table.concat(examples,"; ")}`)
		check("fallback source-dependent layers stay hidden until commit",early==0,`early source/seam observations{early}`)
		check("the live replacement path stays within eight EditableMeshes",maxMeshes<=8,`actual module allocation peak{maxMeshes}`)
		check("complete scenery and seam publication stays bounded",maxPublish<cfg.Spline.Mesh.SliceMs*3,
			`largest synchronous publish{maxPublish}ms; unchanged guard{cfg.Spline.Mesh.SliceMs*3}ms`)
		local debug=view:DebugState();view:Destroy()
		local deadline=os.clock()+20
		while (view.building or view.fieldBuilding or Mesh.liveMeshCount()>0 or view:DebugState().retiringRoots>0) and os.clock()<deadline do run.Heartbeat:Wait() end
		check("destroy releases all real mesh slots and hidden retirement roots",Mesh.liveMeshCount()==0 and view:DebugState().retiringRoots==0 and view.folder.Parent==nil,
			`remaining meshes{Mesh.liveMeshCount()}, retiring roots{view:DebugState().retiringRoots}`)
		table.sort(frameMs);local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks,forcedFallback=o.forceFallback==true,
			frames=frames,heartbeatP95Ms=frameMs[math.max(1,math.ceil(#frameMs*.95))],heartbeatMaxMs=frameMs[#frameMs],debug=debug}
	end,debug.traceback)
	if view and not view.dead then view:Destroy() end
	local cleanupDeadline=os.clock()+20
	while view and (view.building or view.fieldBuilding or Mesh.liveMeshCount()>0 or view:DebugState().retiringRoots>0)
		and os.clock()<cleanupDeadline do run.Heartbeat:Wait() end
	Mesh.drawProfile=savedMesh;Profile.draw=savedProfile;cfg.Spline.Biomes.GroundEnabled=saved
	folder:Destroy()
	if not ok then return {passed=0,total=1,checks={{name="live field-view fixture completes",ok=false,detail=result}}} end
	return result
end

return Tests
