--!strict
--!native
-- Frozen near-level connections. Geometry is plain numeric section data; this
-- module imports neither Spline nor Hill. Support never changes route ownership.
local Infield={}

export type Point={number}
-- weight masks a bank opening; the supplied final floor is always real support.
-- da/db are frozen outward bank slopes. Short collars meet those slopes before
-- reaching the nearly flat middle, without moving either bank endpoint.
export type Row={sa:number,sb:number,sideA:number,sideB:number,a:Point,b:Point,weight:number,da:number?,db:number?,floor:{number}?}
export type Patch={id:string,rows:{Row}}
type Vertex={p:Point,t:number,u:number,q:number}
type Triangle={a:Vertex,b:Vertex,c:Vertex,normal:Vector3,det:number,patch:string,sa0:number,sa1:number,sb0:number,sb1:number,supported:boolean}
type Opening={patch:Patch,bank:string,first:number,last:number}
export type Index={cell:number,patches:{[string]:Patch},triangles:{Triangle},hash:{[string]:{number}},openings:{[string]:{Opening}},closing:{[number]:{Patch}},byPatch:{[string]:{number}}}
export type Hit={y:number,normal:Vector3,patch:string,contactS:number,sa:number,sb:number,across:number,closingS:number}
export type Closing={a:Point,b:Point,normal:Vector3,patch:string}
export type Link={patch:Patch,bank:string,peerS:number,peerSide:number,peerFirst:number,peerLast:number,ownerSide:number}

