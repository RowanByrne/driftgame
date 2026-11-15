--!nonstrict
-- Frozen connector data and physical support; route ownership is deliberately separate.
assert(game:GetService("RunService"):IsStudio(),"SplineInfieldTests is Studio only")
local DefaultInfield=require(game.ReplicatedStorage.Shared.Road.SplineInfield)
local Tests={}

local function fixture(Spline,rise,radius)
	radius=radius or 100
	local sp=Spline.new({x=0,y=50,z=-20000,yaw=0});sp.fall=math.pi*.5
	local sections={}
	local function append(sec)table.insert(sections,sec);sp:append(sec)end
	local function section(length,knots,left,right,bank)
		return {len=length,k=knots,g={length,0},b={length,0},rl={length,16},rr={length,16},
			el={length,left},er={length,right},hl={length,bank},hr={length,0}}
	end
	local a=section(512,{512,0},Spline.ROCK,Spline.CLIFF,rise);a.bm={0,1,0};append(a)
	local length=math.pi*radius+20
	append(section(length,{20,1/radius,length-20,1/radius,length,0},Spline.ROCK,Spline.CLIFF,0))
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
	check("a canonical patch identity cannot retain mutable caller data",not pcall(function()Infield.patch({},source)end),
		"only nonempty string identities enter the frozen geometry certificate")
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
	local retained=Infield.near(index,20,-10,30,true,600)
	local clipped=true;local covered,expectedCount,wrong=0,0,0
	for _,t in retained do for _,v in {t.a,t.b,t.c} do clipped=clipped and v.q>=600 and math.abs(v.p[2]-v.p[1]*.05)<1e-8 end end
	for x=.25,39.75,.5 do for z=-19.75,-.25,.5 do
		local expected=Infield.sample(index,x,z).closingS>=600
		local found=false
		for _,t in retained do
			local a,b,c=t.a.p,t.b.p,t.c.p
			local dx,dz=x-a[1],z-a[3]
			local u=(dx*(c[3]-a[3])-dz*(c[1]-a[1]))/t.det
			local v=((b[1]-a[1])*dz-(b[3]-a[3])*dx)/t.det
			if u>= -1e-8 and v>= -1e-8 and u+v<=1+1e-8 then found=true;break end
		end
		if expected then expectedCount+=1 end;if found then covered+=1 end;if found~=expected then wrong+=1 end
	end end
	check("retained field drawing clips the exact physical closing scalar",clipped and wrong==0 and covered==expectedCount and covered>0,
		`{covered} retained points, {wrong} domain mismatches; all clipped vertices preserve the original plane`)
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
	local cached=Infield.patch("prevalidated candidate",rows(10,12))
	local later=Infield.new(23);Infield.add(later,cached,true)
	local unpublished=#later.triangles==0 and next(later.patches)==nil
	Infield.add(later,patch)
	local lateOverlap=pcall(function()Infield.add(later,cached)end)
	check("prevalidated geometry still checks ground published afterward",unpublished and not lateOverlap
		and #later.triangles==4 and later.patches[cached.id]==nil,"cached self-topology never certifies compatibility with a mutable index")
	local touchingRows=rows(10,12)
	for _,row in touchingRows do row.a[1]+=40;row.b[1]+=40 end
	local touching=Infield.patch("cached touching step",touchingRows);Infield.add(Infield.new(),touching,true)
	check("cached geometry still checks the height of a touching published edge",not pcall(function()Infield.add(index,touching)end)
		and index.patches[touching.id]==nil,"an exact touching edge with a vertical step remains forbidden")
	local allGrids=true
	for _,spacing in {3,17,128} do
		local alternate=Infield.new(spacing);Infield.add(alternate,patch)
		local hit=Infield.sample(alternate,20,-10)
		allGrids=allGrids and hit~=nil and math.abs(hit.y-1)<1e-8 and Infield.sample(alternate,40.01,-10)==nil
	end
	check("reused immutable geometry respects each destination lookup grid",allGrids,"same canonical floor, three different query spacings and finite outside probes")
	local mutableRows=rows(0,2);local shallow=table.freeze({id="shallow frozen input",rows=mutableRows})
	Infield.add(Infield.new(),shallow,true);mutableRows[2].b={-40,2,-20}
	check("a shallow frozen caller cannot reuse stale compiled geometry",not pcall(function()Infield.add(Infield.new(),shallow)end),
		"only the module's own deep frozen canonical patches acquire a topology certificate")
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
				check("acquired field support does not vanish before the visible closing contour",world.probe(pos)~=nil,
					"physical retention remains separate from old owner credit")
				local fresh=subjects.World.new(sp);fresh.hint=midRow.sa;fresh.setClosing(midRow.sa+1)
				check("the real car cannot reacquire a field using retired ownership",fresh.probe(pos)==nil,
					"closure is checked before opposite-bank support")
				fresh.destroy()
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
		local position=Vector3.new(px,py,pz)
		local state,credit=Contact.advance(nil,acquired,position,true,true)
		check("an actual center commit preserves unpaid shortcut debt",state.ownerS==row.sa and state.peer~=nil
			and state.anchorS==row.sa and state.travel==0 and credit<acquired.contactS,
			"physical B becomes tracked while the original asphalt anchor remains A")
		local copied=Contact.copyState(state);copied.peer.s+=1
		check("actor and prediction state copies cannot share a mutable token",copied~=state and copied.peer~=state.peer
			and state.peer.s==acquired.contactS,"independent histories keep the same immutable spline identity")
		local paid=Contact.copyState(state);paid.travel=(acquired.contactS-row.sa-8)/1.05+1
		local adopted=Contact.advance(paid,acquired,position,true,true)
		local refused=Contact.advance(paid,acquired,position,true,false)
		check("only sufficient travel and a live credited road permit a peer handoff",adopted.ownerS==acquired.contactS
			and adopted.anchorS==acquired.contactS and adopted.peer==nil and adopted.travel==0
			and refused.ownerS==row.sa and refused.peer~=nil and refused.travel==paid.travel,
			"an unavailable live target keeps the full anchor and debt")
		check("committing another history never changes its input snapshot",state.ownerS==row.sa and state.peer.s==acquired.contactS
			and state.travel==0 and paid.peer~=adopted.peer,"state advances return new records")
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
		local narrow,narrowB=fixture(Spline,0,70)
		local narrowFields=Planner.plan(narrow,400,480,narrowB,narrow.length);narrow:addInfields(narrowFields)
		local escaped=narrowFields[1].rows[1].sb+33
		local nx,ny,nz=narrow:surfaceXYZ(escaped,0)
		local unapproved=Contact.resolve(narrow,nx,nz,300,{low=ny-1,high=ny+1,limit=640})
		check("ownership guards cover the entire retry interval across bucket boundaries",unapproved==nil,
			"neither a pre-field owner nor a post-field query can hide the known turnaround between them")
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

function Tests.worldTracking(_self,subjects)
	local road=game.ReplicatedStorage.Shared.Road
	local Spline=subjects and subjects.Spline or require(road.Spline)
	local Planner=subjects and subjects.Planner or require(road.SplineInfieldPlanner)
	local Infield=subjects and subjects.Infield or DefaultInfield
	local World=subjects and subjects.World or require(game.StarterPlayer.StarterPlayerScripts.Drift.SplineWorld)
	local cfg=require(game.ReplicatedStorage.Shared.Config)
	local saved=cfg.Spline.Biomes.GroundEnabled;cfg.Spline.Biomes.GroundEnabled=true
	local owned={}
	local ok,result=xpcall(function()
		local checks={};local function check(name,pass,detail)table.insert(checks,{name=name,ok=pass,detail=detail})end
		local sp,b0,sections=fixture(Spline,20)
		local patches=Planner.plan(sp,128,480,b0,sp.length);sp:addInfields(patches);sp:append(sections[#sections])
		local patch=patches[1];local row=patch.rows[math.ceil(#patch.rows*.5)]
		local destroyed=0
		local base={probe=function()return nil end,sweep=function()return nil end,penetration=function()return nil end,
			edge=function()return nil end,destroy=function()destroyed+=1 end}
		local function world()
			local w=World.new(sp,base);table.insert(owned,w);return w
		end
		local function point(s)
			local x,y,z=sp:surfaceXYZ(s,0);return Vector3.new(x,y+cfg.Drift.RideHeight,z)
		end
		local function same(a,b)
			if a==nil or b==nil then return a==b end
			for _,k in {"ownerS","anchorS","travel","position","physicalS","d","kind"} do if a[k]~=b[k] then return false end end
			return (a.peer==nil and b.peer==nil) or (a.peer and b.peer and a.peer.s==b.peer.s
				and a.peer.patchId==b.peer.patchId and a.peer.road==b.peer.road)
		end
		local w=world();local a,b=point(row.sa),point(row.sb)
		w.probe(b);w.sweep(b,b+Vector3.xAxis,sp:yawAt(row.sb));w.penetration(b,sp:yawAt(row.sb))
		check("bootstrap queries cannot choose the actor's initial road",w.hint==nil and w.physicalS==nil and w.contactSnapshot()==nil,
			"only an explicit actor center establishes contact history")
		w.locate(a)
		local anchor=w.contactSnapshot()
		local floorCount,missing,maxHeight,maxNormal=0,0,0,0
		local distance=(b-a).Magnitude
		for i=0,math.ceil(distance) do
			local p=a:Lerp(b,i/math.ceil(distance))
			local floor=Infield.sample(sp.infields,p.X,p.Z)
			local expected=nil;local normal=nil
			for _,s in {row.sa,row.sb} do
				local ss,d=sp:projectFrom(p.X,p.Z,s)
				local kind=ss and d and sp:groundKind(ss,d)
				if kind~=nil and kind~=false then expected=sp:terrainY(ss,d);normal=if kind==sp.TARMAC then sp:normalAt(ss,d) else sp:terrainNormal(ss,d);break end
			end
			if expected==nil and floor then expected=floor.y;normal=floor.normal end
			assert(expected~=nil,"crossing fixture leaves real ground")
			p=Vector3.new(p.X,expected+cfg.Drift.RideHeight,p.Z)
			local hit=w.probe(p);local owner,_,physical=w.locate(p)
			if not hit or not owner or not physical then missing+=1 else
				maxHeight=math.max(maxHeight,math.abs(hit.y-expected));maxNormal=math.max(maxNormal,(hit.normal-normal).Magnitude)
			end
			floorCount+=1
		end
		local crossed=w.contactSnapshot()
		check("real center tracking crosses both field banks without a support gap",missing==0 and maxHeight<.02 and maxNormal<.001,
			`{floorCount} one-stud centers; missing{missing}, height{maxHeight}, normal{maxNormal}`)
		check("the actual world retains route debt while reporting physical peer road",crossed and crossed.peer~=nil
			and crossed.anchorS==anchor.anchorS and crossed.ownerS<500 and math.abs(crossed.physicalS-row.sb)<.05,
			"view contact follows B while asphalt credit remains anchored on A")
		local before=w.contactSnapshot()
		local blocked=world();blocked.restoreContact(anchor);blocked.setClosing(row.sa+1)
		local retainedClosing=w.fork();retainedClosing.setClosing(row.sa+1)
		local middle=Infield.columns(row)[6];local middlePoint=Vector3.new(middle[1],middle[2]+cfg.Drift.RideHeight,middle[3])
		check("current closing refuses fresh copied ownership but retains authorized physical ground",blocked.probe(middlePoint)==nil
			and retainedClosing.probe(middlePoint)~=nil,
			"a walking-style copy applies the current closing before initial field acquisition")
		retainedClosing.destroy()
		for _=1,4 do
			w.probe(point(row.sb+24));w.sweep(point(row.sb),point(row.sb+12),sp:yawAt(row.sb))
			w.penetration(point(row.sb+12),sp:yawAt(row.sb))
		end
		check("rays and car footprint queries do not move actual contact history",same(before,w.contactSnapshot()),
			"future queries leave owner, physical peer, anchor and travel unchanged")
		local continued=true;local steps=0
		for _,target in {patch.rows[#patch.rows].sb-32,patch.rows[1].sb+32} do
			local clone=w.fork();local direction=if target<row.sb then -1 else 1;local s=row.sb
			while math.abs(s-target)>1e-6 do
				s+=direction*math.min(1,math.abs(target-s))
				local p=point(s);local hit=clone.probe(p);local owner,_,physical=clone.locate(p)
				continued=continued and hit~=nil and hit.surface=="tarmac" and owner~=nil and owner<500 and physical~=nil and math.abs(physical-s)<.05
				steps+=1
			end
			clone.destroy()
		end
		check("actual peer centers continue beyond both frozen field ends",continued and steps>64,
			`{steps} completed centers; shared base destroys{destroyed}`)
		check("prediction world forks own independent closures and histories",same(before,w.contactSnapshot()) and destroyed==0,
			"fork commits and disposal leave actual state and shared base alive")
		local later,laterB=fixture(Spline,20)
		local delayed=World.new(later);table.insert(owned,delayed)
		delayed.locate(a)
		local x,y,z=later:terrainXYZ(row.sa,row.sideA*(cfg.Road.Width*.5+5))
		local grass=Vector3.new(x,y+cfg.Drift.RideHeight,z);delayed.locate(grass)
		local debt=delayed.contactSnapshot()
		later:addInfields(Planner.plan(later,128,480,laterB,later.length))
		local unchanged=same(debt,delayed.contactSnapshot());delayed.locate(grass)
		local arrived=delayed.contactSnapshot()
		check("the first published field preserves an existing grass travel budget",unchanged and debt.travel>0
			and arrived.anchorS==debt.anchorS and arrived.travel==debt.travel,
			"contact tracking starts before field publication and cannot forgive prior off-road movement")
		if subjects and subjects.Trajectory and subjects.Model then
			local Model,Trajectory=subjects.Model,subjects.Trajectory
			local yaw=sp:yawAt(row.sb)
			local sim=Model.new(CFrame.new(b)*CFrame.Angles(0,yaw,0));sim.velocity=Model.axes(yaw)*80
			local actual=table.clone(sim);for k,v in actual do if type(v)=="table" then actual[k]=table.clone(v) end end
			local predicted=Trajectory.predict(sim,{steer=0,handbrake=false},{world=w,step=cfg.Drift.FixedStep,maxSteps=120,lengths=100,minSpeed=-1})
			local immutable=same(before,w.contactSnapshot())
			local twin=w.fork()
			for _=1,predicted.steps do Model.step(actual,{steer=0,handbrake=false},cfg.Drift.FixedStep,twin);twin.locate(actual.position) end
			local error=(predicted.points[#predicted.points]-actual.position).Magnitude
			check("spline prediction matches completed actual steps without touching live contact",immutable and destroyed==0
				and predicted.steps==120 and error<.001 and same(before,w.contactSnapshot()),
				`{predicted.steps} identical FixedSteps on peer B; end error{error}; base destroys{destroyed}`)
			twin.destroy()
			if subjects.Sim then
				local reference=nil;local referenceContact=nil;local stable=true;local runs=0
				for _,fps in {30,60,120} do for _,forecast in {false,true} do
					local driveWorld=w.fork();local runner=subjects.Sim.newRunner(CFrame.new(b)*CFrame.Angles(0,yaw,0))
					runner.state.velocity=Model.axes(yaw)*80
					for _=1,fps do
						subjects.Sim.advance(runner,1/fps,{steer=0,handbrake=false},driveWorld,function(center)driveWorld.locate(center.position)end)
						if forecast then Trajectory.predict(runner.state,{steer=0},{world=driveWorld,maxSteps=8,lengths=100,minSpeed=-1}) end
					end
					local contact=driveWorld.contactSnapshot()
					if reference then stable=stable and (reference-runner.state.position).Magnitude<.001 and same(referenceContact,contact)
					else reference=runner.state.position;referenceContact=contact end
					stable=stable and runner.totalSteps==120 and contact.peer~=nil and contact.anchorS==before.anchorS
					runs+=1;driveWorld.destroy()
				end end
				check("prediction leaves fixed-step driving and contact debt identical at every frame rate",stable and same(before,w.contactSnapshot())
					and destroyed==0,`{runs} drives at30/60/120FPS, with and without forecasts; every contact field agrees`)
			end
		end
		local replacement=world();replacement.restoreContact(w.contactSnapshot())
		check("world replacement preserves debt with an independent token",same(w.contactSnapshot(),replacement.contactSnapshot())
			and w.contactState~=replacement.contactState and w.contactState.peer~=replacement.contactState.peer,
			"the same spline may continue its contact history across a live-world rebuild")
		replacement.resetHint()
		check("explicit placement clears both physical and credited contact history",replacement.contactSnapshot()==nil
			and replacement.hint==nil and replacement.physicalS==nil,"respawn can establish a new authoritative starting point")
		local retired=w.fork();local fresh=world();fresh.hint=before.ownerS
		sp:trim(b0+16)
		local retained=retired.probe(b);local retainedOwner,_,retainedS=retired.locate(b)
		check("acquired peer ground survives original owner retirement",retained and retained.surface=="tarmac"
			and retainedOwner==before.ownerS and retainedS>=sp.firstSample*sp.step and fresh.probe(b)==nil,
			"a retained physical token survives; an old initial hint cannot acquire the same remote bank")
		retired.destroy()
		local paid=before;paid.travel=(row.sb-paid.anchorS-8)/1.05+1
		w.restoreContact(paid);w.locate(b)
		local adopted=w.contactSnapshot()
		check("a completed real travel budget hands off only on live peer asphalt",adopted.ownerS==adopted.physicalS
			and adopted.peer==nil and adopted.anchorS==adopted.ownerS and adopted.travel==0,
			"contact becomes ordinary owned B only after the existing re-entry allowance is paid")
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	for _,w in owned do w.destroy() end
	cfg.Spline.Biomes.GroundEnabled=saved
	if not ok then return {passed=0,total=1,checks={{name="actual world tracking fixture completes",ok=false,detail=result}}} end
	return result
end

function Tests.server()
	local road=game.ReplicatedStorage.Shared.Road
	local Spline,Planner=require(road.Spline),require(road.SplineInfieldPlanner)
	local cfg=require(game.ReplicatedStorage.Shared.Config)
	local live=require(game.ServerScriptService.Services.RoadService)
	assert(not live:HasRoad(),"Stop the live road before the isolated field progress check")
	local saved=cfg.Spline.Biomes.GroundEnabled;cfg.Spline.Biomes.GroundEnabled=true
	local holder=Instance.new("Folder");holder.Name="__FieldServerTest";holder.Parent=game.ServerStorage
	local copy=game.ServerScriptService.Services.RoadService:Clone();copy.Parent=holder
	local service=require(copy)
	local car=nil
	local ok,result=xpcall(function()
		local checks={};local function check(name,pass,detail)table.insert(checks,{name=name,ok=pass,detail=detail})end
		service:SetMode("spline");service:Generate(203)
		local seq=service:DebugGenerator();local sp,b0,sections=fixture(Spline,20)
		local patches=Planner.plan(sp,128,480,b0,sp.length);sp:addInfields(patches)
		for _=1,cfg.Road.BehindPieces+cfg.Road.AheadPieces+12 do
			local sec=table.clone(sections[3]);table.insert(sections,sec);sp:append(sec)
		end
		seq.spline=sp;seq.gen.spline=sp;seq.gen.sections=sections
		seq.first=1;seq.last=0;seq.starts={};seq.pieces={};seq.destroyed=0;seq.furthestN=1;seq.furthestT=0;seq:_adopt()
		local id=-2032121;assert(service:DebugJoin(id))
		car=Instance.new("Model");car.Name="FieldProgressFixture";car:SetAttribute("UserId",id)
		local body=Instance.new("Part");body.Anchored=true;body.CanCollide=false;body.CanQuery=false;body.Transparency=1
		body.Parent=car;car.PrimaryPart=body;car.Parent=workspace:FindFirstChild("Cars") or workspace
		local row=patches[1].rows[math.ceil(#patches[1].rows*.5)]
		local function point(s)local x,y,z=sp:surfaceXYZ(s,0);return Vector3.new(x,y+cfg.Drift.RideHeight,z)end
		local function put(p)car:PivotTo(CFrame.new(p));return service:DebugTick()end
		local a,b=point(row.sa),point(row.sb);put(a)
		local anchor=service:DebugContact(id);local missing,grassError=0,0
		for i=1,math.ceil((b-a).Magnitude) do
			local p=a:Lerp(b,i/math.ceil((b-a).Magnitude))
			local floor=sp:infieldAt(p.X,p.Z)
			if floor then p=Vector3.new(p.X,floor.y+cfg.Drift.RideHeight,p.Z) end
			put(p)
			local contact=service:DebugContact(id)
			if contact.position~=p then missing+=1 end
			if floor and i<(b-a).Magnitude-50 then grassError=math.max(grassError,math.abs(contact.n-anchor.n),math.abs(contact.t-anchor.t)) end
			if i%32==0 then task.wait() end
		end
		local crossed=service:DebugContact(id)
		local crossedS=seq.starts[crossed.n]+crossed.t*sections[crossed.n].len
		local allowed=seq:reentryS(anchor.anchorS,crossed.travel,row.sb)
		check("the real server tracks supported field movement without awarding grass progress",missing==0 and grassError<1e-5
			and crossed.peerS~=nil and crossed.anchorS==anchor.anchorS and crossed.ownerS<500,
			`missing supported centers{missing}, grass progress error{grassError}, physical{crossed.physicalS}, owner{crossed.ownerS}`)
		check("physical peer asphalt publishes only live capped credit",math.abs(crossedS-allowed)<.05 and crossedS<row.sb-100,
			`earned{crossedS}, allowed{allowed}, physical{row.sb}`)
		local target=patches[1].rows[1].sb+32;local continued=true
		for s=row.sb+1,target,1 do
			put(point(s));local c=service:DebugContact(id)
			continued=continued and c.peerS~=nil and c.ownerS<500 and math.abs(c.physicalS-s)<.05
			if math.floor(s)%32==0 then task.wait() end
		end
		put(point(target));local before=service:DebugContact(id)
		check("the server retains the acquired physical road beyond the frozen patch",continued and before.peerS~=nil,
			"leaving field geometry cannot lose support or erase unpaid travel")
		seq:trimBefore(3)
		local retired=put(point(target));local held=service:DebugContact(id)
		for _=1,4 do put(point(target)) end
		local waiting=service:DebugContact(id)
		check("retired owner credit cannot fall through to a live physical peer piece",seq:pieceAtS(seq:reentryS(held.anchorS,held.travel,target))==nil
			and held.n==before.n and held.t==before.t and held.peerS~=nil and held.physicalS>=seq.starts[seq.first],
			`first arc{seq.starts[seq.first]}, anchor{held.anchorS}, physical{held.physicalS}, earned piece{held.n}`)
		check("stationary physical peer contact neither earns nor forgets missing credit",waiting.travel==held.travel
			and waiting.ownerS==held.ownerS and waiting.peerS==held.peerS and waiting.n==held.n and waiting.t==held.t,
			"repeated actual server ticks keep both debt and physical support")
		local resumed=false;local capped=true
		for i=1,256 do
			local s=target+i;put(point(s));local c=service:DebugContact(id)
			if c.n>=seq.first then
				resumed=true;local earned=seq.starts[c.n]+c.t*sections[c.n].len
				capped=capped and math.abs(earned-seq:reentryS(held.anchorS,c.travel,s))<.05 and earned<s
			end
			if i%32==0 then task.wait() end
		end
		check("real peer-road travel resumes at the first available capped piece",resumed and capped,
			"the missing-credit branch retains travel until real live credited road becomes available")
		for i=255,0,-1 do put(point(target+i));if i%32==0 then task.wait() end end
		local adopted=service:DebugContact(id)
		check("only a paid live asphalt handoff clears the server's physical peer",adopted.peerS==nil
			and math.abs(adopted.ownerS-target)<.05 and adopted.anchorS==adopted.ownerS and adopted.travel==0,
			`owner{adopted.ownerS}, anchor{adopted.anchorS}, travel{adopted.travel}, peer{adopted.peerS}`)
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	service:Stop();if car then car:Destroy() end;holder:Destroy();cfg.Spline.Biomes.GroundEnabled=saved
	if not ok then return {passed=0,total=1,checks={{name="server field progress fixture completes",ok=false,detail=result}}} end
	return result
end

function Tests.warmSupport()
	local road=game.ReplicatedStorage.Shared.Road
	local Infield,Parts=require(road.SplineInfield),require(road.SplineParts)
	local folder=Instance.new("Folder");folder.Name="__ImmediateFieldSupport";folder.Parent=workspace
	local ok,result=xpcall(function()
		local checks={};local function check(name,pass,detail)table.insert(checks,{name=name,ok=pass,detail=detail})end
		local function patch(id,x,z,rows,spacing,arc)
			local out={}
			for i=0,rows do table.insert(out,{sa=arc+i*spacing,sb=arc+1000-i*spacing,sideA=1,sideB=-1,
				a={x,10,z-i*spacing},b={x+40,10,z-i*spacing},weight=1}) end
			return Infield.patch(id,out)
		end
		local function floorAt(model,x,z)
			local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={model}
			local hit=workspace:Raycast(Vector3.new(x,11,z),Vector3.new(0,-2,0),params)
			return hit and hit.Normal.Y>.8 and math.abs(hit.Position.Y-10)<.02
		end
		local sp={infields=Infield.new(),infieldRevision=1,firstSample=0,step=4}
		Infield.add(sp.infields,patch("original support",0,0,2,10,100))
		local old,oldInfo=Parts.buildInfield(sp,20,-10,160,folder,{supportedOnly=true,collidable=true,queryable=true,noYield=true})
		assert(old,tostring(oldInfo))
		Infield.add(sp.infields,patch("new nearby support",50,0,2,10,200));sp.infieldRevision+=1
		local oldMiss=not floorAt(old,60,-10)
		local yielded=false;task.defer(function()yielded=true end)
		local immediate,info=Parts.warmInfield(sp,60,-10,folder,old)
		check("new revision inside an old radius has an actual collider before a sliced build can yield",oldMiss and immediate~=old
			and info.ready and not info.reused and not yielded and floorAt(immediate,60,-10)
			and immediate:GetAttribute("InfieldRevision")==2 and info.slices==1,
			`old radius160 did not contain the new triangles; immediate parts{info.parts}, time{info.ms}ms`)
		local again,reused=Parts.warmInfield(sp,61,-10,folder,immediate)
		check("only matching revision and real successful support may reuse a floor",again==immediate and reused.ready and reused.reused
			and floorAt(again,61,-10),"coverage is checked against the real colliders as well as the build footprint")
		Infield.add(sp.infields,patch("support after a failed warm attempt",100,0,2,10,300));sp.infieldRevision+=1
		local failed,failure=Parts.warmInfield(sp,110,-10,folder,old,{maxTriangles=1})
		check("a failed warm attempt cannot certify an old floor's radius or revision",failed==old and not failure.ready
			and old:GetAttribute("InfieldRevision")==1 and not floorAt(old,110,-10),failure.failure)
		local retried,retry=Parts.warmInfield(sp,110,-10,folder,failed)
		check("a subsequent attempt supplies missing new support immediately",retry.ready and retried~=old and not yielded
			and retried:GetAttribute("InfieldRevision")==3 and floorAt(retried,110,-10),
			"failed support never becomes cached coverage")
		local dense={infields=Infield.new(),infieldRevision=1,firstSample=0,step=4}
		Infield.add(dense.infields,patch("old sparse patch",-50,0,2,16,500))
		local sparse,why=Parts.buildInfield(dense,-30,-16,100,folder,{supportedOnly=true,collidable=true,queryable=true,noYield=true})
		assert(sparse,tostring(why))
		Infield.add(dense.infields,patch("accepted dense new patch",0,0,64,.5,600));dense.infieldRevision+=1
		local warmed,denseInfo=Parts.warmInfield(dense,20,-16,folder,sparse)
		check("dense accepted support shrinks its immediate neighbourhood within the same allocation bound",denseInfo.ready
			and denseInfo.radius<8 and denseInfo.triangles<=96 and denseInfo.slices==1 and not yielded and floorAt(warmed,20,-16),
			`radius{denseInfo.radius}, triangles{denseInfo.triangles}, parts{denseInfo.parts}, time{denseInfo.ms}ms`)
		local footMissing=0
		for _,dx in {-2,0,2} do for _,dz in {-2,0,2} do if not floorAt(warmed,20.75+dx,-16+dz) then footMissing+=1 end end end
		local moved,movement=Parts.warmInfield(dense,20.75,-16,folder,warmed)
		check("the smallest warm floor covers real foot colliders across seams and the next movement",denseInfo.radius==4
			and footMissing==0 and moved==warmed and movement.ready and movement.reused and not yielded,
			`nine footprint rays after0.75stud movement across a column/row seam; missing{footMissing}`)
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	folder:Destroy()
	if not ok then return {passed=0,total=1,checks={{name="new-field immediate support fixture completes",ok=false,detail=result}}} end
	return result
end

function Tests.retirement()
	local road=game.ReplicatedStorage.Shared.Road
	local Spline,Planner,Infield=require(road.Spline),require(road.SplineInfieldPlanner),require(road.SplineInfield)
	local Mesh,Parts=require(road.SplineMesh),require(road.SplineParts)
	local cfg=require(game.ReplicatedStorage.Shared.Config)
	local saved=cfg.Spline.Biomes.GroundEnabled;cfg.Spline.Biomes.GroundEnabled=true
	local folder=Instance.new("Folder");folder.Name="__RetainedFieldTest";folder.Parent=workspace
	local mesh=nil
	local ok,result=xpcall(function()
		local checks={};local function check(name,pass,detail)table.insert(checks,{name=name,ok=pass,detail=detail})end
		local sp,b0=fixture(Spline,20);sp:addInfields(Planner.plan(sp,128,480,b0,sp.length));sp:trim(600)
		local first=sp.firstSample*sp.step
		local row=sp.infields.patches[next(sp.infields.patches)].rows[18]
		local centre=Infield.columns(row)[6]
		local selected=Infield.near(sp.infields,centre[1],centre[3],600,true,first)
		local all=Infield.near(sp.infields,centre[1],centre[3],600,nil,first)
		local info;mesh,info=Mesh.buildInfield(sp,centre[1],centre[3],600,folder)
		assert(mesh,tostring(info))
		local part=mesh.Infield;local em=part.MeshContent.Object;local below=0
		for _,id in em:GetVertices() do
			local p=part.CFrame:PointToWorldSpace(em:GetPosition(id));local floor=Infield.sample(sp.infields,p.X,p.Z)
			if floor and floor.closingS<first-.05 then below+=1 end
		end
		check("the real retained mesh ends at the same frozen q contour",#em:GetFaces()==#all and below==0,
			`{#em:GetFaces()} retained faces; vertices behind the retained contour{below}`)
		Mesh.destroy(mesh);mesh=nil
		local model,stats=Parts.buildInfield(sp,centre[1],centre[3],600,folder,{supportedOnly=true,collidable=true,queryable=true})
		assert(model,tostring(stats));task.wait()
		local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={model}
		local missing,error,samples=0,0,0
		for i,t in selected do
			local a,b,c=t.a.p,t.b.p,t.c.p
			for _,weights in {{1/3,1/3,1/3},{.2,.3,.5},{.5,.3,.2}} do
				local x,y,z=0,0,0
				for j,p in {a,b,c} do x+=p[1]*weights[j];y+=p[2]*weights[j];z+=p[3]*weights[j] end
				local hit=workspace:Raycast(Vector3.new(x,10000,z),Vector3.new(0,-20000,0),params)
				if not hit or hit.Normal.Y<=.8 then missing+=1 else error=math.max(error,math.abs(hit.Position.Y-y)) end
				samples+=1
			end
			if i%32==0 then task.wait() end
		end
		check("exact collidable slabs cover the complete retained supported floor",missing==0 and error<.02,
			`{samples} rays, missing{missing}, height error{error}, {stats.parts} wedges, slice{stats.sliceMs}ms`)
		local leaked,tested=0,0
		for i,panel in Infield.closing(sp.infields,first) do
			local a,b=panel.a,panel.b
			local x,z=(a[1]+b[1])*.5-panel.normal.X*.1,(a[3]+b[3])*.5-panel.normal.Z*.1
			local hit=workspace:Raycast(Vector3.new(x,10000,z),Vector3.new(0,-20000,0),params)
			if hit and hit.Normal.Y>.8 then leaked+=1 end;tested+=1
			if i%32==0 then task.wait() end
		end
		check("actual walking slabs add no supported floor beyond the retirement edge",tested>0 and leaked==0,
			`{tested} rays0.1stud beyond the contour; supported leaks{leaked}`)
		local t=selected[math.ceil(#selected*.5)];local a,b,c=t.a.p,t.b.p,t.c.p
		local x,z=(a[1]+b[1]+c[1])/3,(a[3]+b[3]+c[3])/3
		local W=cfg.Spline.Biomes.Infield.Walking
		local warm,warmInfo=Parts.buildInfield(sp,x,z,W.WarmRadius,folder,{supportedOnly=true,collidable=true,queryable=true,
			noYield=true,maxTriangles=W.WarmTriangles})
		check("the first walking floor publishes a bounded non-yielding neighbourhood",warm and warmInfo.slices==1
			and warmInfo.triangles<=W.WarmTriangles and warm.Parent==folder,
			`warm triangles{warmInfo and warmInfo.triangles}, time{warmInfo and warmInfo.ms}ms`)
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	if mesh then Mesh.destroy(mesh) end;folder:Destroy();cfg.Spline.Biomes.GroundEnabled=saved
	if not ok then return {passed=0,total=1,checks={{name="retained drawing fixture completes",ok=false,detail=result}}} end
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

function Tests.curvedBanks()
	local road=game.ReplicatedStorage.Shared.Road
	local Spline,Planner,Contact=require(road.Spline),require(road.SplineInfieldPlanner),require(road.SplineContact)
	local cfg=require(game.ReplicatedStorage.Shared.Config)
	local saved=cfg.Spline.Biomes.GroundEnabled;cfg.Spline.Biomes.GroundEnabled=true
	local ok,result=xpcall(function()
		local sp=Spline.new({x=30000,y=50,z=-20000,yaw=0});sp.fall=math.pi*.5
		local function section(length,k,left,right,bank)
			return {len=length,k=k,g={length,0},b={length,0},rl={length,16},rr={length,16},
				el={length,left},er={length,right},hl={length,bank},hr={length,0}}
		end
		local a=section(512,{16,.0005,512,.0005},Spline.ROCK,Spline.CLIFF,20);a.bm={0,1,0};a.g={512,.006};sp:append(a)
		local length=math.pi*100+20
		local turn=section(length,{20,.01,length-20,.01,length,0},Spline.ROCK,Spline.CLIFF,0);turn.g={length,-.006};sp:append(turn)
		local b0=sp.length;local exit=section(384,{16,-.00055,384,-.00055},Spline.CLIFF,Spline.ROCK,0);exit.g={384,-.006};sp:append(exit)
		local patches=Planner.plan(sp,96,480,b0,sp.length);assert(#patches>0,"curved fixture has no accepted connection")
		sp:addInfields(patches)
		local gaps,missing,tested,nonGrass,heightError,finite=0,0,0,0,0,0
		local closingBefore,closingAfter=0,0
		local linked,linkedClosed=0,0
		local unconnected,retired=0,0
		local roadMin,roadMax=math.huge,-math.huge
		for _,patch in patches do for i=1,#patch.rows-1 do
			local a,b=patch.rows[i],patch.rows[i+1]
			if math.min(a.weight,b.weight)<.9 then continue end
			for _,bank in {"A","B"} do
				local sa,sb=if bank=="A" then a.sa else a.sb,if bank=="A" then b.sa else b.sb
				local side=if bank=="A" then a.sideA else a.sideB
				local s=(sa+sb)*.5;local edge=cfg.Road.Width*.5+sp:runoffAt(s,side)
				roadMin,roadMax=math.min(roadMin,sp:heightAt(s)),math.max(roadMax,sp:heightAt(s))
				local px,py,pz=sp:terrainXYZ(s,side*edge)
				local pa,pb=if bank=="A" then a.a else a.b,if bank=="A" then b.a else b.b
				local x,z=(px+(pa[1]+pb[1])*.5)*.5,(pz+(pa[3]+pb[3])*.5)*.5
				local projected,d=sp:projectFrom(x,z,s)
				local inside=projected and d and math.abs(d)<=cfg.Road.Width*.5+sp:runoffAt(projected,side)
				local floor=sp:infieldAt(x,z)
				if not inside and not floor then
					gaps+=1
					if Contact.resolve(sp,x,z,s,{limit=32,closing=s-.05,low=py-2,high=py+2}) then closingBefore+=1 end
					if not Contact.resolve(sp,x,z,s,{limit=32,closing=s+.05,low=py-2,high=py+2}) then closingAfter+=1 end
					if bank=="A" then
						local peer=(a.sb+b.sb)*.5
						if sp:infieldContact(x,z,peer,py-2,py+2,32) then linked+=1 end
						if not sp:infieldContact(x,z,peer,py-2,py+2,32,s+.05) then linkedClosed+=1 end
					end
				end
				local hit=Contact.resolve(sp,x,z,s,{limit=32,low=py-2,high=py+2})
				tested+=1;if not hit then missing+=1 else
					if hit.kind~=Spline.GRASS then nonGrass+=1 end
					heightError=math.max(heightError,math.abs(hit.y-py))
				end
				local pad=cfg.Spline.Biomes.Infield.BankContactPad
				if sp:groundKind(s,side*(edge+pad+.001))==nil then finite+=1 end
				if not Contact.resolve(sp,x,z,s,{limit=32,first=s+1,low=py-2,high=py+2}) then retired+=1 end
			end
		end end
		for _,side in {-1,1} do
			local s=32;local edge=cfg.Road.Width*.5+sp:runoffAt(s,side)
			if sp:infieldOpening(s,side)==0 and sp:groundKind(s,side*(edge+.005))==nil then unconnected+=1 end
		end
		local checks={
			{name="curved bank/chord gaps retain real contact on both arms",ok=tested>0 and gaps>0 and missing==0,
				detail=`{tested} real contact probes, {gaps} midpoint gaps without the contact band, missing{missing}`},
			{name="bank contact remains grass with bounded height error",ok=nonGrass==0 and heightError<.02,
				detail=`non-grass contacts{nonGrass}, maximum bank height difference{heightError}`},
			{name="curved join probes include actual changing road height",ok=roadMax-roadMin>1,detail=`road heights{roadMin} to{roadMax}`},
			{name="the join band is finite and cannot extend unconnected roads",ok=finite==tested and unconnected==2,
				detail=`finite bounds{finite}/{tested}, unchanged unconnected sides{unconnected}/2`},
			{name="retired owners cannot acquire the join band",ok=retired==tested,detail=`rejected retired-owner probes{retired}/{tested}`},
			{name="closing clips gap contact without retiring the road owner",ok=gaps>0 and closingBefore==gaps and closingAfter==gaps,
				detail=`before/after closing{closingBefore}/{closingAfter} across{gaps} true gaps; retained owner unchanged`},
			{name="known peer links cannot reacquire a gap behind closing",ok=linked>0 and linkedClosed==linked,
				detail=`{linked} linked A-bank gap contacts, {linkedClosed} rejected after closing with B owner retained`},
		}
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	cfg.Spline.Biomes.GroundEnabled=saved
	if not ok then return {passed=0,total=1,checks={{name="curved bank contact fixture completes",ok=false,detail=result}}} end
	return result
end

function Tests.generator(_self,subjects)
	local road=game.ReplicatedStorage.Shared.Road
	local Gen=subjects and subjects.Gen or require(road.SplineGen)
	local Spline=subjects and subjects.Spline or require(road.Spline)
	local Corridor=subjects and subjects.Corridor or require(road.SplineCorridor)
	local cfg=require(game.ReplicatedStorage.Shared.Config)
	local C=cfg.Spline.Biomes;local saved,savedGround=C.Infield.Enabled,C.GroundEnabled
	C.Infield.Enabled=true;C.GroundEnabled=true
	local ok,result=xpcall(function()
		local checks={};local function check(name,pass,detail)table.insert(checks,{name=name,ok=not not pass,detail=detail})end
		local observed={};local sp={length=500,tip=function()return 0,0,0,0 end}
		local state=setmetatable({spline=sp,biomes={},infieldArmStart=80,
			_publishInfields=function(_,section,intents)if #intents>0 then table.insert(observed,{section=section,intents=intents})end end},Gen)
		state:_infields({},400,{what="gradeApproach",a1=400,b0=450})
		state:_infields({},450,{what="straighten",a1=450,b0=500})
		check("minor preparation keeps the real approach arm without creating a field",state.infieldArmStart==80
			and state.infieldPending==nil and #observed==0,"grade easing and heading correction cannot truncate the next approach to zero length")
		local section={len=400,k={20,.01,120,.01,140,0,400,0}}
		state:_prepareInfield(section,{what="turnaround",tag="Hairpin"})
		local marker=state.preparedInfield
		check("a field maneuver includes final easing and its existing straight tail is departure",marker.section==section and marker.s0==500 and marker.a1==500 and marker.b0==640,
			"the last nonzero knot at620 is followed by easing to640; departure starts at640, before section end900")
		sp.length=900;state:_infields(section,500,marker)
		check("short known departures stay pending without publishing a moving taper",state.infieldPending and state.infieldPending.b0==640 and #observed==0,
			"publication waits for the bounded arm or next accepted maneuver")
		local nextSection={};sp.length=2100
		state:_infields(nextSection,900,{what="double",tag="Hairpin",a1=1000,b0=1050})
		check("two ready arm pairs share one publication batch",#observed==1 and #observed[1].intents==2
			and observed[1].intents[1].b1==1000 and observed[1].intents[2].pending.a0==640,
			"the older departure ends at the new curve start; a short back arm cannot reach behind its real start")
		observed={};state.infieldPending=nil;state.infieldArmStart=2000
		local group={};sp.length=2500
		state:_infields({},2200,{what="turnaround",tag="Switchback",a1=2200,b0=2300,group=group})
		check("the first switchback half never creates an opposite-arm field",state.infieldTurn and not state.infieldPending and #observed==0,
			"the original approach is retained across the gap")
		sp.length=2800;state:_infields({},2500,{what="switchbackOut",tag="Switchback",a1=2500,b0=2600,group={}})
		check("a different switchback finisher cannot borrow an older approach",state.infieldTurn==nil and state.infieldPending==nil,
			"matching names and tags do not replace pair identity")
		state.infieldTurn={a0=2000,a1=2200,group=group}
		state:_infields({},2800,{what="switchbackOut",tag="Switchback",group=group})
		check("an uncurved finisher still consumes its pair marker",state.infieldTurn==nil and state.infieldPending==nil,
			"a tiny-angle completion cannot leak a group into a later turn")
		state.infieldTurn={a0=2000,a1=2200,group=group}
		state:_infields({},2800,{what="switchbackOut",tag="Switchback",a1=2500,b0=2600,group=group})
		check("a complete switchback pairs the original approach with the final exit",state.infieldPending and state.infieldPending.a0==2000
			and state.infieldPending.a1==2200 and state.infieldPending.b0==2600,"both ninety-degree halves form one field pair")

		local function liveFixture()
			local curve,b0,sections=fixture(Spline,20)
			local fieldEnd=curve.length
			local tail={len=64,k={64,0},g={64,0},b={64,0},rl={64,16},rr={64,16},
				el={64,Spline.CLIFF},er={64,Spline.ROCK},hl={64,0},hr={64,0}}
			curve:append(tail);table.insert(sections,tail)
			local owner=setmetatable({spline=curve,biomes={},corridors=Corridor.new(),infieldStats={planned=0,published=0,declined=0,lastMs=0,worstMs=0}},Gen)
			owner:_registerGround(0,curve.length)
			return owner,curve,b0,sections,fieldEnd
		end
		local owner,curve,b0,sections,fieldEnd=liveFixture();local final=sections[#sections]
		local roadsBefore=#owner.corridors:roadCells(0,curve.length)
		local originalGround={}
		for _,cell in owner.corridors:roadCells(0,curve.length) do originalGround[cell]=table.clone(cell.p) end
		owner:_publishInfields(final,{{pending={a0=128,a1=480,b0=b0},b1=fieldEnd}})
		check("live publication attaches one validated batch and hard reservations together",final.ip and #final.ip>0 and table.isfrozen(final.ip)
			and curve.infieldRevision==1 and owner.corridors.infields>0,"accepted ground was registered before optional field planning")
		local actualRoads=owner.corridors:roadCells(0,curve.length);local onlyAccepted=true
		for _,cell in actualRoads do onlyAccepted=onlyAccepted and cell.road==true and not cell.infield and cell.s1<=curve.length end
		check("accepted-road arc queries exclude fields and provisional escapes",roadsBefore>0 and #actualRoads==roadsBefore and onlyAccepted,
			`{#actualRoads} accepted ground cells retain their identity after field publication`)
		local unchanged,common,bankError,mandatory=true,true,0,0
		for cell,corners in originalGround do for i,v in corners do if cell.p[i]~=v then unchanged=false end end end
		for _,patch in final.ip or {} do
			local stations={A={},B={}};local first,last=patch.rows[1],patch.rows[#patch.rows]
			for _,row in patch.rows do
				stations.A[row.sa]=true;stations.B[row.sb]=true
				for _,bank in {"A","B"} do
					local s,side,p=if bank=="A" then row.sa else row.sb,if bank=="A" then row.sideA else row.sideB,if bank=="A" then row.a else row.b
					local x,y,z=curve:terrainXYZ(s,side*(cfg.Road.Width*.5+curve:runoffAt(s,side)))
					bankError=math.max(bankError,math.abs(x-p[1]),math.abs(y-p[2]),math.abs(z-p[3]))
				end
			end
			for bank,range in {A={first.sa,last.sa},B={last.sb,first.sb}} do
				for _,cell in actualRoads do for _,s in {cell.s0,cell.s1} do
					if s>range[1] and s<range[2] then mandatory+=1;common=common and stations[bank][s]==true end
				end end
			end
		end
		check("field tessellation preserves both actual banks and every source cell end",mandatory>0 and common and bankError<1e-8,
			`{mandatory} source-end events; maximum bank displacement{bankError}`)
		check("refining attached banks never rewrites frozen global road footprints",unchanged,"all original accepted cell corners retain their exact values")
		if final.ip then
			local function wireCopy(value)
				if type(value)~="table" then return value end
				local out={};for key,item in value do out[key]=wireCopy(item) end;return out
			end
			local received=wireCopy(sections)
			local replay=Gen.replay(received,curve.origin,curve.fall)
			local row=final.ip[1].rows[math.ceil(#final.ip[1].rows*.5)]
			local point=DefaultInfield.columns(row)[6]
			local a,b=curve:infieldAt(point[1],point[3]),replay:infieldAt(point[1],point[3])
			check("serialized publication replays the exact frozen support",a and b and math.abs(a.y-b.y)<1e-6
				and #curve.infields.triangles==#replay.infields.triangles,"clients append the published section without replanning")
			local raw=received[#received].ip[1];local normalized=replay.infields.patches[raw.id]
			local oldY=normalized.rows[1].a[2];raw.rows[1].a[2]=999
			check("received numeric fields acquire independent immutable geometry",normalized~=raw and normalized~=final.ip[1]
				and table.isfrozen(normalized.rows[1].a) and normalized.rows[1].a[2]==oldY
				and DefaultInfield.canonical(normalized)==normalized,"raw wire tables are copied once at the batch boundary and cannot alter published support")
		else
			check("serialized publication replays the exact frozen support",false,"the publication needed for replay was missing")
			check("received numeric fields acquire independent immutable geometry",false,"the publication needed for replay was missing")
		end
		local obstructed,blocked,blockedB,_,blockedEnd=liveFixture()
		local patch=assert(final.ip and final.ip[1],"missing publication for obstacle fixture")
		local row=patch.rows[math.ceil(#patch.rows*.5)];local middle=DefaultInfield.columns(row)[6]
		local obstacle=assert(Corridor.cell(Corridor.row(200,middle[1],middle[3]+2,0,0,2,2),
			Corridor.row(204,middle[1],middle[3]-2,0,0,2,2)))
		obstacle.road=true;obstructed.corridors:add(obstacle)
		local blockedPublication={}
		obstructed:_publishInfields(blockedPublication,{{pending={a0=128,a1=480,b0=blockedB},b1=blockedEnd}})
		check("an arm-range tag cannot exempt unrelated occupied ground",blockedPublication.ip==nil and blocked.infields==nil,
			"a road-tagged cell in the arm arc range must also match its actual bank geometry")
		local declined,other,otherB,_,otherEnd=liveFixture();local before=declined.corridors
		local rowA=Corridor.row(other.length,other.origin.x-80,other.origin.z-350,0,0,20,20)
		local rowB=Corridor.row(other.length+32,other.origin.x-80,other.origin.z-382,0,0,20,20)
		declined._groundFrames=function()return {rowA,rowB}end
		local noPublication={}
		declined:_publishInfields(noPublication,{{pending={a0=128,a1=480,b0=otherB},b1=otherEnd}})
		check("optional fields cannot occupy the current tip's promised escape",noPublication.ip==nil and other.infields==nil
			and declined.corridors==before,"a temporary escape-only planning obstacle declines the field without persisting future road")
		local invalid={};owner:_publishInfields(invalid,{{pending={a1=480,b0=b0},b1=curve.length}})
		check("an optional field failure leaves accepted road and published indexes intact",invalid.ip==nil and owner.infieldStats.lastError~=nil
			and curve.length>0 and curve.infieldRevision==1,"invalid optional input does not rewind the accepted road or partially publish a batch")
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	C.Infield.Enabled=saved;C.GroundEnabled=savedGround
	if not ok then return {passed=0,total=1,checks={{name="generated field publication fixture completes",ok=false,detail=result}}} end
	return result
end

return Tests
