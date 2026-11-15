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
	local stitchIndex=Infield.new(8)
	Infield.add(stitchIndex,Infield.patch("stitch",{
		{sa=100,sb=200,sideA=1,sideB=-1,a={-1,.75,1},b={1,.75,1},weight=1},
		{sa=102,sb=198,sideA=1,sideB=-1,a={-1,.75,-1},b={1,.75,-1},weight=1},
	}))
	local stitchContext=Cuts.context(stitchIndex);local seamEdges=Cuts.perimeter(stitchContext)
	local seamId=nil;for id,e in seamEdges do if e.kind=="start" then seamId=id;break end end
	local e=seamEdges[seamId];local edx,edz=e.b[1]-e.a[1],e.b[3]-e.a[3];local edgeLength=math.sqrt(edx*edx+edz*edz)
	local function seamPoint(u,y)return {e.a[1]+edx*u,y,e.a[3]+edz*u}end
	local function seamU(p)return ((p[1]-e.a[1])*edx+(p[3]-e.a[3])*edz)/(edgeLength*edgeLength)end
	local function seamArea(seams)local ts={};for _,s in seams do table.insert(ts,s.points) end;return area(ts)end
	local function seamFixture(lines,copies)
		local cap=Cuts.newCapture(stitchContext);cap.lines[seamId]=lines or {};cap.copies=copies or {};return cap
	end
	local envelope=seamFixture({{u0=0,u1=1,y0=0,y1=1,material="up"},{u0=0,u1=1,y0=1,y1=0,material="down"}})
	local stitched,stitchReason=Cuts.stitch(envelope);assert(stitched,stitchReason)
	local splits={};local wrongNormal=0
	for _,s in stitched do
		local a,b,c=s.points[1],s.points[2],s.points[3]
		for _,p in s.points do splits[math.round(seamU(p)*100)]=true end
		local u=(seamU(a)+seamU(b)+seamU(c))/3;local height=math.max(u,1-u)
		local nx=(b[2]-a[2])*(c[3]-a[3])-(b[3]-a[3])*(c[2]-a[2])
		local nz=(b[1]-a[1])*(c[2]-a[2])-(b[2]-a[2])*(c[1]-a[1])
		if (nx*e.nx+nz*e.nz)*(if height>.75 then -1 else 1)<=0 then wrongNormal+=1 end
	end
	check("seams split at source-envelope and field-height crossings",splits[25] and splits[50] and splits[75]
		and wrongNormal==0 and math.abs(seamArea(stitched)-.125*edgeLength)<1e-8,
		`{#stitched} triangles; wrong exposed normals{wrongNormal}; area{seamArea(stitched)}`)
	local below=Cuts.stitch(seamFixture({{u0=0,u1=1,y0=0,y1=0,material="low"}}))
	check("source terrain below a field retains its full downward skirt",math.abs(seamArea(below)-.75*edgeLength)<1e-8,
		"the source envelope is independent of the frozen field height")
	local gap=Cuts.stitch(seamFixture({{u0=0,u1=.25,y0=1,y1=1,material="left"},{u0=.75,u1=1,y0=1,y1=1,material="right"}}))
	local bridged=false
	for _,s in gap do for _,p in s.points do local u=seamU(p);if u>.25+1e-8 and u<.75-1e-8 then bridged=true end end end
	check("seams never extrapolate across missing source intervals",not bridged and math.abs(seamArea(gap)-.125*edgeLength)<1e-8,
		"two finite source intervals leave their middle unfilled")
	local zero=Cuts.stitch(seamFixture({{u0=0,u1=1,y0=.75,y1=.75,material="flat"}}))
	check("matching heights do not emit degenerate seam triangles",#zero==0,"a zero-height join contributes no geometry")
	local copyPoints={seamPoint(0,.75),seamPoint(1,.75),seamPoint(0,1.75)}
	local repeated=seamFixture({{u0=0,u1=1,y0=1.75,y1=1.75,material="roof"}},
		{{edge=seamId,points=copyPoints,material="wall"},{edge=seamId,points={copyPoints[3],copyPoints[2],copyPoints[1]},material="duplicate"}})
	local united=Cuts.stitch(repeated);local localTriangles={};local copiesArea=0;local copyVisibility=true
	for _,s in united do
		local tri={};for _,p in s.points do table.insert(tri,{seamU(p),0,p[2]}) end;table.insert(localTriangles,tri)
		if s.copy then copiesArea+=area({s.points});copyVisibility=copyVisibility and s.twoSided==true end
	end
	local copyOverlap,copyMissing=0,0
	for ix=0,79 do for iy=0,79 do
		local u,y=(ix+.37)/80,.75+(iy+.61)/80;local count=0
		for _,tri in localTriangles do if contains({tri},u,y) then count+=1 end end
		if count>1 then copyOverlap+=1 elseif count==0 then copyMissing+=1 end
	end end
	check("coplanar copies and ribbons form one union without duplicate faces",math.abs(seamArea(united)-edgeLength)<1e-8
		and math.abs(copiesArea-edgeLength*.5)<1e-8 and copyOverlap==0 and copyMissing==0,
		`6400 seam-plane probes; overlap{copyOverlap}, missing{copyMissing}, total area{seamArea(united)}`)
	check("unioned coplanar closures retain their two-sided visibility intent",copiesArea>0 and copyVisibility,
		"a renderer must draw the single union face from both sides")
	local tied=Cuts.stitch(seamFixture({{u0=0,u1=1,y0=2,y1=2,material="first"},{u0=0,u1=1,y0=2,y1=2,material="second"}}))
	local firstWins=true;for _,s in tied do firstWins=firstWins and s.material=="first" end
	check("coincident source traces select a deterministic first material",#tied>0 and firstWins,"equal geometry cannot flicker between source materials")
	local many={};for i=1,64 do table.insert(many,{u0=0,u1=1,y0=i,y1=i,material="parallel"}) end
	local overWork,workReason=Cuts.stitch(seamFixture(many),{maxWork=1000})
	check("seam work is bounded even when source lines never cross",overWork==nil and workReason=="field seam work limit",
		"pair comparisons and envelope scans count against the same explicit work bound")
	local duplicates={};for i=1,600 do table.insert(duplicates,{u0=0,u1=1,y0=2,y1=2,material="same"}) end
	local overRaw,rawReason=Cuts.stitch(seamFixture(duplicates))
	check("duplicate-heavy seam input is bounded before cloning and sorting",overRaw==nil and rawReason=="field seam raw line limit",
		"deduplication cannot hide unbounded preparatory work")
	local overTriangles,triReason=Cuts.stitch(envelope,{maxTriangles=1})
	check("seam output overflow rejects the complete geometry",overTriangles==nil and triReason=="field seam triangle limit",
		"a partial seam is never returned as a successful mesh")
	local invalidTrace,traceReason=Cuts.stitch(seamFixture({{u0=0,u1=1,y0=0/0,y1=2,material="bad"}}))
	check("nonfinite seam traces fail before publication",invalidTrace==nil and traceReason=="invalid finite field seam trace",
		"invalid envelope inputs cannot leak nonfinite vertices")
	local sliver=Infield.new(8)
	Infield.add(sliver,Infield.patch("sliver",{
		{sa=100,sb=900,sideA=1,sideB=-1,a={0,0,0},b={40,0,0},weight=1},
		{sa=120,sb=899.9999999,sideA=1,sideB=-1,a={0,0,20},b={40,0,20},weight=1},
	}))
	local sliverContext=Cuts.context(sliver,nil,899.99999999)
	check("discarded retirement slivers cannot leave a ghost perimeter",#sliverContext.masks==0 and #Cuts.perimeter(sliverContext)==0,
		"perimeter coverage is filtered through the exact surviving mask triangles")
	local complete=Infield.new(32);local longRows={}
	for i=0,7 do table.insert(longRows,{sa=100+i*64,sb=2000-i*64,sideA=1,sideB=-1,a={-20,0,-i*64},b={20,0,-i*64},weight=1}) end
	Infield.add(complete,Infield.patch("long",longRows))
	local nearby=Infield.near(complete,0,0,1)
	local plan,planReason=Cuts.plan(complete,{long=true},100,3);assert(plan,planReason)
	check("a coverage plan retains a complete selected field beyond the query radius",#nearby<#plan.triangles and #plan.triangles==#complete.triangles
		and plan.hi[3]-plan.lo[3]==448 and #plan.context.masks==7,
		`near subset{#nearby}; complete frozen triangles{#plan.triangles}`)
	local retiredPlan=Cuts.plan(complete,{long=true},1000.125,4)
	local floorTriangles={};for _,t in retiredPlan.triangles do table.insert(floorTriangles,{t.a.p,t.b.p,t.c.p}) end
	local maskTriangles={};for _,m in retiredPlan.context.masks do for i=2,#m.points-1 do table.insert(maskTriangles,{m.points[1],m.points[i],m.points[i+1]}) end end
	local coverageMismatch=0
	for ix=0,39 do for iz=0,79 do
		local x,z=-20+(ix+.37),-(iz+.61)*5.6
		if contains(floorTriangles,x,z)~=contains(maskTriangles,x,z) then coverageMismatch+=1 end
	end;if ix%8==0 then task.wait() end end
	check("one retained coverage plan gives drawing and subtraction identical domains",coverageMismatch==0,
		`3200 fractional-q probes, mismatches{coverageMismatch}`)
	local frozenPlan=not pcall(function()retiredPlan.selection.long=false end)
		and not pcall(function()retiredPlan.triangles[1].a.p[1]+=1 end)
		and not pcall(function()retiredPlan.context.masks[1]=nil end)
		and not pcall(function()retiredPlan.context.edges[1].a[1]+=1 end)
	check("coverage geometry freezes nested retained points, masks and perimeter",frozenPlan,"builders cannot change a shared plan while yielding")
	local tickA,tickB=0,0
	local buildA=Cuts.forBuild(retiredPlan,function()tickA+=1 end,{maxPolygons=9})
	local buildB=Cuts.forBuild(retiredPlan,function()tickB+=1 end,{maxPolygons=17})
	buildA.tick();buildB.tick();buildB.tick()
	check("each builder has isolated callbacks and budgets over shared frozen geometry",tickA==1 and tickB==2
		and buildA.maxPolygons==9 and buildB.maxPolygons==17 and buildA.masks==buildB.masks
		and retiredPlan.context.tick==nil and retiredPlan.context.index==nil,
		"a fallback cannot inherit another job's cancellation callback")
	local empty,emptyReason=Cuts.plan(complete,{},100,3)
	local unknown,unknownReason=Cuts.plan(complete,{missing=true},100,3)
	local gone,goneReason=Cuts.plan(complete,{long=true},3000,3)
	check("empty, unknown and fully retired coverage choices are explicit",empty==nil and emptyReason=="empty"
		and unknown==nil and unknownReason=="unknown field patch" and gone==nil and goneReason=="empty",
		"empty selection never becomes all patches and unknown IDs never disappear silently")
	local steepEnds=Infield.new(8)
	Infield.add(steepEnds,Infield.patch("steep",{
		{sa=100,sb=300,sideA=1,sideB=-1,a={-1,0,1},b={1,0,1},weight=1,floor=floor},
		{sa=102,sb=298,sideA=1,sideB=-1,a={-1,0,-1},b={1,0,-1},weight=1,floor=floor},
	}))
	local visualPlan=Cuts.plan(steepEnds,{steep=true},100,1);local unsupported=0
	for _,t in visualPlan.triangles do if not t.supported then unsupported+=1 end end
	check("visual coverage includes unsupported frozen end faces",unsupported>0 and #visualPlan.triangles==#steepEnds.triangles,
		"only walking colliders filter support; visual masks retain the whole selected field")
	local hugeIndex=Infield.new(128);local hugeRows={}
	for i=0,39 do table.insert(hugeRows,{sa=100+i*64,sb=20000-i*64,sideA=1,sideB=-1,a={-20,0,-i*64},b={20,0,-i*64},weight=1}) end
	Infield.add(hugeIndex,Infield.patch("too long",hugeRows))
	local oversized,oversizedReason=Cuts.plan(hugeIndex,{["too long"]=true},100,1,{maxExtent=9000})
	check("field coverage cannot bypass the hard mesh extent bound",oversized==nil and oversizedReason=="field coverage exceeds the mesh bounds",
		"even a caller's larger extent option cannot allow a mesh wider than2048")
	local identityPlan=Cuts.plan(index,{one=true},100,3)
	check("coverage identity is scoped to its exact road index",plan.identity==complete and identityPlan.identity==index and plan.identity~=identityPlan.identity,
		"matching revisions and patch names from another road cannot reuse a plan")
	local passed=0;for _,c in checks do if c.ok then passed+=1 end end
	return {passed=passed,total=#checks,checks=checks}
end

function Tests.render()
	local root=game.ReplicatedStorage.Shared.Road
	local Infield,Cuts,Mesh,Parts=require(root.SplineInfield),require(root.SplineFieldCuts),require(root.SplineMesh),require(root.SplineParts)
	local cfg=require(game.ReplicatedStorage.Shared.Config)
	local folder=Instance.new("Folder");folder.Name="__T212PlannedFieldRender";folder.Parent=workspace
	local mesh,parts=nil,nil
	local ok,result=xpcall(function()
		local checks={};local function check(name,pass,detail)table.insert(checks,{name=name,ok=pass,detail=detail})end
		local index=Infield.new(32);local rows={}
		for i=0,7 do table.insert(rows,{sa=100+i*64,sb=2000-i*64,sideA=1,sideB=-1,
			a={29980,50,-20000-i*64},b={30020,50,-20000-i*64},weight=1}) end
		Infield.add(index,Infield.patch("complete",rows))
		local sp={infields=index,firstSample=0,step=2,infieldRevision=7}
		local plan=Cuts.plan(index,{complete=true},0,7)
		local capture=Cuts.newCapture(plan.context)
		local roof={{29970,60,-20020},{30030,60,-20020},{30030,60,-19980},{29970,60,-19980}}
		for _,t in {{roof[1],roof[2],roof[3]},{roof[1],roof[3],roof[4]}} do
			local captured,why=Cuts.capture(capture,t[1],t[2],t[3],cfg.Spline.Terrain.RockColour);assert(captured,why)
		end
		local seams,reason=Cuts.stitch(capture);assert(seams,reason)
		local info;mesh,info=Mesh.buildInfield(sp,30000,-20000,1,folder,{plan=plan,seams=seams})
		assert(mesh,tostring(info));local part=mesh.Infield;local em=part.MeshContent.Object
		check("actual planned field and all end seams share one double-sided mesh",#mesh:GetChildren()==1 and part.DoubleSided
			and #em:GetFaces()==#plan.triangles+#seams and info.seamTriangles==#seams and #seams>0
			and mesh:GetAttribute("InfieldCoverage")==plan.key,
			`{#plan.triangles} complete floor faces +{#seams} seam faces; radius1 did not truncate coverage`)
		local ground={};local seamHeightError=0;local seamFaces=0
		for _,face in em:GetFaces() do
			local points={};for _,id in em:GetFaceVertices(face) do table.insert(points,part.CFrame:PointToWorldSpace(em:GetPosition(id))) end
			local n=(points[2]-points[1]):Cross(points[3]-points[1]).Unit
			if math.abs(n.Y)>.8 then table.insert(ground,points) else
				seamFaces+=1
				for _,p in points do seamHeightError=math.max(seamHeightError,math.abs(p.Z+20000),math.max(50-p.Y,p.Y-60,0)) end
			end
		end
		local missing,heightError=0,0
		for _,t in plan.triangles do
			local a,b,c=t.a.p,t.b.p,t.c.p;local x,z=(a[1]+b[1]+c[1])/3,(a[3]+b[3]+c[3])/3;local found=false
			for _,p in ground do
				local aa,bb,cc=p[1],p[2],p[3];local bx,bz,cx,cz=bb.X-aa.X,bb.Z-aa.Z,cc.X-aa.X,cc.Z-aa.Z
				local det=bx*cz-bz*cx;local dx,dz=x-aa.X,z-aa.Z
				local u,v=(dx*cz-dz*cx)/det,(bx*dz-bz*dx)/det
				if u>= -1e-6 and v>= -1e-6 and u+v<=1+1e-6 then
					found=true;heightError=math.max(heightError,math.abs(aa.Y+u*(bb.Y-aa.Y)+v*(cc.Y-aa.Y)-50));break
				end
			end
			if not found then missing+=1 end
		end
		check("actual mesh retains distant plan floor and exact finite seam endpoints",missing==0 and heightError<.02 and seamFaces==#seams and seamHeightError<.02,
			`{#plan.triangles} floor centroids; missing{missing}; floor error{heightError}; seam error{seamHeightError}`)
		Mesh.destroy(mesh);mesh=nil
		parts,info=Parts.buildInfield(sp,30000,-20000,1,folder,{plan=plan,seams=seams,queryable=true})
		assert(parts,tostring(info));task.wait()
		local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={parts}
		local floor=workspace:Raycast(Vector3.new(30003.37,100,-20410.33),Vector3.new(0,-100,0),params)
		local front=workspace:Raycast(Vector3.new(30001.37,55,-19999),Vector3.new(0,0,-2),params)
		local back=workspace:Raycast(Vector3.new(30001.37,55,-20001),Vector3.new(0,0,2),params)
		local colliders=0;for _,p in parts:GetDescendants() do if p:IsA("BasePart") and p.CanCollide then colliders+=1 end end
		check("Parts fallback retains the same complete floor and seams from both sides",floor and math.abs(floor.Position.Y-50)<.02
			and front and back and math.abs(front.Position.Z+20000)<.15 and math.abs(back.Position.Z+20000)<.15
			and colliders==0 and info.triangles==#plan.triangles+#seams and parts:GetAttribute("InfieldCoverage")==plan.key,
			`distant floor{floor~=nil}, seam front{front~=nil}/back{back~=nil}, colliders{colliders}, Parts{info.parts}`)
		parts:Destroy();parts=nil
		local tooHigh={{points={{29980,50,-20000},{30020,50,-20000},{30000,3000,-20000}},material=cfg.Spline.Terrain.RockColour}}
		local refused,why=Mesh.buildInfield(sp,30000,-20000,1,folder,{plan=plan,seams=tooHigh})
		check("combined seam bounds are checked before allocating a field mesh",refused==nil and why=="infield view exceeds the mesh bounds" and #folder:GetChildren()==0,
			"a bounded floor cannot hide an oversized copied wall")
		local other={infields=Infield.new(32),firstSample=0,step=2,infieldRevision=7}
		local wrongRoad,wrongWhy=Mesh.buildInfield(other,30000,-20000,1,folder,{plan=plan,seams=seams})
		local wrongFirst,firstWhy=Parts.buildInfield(sp,30000,-20000,1,folder,{plan=plan,first=1})
		check("renderers refuse a coverage plan for another road or retained first",not wrongRoad and not wrongFirst and #folder:GetChildren()==0
			and string.find(wrongWhy,"another road")~=nil and string.find(firstWhy,"retained first")~=nil,"stale plan identity cannot publish either representation")
		local calls=0
		local cancelled,cancelWhy=Mesh.buildInfield(sp,30000,-20000,1,folder,{plan=plan,seams=seams,sliceMs=.001,
			cancelled=function()calls+=1;return calls>=2 end})
		local partCalls=0
		local cancelledParts,partsWhy=Parts.buildInfield(sp,30000,-20000,1,folder,{plan=plan,seams=seams,sliceMs=.001,
			cancelled=function()partCalls+=1;return partCalls>=2 end})
		check("cancelled planned field jobs publish no partial mesh or Parts",not cancelled and not cancelledParts and #folder:GetChildren()==0
			and string.find(cancelWhy,"cancelled")~=nil and string.find(partsWhy,"cancelled")~=nil,"cancellation is rechecked immediately after yielding")
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	if mesh then Mesh.destroy(mesh) end;if parts then parts:Destroy() end;folder:Destroy()
	if not ok then return {passed=0,total=1,checks={{name="planned field renderer fixture completes",ok=false,detail=result}}} end
	return result
end

return Tests
