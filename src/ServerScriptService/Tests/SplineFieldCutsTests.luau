--!nonstrict
-- Scenery subtraction must preserve source planes and finite field boundaries.
assert(game:GetService("RunService"):IsStudio(),"SplineFieldCutsTests is Studio only")
local Tests={}

local function area(triangles)
	local total=0
	for _,t in triangles do
		local a,b,c=t[1],t[2],t[3]
		local dx,dy,dz=b[1]-a[1],b[2]-a[2],b[3]-a[3]
		local ex,ey,ez=c[1]-a[1],c[2]-a[2],c[3]-a[3]
		total+=math.sqrt((dy*ez-dz*ey)^2+(dz*ex-dx*ez)^2+(dx*ey-dy*ex)^2)*.5
	end
	return total
end

local function contains(triangles,x,z)
	for _,t in triangles do
		local a,b,c=t[1],t[2],t[3]
		local bx,bz,cx,cz=b[1]-a[1],b[3]-a[3],c[1]-a[1],c[3]-a[3]
		local det=bx*cz-bz*cx
		if math.abs(det)<1e-10 then continue end
		local dx,dz=x-a[1],z-a[3]
		local u,v=(dx*cz-dz*cx)/det,(bx*dz-bz*dx)/det
		if u>= -1e-8 and v>= -1e-8 and u+v<=1+1e-8 then return true end
	end
	return false
end

