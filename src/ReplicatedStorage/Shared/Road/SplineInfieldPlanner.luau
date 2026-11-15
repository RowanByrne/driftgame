--!strict
--!native
-- Plan a frozen connection between the known arms of an accepted turnaround.
-- The consumer never solves a mutable hillside during a car/walking probe.
local Config=require(game.ReplicatedStorage.Shared.Config)
local Infield=require(script.Parent.SplineInfield)
local Hill=require(script.Parent.SplineHill)
local Profile=require(script.Parent.SplineProfile)
local Corridor=require(script.Parent.SplineCorridor)
local Planner={}

local function smooth(x:number):number x=math.clamp(x,0,1);return x*x*(3-2*x) end

function Planner.cell(a:Infield.Row,b:Infield.Row):Corridor.Cell
	local p={a.a[1],a.a[3],b.a[1],b.a[3],b.b[1],b.b[3],a.b[1],a.b[3]}
	local x,z=(p[1]+p[3]+p[5]+p[7])*.25,(p[2]+p[4]+p[6]+p[8])*.25
	local minX,maxX,minZ,maxZ,r2=math.huge,-math.huge,math.huge,-math.huge,0
	for j=1,7,2 do
		minX,maxX=math.min(minX,p[j]),math.max(maxX,p[j])
		minZ,maxZ=math.min(minZ,p[j+1]),math.max(maxZ,p[j+1])
		r2=math.max(r2,(p[j]-x)^2+(p[j+1]-z)^2)
	end
	return {s0=a.sa,s1=b.sa,x=x,z=z,radius=math.sqrt(r2),minX=minX,maxX=maxX,minZ=minZ,maxZ=maxZ,p=p,infield=true}
end

