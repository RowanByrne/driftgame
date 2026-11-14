--!strict
-- Actual fallback wedges, shared boundary protection and capped visible faces.
local RS=game:GetService("ReplicatedStorage")
local Config=require(RS.Shared.Config)
local Gen=require(RS.Shared.Road.SplineGen)
local Spline=require(RS.Shared.Road.Spline)
local Parts=require(RS.Shared.Road.SplineParts)
local Profile=require(RS.Shared.Road.SplineProfile)
local Hill=require(RS.Shared.Road.SplineHill)
local Boundary=require(RS.Shared.Road.SplineBoundary)
local Sequence=require(RS.Shared.Road.SplineSequence)
local Tests={}

function Tests.run()
	assert(game:GetService("RunService"):IsStudio())
	local old=Config.Spline.Biomes.GroundEnabled
	Config.Spline.Biomes.GroundEnabled=true
	local folder=Instance.new("Folder");folder.Name="BiomeDrawYardstick";folder.Parent=workspace
	local ok,result=xpcall(function()
		local checks={}
		local function check(name,pass,detail)table.insert(checks,{name=name,ok=pass,detail=detail})end
		local gen=Gen.new(203)
		gen:extendTo(12000)
		local spline=gen.spline
		local half=Config.Road.Width*.5
		local covered,total,worst=0,0,0
		local lowRock,flatDrop=0,0
		local sliceStart=os.clock()
		local function tick()if os.clock()-sliceStart>.003 then task.wait();sliceStart=os.clock()end end
		for s0=0,spline.length-1,480 do
			local ctx=Hill.context(spline,s0,math.min(s0+480,spline.length),Profile.profile,tick)
			for s=s0,math.min(s0+480,spline.length),8 do
				for _,side in {-1,1} do
					local ray=Hill.ray(ctx,s,side)
					local pts=Profile.profile(spline,s,side,spline:edgeAt(s,side),Hill.cap(ray))
					-- The stable low rock foot is drawn independently of the capped
					-- far mountain, so later neighbouring legs cannot remove it.
					local height=math.max(math.abs(pts[5].Y-pts[1].Y),if spline:edgeAt(s,side)==Spline.ROCK then 4 else 0)
					local declared=spline:boundaryHeight(s,side)
					local rail=spline:outerRailAt(s)
					local gap=if declared>0 then declared-height else math.max(0,1-height)
					if rail or gap<=.01 then covered+=1 else
						worst=math.max(worst,gap)
						if declared>0 then lowRock+=1 else flatDrop+=1 end
					end
					total+=1
					tick()
				end
			end
		end
		check("every finite boundary is a visible face/drop or outer rail",covered==total,`{covered}/{total}; uncovered rock {lowRock}, drop {flatDrop}, largest gap {worst}`)
		-- Samples actual wedge top faces, including each field/bank interior and bevel.
		local missing,worstError,samples,partCount,maxSlice=0,0,0,0,0
		local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={folder}
		for _,s0 in {200,1600,2800} do
			local chunk=Instance.new("Folder");chunk.Parent=folder
			local parts,stats=Parts.build(spline,s0,s0+96,chunk,{terrain=true,queryable=true,sliceMs=3})
			partCount+=#parts;maxSlice=math.max(maxSlice,stats.sliceMs)
			for s=s0+1.3,s0+95,7.1 do
				for _,side in {-1,1} do
					local w=spline:runoffAt(s,side)
					for _,u in {.03,.15,.33,.57,.81,.97} do
						local d=side*(half+w*u)
						local p=Vector3.new(spline:terrainXYZ(s,d))
						local hit=workspace:Raycast(p+Vector3.yAxis*2,-Vector3.yAxis*4,params)
						if not hit then missing+=1 else worstError=math.max(worstError,math.abs(hit.Position.Y-p.Y)) end
						samples+=1
					end
				end
			end
			chunk:Destroy()
		end
		check("fallback wedges follow the supported terrain",missing==0 and worstError<=.2,`{samples} interior rays, {missing} missing, largest height error {worstError}`)
		check("fallback build yields within a bounded slice",maxSlice<16,`{partCount} parts across three 96-stud samples; worst slice {maxSlice} ms`)
		local runs=Boundary.runs(spline,0,480)
		local before=table.clone(runs)
		gen:extendTo(15000)
		local after=Boundary.runs(spline,0,480)
		local stable=#before==#after
		for i,v in before do stable=stable and math.abs(v-after[i])<1e-6 end
		check("new neighbours cannot move outer protection",stable,`{#runs/2} runs in first chunk`)
		-- An asymmetric field can be closer to the next leg's centre line while
		-- still belonging to the first leg. Gameplay must keep its accepted arc.
		local sp=Spline.new({x=0,y=0,z=0,yaw=0})
		sp.fall=math.pi*.5
		sp:append({len=600,k={600,0},g={600,0},b={600,0},rl={80,80,600,80},rr={80,80,600,80},el={600,Spline.ROCK},er={600,Spline.CLIFF},bm={0,1,0}})
		local turn=math.pi*100+50
		sp:append({len=turn,k={50,.01,turn-50,.01,turn,0},g={turn,0},b={turn,0},rl={turn,12},rr={turn,12},el={turn,Spline.ROCK},er={turn,Spline.CLIFF}})
		sp:append({len=600,k={600,0},g={600,0},b={600,0},rl={600,12},rr={600,12},el={600,Spline.ROCK},er={600,Spline.CLIFF}})
		local seq=setmetatable({spline=sp,first=1,last=3,starts={0,600,600+turn},pieces={
			{n=1,s0=0,length=600},{n=2,s0=600,length=turn},{n=3,s0=600+turn,length=600}},furthestN=1,furthestT=0},Sequence)
		local at=Vector3.new(sp:terrainXYZ(300,-104))
		local broad=seq:locate(at)
		local owned,_,lateral,accepted=seq:locateOwned(at,300)
		check("wide grass retains its owner beside a nearer leg",owned==1 and broad==3 and accepted and math.abs(accepted-300)<.01,`broad piece {broad}; owned {owned}; lateral {lateral}`)
		local grass=seq:progressAt(1,.7,100)
		check("grass cannot earn progress",not grass.forwardOnNewRoad and seq.furthestT==0,"ownership and earned progress are separate")
		local road=seq:progressAt(1,.5,0)
		check("a local asphalt re-entry earns progress",road.forwardOnNewRoad and seq.furthestT==.5,"accepted projection is consumed without searching again")
		local off=Vector3.new(sp:terrainXYZ(300,-110))
		check("leaving finite ground never acquires another leg",seq:locateOwned(off,300)==nil,"no broad fallback after support ends")
		local other=Vector3.new(sp:terrainXYZ(600+turn+300,0))
		check("a different runner can hold a different leg",seq:locateOwned(other,600+turn+300)==3,"the sequence has no shared mutable ownership hint")
		local catchup=Vector3.new(sp:terrainXYZ(500,0))
		check("a delayed tick catches up within the same bounded road arc",seq:locateOwned(catchup,100,640)==1,"a 400-stud tick does not permanently freeze the accepted hint")
		check("asphalt re-entry cannot defer a field shortcut",seq:reentryS(100,100,400)<220,"300studs of arc skipped by100studs of travel cannot become full progress on re-entry")
		check("ordinary off-road drift can rejoin without losing progress",seq:reentryS(100,100,200)==200,"normal travel covers its projected advance")
		local rock=Instance.new("Folder");rock.Parent=folder
		Boundary.build(sp,280,320,rock)
		for _,p in rock:GetDescendants() do if p:IsA("BasePart") then p.CanQuery=true end end
		params.FilterDescendantsInstances={rock}
		local edge=half+sp:runoffAt(300,-1)
		local top=Vector3.new(sp:terrainXYZ(300,-edge))
		local tip=Vector3.new(sp:terrainXYZ(300,-edge-2))
		local rim=workspace:Raycast(Vector3.new(tip.X,top.Y+8,tip.Z),-Vector3.yAxis*12,params)
		check("the stable rock foot is actually drawn to its solid height",rim~=nil and math.abs(rim.Position.Y-top.Y-4)<.06,`drawn rise {rim and rim.Position.Y-top.Y}`)
		rock:Destroy()
		local brief=Spline.new({x=0,y=0,z=0,yaw=math.pi/4+.00012});brief.fall=0
		brief:append({len=6,k={2,-.0001,4,.0001,6,0},g={6,0},b={6,0},bm={0,1,0}})
		local short=Boundary.runs(brief,0,6)
		check("a brief rail-angle crossing cannot disappear between samples",#short==2 and short[1]>2 and short[2]<4,`rail endpoints {short[1]}, {short[2]}`)
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	folder:Destroy();Config.Spline.Biomes.GroundEnabled=old
	if not ok then return {passed=0,total=1,checks={{name="terrain drawing fixture completes",ok=false,detail=result}}} end
	return result
end
function Tests.lifecycle()
	local View=require(game.StarterPlayer.StarterPlayerScripts.Drift.SplineRoadView)
	local Mesh=require(RS.Shared.Road.SplineMesh)
	local gen=Gen.new(203);gen:extendTo(1500)
	local view=View.new(gen.spline)
	view.forceFallback=true;view:_start(0)
	local deadline=os.clock()+15
	while view.building and os.clock()<deadline do task.wait() end
	local built=view:DebugState()
	local checks={{name="a complete forced fallback is published in bounded slices",ok=built.chunks==1 and built.fallbackParts>0 and built.worstSliceMs<20,detail=game:GetService("HttpService"):JSONEncode(built)}}
	-- Put a real mesh behind an earlier fallback folder. Its slot must be freed
	-- synchronously, before the large folder's retirement first yields.
	local model,info=Mesh.build(gen.spline,480,576,view.folder)
	if model then
		view:Destroy()
		table.insert(checks,{name="destroy frees every mesh before draining parts",ok=model.Parent==nil,detail="fallback folder inserted before the real mesh"})
	else
		view:Destroy()
		table.insert(checks,{name="a real mesh is available for the lifetime check",ok=false,detail=tostring(info)})
	end
	deadline=os.clock()+15
	while view.folder.Parent and os.clock()<deadline do task.wait() end
	table.insert(checks,{name="fallback retirement releases its whole tree",ok=view.folder.Parent==nil,detail="bounded child batches finish after destroy"})
	local cancelled=View.new(gen.spline);cancelled.forceFallback=true;cancelled:_start(0)
	task.wait(.1);cancelled:Destroy()
	deadline=os.clock()+15
	while (cancelled.building or cancelled.folder.Parent) and os.clock()<deadline do task.wait() end
	table.insert(checks,{name="cancelling a partly built fallback leaves no pending view",ok=cancelled.building==nil and cancelled.folder.Parent==nil,detail="build stopped before the full480-stud chunk was ready"})
	local passed=0;for _,c in checks do if c.ok then passed+=1 end end
	return {passed=passed,total=#checks,checks=checks}
end

return Tests