function Tests.run(_self,subjects)
	local root=game.ReplicatedStorage.Shared.Road
	local Cuts=subjects and subjects.Cuts or require(root.SplineFieldCuts)
	local Infield=subjects and subjects.Infield or require(root.SplineInfield)
	local checks={};local function check(name,pass,detail)table.insert(checks,{name=name,ok=pass,detail=detail})end
	local function rectangle(index,id,x0,x1,z0,z1,arc,collars)
		local rows={}
		for i,z in {z1,z0} do
			local row={sa=arc+(i-1)*2,sb=arc+100-(i-1)*2,sideA=1,sideB=-1,a={x0,0,z},b={x1,0,z},weight=1}
			if collars then row.floor={0,0,0,0,0,0,0,0,0,0,0} end
			table.insert(rows,row)
		end
		Infield.add(index,Infield.patch(id,rows))
	end
	local index=Infield.new(8);rectangle(index,"one",-1,1,-1,1,100,true)
	local context=Cuts.context(index)
	check("convex row masks compress the entire frozen eleven-column footprint",#index.triangles==20 and #context.masks==1,
		"twenty published surface triangles have one identical convex footprint")
	check("cached mask planes cannot be changed by a mesh builder",not pcall(function()context.masks[1].planes[1].nx+=1 end),
		"contexts share immutable mask geometry")
	local function point(x,z)return {x,2*x+3*z+7,z}end
	local a,b,c=point(-3,-3),point(3,-3),point(0,3)
	local result,changed,reason=Cuts.triangle(context,a,b,c)
	assert(result,reason)
	local planeError=0
	for _,t in result do for _,p in t do planeError=math.max(planeError,math.abs(p[2]-(2*p[1]+3*p[3]+7))) end end
	check("subtraction retains exact source heights instead of lowering a repaired hillside",changed and planeError<1e-8
		and math.abs(area(result)-14*math.sqrt(14))<1e-7,`{#result} triangles, plane error{planeError}, 3D area{area(result)}`)
	local missing,leaks,tested=0,0,0
	for ix=0,119 do for iz=0,119 do
		local x,z=-3+(ix+.37)*.05,-3+(iz+.61)*.05
		local source=contains({{a,b,c}},x,z)
		local masked=x> -1 and x<1 and z> -1 and z<1
		local found=contains(result,x,z)
		if source and not masked and not found then missing+=1 end
		if masked and found then leaks+=1 end;tested+=1
	end;if ix%16==0 then task.wait() end end
	check("cut triangles cover all outside scenery and none of the field interior",missing==0 and leaks==0,
		`{tested} finite footprint probes; missing{missing}, leaks{leaks}`)
	local reverse=Cuts.triangle(context,c,b,a)
	local reverseWinding=true
	for _,t in reverse do local x,y,z=t[1],t[2],t[3]
		reverseWinding=reverseWinding and (y[1]-x[1])*(z[3]-x[3])-(y[3]-x[3])*(z[1]-x[1])<0
	end
	check("reversing source winding keeps the same finite retained geometry",reverseWinding and math.abs(area(reverse)-area(result))<1e-7,
		"flat normals may follow the original face direction without changing the cut")
	local unchanged,cut=Cuts.triangle(context,point(4,0),point(6,0),point(5,2))
	check("unrelated triangles retain their original vertices",not cut and #unchanged==1 and unchanged[1][1][1]==4,
		"a field mask has no effect beyond its finite footprint")
	local wall,didCut=Cuts.triangle(context,{0,-10,-3},{0,10,-3},{0,0,3})
	check("vertical faces are clipped by 3D area despite their zero plan area",didCut and math.abs(area(wall)-40)<1e-7,
		`vertical wall retained area{area(wall)}, expected40`)
	local adjacent=Infield.new(8)
	rectangle(adjacent,"left",-2,0,-1,1,200,false);rectangle(adjacent,"right",0,2,-1,1,400,false)
	local union=Cuts.context(adjacent)
	local fin,finCut=Cuts.triangle(union,{0,-3,-.9},{0,3,-.9},{0,0,.9})
	check("a vertical fin on a shared internal mask edge is removed",finCut and #fin==0,
		"closed halfspaces do not leave an internal raised wall")
	local selected=Cuts.context(adjacent,{left=true})
	local kept=Cuts.triangle(selected,{.2,0,-.5},{1.8,0,-.5},{1,0,.5})
	check("mask selection cuts only the complete chosen patches",#selected.masks==1 and #kept==1 and math.abs(area(kept)-.8)<1e-8,
		"later field-view coverage can name its exact matching clipping set")
	local retired=Cuts.context(index,nil,150)
	local low,retiredCut=Cuts.triangle(retired,{-2,0,-2},{2,0,-2},{0,0,2})
	local mismatch=0
	for ix=0,59 do for iz=0,59 do
		local x,z=-2+(ix+.29)/15,-2+(iz+.43)/15
		local source=contains({{{-2,0,-2},{2,0,-2},{0,0,2}}},x,z)
		local floor=Infield.sample(index,x,z)
		local expected=source and not (floor and floor.closingS>=150)
		if contains(low,x,z)~=expected then mismatch+=1 end
	end end
	check("retirement masks use the stored per-triangle closure scalar",retiredCut and mismatch==0,
		`3600 retained-domain probes, mismatches{mismatch}`)
	local concave=Infield.new(8)
	Infield.add(concave,Infield.patch("concave",{
		{sa=100,sb=900,sideA=1,sideB=-1,a={0,0,0},b={4,0,0},weight=1},
		{sa=102,sb=898,sideA=1,sideB=-1,a={0,0,-4},b={3.9,0,-.09},weight=1},
	}))
	local concaveContext=Cuts.context(concave)
	local ca,cb,cc={-10,0,-10},{10,0,-10},{0,0,10}
	local concaveCut=Cuts.triangle(concaveContext,ca,cb,cc)
	local concaveRetained=Cuts.triangle(Cuts.context(concave,nil,500),ca,cb,cc)
	check("a valid concave field cell retains its actual triangulation",#concaveContext.masks>1
		and math.abs(area(concaveCut)-(200-7.98))<1e-7 and math.abs(area(concaveRetained)-(200-2.035))<1e-7,
		`{#concaveContext.masks} exact masks; whole area{area(concaveCut)}, retained-q area{area(concaveRetained)}`)
	local crossing=CFrame.new(0,50,0)*CFrame.Angles(.3,.7,.2)
	local clear=CFrame.new(10,50,10)*CFrame.Angles(.3,.7,.2)
	check("caster rejection detects fields crossing a tilted box's middle",Cuts.intersectsBox(context,crossing,Vector3.new(8,2,8))
		and not Cuts.intersectsBox(context,clear,Vector3.new(2,2,2)),
		"full projected box SAT, independent of its height and corner membership")
	check("a separated tilted caster does not fail only because its bounding boxes overlap",not Cuts.intersectsBox(context,
		CFrame.new(1.6,0,1.6)*CFrame.Angles(0,math.pi*.25,0),Vector3.new(4,.5,.1)),
		"the thin diagonal passes beyond the field corner")
	local shifted=Infield.new(8)
	rectangle(shifted,"far",1000000.125-1,1000000.125+1,-2000000.25-1,-2000000.25+1,100,true)
	local function move(p)return {p[1]+1000000.125,p[2],p[3]-2000000.25}end
	local far=Cuts.triangle(Cuts.context(shifted),move(a),move(b),move(c))
	check("large translated coordinates preserve source plane area",math.abs(area(far)-area(result))<1e-5,
		`translated area error{math.abs(area(far)-area(result))}`)
	local failed,_,why=Cuts.triangle(Cuts.context(index,nil,nil,{maxPolygons=1}),a,b,c)
	check("fragmentation overflow rejects the certified build explicitly",failed==nil and string.find(tostring(why),"fragmentation")~=nil,
		"no uncut or silently missing scenery is substituted")
	local invalid,_,invalidReason=Cuts.triangle(context,{0/0,0,0},b,c)
	check("nonfinite source geometry fails before clipping",invalid==nil and invalidReason~=nil,"bad vertices cannot publish a partial mesh")
	local function perimeterLength(edges)
		local total=0;for _,e in edges do total+=math.sqrt((e.b[1]-e.a[1])^2+(e.b[3]-e.a[3])^2) end;return total
	end
	local perimeter=Cuts.perimeter(context)
	check("finite perimeter omits internal row and column diagonals",math.abs(perimeterLength(perimeter)-8)<1e-8,
		`{#perimeter} frozen linear edge pieces; length{perimeterLength(perimeter)}`)
	local unionEdges=Cuts.perimeter(union);local internal=0
	for _,e in unionEdges do if math.abs(e.a[1])+math.abs(e.b[1])<1e-8 then internal+=1 end end
	check("touching patches have no shared internal perimeter",internal==0 and math.abs(perimeterLength(unionEdges)-12)<1e-8,
		`internal edges{internal}; exterior length{perimeterLength(unionEdges)}`)
	local retainedEdges=Cuts.perimeter(retired);local badOutward,retiredCount=0,0
	for _,e in retainedEdges do
		local mx,mz=(e.a[1]+e.b[1])*.5,(e.a[3]+e.b[3])*.5
		local inside=contains((function()local ts={};for _,m in retired.masks do table.insert(ts,m.points) end;return ts end)(),mx+e.nx*1e-5,mz+e.nz*1e-5)
		if inside then badOutward+=1 end
		if e.kind=="retired" then retiredCount+=1 end
	end
	check("retained perimeter includes exact closure contours facing retired space",retiredCount>0 and badOutward==0,
		`closure segments{retiredCount}, outward samples inside retained masks{badOutward}`)
	local frozenEnds=Infield.new(8)
	local floor={0,1,2,3,4,9,4,3,2,1,0}
	Infield.add(frozenEnds,Infield.patch("uneven",{
		{sa=100,sb=300,sideA=1,sideB=-1,a={-20,0,1},b={20,0,1},weight=1,floor=floor},
		{sa=102,sb=298,sideA=1,sideB=-1,a={-20,0,-1},b={20,0,-1},weight=1,floor=floor},
	}))
	local uneven=Cuts.context(frozenEnds);local maxY=0;local endCount=0
	for _,e in Cuts.perimeter(uneven) do if e.kind=="start" or e.kind=="end" then
		endCount+=1;maxY=math.max(maxY,e.a[2],e.b[2])
	end end
	check("perimeter retains every frozen end-height crease",endCount==20 and maxY==9,
		"eleven published columns remain ten linear pieces at both ends")
	local capture=Cuts.newCapture(context)
	local function planePoint(x,z)return {x,2*x+3*z+7,z}end
	local captured,capReason=Cuts.capture(capture,planePoint(-10,-10),planePoint(10,-10),planePoint(0,10),"hill")
	local traces,traceError,bankTraces=0,0,0
	for id,lines in capture.lines do for _,line in lines do
		local e=perimeter[id];if e.kind=="bank" then bankTraces+=1 end
		for _,v in {{line.u0,line.y0},{line.u1,line.y1}} do
			local x=e.a[1]+(e.b[1]-e.a[1])*v[1];local z=e.a[3]+(e.b[3]-e.a[3])*v[1]
			traceError=math.max(traceError,math.abs(v[2]-(2*x+3*z+7)))
		end
		traces+=1
	end end
	check("actual cut-edge traces preserve the source triangle height plane",captured and traces==20 and traceError<1e-8 and bankTraces==0,
		`traces{traces}, height error{traceError}, bank wall traces{bankTraces}; {tostring(capReason)}`)
	local wallCapture=Cuts.newCapture(context)
	local wallOK=Cuts.capture(wallCapture,{-2,-3,1},{2,-3,1},{0,5,1},"wall")
	local copied={};local wrongEdge=0
	for _,copy in wallCapture.copies do
		table.insert(copied,copy.points)
		local e=perimeter[copy.edge]
		if e.kind~="start" then wrongEdge+=1 end
		for _,p in copy.points do if p[1]< -1-1e-8 or p[1]>1+1e-8 or math.abs(p[3]-1)>1e-8 then wrongEdge+=1 end end
	end
	check("coplanar exterior walls preserve their finite removed faces",wallOK and #copied>0 and wrongEdge==0 and math.abs(area(copied)-12)<1e-7,
		`copied area{area(copied)}, expected12; invalid copies{wrongEdge}`)
	local bankCapture=Cuts.newCapture(context)
	Cuts.capture(bankCapture,{-1,-3,-2},{-1,-3,2},{-1,5,0},"old mountain")
	check("opened bank walls are removed instead of restored as scenery joins",#bankCapture.copies==0 and next(bankCapture.lines)==nil,
		"the existing supported road bank owns the attachment")
	local finiteCapture=Cuts.newCapture(context)
	Cuts.capture(finiteCapture,{-.2,4,1},{.2,4,1},{0,4,2},"small roof")
	local finiteLength=0
	for id,lines in finiteCapture.lines do for _,line in lines do
		local e=perimeter[id];finiteLength+=(line.u1-line.u0)*math.sqrt((e.b[1]-e.a[1])^2+(e.b[3]-e.a[3])^2)
	end end
	check("seam capture stops at actual triangle edges rather than infinite planes",math.abs(finiteLength-.4)<1e-8,
		`finite source span{finiteLength}, expected0.4`)
	local interiorCapture=Cuts.newCapture(context)
	Cuts.capture(interiorCapture,{-.2,40,1},{.2,40,1},{0,40,0},"removed roof")
	check("an interior roof touching the perimeter cannot resurrect a raised join",next(interiorCapture.lines)==nil and #interiorCapture.copies==0,
		"only retained outward scenery supplies a seam height")
	local limited=Cuts.newCapture(context,1)
	local limitOK,limitReason=Cuts.capture(limited,planePoint(-10,-10),planePoint(10,-10),planePoint(0,10),"hill")
	check("seam capture overflow fails the entire proposed build",not limitOK and limitReason=="field seam capture limit",
		"caller must discard the capture instead of publishing a partial join")
	local snapshot=Infield.new(8);rectangle(snapshot,"before",-1,1,-1,1,100,false)
	local snapshotContext=Cuts.context(snapshot)
	rectangle(snapshot,"after",10,12,-1,1,300,false)
	check("a draw context cannot acquire later patches while yielding",math.abs(perimeterLength(Cuts.perimeter(snapshotContext))-8)<1e-8,
		"immutable selected patch identities survive incremental builds")
	local angled=Infield.new(32);local angle=.371;local angledRows={}
	local function rotate(x,z)return {1000000.125+x*math.cos(angle)-z*math.sin(angle),0,-2000000.25+x*math.sin(angle)+z*math.cos(angle)}end
	for i=0,4 do table.insert(angledRows,{sa=100+i*32,sb=2000-i*32,sideA=1,sideB=-1,a=rotate(-60,-i*32),b=rotate(60,-i*32),weight=1}) end
	Infield.add(angled,Infield.patch("angled",angledRows))
	local angledContext=Cuts.context(angled,nil,1000);local chordError=0;local chosen=nil
	for _,e in Cuts.perimeter(angledContext) do if e.kind=="retired" then
		chordError=math.max(chordError,math.abs((e.b[1]-e.a[1])*e.nx+(e.b[3]-e.a[3])*e.nz));chosen=chosen or e
	end end
	local angledCapture=Cuts.newCapture(angledContext)
	Cuts.capture(angledCapture,{chosen.a[1],-2,chosen.a[3]},{chosen.b[1],-2,chosen.b[3]},{chosen.a[1],2,chosen.a[3]},"retired wall")
	check("retired coplanar capture uses numeric chord planes at large coordinates",chordError<1e-12 and #angledCapture.copies>0,
		`normal/chord error{chordError}, copied triangles{#angledCapture.copies}`)
	local touching=Infield.new(8);rectangle(touching,"flat",-20,20,-2,0,100,true)
	local oldCount=#touching.triangles
	local accepted=pcall(function()Infield.add(touching,Infield.patch("raised middle",{
		{sa=400,sb=600,sideA=1,sideB=-1,a={-20,0,2},b={20,0,2},weight=1,floor=floor},
		{sa=402,sb=598,sideA=1,sideB=-1,a={-20,0,0},b={20,0,0},weight=1,floor=floor},
	}))end)
	check("touching fields cannot publish unequal frozen end heights",not accepted and #touching.triangles==oldCount and touching.patches["raised middle"]==nil,
		"matching bank endpoints cannot hide a raised center step; rejection remains atomic")
	local passed=0;for _,c in checks do if c.ok then passed+=1 end end
	return {passed=passed,total=#checks,checks=checks}
end

return Tests