-- Bounds describe the actual approach and departure arms, never arbitrary
-- nearby parallel roads. All geometry must still be in the retained spline.
function Planner.plan(sp:any,a0:number,a1:number,b0:number,b1:number,corridors:Corridor.Index?):({Infield.Patch},{Corridor.Cell})
	local patches,cells={},{}
	local C=Config.Spline.Biomes.Infield
	local first=sp.firstSample*sp.step
	a0=math.max(a0,a1-C.ArmLength,first);b1=math.min(b1,b0+C.ArmLength,sp.length)
	if a1-a0<C.MinSpan or b1-b0<C.MinSpan or b0<=a1 then return patches,cells end
	local half=Config.Road.Width*.5
	local function pair(sa:number,sb:number):Infield.Row?
		local ax,az=sp:planAt(sa);local bx,bz=sp:planAt(sb)
		local ya,yb=sp:yawAt(sa),sp:yawAt(sb)
		local d=(bx-ax)*math.cos(ya)-(bz-az)*math.sin(ya)
		if math.abs(d)<half*2 or math.cos(ya-yb)>C.HeadingDot then return nil end
		local sideA=if d<0 then -1 else 1
		local across=(ax-bx)*math.cos(yb)-(az-bz)*math.sin(yb)
		local sideB=if across<0 then -1 else 1
		local wa,wb=half+sp:runoffAt(sa,sideA),half+sp:runoffAt(sb,sideB)
		local x,y,z=sp:terrainXYZ(sa,sideA*wa)
		local xx,yy,zz=sp:terrainXYZ(sb,sideB*wb)
		local dx,dz=xx-x,zz-z;local gap=math.sqrt(dx*dx+dz*dz)
		if gap<C.MinGap or gap>C.MaxGap or math.abs(yy-y)/gap>C.MaxCrossSlope then return nil end
		if sideA*(dx*math.cos(ya)-dz*math.sin(ya))<gap*C.Facing
			or sideB*(-dx*math.cos(yb)+dz*math.sin(yb))<gap*C.Facing then return nil end
		local roadA=sp:heightAt(sa)+sideA*half*math.tan(sp:bankAt(sa))
		local roadB=sp:heightAt(sb)+sideB*half*math.tan(sp:bankAt(sb))
		local weight=Infield.strength(roadB-roadA,gap,C.FullRise,C.MaxRise,C.FullGap,C.MaxGap,C.MaxCrossSlope)
		if weight<=0 then return nil end
		local da=(y-sp:terrainY(sa,sideA*(wa-.1)))/.1
		local db=(yy-sp:terrainY(sb,sideB*(wb-.1)))/.1
		if math.abs(da)>.5+1e-6 or math.abs(db)>.5+1e-6 then return nil end
		return {sa=sa,sb=sb,sideA=sideA,sideB=sideB,a={x,y,z},b={xx,yy,zz},weight=weight,da=math.clamp(da,-.5,.5),db=math.clamp(db,-.5,.5)}
	end
	local function row(sb:number):Infield.Row?
		local bx,bz=sp:planAt(sb)
		local best,seed=math.huge,nil
		for s=a0,a1,32 do
			local x,z=sp:planAt(s);local d=(x-bx)^2+(z-bz)^2
			if d<best then best,seed=d,s end
		end
		if not seed then return nil end
		local sa,d=sp:projectFrom(bx,bz,seed)
		if not sa or not d or sa<a0 or sa>a1 or math.abs(d)<half*2 then return nil end
		return pair(sa,sb)
	end
	local chains,chain={},{}
	local function finish()
		if #chain>=5 then table.insert(chains,chain) end;chain={}
	end
	local sb=b0
	while true do
		local r=row(sb)
		local old=chain[#chain]
		if old and (not r or r.sideA~=old.sideA or r.sideB~=old.sideB or old.sa-r.sa<.1 or old.sa-r.sa>32) then finish() end
		if r then table.insert(chain,r) end
		if sb>=b1 then break end;sb=math.min(sb+C.Step,b1)
	end
	finish()
	if #chains==0 then return patches,cells end
	local function groundRow(s:number):Corridor.Row
		local x,z=sp:planAt(s)
		return Corridor.row(s,x,z,sp:yawAt(s),sp:curvatureAt(s),half+sp:runoffAt(s,-1),half+sp:runoffAt(s,1))
	end
	local known={};local sources={};local stations={A={},B={}}
	if corridors and corridors.roadCells then
		for bank,bounds in {A={a0,a1},B={b0,b1}} do
			for _,old in corridors:roadCells(bounds[1],bounds[2]) do
				if old.road and not old.infield and old.s0>=first and old.s1<=sp.length then
					local actual=Corridor.cell(groundRow(old.s0),groundRow(old.s1))
					local same=actual~=nil
					if actual then for i,v in old.p do if math.abs(v-actual.p[i])>1e-8 then same=false;break end end end
					if same then
						known[old]=bank;table.insert(sources,old)
						table.insert(stations[bank],old.s0);table.insert(stations[bank],old.s1)
					end
				end
			end
		end
	end
	local function refine(original:{Infield.Row}):{Infield.Row}?
		local sets={A={},B={}}
		for bank,values in stations do for _,s in values do sets[bank][s]=true end end
		local function trackStations(values:{number},low:number,high:number,target:any)
			local lo,hi=1,#values
			while lo<=hi do local mid=(lo+hi)//2;if values[mid]<low then lo=mid+1 else hi=mid-1 end end
			for i=lo,#values do local s=values[i];if s>high then break end;target[s]=true end
		end
		for _,name in {"curv","grade","bank","runL","runR","liftL","liftR"} do
			local track=sp[name]
			if track then
				trackStations(track.s,original[1].sa,original[#original].sa,sets.A)
				trackStations(track.s,original[#original].sb,original[1].sb,sets.B)
			end
		end
		local normalized={};local lists={A={},B={}}
		for bank,values in sets do for s in values do table.insert(lists[bank],s) end end
		local function snap(value:number,bank:string):number
			local closest,delta=value,1e-4
			for _,s in lists[bank] do
				local allowed=if bank=="A" then s>=a0 and s<=a1 else s>=b0 and s<=b1
				if allowed and math.abs(s-value)<delta then closest,delta=s,math.abs(s-value) end
			end
			return closest
		end
		for _,r in original do
			local a,b=snap(r.sa,"A"),snap(r.sb,"B")
			local nextRow=pair(a,b)
			if not nextRow or nextRow.sideA~=r.sideA or nextRow.sideB~=r.sideB then return nil end
			table.insert(normalized,nextRow)
		end
		local events={}
		local function event(u:number,sa:number,sb:number,ma:boolean,mb:boolean)
			table.insert(events,{u=u,sa=sa,sb=sb,ma=ma,mb=mb})
		end
		for i,r in normalized do event(i-1,r.sa,r.sb,sets.A[r.sa]==true,sets.B[r.sb]==true) end
		for i=1,#normalized-1 do
			local a,b=normalized[i],normalized[i+1]
			if b.sa<=a.sa or b.sb>=a.sb then return nil end
			for bank,values in lists do
				local start,finish=if bank=="A" then a.sa else a.sb,if bank=="A" then b.sa else b.sb
				for _,s in values do
					local t=(s-start)/(finish-start)
					if t>0 and t<1 then event(i-1+t,if bank=="A" then s else a.sa+(b.sa-a.sa)*t,
						if bank=="B" then s else a.sb+(b.sb-a.sb)*t,bank=="A",bank=="B") end
				end
			end
		end
		table.sort(events,function(a,b)return a.u<b.u end)
		local common={}
		for _,e in events do
			local previous=common[#common]
			if previous and math.abs(e.sa-previous.sa)<=1e-4 and math.abs(e.sb-previous.sb)<=1e-4 then
				-- Coincident events from opposite banks share one row, retaining
				-- BOTH exact stations. Distinct same-bank events cannot be dropped.
				if previous.ma and e.ma and previous.sa~=e.sa or previous.mb and e.mb and previous.sb~=e.sb then return nil end
				if e.ma then previous.sa=e.sa end;if e.mb then previous.sb=e.sb end
				previous.ma=previous.ma or e.ma;previous.mb=previous.mb or e.mb
			else table.insert(common,e) end
		end
		if #common>512 then return nil end
		local firstRow=pair(common[1].sa,common[1].sb);if not firstRow then return nil end
		local output={firstRow}
		local function append(a:Infield.Row,b:Infield.Row,depth:number):boolean
			local sa,sb=(a.sa+b.sa)*.5,(a.sb+b.sb)*.5
			local middle=pair(sa,sb)
			if not middle or middle.sideA~=a.sideA or middle.sideB~=a.sideB then return false end
			local error=0;local certified=true
			for _,t in {.25,.5,.75} do
				local sample=if t==.5 then middle else pair(a.sa+(b.sa-a.sa)*t,a.sb+(b.sb-a.sb)*t)
				if not sample or sample.sideA~=a.sideA or sample.sideB~=a.sideB then return false end
				for _,bank in {"a","b"} do for j=1,3 do error=math.max(error,math.abs((sample[bank][j]-a[bank][j])-(b[bank][j]-a[bank][j])*t)) end end
				-- Contact meets the chord along the actual outward bank normal,
				-- not necessarily at the parameter-linear fraction used above.
				for _,bank in {"a","b"} do
					local s,side=if bank=="a" then sample.sa else sample.sb,if bank=="a" then sample.sideA else sample.sideB
					local yaw=sp:yawAt(s);local nx,nz=side*math.cos(yaw),-side*math.sin(yaw)
					local p,q,v=a[bank],b[bank],sample[bank]
					local dx,dz=q[1]-p[1],q[3]-p[3];local denominator=nx*dz-nz*dx
					if math.abs(denominator)<1e-12 then certified=false;continue end
					local rx,rz=p[1]-v[1],p[3]-v[3]
					local distance=(rx*dz-rz*dx)/denominator
					if distance>0 then
						local u=(rx*nz-rz*nx)/denominator
						if u<=0 or u>=1 or distance>C.BankContactPad or math.abs(p[2]+(q[2]-p[2])*u-v[2])>C.BankSag then certified=false end
					end
				end
			end
			if error>C.BankSag or not certified then
				if depth>=8 or #output>=511 then return false end
				return append(a,middle,depth+1) and append(middle,b,depth+1)
			end
			if #output>=512 then return false end
			table.insert(output,b);return true
		end
		for i=2,#common do
			local previous=output[#output];local e=common[i];local nextRow=pair(e.sa,e.sb)
			if not nextRow or nextRow.sa<=previous.sa or nextRow.sb>=previous.sb or not append(previous,nextRow,0) then return nil end
		end
		return output
	end
	local function refinedGround(rows:{Infield.Row}):Corridor.Index?
		local precise=Corridor.new()
		local points={A={},B={}}
		for _,r in rows do points.A[r.sa]=r.a;points.B[r.sb]=r.b end
		for _,old in sources do
			local bank=known[old];local cuts={old.s0,old.s1}
			for s in points[bank] do if s>old.s0 and s<old.s1 then table.insert(cuts,s) end end
			table.sort(cuts)
			for i=1,#cuts-1 do
				local a,b=groundRow(cuts[i]),groundRow(cuts[i+1])
				local cell=Corridor.cell(a,b);if not cell then return nil end
				local side=if bank=="A" then rows[1].sideA else rows[1].sideB
				for _,entry in {{cuts[i],if side<0 then 1 else 3},{cuts[i+1],if side<0 then 7 else 5}} do
					local p=points[bank][entry[1]]
					if p then cell.p[entry[2]],cell.p[entry[2]+1]=p[1],p[3] end
				end
				-- The field's exact corner values are authoritative at a shared
				-- bank. Recompute broadphase bounds after their identical copy.
				cell.minX,cell.maxX,cell.minZ,cell.maxZ=math.huge,-math.huge,math.huge,-math.huge
				local radius=0
				for j=1,7,2 do
					local x,z=cell.p[j],cell.p[j+1]
					cell.minX,cell.maxX=math.min(cell.minX,x),math.max(cell.maxX,x)
					cell.minZ,cell.maxZ=math.min(cell.minZ,z),math.max(cell.maxZ,z)
					radius=math.max(radius,(x-cell.x)^2+(z-cell.z)^2)
				end
				cell.radius=math.sqrt(radius);precise:add(cell)
			end
		end
		return precise
	end
	local ctx=nil
	local pending=Infield.new()
	for _,backward in chains do
		local rows={}
		for i=#backward,1,-1 do table.insert(rows,backward[i]) end
		local common=refine(rows);if not common then continue end;rows=common
		local precise=refinedGround(rows);if not precise then continue end
		ctx=ctx or Hill.context(sp,a0,b1,Profile.draw,nil,true)
		local start,ending=rows[1],rows[#rows]
		local length=math.min(ending.sa-start.sa,start.sb-ending.sb)
		local fade=math.min(C.EndBlend,length*.25)
		if length<C.MinSpan then continue end
		local baselineValid=true
		for _,r in rows do
			local distance=math.min(r.sa-start.sa,ending.sa-r.sa,start.sb-r.sb,r.sb-ending.sb)
			r.weight*=smooth(distance/fade)
			local heights={}
			for j,p in Infield.columns(r) do
				local base=if r.weight==1 or j==1 or j==11 then p[2] else Hill.heightAt(ctx,p[1],p[3])
				if not base then baselineValid=false;break end
				heights[j]=base+(p[2]-base)*r.weight
			end
			if not baselineValid then break end
			heights[1],heights[11]=r.a[2],r.b[2];r.floor=heights
		end
		if not baselineValid then continue end
		-- An end can retain a steep original face. Keep its existing bank
		-- boundary closed until both complete collars really provide support.
		local function supported(a:{number},b:{number},c:{number}):boolean
			local n=Vector3.new(b[1]-a[1],b[2]-a[2],b[3]-a[3]):Cross(Vector3.new(c[1]-a[1],c[2]-a[2],c[3]-a[3]))
			return n.Magnitude>1e-8 and math.abs(n.Y)/n.Magnitude>.8
		end
		for i=1,#rows-1 do
			local a,b=Infield.columns(rows[i]),Infield.columns(rows[i+1])
			for j=1,10 do
				if j==5 or j==6 then continue end
				if not supported(a[j],b[j],b[j+1]) or not supported(a[j],b[j+1],a[j+1]) then
					rows[i].weight,rows[i+1].weight=0,0;break
				end
			end
		end
		local reserved={};local clear=true
		for i=1,#rows-1 do
			local cell=Planner.cell(rows[i],rows[i+1]);table.insert(reserved,cell)
			if corridors then
				for _,old in corridors:near(cell,0,0) do
					-- The attached banks may touch this boundary, but no occupied
					-- ground, including a bulge in either arm, may enter its interior.
					if not known[old] and Corridor.overlap(cell,old,0) then clear=false;break end
				end
			end
			if clear then for _,old in precise:near(cell,0,0) do if Corridor.overlap(cell,old,0) then clear=false;break end end end
			if not clear then break end
		end
		if not clear then continue end
		local id=`infield:{start.sa}:{ending.sa}:{ending.sb}:{start.sb}`
		local patch=Infield.patch(id,rows)
		local ok=pcall(function()
			if sp.infields then Infield.add(sp.infields,patch,true) end
			Infield.add(pending,patch)
		end)
		if not ok then continue end
		table.insert(patches,patch)
		for _,cell in reserved do table.insert(cells,cell) end
	end
	return patches,cells
end

return Planner
