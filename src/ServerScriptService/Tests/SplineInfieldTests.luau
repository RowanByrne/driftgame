--!nonstrict
-- Frozen connector data and physical support; route ownership is deliberately separate.
assert(game:GetService("RunService"):IsStudio(),"SplineInfieldTests is Studio only")
local DefaultInfield=require(game.ReplicatedStorage.Shared.Road.SplineInfield)
local Tests={}

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

return Tests
