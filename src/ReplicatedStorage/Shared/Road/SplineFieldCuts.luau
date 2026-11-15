--!strict
--!native
-- Scenery subtraction only. Frozen supported banks, tarmac and physical feet
-- remain their own authority; this never moves a source vertex vertically.
local Infield=require(script.Parent.SplineInfield)
local Cuts={}

export type Point={number}
type Polygon={Point}
type Plane={x:number,z:number,nx:number,nz:number}
type Mask={points:Polygon,planes:{Plane},x0:number,x1:number,z0:number,z1:number,patch:string}
export type Context={masks:{Mask},hash:{[string]:{number}},cell:number,maxPolygons:number,maxVertices:number,tick:(()->())?}

local EPS=1e-8
local fullCache=setmetatable({}, {__mode="k"}) :: any

local function finite(n:number):boolean return n==n and math.abs(n)<math.huge end
local function area2(polygon:Polygon):number
	local a=polygon[1];local area=0
	for i=2,#polygon-1 do local b,c=polygon[i],polygon[i+1];area+=(b[1]-a[1])*(c[3]-a[3])-(b[3]-a[3])*(c[1]-a[1]) end
	return area
end

local function bounds(polygon:Polygon):(number,number,number,number)
	local x0,x1,z0,z1=math.huge,-math.huge,math.huge,-math.huge
	for _,p in polygon do x0=math.min(x0,p[1]);x1=math.max(x1,p[1]);z0=math.min(z0,p[3]);z1=math.max(z1,p[3]) end
	return x0,x1,z0,z1
end

