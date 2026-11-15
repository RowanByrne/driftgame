--!nonstrict
-- Frozen connector data and physical support; route ownership is deliberately separate.
assert(game:GetService("RunService"):IsStudio(),"SplineInfieldTests is Studio only")
local DefaultInfield=require(game.ReplicatedStorage.Shared.Road.SplineInfield)
local Tests={}

local function fixture(Spline,rise)
	local sp=Spline.new({x=0,y=50,z=-20000,yaw=0});sp.fall=math.pi*.5
	local sections={}
	local function append(sec)table.insert(sections,sec);sp:append(sec)end
	local function section(length,knots,left,right,bank)
		return {len=length,k=knots,g={length,0},b={length,0},rl={length,16},rr={length,16},
			el={length,left},er={length,right},hl={length,bank},hr={length,0}}
	end
	local a=section(512,{512,0},Spline.ROCK,Spline.CLIFF,rise);a.bm={0,1,0};append(a)
	local length=math.pi*100+20
	append(section(length,{20,.01,length-20,.01,length,0},Spline.ROCK,Spline.CLIFF,0))
	local b0=sp.length
	append(section(320,{320,0},Spline.CLIFF,Spline.ROCK,0))
	return sp,b0,sections
end

function Tests.run(_self,subject)
	local Infield=subject or DefaultInfield
	local checks={}
	local function check(name,ok,detail)table.insert(checks,{name=name,ok=ok,detail=detail})end
	local function rows(y0,y1)
		return {
			{sa=100,sb=900,sideA=1,sideB=-1,a={0,y0,0},b={40,y1,0},weight=1},
			{sa=120,sb=880,sideA=1,sideB=-1,a={0,y0,-20},b={40,y1,-20},weight=1},
		}
	end
	local source=rows(0,2)
	local patch=Infield.patch("fixture",source)
	source[1].a[2]=1000;source[1].weight=0
	check("published boundaries are independent of mutable planning data",patch.rows[1].a[2]==0 and patch.rows[1].weight==1,
		"numeric points and both bank arcs are frozen copies")
	local index=Infield.new(16)
	check("replaying a patch identity adds it once",Infield.add(index,patch) and not Infield.add(index,patch) and #index.triangles==4,
		"two rendering halves share one physical midline")
	local samples,missing,error,normal=0,0,0,0
	for x=0,40,1 do for z=-20,0,1 do
		local hit=Infield.sample(index,x,z)
		if not hit then missing+=1 else
			error=math.max(error,math.abs(hit.y-x*.05))
			normal=math.max(normal,(hit.normal-Vector3.new(-.05,1,0).Unit).Magnitude)
		end
		samples+=1
	end end
	check("both banks and the entire flat connector have continuous support",missing==0 and error<1e-6 and normal<1e-6,
		`{samples} samples; {missing} missing, height error {error}, normal gap {normal}`)
	check("the finite connector provides no hidden ground outside its perimeter",Infield.sample(index,-.01,-10)==nil and Infield.sample(index,40.01,-10)==nil
		and Infield.sample(index,20,.01)==nil and Infield.sample(index,20,-20.01)==nil,"support is the published polygon")
	local owner=110
	local near=Infield.sample(index,1,-10)
	local far=Infield.sample(index,39,-10)
	check("contact can reach the opposite bank without changing the accepted route",near.contactS==110 and far.contactS==890 and owner==110,
		"physical contact identifies each bank; the caller retains its own route")
	check("bounded accepted ownership stays on its original bank across the field",Infield.route(far,110,160,patch)==110
		and Infield.route(near,890,160,patch)==890 and Infield.route(far,nil,160,patch)==nil and Infield.route(far,4000,160,patch)==nil,
		"physical bank choice cannot establish or replace route history")
	local delayedRows=rows(0,0);delayedRows[1].sb=600;delayedRows[2].sa=500;delayedRows[2].sb=550
	local delayedPatch=Infield.patch("delayed",delayedRows);local delayed=Infield.new();Infield.add(delayed,delayedPatch)
	check("a delayed move cannot switch to whichever bank arc is now closer",Infield.route(Infield.sample(delayed,20,0),500,160,delayedPatch)==nil,
		"an excessive owner-side advance is refused even if the other bank lies within the limit")
	local links=Infield.links(index,110)
	check("the known opposite bank is paired without a nearby-road search",#links==1 and links[1].peerS==890
		and Infield.pair(patch,"B",890)==110 and Infield.pair(patch,"A",99)==nil,
		"forward and inverse pairing use the same frozen rows")
	check("nearby ground includes both physical halves independently of the road window",#Infield.near(index,20,-10,30)==4,
		"a world-space query returns complete nearby ground")
	local contours=Infield.closing(index,500)
	local contourLength,contourError=0,0
	for _,line in contours do
		local a,b=line.a,line.b
		contourLength+=math.sqrt((b[1]-a[1])^2+(b[3]-a[3])^2)
		local x,z=(a[1]+b[1])*.5,(a[3]+b[3])*.5
		local hit=Infield.sample(index,x,z)
		contourError=math.max(contourError,math.abs(hit.closingS-500))
	end
	check("closure crosses a field even while its road arc lies between both bank ranges",#contours>0 and math.abs(contourLength-20)<1e-6 and contourError<1e-6,
		`{#contours} exact triangle segments; length{contourLength}, scalar error{contourError}`)
	local early=Infield.closing(index,110)
	local farthest=0
	for _,line in early do farthest=math.max(farthest,line.a[1],line.b[1]) end
	check("a closing on the early bank leaves later peer traffic unobstructed",#early>0 and farthest<1,
		"the connected contour returns to the finite field edge before reaching live peer asphalt")
	check("height-limited probes reject a ceiling and a floor beyond their ray",Infield.sample(index,20,-10,2,4)==nil
		and Infield.sample(index,20,-10,-4,0)==nil and Infield.sample(index,20,-10,0,2)~=nil,"one indexed height query, no nearest-road reacquisition")
	check("both opposed bank openings share a smooth end taper",Infield.opening(index,110,1)==1 and Infield.opening(index,890,-1)==1
		and math.abs(Infield.opening(index,102.5,1)-.5)<1e-8 and math.abs(Infield.opening(index,882.5,-1)-.5)<1e-8
		and Infield.opening(index,99.99,1)==0 and Infield.opening(index,900.01,-1)==0 and Infield.opening(index,110,-1)==0,
		"the taper stays inside real support and short patches retain a fully open middle")
	local a=Infield.triangles(index,100,120)
	local b=Infield.triangles(index,880,900)
	check("each leg receives exactly its rendering half",#a==2 and #b==2,"four exact physical triangles, two per arc owner")
	check("eligibility depends on actual height, spacing and cross-gap slope",Infield.strength(0,40,4,16,96,240,.3)==1
		and Infield.strength(4,2,4,16,96,240,.3)==0 and Infield.strength(20,80,4,16,96,240,.3)==0
		and Infield.strength(0,300,4,16,96,240,.3)==0,"a near-level label cannot make an impossible short ramp drivable")
	local folded=rows(0,0);folded[2].b={-40,0,-20}
	local before=#index.triangles
	local ok=pcall(function()Infield.add(index,Infield.patch("folded",folded))end)
	check("a folded patch is rejected before any index publication",not ok and #index.triangles==before and index.patches.folded==nil,
		"no partial cells survive an invalid pairing")
	local reversed=rows(0,0);reversed[2].sb=920
	check("pairing cannot reverse halfway along an opposed bank",not pcall(function()Infield.patch("reversed",reversed)end),"old arc must move monotonically backwards")
	local crossed=rows(0,0);crossed[2].sa=890;crossed[2].sb=880
	check("approach and departure ownership ranges cannot overlap",not pcall(function()Infield.patch("crossed ranges",crossed)end),
		"the frozen pair retains two disjoint route histories")
	local loop={
		{sa=0,sb=60,sideA=1,sideB=-1,a={0,0,0},b={0,0,10},weight=1},
		{sa=10,sb=50,sideA=1,sideB=-1,a={10,0,0},b={10,0,10},weight=1},
		{sa=20,sb=40,sideA=1,sideB=-1,a={0,0,0},b={0,0,10},weight=1},
	}
	check("a strip cannot double back between otherwise valid cells",not pcall(function()Infield.add(Infield.new(),Infield.patch("loop",loop))end),
		"one orientation and spatially disjoint cells across the whole published patch")
	local oldY=Infield.sample(index,20,-10).y
	local overlap=pcall(function()Infield.add(index,Infield.patch("overlap",rows(10,12)))end)
	check("later support cannot cover or raise occupied connector ground",not overlap and Infield.sample(index,20,-10).y==oldY and index.patches.overlap==nil,
		"spatial reservation is checked before any new triangles or masks are published")
	check("a repeated identity cannot hide different geometry",not pcall(function()Infield.add(index,Infield.patch("fixture",rows(1,3)))end),"identical replay is idempotent; conflicting data is refused")
	local collarRows=rows(25,25)
	for _,row in collarRows do row.da=.3;row.db=.3 end
	local collar=Infield.new();Infield.add(collar,Infield.patch("collar",collarRows))
	local nearBank=Infield.sample(collar,.01,-10)
	local angle=math.deg(math.acos(math.clamp(nearBank.normal:Dot(Vector3.new(-.3,1,0).Unit),-1,1)))
	local middle=Infield.sample(collar,20,-10)
	check("short collars preserve incoming bank slope before the flat middle",angle<5 and middle.y<27 and math.abs(middle.normal.Y-1)<1e-6
		and Infield.sample(collar,0,-10).y==25 and Infield.sample(collar,40,-10).y==25,`bank normal gap {angle} degrees; middle height {middle.y}`)
	local explicitRows=rows(0,2)
	for _,row in explicitRows do
		local heights={};for _,p in Infield.columns(row) do table.insert(heights,p[2]) end;row.floor=heights
		row.weight=.3
	end
	local explicitPatch=Infield.patch("explicit",explicitRows)
	explicitRows[1].floor[6]=999
	local explicit=Infield.new();Infield.add(explicit,explicitPatch)
	check("explicit end sections freeze exactly the same final floor columns",Infield.sample(explicit,20,-10).y==1
		and #Infield.triangles(explicit,100,120)==10 and explicitPatch.rows[1].floor[6]==1,
		"final numeric columns are shared by support and drawing")
	check("explicit section openings use the stored geometry blend once",math.abs(Infield.opening(explicit,100,1)-.3)<1e-8
		and math.abs(Infield.opening(explicit,110,1)-.3)<1e-8,"no extra analytic fade changes the frozen end blend")
	local steepRows=rows(0,0)
	for _,row in steepRows do row.floor={0,20,20,20,20,20,20,20,20,20,0} end
	local steep=Infield.new();Infield.add(steep,Infield.patch("retained terrain",steepRows))
	check("a retained steep end face is drawn without invisible physical support",Infield.sample(steep,.1,-10)==nil
		and #Infield.triangles(steep,100,120)==10 and Infield.sample(steep,20,-10).y==20,
		"only triangles within the original supported slope limit provide ground")
	local high=Infield.new();Infield.add(high,Infield.patch("high",{
		{sa=100,sb=900,sideA=1,sideB=-1,a={50000,100,-20000},b={50040,102,-20000},weight=1},
		{sa=120,sb=880,sideA=1,sideB=-1,a={50000,100,-20020},b={50040,102,-20020},weight=1},
	}))
	local h=Infield.sample(high,50020,-20010)
	check("large world coordinates preserve the same physical surface",h and math.abs(h.y-101)<1e-6 and h.normal.Y>.99,"frozen geometry stays stable far along the run")
	local precise=Infield.new()
	local fx,fz,fy=50000.0001234,-20000.0004567,10.123456789
	Infield.add(precise,Infield.patch("precise",{
		{sa=100,sb=900,sideA=1,sideB=-1,a={fx,fy,fz},b={fx+40,fy+2,fz},weight=1},
		{sa=120,sb=880,sideA=1,sideB=-1,a={fx,fy,fz-20},b={fx+40,fy+2,fz-20},weight=1},
	}))
	local exact=Infield.sample(precise,fx+20,fz-10)
	local localFaces=Infield.triangles(precise,100,120,Vector3.new(50000,10,-20000))
	check("physical contacts retain doubles and rendering subtracts origin before packing",math.abs(exact.y-fy-1)<1e-9
		and math.abs(localFaces[1][1].X-(fx-50000))<1e-9,"world fractions survive both contact and local mesh coordinates")
	local passed=0;for _,item in checks do if item.ok then passed+=1 end end
	return {passed=passed,total=#checks,checks=checks}
end

function Tests.planner(_self,subjects)
	local road=game.ReplicatedStorage.Shared.Road
	local Spline=subjects and subjects.Spline or require(road.Spline)
	local Planner=subjects and subjects.Planner or require(road.SplineInfieldPlanner)
	local Infield=subjects and subjects.Infield or DefaultInfield
	local Corridor=subjects and subjects.Corridor or require(road.SplineCorridor)
	local cfg=require(game.ReplicatedStorage.Shared.Config)
	local saved=cfg.Spline.Biomes.GroundEnabled
	cfg.Spline.Biomes.GroundEnabled=true
	local ok,result=xpcall(function()
		local checks={}
		local function check(name,pass,detail)table.insert(checks,{name=name,ok=pass,detail=detail})end
		local sp,b0,sections=fixture(Spline,20)
		local patches,cells=Planner.plan(sp,128,480,b0,sp.length)
		check("a level turnaround uses actual tarmac height despite different frozen bank lifts",#patches>0 and #cells>0,
			`{#patches} frozen patches and {#cells} reserved cells; bank difference20studs`)
		local floor=Infield.new()
		for _,patch in patches do Infield.add(floor,patch) end
		local sampleCount=0;local largest=0;local endBlend=true
		for _,patch in patches do
			endBlend=endBlend and patch.rows[1].weight==0 and patch.rows[#patch.rows].weight==0
			for _,r in patch.rows do
				if r.weight>.99 then
					local p=Infield.columns(r)[6];local hit=Infield.sample(floor,p[1],p[3])
					if hit then sampleCount+=1;largest=math.max(largest,math.abs(hit.y-(r.a[2]+r.b[2])*.5)) end
				end
			end
		end
		check("the eligible middle has low shared ground and stored end transitions",sampleCount>0 and largest<2 and endBlend,
			`{sampleCount} full-strength middle rows; bank-average error{largest}`)
		local oldX,oldY,oldZ=sp:terrainXYZ(300,-41)
		sp:addInfields(patches)
		local x,y,z=sp:terrainXYZ(300,-41)
		check("publishing field terrain never changes an occupied bank",oldX==x and oldY==y and oldZ==z and sp.infieldRevision==1,
			"old bank height, position and route tracks stay exact")
		local replay=Spline.new(sp.origin);replay.fall=sp.fall
		for i,sec in sections do local copy=table.clone(sec);if i==#sections then copy.ip=patches end;replay:append(copy) end
		check("serialized newer-section fields replay the same frozen support",#replay.infields.triangles==#sp.infields.triangles
			and replay.infieldRevision==1,"both legs and final floor heights arrive in plain section data")
		local midRow=nil
		for _,r in patches[1].rows do if r.weight==1 then midRow=r;break end end
		if midRow then
			local points=Infield.columns(midRow)
			local p=points[6]
			local a=sp:infieldContact(p[1],p[3],midRow.sa,p[2]-1,p[2]+1)
			local b=sp:infieldContact(p[1],p[3],midRow.sb,p[2]-1,p[2]+1)
			check("actual Spline field contacts retain each caller's accepted leg",a and b and math.abs(a.ownerS-midRow.sa)<1e-6
				and math.abs(b.ownerS-midRow.sb)<1e-6 and a.kind==Spline.GRASS and math.abs(a.routeD)>cfg.Road.Width*.5,
				"the same floor supplies independent route-owned grass contacts")
			local px,py,pz=sp:surfaceXYZ(midRow.sb,0)
			local peer=sp:infieldContact(px,pz,midRow.sa,py-1,py+1)
			check("opposite-bank physical contact does not claim opposite-leg progress",peer and peer.kind==Spline.TARMAC
				and math.abs(peer.contactS-midRow.sb)<1e-5 and math.abs(peer.ownerS-midRow.sa)<1e-5
				and math.abs(peer.routeD)>cfg.Road.Width*.5,"physical road grip remains separate from route progress")
			check("retired accepted ownership cannot transfer onto the live opposite bank",sp:infieldContact(p[1],p[3],midRow.sa,p[2]-1,p[2]+1,160,midRow.sa+1)==nil
				and sp:infieldContact(px,pz,midRow.sa,py-1,py+1,160,midRow.sa+1)==nil,
				"both field and known-peer paths refuse retired owner history")
			if subjects and subjects.World then
				local world=subjects.World.new(sp);world.hint=midRow.sa
				local pos=Vector3.new(p[1],p[2]+cfg.Drift.RideHeight,p[3])
				local ground=world.probe(pos)
				local along,lateral=world.locate(pos)
				check("the real car world finds the shared floor beyond ordinary finite banks",ground and ground.surface=="grass"
					and math.abs(ground.y-p[2])<.02 and math.abs(world.hint-midRow.sa)<.05
					and along and math.abs(lateral)>cfg.Road.Width*.5,"height, grip and route-owned location come from one field contact")
				local peerGround=world.probe(Vector3.new(px,py+cfg.Drift.RideHeight,pz))
				check("the car receives real opposite-bank grip while retaining accepted ownership",peerGround and peerGround.surface=="tarmac"
					and math.abs(peerGround.y-py)<.02 and math.abs(world.hint-midRow.sa)<.05,"physical contact is not a route handoff")
				local from=Vector3.new(midRow.a[1],midRow.a[2]+cfg.Drift.RideHeight,midRow.a[3])
				local stopped=world.sweep(from,pos,sp:yawAt(midRow.sa))
				local pushed,depth=world.penetration(pos,sp:yawAt(midRow.sa))
				check("the real car crosses a certified opening without a hidden bank wall",not stopped and not pushed and depth==0,
					`sweep={tostring(stopped)}, push={tostring(pushed)}, depth={depth}; opening={sp:infieldOpening(midRow.sa,midRow.sideA)}`)
				world.setClosing(midRow.sa+1)
				check("the real car cannot reacquire a field using retired ownership",world.probe(pos)==nil,
					"closure is checked before opposite-bank support")
				world.destroy()
			end
			if subjects and subjects.Sequence then
				local seq=setmetatable({spline=sp,first=1,last=#sections,starts={},pieces={},furthestN=1,furthestT=0},subjects.Sequence)
				local s=0
				for i,sec in sections do seq.starts[i]=s;seq.pieces[i]={n=i,s0=s,s1=s+sec.len,length=sec.len};s+=sec.len end
				local n,t,lateral,owner=seq:locateOwned(Vector3.new(p[1],p[2]+2,p[3]),midRow.sa,160)
				local state=n and seq:progressAt(n,t,lateral)
				local pn,pt,plateral,powner=seq:locateOwned(Vector3.new(px,py+2,pz),midRow.sa,160)
				check("the real sequence keeps field and known-peer contacts off earned asphalt",n and pn and owner and powner
					and math.abs(owner-midRow.sa)<.05 and math.abs(powner-midRow.sa)<.05
					and lateral>cfg.Road.Width*.5 and plateral>cfg.Road.Width*.5 and seq.furthestT==0,
					"both physical locations retain the original owner and advance no route progress")
			end
		end
		if patches[1] then
			local moved={}
			for _,r in patches[1].rows do
				local q=table.clone(r);q.a={r.a[1]+1000,r.a[2],r.a[3]};q.b={r.b[1]+1000,r.b[2],r.b[3]};table.insert(moved,q)
			end
			local one,two=Infield.patch("atomic one",moved),Infield.patch("atomic two",moved)
			local count=#sp.infields.triangles
			local accepted=pcall(function()sp:addInfields({one,two})end)
			check("a later invalid patch cannot partially publish a batch",not accepted and #sp.infields.triangles==count
				and sp.infields.patches["atomic one"]==nil and sp.infieldRevision==1,"geometry and revision remain unchanged together")
			local beforeLength,beforeKnots=sp.length,#sp.curv.s
			local sec=table.clone(sections[#sections]);sec.ip={one,two}
			local appended=pcall(function()sp:append(sec)end)
			check("invalid section fields fail before any route tracks append",not appended and sp.length==beforeLength
				and #sp.curv.s==beforeKnots and #sp.infields.triangles==count,"the section and its fields publish together")
		end
		local blocked=Corridor.new()
		-- A narrow unrelated arm crosses the interior of the proposed field.
		blocked:add(Corridor.cell(Corridor.row(300,-100,-20200,0,0,10,10),Corridor.row(308,-100,-20500,0,0,10,10)))
		local another,b=fixture(Spline,20)
		local refused=Planner.plan(another,128,480,b,another.length,blocked)
		check("a connector cannot cover an occupied road inside either attached arc range",#refused==0,
			"positive-area overlap is refused even when the obstacle has an attached arm's arc")
		local patch=patches[1]
		if patch then
			local protected=Corridor.new();for _,cell in cells do protected:add(cell) end
			local middle=patch.rows[math.ceil(#patch.rows*.5)]
			local p=Infield.columns(middle)[6]
			local candidate=Corridor.cell(Corridor.row(middle.sa,p[1],p[3]-2,0,0,2,2),Corridor.row(middle.sa+4,p[1],p[3]+2,0,0,2,2))
			check("future adjacent sections cannot use arc separation to cross reserved field ground",not protected:clear(candidate,100000,0),
				"connector reservations have no generic neighbouring-section exemption")
		end
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	cfg.Spline.Biomes.GroundEnabled=saved
	if not ok then return {passed=0,total=1,checks={{name="planner fixture completes",ok=false,detail=result}}} end
	return result
end

function Tests.closing(_self,subjects)
	local road=game.ReplicatedStorage.Shared.Road
	if not subjects then
		local drift=game.StarterPlayer.StarterPlayerScripts.Drift
		subjects={World=require(drift.SplineWorld),View=require(drift.SplineRoadView)}
	end
	local Spline=subjects and subjects.Spline or require(road.Spline)
	local Planner=subjects and subjects.Planner or require(road.SplineInfieldPlanner)
	local Infield=subjects and subjects.Infield or DefaultInfield
	local Boundary=subjects and subjects.Boundary or require(road.SplineBoundary)
	local cfg=require(game.ReplicatedStorage.Shared.Config)
	local saved=cfg.Spline.Biomes.GroundEnabled;cfg.Spline.Biomes.GroundEnabled=true
	local ok,result=xpcall(function()
		local checks={};local function check(name,pass,detail)table.insert(checks,{name=name,ok=pass,detail=detail})end
		local sp,b0,sections=fixture(Spline,20);sp:addInfields(Planner.plan(sp,128,480,b0,sp.length))
		local panels=sp:closingPanels(600)
		local fields,specError=0,0
		for _,p in panels do
			if p.field then fields+=1 end
			local cf,size=Boundary.closingSpec(p)
			local centre=cf.Position+p.normal*(size.Z*.5)
			specError=math.max(specError,math.abs(centre.X-(p.a[1]+p.b[1])*.5),math.abs(centre.Z-(p.a[3]+p.b[3])*.5))
		end
		check("field closing panels share one cached frozen front edge",fields>0 and panels==sp:closingPanels(600) and specError<.005,
			`{fields} field panels; front-edge packing error{specError}`)
		check("shared closing front edges cannot be changed by a consumer",not pcall(function()panels[1].a[1]+=1 end),
			"cached panel vertices and records are immutable")
		local p={a={0,0,0},b={10,0,0},normal=Vector3.zAxis,bottom=-3,top=24,depth=1,field=true}
		local front,fn=Boundary.closingSweep(p,5,2,5,-2)
		local back,bn=Boundary.closingSweep(p,5,-2,5,2)
		check("closing slabs stop entry from their real front and back faces",front and back and math.abs(front-.5)<1e-8
			and math.abs(back-.25)<1e-8 and fn.Z==1 and bn.Z== -1,"one-stud depth, front0 and back-1")
		local endpoint,en=Boundary.closingSweep(p,-5,-.5,5,-.5)
		local diagonal,dn=Boundary.closingSweep(p,-5,-2,5,-.5)
		check("finite closing slabs catch endpoint and diagonal entry",endpoint and diagonal and math.abs(endpoint-.5)<1e-8
			and math.abs(diagonal-2/3)<1e-8 and en.X== -1 and dn.Z== -1,"a start beyond the segment cannot skip its end cap")
		local depth,n=Boundary.closingPush(p,5,-.5,.05)
		local outside=Boundary.closingPush(p,-.1,-.5,.05)
		check("closing penetration uses the same finite slab",depth>.5 and n~=nil and outside==0,"no infinite half-plane beyond an endpoint")
		local small=table.clone(p);small.b={.01,0,0}
		local _,size=Boundary.closingSpec(small)
		local push=Boundary.closingPush(small,-.019,-.5,0)
		check("minimum Part size and physical endpoint extents agree",math.abs(size.X-.05)<1e-6 and push>0,"tiny contour segments use the same real0.05stud box")
		local patch=next(sp.infields.patches) and sp.infields.patches[next(sp.infields.patches)]
		local row=patch.rows[math.ceil(#patch.rows*.5)]
		local hit=nil
		for _,panel in panels do local t=Boundary.closingSweep(panel,row.a[1],row.a[3],row.b[1],row.b[3]);if t then hit=math.min(hit or 1,t) end end
		check("the triangle contour closes a route across the connected field",hit~=nil and hit>0 and hit<1,"a crossing from retired A towards later B meets a real finite panel")
		local x0,_,z0=sp:surfaceXYZ(row.sb-16,0);local x1,_,z1=sp:surfaceXYZ(row.sb+16,0)
		local peerBlocked=false
		for _,panel in panels do if Boundary.closingSweep(panel,x0,z0,x1,z1) then peerBlocked=true;break end end
		check("the later live peer road remains open",not peerBlocked,"ordinary B traffic crosses neither the field contour nor the older road slab")
		if subjects.World then
			local world=subjects.World.new(sp);world.hint=row.sa;world.setClosing(600)
			local from=Vector3.new(row.a[1],row.a[2]+cfg.Drift.RideHeight,row.a[3])
			local to=Vector3.new(row.b[1],row.b[2]+cfg.Drift.RideHeight,row.b[3])
			local stopped=world.sweep(from,to,sp:yawAt(row.sa))
			check("the real car cannot bypass the closing through a connected field",stopped~=nil and world.stats.closingStops>0,
				"the car's whole footprint meets the shared finite panels")
			world.destroy()
			local peer=subjects.World.new(sp);peer.hint=row.sb;peer.setClosing(600)
			local by=sp:heightAt(row.sb)+cfg.Drift.RideHeight
			check("the real later-leg car keeps ground and clear passage",peer.probe(Vector3.new(x0,by,z0))~=nil
				and peer.sweep(Vector3.new(x0,by,z0),Vector3.new(x1,by,z1),sp:yawAt(row.sb))==nil,
				"an older field closure does not stop native live B traffic")
			peer.destroy()
		end
		if subjects.View then
			local parent=Instance.new("Folder");parent.Name="__ClosingPanelViewTest";parent.Parent=workspace
			local view=subjects.View.new(sp,parent);view:SetClosing(600)
			local drawn,error=0,0
			for i,panel in panels do
				local part=if panel.field then view.closingFields:FindFirstChild(`ClosingField_{i}`) else view.closing
				if not part then error=math.huge;continue end
				local cf,size=Boundary.closingSpec(panel)
				error=math.max(error,(part.CFrame.Position-cf.Position).Magnitude,(part.Size-size).Magnitude)
				drawn+=1
			end
			check("the actual visible barrier uses the collision panel geometry",drawn==#panels and error<.005,
				`{drawn} actual Parts, placement/size error{error}`)
			local before=view.closingFields
			sp.infieldRevision+=1;view.building=-1;view:Update(row.sa);view.building=nil
			check("new field geometry refreshes closure during a pending road build",view.closingFields~=before and view.closingRevision==sp.infieldRevision,
				"panel refresh follows field revision as well as closing messages")
			view:SetClosing(nil);view:Destroy();parent:Destroy()
		end
		local future=sp.length+8
		local pending=sp:closingPanels(future)
		local lifecycleParent,lateView,retiringView=nil,nil,nil
		if subjects.View then
			lifecycleParent=Instance.new("Folder");lifecycleParent.Name="__ClosingRefreshTest";lifecycleParent.Parent=workspace
			lateView=subjects.View.new(sp,lifecycleParent);lateView:SetClosing(future)
			retiringView=subjects.View.new(sp,lifecycleParent);retiringView:SetClosing(600)
		end
		sp:append(sections[#sections])
		check("a closing received before its road is not cached as permanently empty",#pending==0 and #sp:closingPanels(future)==1,
			"new retained road length refreshes the base panel")
		if lateView then
			lateView.building=-1;lateView:Update(row.sb);lateView.building=nil
			check("the visible barrier appears when its delayed road arrives",lateView.closing~=nil,
				"an unchanged closing message still responds to newly available geometry")
		end
		sp:trim(b0+16)
		local retired=sp:closingPanels(600);local allFrozen=#retired>0
		for _,panel in retired do allFrozen=allFrozen and panel.field end
		check("retired A geometry is not reconstructed to close the remaining field",allFrozen and retired~=panels,
			"retirement invalidates the cache and the contour uses only frozen vertices")
		if retiringView then
			retiringView.building=-1;retiringView:Update(row.sb);retiringView.building=nil
			check("the visible field closure refreshes when its old leg retires",retiringView.closing==nil
				and retiringView.closingFields~=nil and retiringView.closingFirst==sp.firstSample,
				"the retired base panel disappears while the frozen field contour remains")
			lateView:Destroy();retiringView:Destroy();lifecycleParent:Destroy()
		end
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	cfg.Spline.Biomes.GroundEnabled=saved
	if not ok then return {passed=0,total=1,checks={{name="field closing fixture completes",ok=false,detail=result}}} end
	return result
end

function Tests.contacts(_self,subjects)
	local road=game.ReplicatedStorage.Shared.Road
	local Spline=subjects and subjects.Spline or require(road.Spline)
	local Planner=subjects and subjects.Planner or require(road.SplineInfieldPlanner)
	local Infield=subjects and subjects.Infield or DefaultInfield
	local Contact=subjects and subjects.Contact or require(road.SplineContact)
	local cfg=require(game.ReplicatedStorage.Shared.Config)
	local saved=cfg.Spline.Biomes.GroundEnabled;cfg.Spline.Biomes.GroundEnabled=true
	local ok,result=xpcall(function()
		local checks={};local function check(name,pass,detail)table.insert(checks,{name=name,ok=pass,detail=detail})end
		local sp,b0,sections=fixture(Spline,20)
		local patches=Planner.plan(sp,128,480,b0,sp.length);sp:addInfields(patches)
		-- The field freezes before additional real peer road arrives.
		sp:append(sections[#sections])
		local patch=patches[1];local row=patch.rows[math.ceil(#patch.rows*.5)]
		local px,py,pz=sp:surfaceXYZ(row.sb,0)
		local function resolve(s,owner,token,limit,override)
			local x,y,z=sp:surfaceXYZ(s,0)
			local opts={low=y-1,high=y+1,limit=limit or 12,peer=token}
			for k,v in override or {} do opts[k]=v end
			return Contact.resolve(sp,x,z,owner,opts)
		end
		local acquired=Contact.resolve(sp,px,pz,row.sa,{low=py-1,high=py+1,limit=160})
		check("a peer token comes from a real known field connection",acquired and acquired.peer and acquired.contactS==row.sb
			and math.abs(acquired.ownerS-row.sa)<1e-6 and acquired.kind==sp.TARMAC,
			"physical asphalt is recognized without replacing accepted A")
		local distant=nil
		for _,r in patch.rows do if r.weight==1 and math.abs(r.sb-acquired.peer.s)>24 then distant=r;break end end
		local boundedFloor=true
		if distant then
			local p=Infield.columns(distant)[6]
			boundedFloor=Contact.resolve(sp,p[1],p[3],row.sa,{low=p[2]-1,high=p[2]+1,peer=acquired.peer,limit=12})==nil
		end
		check("retained field rows obey the same physical movement bound",distant and boundedFloor,
			"cross-gap bank changes remain legal, but distant rows cannot advance the token")
		local all=true;local count=0
		for _,target in {patch.rows[#patch.rows].sb-32,patch.rows[1].sb+32} do
			local token=Contact.copy(acquired.peer)
			local direction=if target<token.s then -1 else 1
			local s=token.s
			while math.abs(s-target)>1e-7 do
				s+=direction*math.min(1,math.abs(target-s))
				local hit=resolve(s,row.sa,token)
				if not hit then all=false;break end
				all=all and math.abs(hit.ownerS-row.sa)<1e-6 and hit.kind==sp.TARMAC and math.abs(hit.contactS-s)<1e-5
				token=Contact.copy(hit.peer);count+=1
			end
		end
		check("physical peer contact continues past both field endpoints",all and count>64,
			`{count} one-stud peer steps, each retaining A ownership`)
		local outside=patch.rows[1].sb+32
		check("a missing token cannot reacquire remote peer road",resolve(outside,row.sa,nil)==nil,
			"retention cannot become a new global road search")
		local ownerEnd=patch.rows[#patch.rows].sa
		local beforePeer=patch.rows[#patch.rows].sb-32
		local wide=resolve(beforePeer,ownerEnd,nil,640)
		local credited=resolve(beforePeer,ownerEnd,nil,640,{creditS=beforePeer})
		check("wide owned retries cannot bypass the known peer's credit gate",wide==nil and credited and math.abs(credited.ownerS-beforePeer)<1e-5,
			`wide={wide and wide.ownerS}, credited={credited and credited.ownerS}, target={beforePeer}; explicit credit is required`)
		local last=resolve(outside,row.sa,acquired.peer,640)
		local token=Contact.copy(last.peer)
		local before=token.s
		for _=1,12 do resolve(outside+24,row.sa,token,160) end
		check("auxiliary and predicted probes never advance a retained token",token.s==before,
			"the resolver returns copies and commits no tracking state")
		local other=fixture(Spline,20);local otherB=512+math.pi*100+20
		other:addInfields(Planner.plan(other,128,480,otherB,other.length));other:append(sections[#sections])
		local x,y,z=other:surfaceXYZ(outside,0)
		check("a token belongs to exactly one spline",Contact.resolve(other,x,z,row.sa,{low=y-1,high=y+1,peer=token,limit=12})==nil,
			"a copied token cannot authorize another road instance")
		check("retained physical movement remains bounded",resolve(outside+180,row.sa,token,12)==nil,
			"a physical token does not permit an arbitrary arc jump")
		check("retained contacts keep the physical ray's height window",resolve(outside,row.sa,token,12,{low=py+100,high=py+110})==nil,
			"peer road cannot act as a ceiling or a distant floor")
		local turnStart=sp.length;local length=math.pi*100+20
		local bend=table.clone(sections[2]);bend.k={20,-.01,length-20,-.01,length,0}
		sp:append(bend)
		local departure=sp.length;sp:append(sections[#sections])
		local more=Planner.plan(sp,turnStart-480,turnStart-32,departure,sp.length)
		sp:addInfields(more)
		local chained=false;local chainToken=nil
		if #more>0 then
			local nextRow=more[1].rows[math.ceil(#more[1].rows*.5)]
			local history=Contact.copy(token)
			for s=token.s+1,nextRow.sa,1 do local hit=resolve(s,row.sa,history,12);if not hit then history=nil;break end;history=Contact.copy(hit.peer) end
			if history then
				local a,b=nextRow.a,nextRow.b
				local x,z=a[1]+(b[1]-a[1])*.1,a[3]+(b[3]-a[3])*.1
				local floor=Infield.sample(sp.infields,x,z)
				local hit=Contact.resolve(sp,x,z,row.sa,{low=floor.y-1,high=floor.y+1,limit=160,peer=history})
				chained=hit and hit.peer.patchId==more[1].id and hit.ownerS==row.sa and hit.kind==sp.GRASS
				chainToken=hit and Contact.copy(hit.peer)
			end
		end
		check("an authorized physical leg can enter its next real field without erasing debt",chained,
			"connection acquisition follows physical B while accepted ownership stays on original A")
		local backward=chainToken and resolve(row.sb,ownerEnd,chainToken,640)
		check("chaining fields cannot reclassify original A debt as owned B asphalt",backward and backward.ownerS==ownerEnd
			and backward.peer~=nil and backward.source=="peer","native contact remains physical until the caller approves a credit-complete handoff")
		sp:trim(b0+16)
		local retained=resolve(outside,row.sa,token,12)
		check("physical B survives retirement of old A ownership",retained and retained.contactS>=sp.firstSample*sp.step
			and retained.ownerS==row.sa,"live physical support is separate from a retired earned-credit anchor")
		local a,b=row.a,row.b
		local x,z=a[1]+(b[1]-a[1])*.95,a[3]+(b[3]-a[3])*.95
		local floor=Infield.sample(sp.infields,x,z)
		local liveFloor=Contact.resolve(sp,x,z,row.sa,{low=floor.y-1,high=floor.y+1,peer=acquired.peer,limit=160})
		local fresh=Contact.resolve(sp,x,z,row.sa,{low=floor.y-1,high=floor.y+1,limit=160})
		check("already acquired field support follows the real retained closure domain",liveFloor and floor.closingS>=sp.firstSample*sp.step
			and liveFloor.kind==sp.GRASS and fresh==nil,"retained support remains real; retired history cannot acquire it anew")
		local deficient=Contact.credit(row.sa,100,outside)
		local sufficient=Contact.credit(row.sa,(outside-row.sa-8)/1.05+.001,outside)
		check("retained physical contact grants no extra re-entry credit",deficient<outside and sufficient==outside,
			"the existing1.05times travel plus8stud allowance remains exact")
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	cfg.Spline.Biomes.GroundEnabled=saved
	if not ok then return {passed=0,total=1,checks={{name="retained contact fixture completes",ok=false,detail=result}}} end
	return result
end

function Tests.render()
	local road=game.ReplicatedStorage.Shared.Road
	local Spline,Planner,Infield=require(road.Spline),require(road.SplineInfieldPlanner),require(road.SplineInfield)
	local Mesh,Parts=require(road.SplineMesh),require(road.SplineParts)
	local cfg=require(game.ReplicatedStorage.Shared.Config)
	local saved=cfg.Spline.Biomes.GroundEnabled;cfg.Spline.Biomes.GroundEnabled=true
	local folder=Instance.new("Folder");folder.Name="__InfieldRenderTest";folder.Parent=workspace
	local mesh,parts=nil,nil
	local ok,result=xpcall(function()
		local checks={}
		local function check(name,pass,detail)table.insert(checks,{name=name,ok=pass,detail=detail})end
		local sp,b0=fixture(Spline,20)
		local patches=Planner.plan(sp,128,480,b0,sp.length);sp:addInfields(patches)
		local row=patches[1].rows[math.ceil(#patches[1].rows*.5)]
		local centre=Infield.columns(row)[6]
		local info;mesh,info=Mesh.buildInfield(sp,centre[1],centre[3],600,folder)
		assert(mesh,tostring(info))
		local part=mesh.Infield;local em=part.MeshContent.Object
		local faces={}
		for _,f in em:GetFaces() do
			local ids=em:GetFaceVertices(f)
			local p={};for _,id in ids do table.insert(p,part.CFrame:PointToWorldSpace(em:GetPosition(id))) end
			table.insert(faces,p)
		end
		local tested,missing,heightError,normalError=0,0,0,0
		for i,t in sp.infields.triangles do
			if not t.supported then continue end
			local a,b,c=t.a.p,t.b.p,t.c.p
			local x,z=(a[1]+b[1]+c[1])/3,(a[3]+b[3]+c[3])/3
			local expected=Infield.sample(sp.infields,x,z)
			local top,normal=-math.huge,nil
			for _,p in faces do
				local aa,bb,cc=p[1],p[2],p[3]
				local bx,bz,cx,cz=bb.X-aa.X,bb.Z-aa.Z,cc.X-aa.X,cc.Z-aa.Z
				local det=bx*cz-bz*cx
				if math.abs(det)<1e-9 then continue end
				local dx,dz=x-aa.X,z-aa.Z
				local u,v=(dx*cz-dz*cx)/det,(bx*dz-bz*dx)/det
				if u< -1e-7 or v< -1e-7 or u+v>1+1e-7 then continue end
				local y=aa.Y+u*(bb.Y-aa.Y)+v*(cc.Y-aa.Y)
				if y>top then top=y;normal=(bb-aa):Cross(cc-aa).Unit end
			end
			if not normal then missing+=1 else
				heightError=math.max(heightError,math.abs(top-expected.y))
				normalError=math.max(normalError,math.deg(math.acos(math.clamp(normal:Dot(expected.normal),-1,1))))
			end
			tested+=1;if i%32==0 then task.wait() end
		end
		check("actual field mesh contains both exact halves in one bounded mesh",#faces==#sp.infields.triangles and #mesh:GetChildren()==1
			and math.max(part.Size.X,part.Size.Y,part.Size.Z)<=2048 and not part.CanCollide and not part.CanQuery,
			`{#faces} faces, {info.vertices} vertices, size{part.Size}`)
		check("actual field mesh agrees with the physical triangle floor",tested>0 and missing==0 and heightError<.02 and normalError<1,
			`{tested} samples, missing{missing}, height{heightError}, normal{normalError}degrees`)
		Mesh.destroy(mesh);mesh=nil
		parts,info=Parts.buildInfield(sp,centre[1],centre[3],600,folder,{queryable=true})
		assert(parts,tostring(info));task.wait()
		local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={parts}
		local rays,misses,error=0,0,0
		for i,t in sp.infields.triangles do
			if not t.supported then continue end
			local a,b,c=t.a.p,t.b.p,t.c.p
			local x,y,z=(a[1]+b[1]+c[1])/3,(a[2]+b[2]+c[2])/3,(a[3]+b[3]+c[3])/3
			local hit=workspace:Raycast(Vector3.new(x,10000,z),Vector3.new(0,-20000,0),params)
			if not hit then misses+=1 else error=math.max(error,math.abs(hit.Position.Y-y)) end
			rays+=1;if i%32==0 then task.wait() end
		end
		check("actual Parts fallback preserves the complete finite field floor",rays>0 and misses==0 and error<.15,
			`{rays} high-origin rays, missing{misses}, height{error}, {info.parts} Parts, slice{info.sliceMs}ms`)
		parts:Destroy();parts=nil
		local count=0
		local cancelled,reason=Mesh.buildInfield(sp,centre[1],centre[3],600,folder,{cancelled=function()count+=1;return count>=10 end})
		check("cancelled field meshes publish no partial model",not cancelled and string.find(tostring(reason),"cancelled")~=nil and #folder:GetChildren()==0,
			"temporary mesh resources are discarded before publication")
		count=0
		local cancelledParts,why=Parts.buildInfield(sp,centre[1],centre[3],600,folder,{cancelled=function()count+=1;return count>=3 end})
		check("cancelled field fallback publishes no partial model",not cancelledParts and string.find(tostring(why),"cancelled")~=nil and #folder:GetChildren()==0,
			"staged batches are destroyed together")
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	if mesh then Mesh.destroy(mesh) end;if parts then parts:Destroy() end
	folder:Destroy();cfg.Spline.Biomes.GroundEnabled=saved
	if not ok then return {passed=0,total=1,checks={{name="field renderer fixture completes",ok=false,detail=result}}} end
	return result
end

return Tests