local function finite(n:number):boolean return n==n and math.abs(n)<math.huge end
local function copyPoint(p:Point):Point
	assert(#p==3 and finite(p[1]) and finite(p[2]) and finite(p[3]),"invalid infield point")
	return table.freeze({p[1],p[2],p[3]})
end

function Infield.strength(rise:number,gap:number,fullRise:number,maxRise:number,fullGap:number,maxGap:number,maxSlope:number):number
	if gap<=0 or math.abs(rise)/gap>maxSlope then return 0 end
	local function fade(value:number,full:number,maximum:number):number
		local t=math.clamp((value-full)/math.max(maximum-full,1e-6),0,1)
		return 1-t*t*(3-2*t)
	end
	return fade(math.abs(rise),fullRise,maxRise)*fade(gap,fullGap,maxGap)
end

function Infield.patch(id:string,rows:{Row}):Patch
	assert(id~="","an infield needs a stable identity")
	assert(#rows>=2 and #rows<=512,"an infield needs 2..512 boundary rows")
	assert(rows[#rows].sa<rows[#rows].sb,"infield approach and departure arc ranges must be disjoint")
	local copy={}
	for i,row in rows do
		assert(finite(row.sa) and finite(row.sb) and row.weight>=0 and row.weight<=1,"invalid infield row")
		assert((row.sideA==-1 or row.sideA==1) and (row.sideB==-1 or row.sideB==1),"invalid infield side")
		assert(finite(row.da or 0) and finite(row.db or 0) and math.abs(row.da or 0)<=.5 and math.abs(row.db or 0)<=.5,"invalid infield bank slope")
		if i>1 then
			assert(row.sa>rows[i-1].sa and row.sb<rows[i-1].sb,"infield pairing must be monotone and opposed")
			assert(row.sideA==rows[i-1].sideA and row.sideB==rows[i-1].sideB,"infield cannot switch boundary sides")
		end
		local floor=nil
		if row.floor then
			assert(#row.floor==11,"an explicit infield section needs eleven heights")
			floor={};for _,y in row.floor do assert(finite(y),"invalid infield height");table.insert(floor,y) end
			assert(math.abs(floor[1]-row.a[2])<1e-8 and math.abs(floor[11]-row.b[2])<1e-8,"infield cannot move a bank")
			floor=table.freeze(floor)
		end
		table.insert(copy,table.freeze({sa=row.sa,sb=row.sb,sideA=row.sideA,sideB=row.sideB,a=copyPoint(row.a),b=copyPoint(row.b),weight=row.weight,da=row.da or 0,db=row.db or 0,floor=floor}))
	end
	return table.freeze({id=id,rows=table.freeze(copy)})
end

-- The planner freezes final heights in these same eleven columns. The short
-- collars preserve an occupied bank's slope; the broad middle stays low poly.
function Infield.columns(row:Row):{Point}
	local a,b=row.a,row.b
	local gap=math.sqrt((b[1]-a[1])^2+(b[3]-a[3])^2)
	assert(gap>.01,"infield has no clear gap")
	local reach=math.min(6,gap*.2)
	local out={}
	local function vertex(u:number,y:number)
		local i=#out+1
		table.insert(out,{a[1]+(b[1]-a[1])*u,if row.floor then row.floor[i] else y,a[3]+(b[3]-a[3])*u})
	end
	for j=0,4 do local v=j/4;vertex(reach*v/gap,a[2]+(row.da or 0)*reach*(v-.5*v*v)) end
	vertex(.5,(a[2]+(row.da or 0)*reach*.5+b[2]+(row.db or 0)*reach*.5)*.5)
	for j=4,0,-1 do local v=j/4;vertex(1-reach*v/gap,b[2]+(row.db or 0)*reach*(v-.5*v*v)) end
	return out
end

function Infield.new(cell:number?):Index
	assert(not cell or finite(cell) and cell>0,"invalid infield index spacing")
	return {cell=cell or 128,patches={},triangles={},hash={},openings={},closing={},byPatch={}}
end

local function key(x:number,z:number,cell:number):string return `{math.floor(x/cell)}:{math.floor(z/cell)}` end

local function keys(index:Index,triangle:Triangle):{string}
	local a,b,c=triangle.a.p,triangle.b.p,triangle.c.p
	local out={}
	for x=math.floor(math.min(a[1],b[1],c[1])/index.cell),math.floor(math.max(a[1],b[1],c[1])/index.cell) do
		for z=math.floor(math.min(a[3],b[3],c[3])/index.cell),math.floor(math.max(a[3],b[3],c[3])/index.cell) do table.insert(out,`{x}:{z}`) end
	end
	return out
end

local function overlaps(a:Triangle,b:Triangle):boolean
	local aa,bb={a.a.p,a.b.p,a.c.p},{b.a.p,b.b.p,b.c.p}
	local ox,oz=aa[1][1],aa[1][3]
	for _,polygon in {aa,bb} do for i,p in polygon do
		local q=polygon[i%3+1]
		local nx,nz=-(q[3]-p[3]),q[1]-p[1]
		local length=math.sqrt(nx*nx+nz*nz)
		if length<1e-10 then continue end
		local alo,ahi,blo,bhi=math.huge,-math.huge,math.huge,-math.huge
		for _,v in aa do local d=(v[1]-ox)*nx+(v[3]-oz)*nz;alo=math.min(alo,d);ahi=math.max(ahi,d) end
		for _,v in bb do local d=(v[1]-ox)*nx+(v[3]-oz)*nz;blo=math.min(blo,d);bhi=math.max(bhi,d) end
		if math.min(ahi,bhi)-math.max(alo,blo)<=1e-7*length then return false end
	end end
	return true
end

-- Triangles share a fixed midline, with optional bank collars. Rendering and physical
-- contacts use these exact triangles, including a twisted pair of bank edges.
function Infield.add(index:Index,patch:Patch,validateOnly:boolean?):boolean
	patch=Infield.patch(patch.id,patch.rows)
	local previous=index.patches[patch.id]
	if previous then
		assert(#previous.rows==#patch.rows,"conflicting infield identity")
		for i,row in patch.rows do
			local old=previous.rows[i]
			for _,name in {"sa","sb","sideA","sideB","weight","da","db"} do assert((row :: any)[name]==(old :: any)[name],"conflicting infield identity") end
			for _,name in {"a","b"} do for j=1,3 do assert((row :: any)[name][j]==(old :: any)[name][j],"conflicting infield identity") end end
			assert((row.floor~=nil)==(old.floor~=nil),"conflicting infield identity")
			if row.floor and old.floor then for j=1,11 do assert(row.floor[j]==old.floor[j],"conflicting infield identity") end end
		end
		return false
	end
	local pending:{Triangle}={}
	local sign:number?=nil
	local collars=false
	for _,row in patch.rows do if row.floor or math.abs(row.da or 0)+math.abs(row.db or 0)>1e-8 then collars=true;break end end
	local function cross(row:Row,t:number):{Vertex}
		local a,b=row.a,row.b
		local gap=math.sqrt((b[1]-a[1])^2+(b[3]-a[3])^2)
		assert(gap>.01,"infield has no clear gap")
		local reach=math.min(6,gap*.2)
		local out={}
		local function vertex(u:number,y:number)
			table.insert(out,table.freeze({p=table.freeze({a[1]+(b[1]-a[1])*u,y,a[3]+(b[3]-a[3])*u}),t=t,u=u,q=row.sa+(row.sb-row.sa)*u}))
		end
		if collars then
			for _,p in Infield.columns(row) do
				local u=math.sqrt((p[1]-a[1])^2+(p[3]-a[3])^2)/gap
				vertex(u,p[2])
			end
		else
			vertex(0,a[2]);vertex(.5,(a[2]+b[2])*.5);vertex(1,b[2])
		end
		return out
	end
	for i=1,#patch.rows-1 do
		local a,b=patch.rows[i],patch.rows[i+1]
		local pa,pb,qa,qb=a.a,b.a,a.b,b.b
		local function distance(x:Point,y:Point):number return math.sqrt((x[1]-y[1])^2+(x[3]-y[3])^2) end
		assert(distance(pa,pb)<=64 and distance(qa,qb)<=64,"infield row span exceeds its bounded lookup")
		assert(distance(pa,qa)<=256 and distance(pb,qb)<=256,"infield gap exceeds its bounded lookup")
		local A,B=cross(a,0),cross(b,1)
		for j=1,#A-1 do for _,vertices in {{A[j],B[j],B[j+1]},{A[j],B[j+1],A[j+1]}} do
			local x,y,z=vertices[1],vertices[2],vertices[3]
			local dx,dy,dz=y.p[1]-x.p[1],y.p[2]-x.p[2],y.p[3]-x.p[3]
			local ex,ey,ez=z.p[1]-x.p[1],z.p[2]-x.p[2],z.p[3]-x.p[3]
			local det=dx*ez-dz*ex
			assert(math.abs(det)>1e-5,"collapsed infield cell")
			local orientation=if det>0 then 1 else -1
			assert(not sign or sign==orientation,"folded infield cell")
			sign=orientation
			local normal=Vector3.new(dx,dy,dz):Cross(Vector3.new(ex,ey,ez)).Unit
			if normal.Y<0 then normal=-normal end
			-- Explicit end sections may retain an existing steep hillside. They
			-- are visible terrain, never a hidden driveable/walkable floor.
			assert(normal.Y>.01 and (a.floor or b.floor or normal.Y>.8),"infield surface is too steep")
			table.insert(pending,table.freeze({a=x,b=y,c=z,normal=normal,det=det,patch=patch.id,sa0=a.sa,sa1=b.sa,sb0=a.sb,sb1=b.sb,supported=normal.Y>.8}))
		end end
	end
	local staged:{[string]:{Triangle}}={}
	local byTriangle:{[Triangle]:{string}}={}
	for _,triangle in pending do
		local seen:{[Triangle]:boolean}={}
		local buckets=keys(index,triangle);byTriangle[triangle]=buckets
		for _,k in buckets do
			for _,id in index.hash[k] or {} do
				local old=index.triangles[id]
				if seen[old] then continue end;seen[old]=true
				assert(not overlaps(triangle,old),"infield would change an already published support domain")
			end
			for _,old in staged[k] or {} do
				if seen[old] then continue end;seen[old]=true
				assert(not overlaps(triangle,old),"infield strip overlaps itself")
			end
		end
		for _,k in buckets do
			local bucket=staged[k];if not bucket then bucket={};staged[k]=bucket end
			table.insert(bucket,triangle)
		end
	end
	-- Validation is complete before the index acquires any of the patch.
	if validateOnly then return true end
	index.patches[patch.id]=patch
	local patchIds={};index.byPatch[patch.id]=patchIds
	for _,triangle in pending do
		table.insert(index.triangles,triangle)
		local id=#index.triangles
		table.insert(patchIds,id)
		for _,k in byTriangle[triangle] do
			local bucket=index.hash[k]
			if not bucket then bucket={};index.hash[k]=bucket end
			table.insert(bucket,id)
		end
	end
	local first,last=patch.rows[1],patch.rows[#patch.rows]
	local q0,q1=math.min(first.sa,last.sa,first.sb,last.sb),math.max(first.sa,last.sa,first.sb,last.sb)
	for arc=math.floor(q0/index.cell),math.floor(q1/index.cell) do
		local bucket=index.closing[arc];if not bucket then bucket={};index.closing[arc]=bucket end
		table.insert(bucket,patch)
	end
	for _,bank in {"A","B"} do
		local side=if bank=="A" then first.sideA else first.sideB
		local start=if bank=="A" then first.sa else last.sb
		local finish=if bank=="A" then last.sa else first.sb
		local opening={patch=patch,bank=bank,first=start,last=finish}
		for arc=math.floor(start/index.cell),math.floor(finish/index.cell) do
			local k=`{side}:{arc}`
			local bucket=index.openings[k]
			if not bucket then bucket={};index.openings[k]=bucket end
			table.insert(bucket,opening)
		end
	end
	return true
end

function Infield.sample(index:Index,x:number,z:number,low:number?,high:number?):Hit?
	local best:Hit?=nil
	for _,id in index.hash[key(x,z,index.cell)] or {} do
		local triangle=index.triangles[id]
		if not triangle.supported then continue end
		local a,b,c=triangle.a,triangle.b,triangle.c
		local dx,dz=x-a.p[1],z-a.p[3]
		local u=(dx*(c.p[3]-a.p[3])-dz*(c.p[1]-a.p[1]))/triangle.det
		local v=((b.p[1]-a.p[1])*dz-(b.p[3]-a.p[3])*dx)/triangle.det
		if u< -1e-7 or v< -1e-7 or u+v>1+1e-7 then continue end
		local y=a.p[2]+u*(b.p[2]-a.p[2])+v*(c.p[2]-a.p[2])
		if (low and y<low) or (high and y>high) or (best and y<=best.y) then continue end
		local t=a.t+u*(b.t-a.t)+v*(c.t-a.t)
		local across=a.u+u*(b.u-a.u)+v*(c.u-a.u)
		local sa=triangle.sa0+(triangle.sa1-triangle.sa0)*t
		local sb=triangle.sb0+(triangle.sb1-triangle.sb0)*t
		best={y=y,normal=triangle.normal,patch=triangle.patch,contactS=if across<=.5 then sa else sb,sa=sa,sb=sb,across=across,
			closingS=a.q+u*(b.q-a.q)+v*(c.q-a.q)}
	end
	return best
end

-- Accepted ownership is selected by the caller's bounded route history, never
-- by which physical bank happens to be nearest across the field.
function Infield.route(hit:Hit,hint:number?,limit:number,patch:Patch):number?
	if hint==nil then return nil end
	local first,last=patch.rows[1],patch.rows[#patch.rows]
	local function distance(a:number,b:number):number return math.max(a-hint,hint-b,0) end
	local a,b=distance(first.sa,last.sa),distance(last.sb,first.sb)
	if a==b or math.min(a,b)>limit then return nil end
	local owner=if a<b then hit.sa else hit.sb
	return if math.abs(owner-hint)<=limit then owner else nil
end

function Infield.pair(patch:Patch,bank:string,s:number):number?
	local rows=patch.rows
	local function arc(row:Row):number return if bank=="A" then row.sa else row.sb end
	local first,last=arc(rows[1]),arc(rows[#rows])
	if s<math.min(first,last)-1e-7 or s>math.max(first,last)+1e-7 then return nil end
	local lo,hi=1,#rows
	while lo<hi do
		local mid=(lo+hi+1)//2
		if (if bank=="A" then arc(rows[mid])<=s else arc(rows[mid])>=s) then lo=mid else hi=mid-1 end
	end
	local a,b=rows[math.min(lo,#rows-1)],rows[math.min(lo+1,#rows)]
	local u=math.clamp((s-arc(a))/(arc(b)-arc(a)),0,1)
	local aa,bb=if bank=="A" then a.sb else a.sa,if bank=="A" then b.sb else b.sa
	return aa+(bb-aa)*u
end

function Infield.links(index:Index,s:number):{Link}
	local out={}
	for _,side in {-1,1} do
		for _,opening in index.openings[`{side}:{math.floor(s/index.cell)}`] or {} do
			if s<opening.first or s>opening.last then continue end
			local patch,bank=opening.patch,opening.bank
			local peer=Infield.pair(patch,bank,s)
			if not peer then continue end
			local a,b=patch.rows[1],patch.rows[#patch.rows]
			table.insert(out,{patch=patch,bank=bank,peerS=peer,ownerSide=side,
				peerSide=if bank=="A" then a.sideB else a.sideA,
				peerFirst=if bank=="A" then b.sb else a.sa,peerLast=if bank=="A" then a.sb else b.sa})
		end
	end
	return out
end

-- Return whole nearby triangles: rendering must not lose the opposite half
-- merely because its road leg lies outside the ordinary arc-length window.
function Infield.near(index:Index,x:number,z:number,radius:number,supportedOnly:boolean?):{Triangle}
	local ids={}
	for cx=math.floor((x-radius)/index.cell),math.floor((x+radius)/index.cell) do
		for cz=math.floor((z-radius)/index.cell),math.floor((z+radius)/index.cell) do
			for _,id in index.hash[`{cx}:{cz}`] or {} do ids[id]=true end
		end
	end
	local ordered={};for id in ids do table.insert(ordered,id) end;table.sort(ordered)
	local out={}
	for _,id in ordered do
		local t=index.triangles[id]
		if supportedOnly and not t.supported then continue end
		local a,b,c=t.a.p,t.b.p,t.c.p
		if math.max(a[1],b[1],c[1])<x-radius or math.min(a[1],b[1],c[1])>x+radius
			or math.max(a[3],b[3],c[3])<z-radius or math.min(a[3],b[3],c[3])>z+radius then continue end
		table.insert(out,t)
	end
	return out
end

-- A separate closure coordinate joins both road arcs continuously across the
-- exact frozen triangles. It grants no progress or accepted route ownership.
-- Its isoline closes the field while leaving a later live peer road open.
function Infield.closing(index:Index,s:number):{Closing}
	local out={};local seen={}
	local function pointKey(p:Point):string return `{math.round(p[1]*1e5)}:{math.round(p[3]*1e5)}` end
	for _,patch in index.closing[math.floor(s/index.cell)] or {} do
		for _,id in index.byPatch[patch.id] do
			local t=index.triangles[id]
			local vertices={t.a,t.b,t.c}
			local points={}
			local function add(p:Point)
				for _,old in points do if (old[1]-p[1])^2+(old[3]-p[3])^2<1e-12 then return end end
				table.insert(points,p)
			end
			for i,v in vertices do
				local w=vertices[i%3+1]
				local a,b=v.q-s,w.q-s
				if math.abs(a)<1e-8 then add(v.p) end
				if a*b<0 then
					local u=a/(a-b)
					add({v.p[1]+(w.p[1]-v.p[1])*u,v.p[2]+(w.p[2]-v.p[2])*u,v.p[3]+(w.p[3]-v.p[3])*u})
				end
			end
			if #points~=2 then continue end
			local a,b,c=t.a,t.b,t.c
			local dx,dz=b.p[1]-a.p[1],b.p[3]-a.p[3]
			local ex,ez=c.p[1]-a.p[1],c.p[3]-a.p[3]
			local normal=Vector3.new(((b.q-a.q)*ez-(c.q-a.q)*dz)/t.det,0,(dx*(c.q-a.q)-ex*(b.q-a.q))/t.det)
			if normal.Magnitude<1e-8 then continue end
			local ka,kb=pointKey(points[1]),pointKey(points[2])
			local key=if ka<kb then ka.."/"..kb else kb.."/"..ka
			if seen[key] then continue end;seen[key]=true
			table.insert(out,{a=points[1],b=points[2],normal=normal.Unit,patch=patch.id})
		end
	end
	return out
end

-- This is a boundary mask only. A caller still owns its accepted route hint;
-- contactS from sample() must never be fed straight into earned progress.
function Infield.opening(index:Index,s:number,side:number,taper:number?):number
	local amount=0
	for _,opening in index.openings[`{side}:{math.floor(s/index.cell)}`] or {} do
		local start,finish,bank=opening.first,opening.last,opening.bank
		if s<start or s>finish then continue end
		local rows=opening.patch.rows
		local lo,hi=1,#rows
		while lo<hi do
			local mid=(lo+hi+1)//2
			if (if bank=="A" then rows[mid].sa<=s else rows[mid].sb>=s) then lo=mid else hi=mid-1 end
		end
		local a,b=rows[math.min(lo,#rows-1)],rows[math.min(lo+1,#rows)]
		local sa,sb=if bank=="A" then a.sa else a.sb,if bank=="A" then b.sa else b.sb
		local u=math.clamp((s-sa)/(sb-sa),0,1)
		local weight=a.weight+(b.weight-a.weight)*u
		-- Explicit geometry already contains its frozen end blend. Do not
		-- apply a second, different fade to its physical bank opening.
		local fade=math.max(1e-6,math.min(taper or 64,(finish-start)*.25))
		local t=if a.floor and b.floor then 1 else math.clamp(math.min(s-start,finish-s)/fade,0,1)
		amount=math.max(amount,weight*t*t*(3-2*t))
	end
	return amount
end

function Infield.triangles(index:Index,s0:number,s1:number,origin:Vector3?):{{Vector3}}
	local out={}
	for _,triangle in index.triangles do
		local a,b=triangle.a,triangle.b
		local bankA=(a.u+b.u+triangle.c.u)/3<.5
		local first,last=if bankA then triangle.sa0 else triangle.sb1,if bankA then triangle.sa1 else triangle.sb0
		if last<s0 or first>s1 then continue end
		local row={}
		for _,v in {triangle.a,triangle.b,triangle.c} do
			local p=v.p
			table.insert(row,Vector3.new(p[1]-(if origin then origin.X else 0),p[2]-(if origin then origin.Y else 0),p[3]-(if origin then origin.Z else 0)))
		end
		table.insert(out,row)
	end
	return out
end

return Infield