local function mask(points:Polygon,id:string):Mask?
	local area=area2(points)
	if math.abs(area)<EPS then return nil end
	local sign=if area>0 then 1 else -1
	local planes={}
	for i,a in points do
		local b,c=points[i%#points+1],points[(i+1)%#points+1]
		local dx,dz=b[1]-a[1],b[3]-a[3];local length=math.sqrt(dx*dx+dz*dz)
		if length<EPS or sign*(dx*(c[3]-b[3])-dz*(c[1]-b[1]))<=EPS then return nil end
		table.insert(planes,table.freeze({x=a[1],z=a[3],nx= -sign*dz/length,nz=sign*dx/length}))
	end
	local x0,x1,z0,z1=bounds(points)
	return table.freeze({points=table.freeze(table.clone(points)),planes=table.freeze(planes),x0=x0,x1=x1,z0=z0,z1=z1,patch=id})
end

local function patchMasks(index:any,patch:any):{Mask}
	local cached=fullCache[patch]
	if cached then return cached end
	local byRow={}
	for _,id in index.byPatch[patch.id] do
		local t=index.triangles[id]
		byRow[t.sa0]=byRow[t.sa0] or {};table.insert(byRow[t.sa0],t)
	end
	local out={}
	for i=1,#patch.rows-1 do
		local a,b=patch.rows[i],patch.rows[i+1]
		local quad=mask({a.a,b.a,b.b,a.b},patch.id)
		if quad then table.insert(out,quad) else
			-- A concave/ambiguous cell keeps the exact published triangulation.
			for _,t in byRow[a.sa] do
				local triangle=mask({t.a.p,t.b.p,t.c.p},patch.id)
				assert(triangle,"invalid frozen field footprint")
				table.insert(out,triangle)
			end
		end
	end
	fullCache[patch]=table.freeze(out)
	return out
end

-- Selection contains complete chosen patch identities. A retained first clips
-- using the exact affine q triangles, not a bilinear approximation of a quad.
function Cuts.context(index:any,selection:{[string]:boolean}?,first:number?,options:any?):Context
	local o=options or {}
	local context:Context={masks={},hash={},cell=if index then index.cell else 128,
		maxPolygons=o.maxPolygons or 512,maxVertices=o.maxVertices or 2048,tick=o.tick}
	if not index then return context end
	local ids={};for id in index.patches do if not selection or selection[id] then table.insert(ids,id) end end;table.sort(ids)
	local function append(m:Mask)
		table.insert(context.masks,m);local id=#context.masks
		for x=math.floor(m.x0/context.cell),math.floor(m.x1/context.cell) do
			for z=math.floor(m.z0/context.cell),math.floor(m.z1/context.cell) do
				local key=`{x}:{z}`;context.hash[key]=context.hash[key] or {};table.insert(context.hash[key],id)
			end
		end
	end
	for _,id in ids do
		local patch=index.patches[id];local rows=patch.rows
		if first and first>=rows[1].sb then continue end
		if not first or first<=rows[1].sa then
			for _,m in patchMasks(index,patch) do append(m) end
		else
			local points={};for _,row in rows do table.insert(points,row.a);table.insert(points,row.b) end
			local x0,x1,z0,z1=bounds(points)
			local x,z=(x0+x1)*.5,(z0+z1)*.5;local radius=math.max(x1-x0,z1-z0)*.5+1
			for _,t in Infield.near(index,x,z,radius,nil,first) do
				if t.patch~=id then continue end
				local m=mask({t.a.p,t.b.p,t.c.p},id)
				if m then append(m) end
			end
		end
		if context.tick then context.tick() end
	end
	return context
end

local function candidates(context:Context,x0:number,x1:number,z0:number,z1:number):{number}
	local seen={};local out={}
	for x=math.floor((x0-EPS)/context.cell),math.floor((x1+EPS)/context.cell) do
		for z=math.floor((z0-EPS)/context.cell),math.floor((z1+EPS)/context.cell) do
			for _,id in context.hash[`{x}:{z}`] or {} do
				if seen[id] then continue end;seen[id]=true
				local m=context.masks[id]
				if x1<m.x0-EPS or x0>m.x1+EPS or z1<m.z0-EPS or z0>m.z1+EPS then continue end
				table.insert(out,id)
			end
		end
	end
	table.sort(out);return out
end

local function valid(polygon:Polygon):boolean
	if #polygon<3 then return false end
	local a=polygon[1]
	for i=2,#polygon-1 do
		local b,c=polygon[i],polygon[i+1]
		local dx,dy,dz=b[1]-a[1],b[2]-a[2],b[3]-a[3]
		local ex,ey,ez=c[1]-a[1],c[2]-a[2],c[3]-a[3]
		if (dy*ez-dz*ey)^2+(dz*ex-dx*ez)^2+(dx*ey-dy*ex)^2>1e-18 then return true end
	end
	return false
end

local function distance(plane:Plane,p:Point):number return (p[1]-plane.x)*plane.nx+(p[3]-plane.z)*plane.nz end

local function halfspace(polygon:Polygon,plane:Plane,inside:boolean):Polygon
	local out={};local previous=polygon[#polygon]
	if not previous then return out end
	local sign=if inside then 1 else -1
	local dp=distance(plane,previous)*sign
	for _,point in polygon do
		local d=distance(plane,point)*sign
		if (dp>=0)~=(d>=0) then
			local u=dp/(dp-d)
			table.insert(out,{previous[1]+(point[1]-previous[1])*u,previous[2]+(point[2]-previous[2])*u,previous[3]+(point[3]-previous[3])*u})
		end
		if d>=0 then table.insert(out,point) end
		previous,dp=point,d
	end
	return out
end

local function difference(polygon:Polygon,m:Mask):({Polygon},boolean)
	local inside=polygon;local outside={}
	for _,plane in m.planes do
		local lo,hi=math.huge,-math.huge
		for _,p in inside do local d=distance(plane,p);lo=math.min(lo,d);hi=math.max(hi,d) end
		-- Closed mask boundaries deliberately include vertical fins on a shared
		-- internal edge. Exterior coplanar faces need explicit seam capture.
		if lo>= -EPS then continue end
		if hi<=EPS then return {polygon},false end
		local part=halfspace(inside,plane,false)
		if valid(part) then table.insert(outside,part) end
		inside=halfspace(inside,plane,true)
		if not valid(inside) then return {polygon},false end
	end
	if not valid(inside) then return {polygon},false end
	return outside,true
end

-- Preserve each original triangle's 3D plane/winding, including vertical faces.
-- A fragmentation overflow is a failed certified build, never uncut geometry.
function Cuts.triangle(context:Context,a:Point,b:Point,c:Point):({Polygon}?,boolean,string?)
	local source={a,b,c}
	for _,p in source do if #p~=3 or not finite(p[1]) or not finite(p[2]) or not finite(p[3]) then return nil,false,"non-finite scenery triangle" end end
	if not valid(source) then return {},false,nil end
	local x0,x1,z0,z1=bounds(source)
	local polygons={source};local changed=false
	for n,id in candidates(context,x0,x1,z0,z1) do
		local nextPolygons={};local vertices=0
		for pindex,polygon in polygons do
			local pieces,cut=difference(polygon,context.masks[id]);changed=changed or cut
			for _,piece in pieces do
				vertices+=#piece
				if #nextPolygons>=context.maxPolygons or vertices>context.maxVertices then return nil,true,"field clipping fragmentation limit" end
				table.insert(nextPolygons,piece)
			end
			if context.tick and pindex%16==0 then context.tick() end
		end
		polygons=nextPolygons
		if #polygons==0 then break end
		if context.tick and n%16==0 then context.tick() end
	end
	if not changed then return {source},false,nil end
	local triangles={}
	for _,polygon in polygons do for i=2,#polygon-1 do
		local triangle={polygon[1],polygon[i],polygon[i+1]}
		if valid(triangle) then table.insert(triangles,triangle) end
	end end
	return triangles,true,nil
end

-- A field can pass through the middle of a caster with every box corner
-- outside. SAT uses the complete projected box, including its tilted axes.
function Cuts.intersectsBox(context:Context,cf:CFrame,size:Vector3):boolean
	local centre=cf.Position
	local axes={cf.RightVector,cf.UpVector,cf.LookVector}
	local half={size.X*.5,size.Y*.5,size.Z*.5}
	local hx,hz=0,0
	for i,axis in axes do hx+=math.abs(axis.X)*half[i];hz+=math.abs(axis.Z)*half[i] end
	local function overlap(m:Mask,nx:number,nz:number):boolean
		if nx*nx+nz*nz<1e-16 then return true end
		local radius=0
		for i,axis in axes do radius+=math.abs(nx*axis.X+nz*axis.Z)*half[i] end
		local lo,hi=math.huge,-math.huge
		for _,p in m.points do local d=(p[1]-centre.X)*nx+(p[3]-centre.Z)*nz;lo=math.min(lo,d);hi=math.max(hi,d) end
		return hi>= -radius-EPS and lo<=radius+EPS
	end
	for _,id in candidates(context,centre.X-hx,centre.X+hx,centre.Z-hz,centre.Z+hz) do
		local m=context.masks[id];local inside=true
		for _,plane in m.planes do if not overlap(m,plane.nx,plane.nz) then inside=false;break end end
		if not inside then continue end
		for _,axis in axes do if not overlap(m,-axis.Z,axis.X) then inside=false;break end end
		if inside then return true end
	end
	return false
end

return Cuts
