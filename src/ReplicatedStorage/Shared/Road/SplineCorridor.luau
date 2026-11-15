--!strict
--!native
-- Frozen plan footprints for supported ground (T-203). The no-crossing centre-line
-- check stays unchanged; these offset strips additionally protect wide fields.
-- Corners are retained when old curve samples retire. No world/instance queries.
local Config = require(game.ReplicatedStorage.Shared.Config)
local Corridor = {}
local Index = {}
Index.__index = Index

export type Row = {s:number, x:number, z:number, yaw:number, k:number, rx:number, rz:number, left:number, right:number}
export type Cell = {s0:number, s1:number, x:number, z:number, radius:number,
	minX:number, maxX:number, minZ:number, maxZ:number, p:{number},infield:boolean?,road:boolean?}
export type Index = typeof(setmetatable({} :: {
	buckets:{[number]:{Cell}}, reach:number, count:number, minS:number, maxS:number,infields:number,
	roads:{[number]:{Cell}},
}, Index))

function Corridor.row(s:number, x:number, z:number, yaw:number, k:number, left:number, right:number): Row
	if k > 0 then left = math.min(left, Config.Spline.Terrain.InsideShare / k)
	elseif k < 0 then right = math.min(right, -Config.Spline.Terrain.InsideShare / k) end
	return {s=s,x=x,z=z,yaw=yaw,k=k,rx=math.cos(yaw),rz=-math.sin(yaw),left=left,right=right}
end

local function resized(frame:Row,left:number,right:number):Row
	if frame.k>0 then left=math.min(left,Config.Spline.Terrain.InsideShare/frame.k)
	elseif frame.k<0 then right=math.min(right,-Config.Spline.Terrain.InsideShare/frame.k) end
	return {s=frame.s,x=frame.x,z=frame.z,yaw=frame.yaw,k=frame.k,rx=frame.rx,rz=frame.rz,left=left,right=right}
end

function Corridor.cell(a:Row, b:Row, boundsOnly:boolean?): Cell?
	local arx, arz, brx, brz = a.rx,a.rz,b.rx,b.rz
	local p = {a.x-a.left*arx,a.z-a.left*arz, a.x+a.right*arx,a.z+a.right*arz,
		b.x+b.right*brx,b.z+b.right*brz, b.x-b.left*brx,b.z-b.left*brz}
	local sign = 0
	for i=1,7,2 do
		local j, k = (i+1)%8+1, (i+3)%8+1
		local cross = (p[j]-p[i])*(p[k+1]-p[j+1])-(p[j+1]-p[i+1])*(p[k]-p[j])
		if math.abs(cross)>1e-7 then
			local here = if cross>0 then 1 else -1
			if sign~=0 and here~=sign and not boundsOnly then return nil end
			sign=here
		end
	end
	if sign==0 and not boundsOnly then return nil end
	local x,z=(a.x+b.x)*.5,(a.z+b.z)*.5
	local minX,maxX,minZ,maxZ,r2=math.huge,-math.huge,math.huge,-math.huge,0
	for i=1,7,2 do
		minX,maxX=math.min(minX,p[i]),math.max(maxX,p[i])
		minZ,maxZ=math.min(minZ,p[i+1]),math.max(maxZ,p[i+1])
		r2=math.max(r2,(p[i]-x)^2+(p[i+1]-z)^2)
	end
	return {s0=a.s,s1=b.s,x=x,z=z,radius=math.sqrt(r2),minX=minX,maxX=maxX,minZ=minZ,maxZ=maxZ,p=p}
end

function Corridor.overlap(a:Cell, b:Cell, gap:number): boolean
	if a.infield or b.infield then gap=0 end
	if a.maxX+gap<=b.minX or b.maxX+gap<=a.minX or a.maxZ+gap<=b.minZ or b.maxZ+gap<=a.minZ then return false end
	for _, polygon in {a.p,b.p} do
		for i=1,7,2 do
			local j=(i+1)%8+1
			-- Anchor each projection to this edge. Identical shared bank edges
			-- then have zero thickness even far from the world origin.
			local ox,oz=polygon[i],polygon[i+1]
			local nx,nz=polygon[j+1]-polygon[i+1],polygon[i]-polygon[j]
			local length=math.sqrt(nx*nx+nz*nz)
			if length>1e-7 then
				local amin,amax,bmin,bmax=math.huge,-math.huge,math.huge,-math.huge
				for k=1,7,2 do
					local av=(a.p[k]-ox)*nx+(a.p[k+1]-oz)*nz
					local bv=(b.p[k]-ox)*nx+(b.p[k+1]-oz)*nz
					amin,amax=math.min(amin,av),math.max(amax,av)
					bmin,bmax=math.min(bmin,bv),math.max(bmax,bv)
				end
				if amax+gap*length<=bmin or bmax+gap*length<=amin then return false end
			end
		end
	end
	return true
end

local function key(x:number,z:number):number
	return (x+1048576)*2097152+(z+1048576)
end

function Corridor.new():Index
	return setmetatable({buckets={},roads={},reach=0,count=0,minS=math.huge,maxS=-math.huge,infields=0},Index)
end

-- A decreasing smoothstep track can sit slightly above its linear taper between
-- knots. Reserve that complete envelope, including one check-grid rounding step.
function Corridor.reserve(width:number,distance:number):number
	local C=Config.Spline.Biomes
	local easing=C.CorridorRate*(C.CorridorKnot+Config.Spline.CheckStep)*0.1
	return math.max(Config.Spline.Terrain.RunoffMax,width-C.CorridorRate*distance)+easing
end

function Index.add(self:Index, cell:Cell)
	local size=Config.Spline.HashCell
	local at=key(math.floor(cell.x/size),math.floor(cell.z/size))
	local bucket=self.buckets[at]
	if not bucket then bucket={};self.buckets[at]=bucket end
	table.insert(bucket,cell)
	self.reach=math.max(self.reach,cell.radius)
	self.count+=1
	if cell.infield then self.infields+=1 end
	if cell.road then
		local arc=math.floor(cell.s0/size);local roadBucket=self.roads[arc]
		if not roadBucket then roadBucket={};self.roads[arc]=roadBucket end
		table.insert(roadBucket,cell)
	end
	local s=(cell.s0+cell.s1)*.5
	self.minS,self.maxS=math.min(self.minS,s),math.max(self.maxS,s)
end

-- Only actual accepted ground is tagged `road`; provisional envelopes and
-- field reservations cannot acquire this provenance. Its cells are <=CheckStep.
function Index.roadCells(self:Index,first:number,last:number):{Cell}
	local out={};local size=Config.Spline.HashCell
	for arc=math.floor((first-Config.Spline.CheckStep)/size),math.floor(last/size) do
		for _,cell in self.roads[arc] or {} do
			if cell.s1>first and cell.s0<last then table.insert(out,cell) end
		end
	end
	return out
end

function Index.clear(self:Index, cell:Cell, separation:number, gap:number):(boolean,Cell?,number,number)
	local s=(cell.s0+cell.s1)*.5
	if self.count==0 or (not cell.infield and self.infields==0 and math.abs(s-self.minS)<=separation and math.abs(s-self.maxS)<=separation) then return true,nil,0,0 end
	local size=Config.Spline.HashCell
	local reach=self.reach+gap
	local visited,tests=0,0
	for x=math.floor((cell.minX-reach)/size),math.floor((cell.maxX+reach)/size) do
		for z=math.floor((cell.minZ-reach)/size),math.floor((cell.maxZ+reach)/size) do
			local bucket=self.buckets[key(x,z)]
			if bucket then
				for _,old in bucket do
					visited+=1
					if cell.infield or old.infield or math.abs(s-(old.s0+old.s1)*.5)>separation then
						tests+=1
						if Corridor.overlap(cell,old,gap) then return false,old,visited,tests end
					end
				end
			end
		end
	end
	return true,nil,visited,tests
end

-- Candidate envelopes are fixed while fitting a width. Gather their possible
-- neighbours once, then reuse that short list for every bisection trial.
function Index.near(self:Index, cell:Cell, separation:number, gap:number):{Cell}
	local out={}
	local s=(cell.s0+cell.s1)*.5
	if self.count==0 or (not cell.infield and self.infields==0 and math.abs(s-self.minS)<=separation and math.abs(s-self.maxS)<=separation) then return out end
	local size=Config.Spline.HashCell
	local reach=self.reach+gap
	for x=math.floor((cell.minX-reach)/size),math.floor((cell.maxX+reach)/size) do
		for z=math.floor((cell.minZ-reach)/size),math.floor((cell.maxZ+reach)/size) do
			local bucket=self.buckets[key(x,z)]
			if bucket then
				for _,old in bucket do
					if (cell.infield or old.infield or math.abs(s-(old.s0+old.s1)*.5)>separation)
						and cell.maxX+gap>old.minX and old.maxX+gap>cell.minX
						and cell.maxZ+gap>old.minZ and old.maxZ+gap>cell.minZ then table.insert(out,old) end
				end
			end
		end
	end
	return out
end

-- Fit one section and a continuation reserved from its actual outgoing widths.
-- Both ends of every 8-stud cell are tested, using the actual eased
-- width track, not just the chosen knots. A uniform reduction preserves its taper;
-- each side can then reopen independently wherever the other side was the limit.
-- `tick`, when given, is called between bounded pieces of the search: a private
-- generator may suspend there. The fitted widths do not depend on it.
function Corridor.fit(frames:{Row}, sectionEnd:number, incoming:{number}, desired:(number,number)->number,
	old:Index, separation:number, tick:(()->())?):({number}?,{number}?,{number}?)
	local checkpoint:()->()=tick or function() end
	local C=Config.Spline.Biomes
	local half=Config.Road.Width*.5
	local gap=Config.Spline.ClearanceGap+C.CorridorMargin
	if frames[#frames].s<sectionEnd+Config.Spline.EscapeLength-1e-6 then return nil,nil,nil end
	local start=frames[1].s
	local ends={start}
	local baseline={{incoming[1]},{incoming[2]}}
	local wanted={{incoming[1]},{incoming[2]}}
	local last=start
	for _,frame in frames do
		local at=frame.s
		if at>start and at<=sectionEnd+1e-6 and (at-last>=C.CorridorKnot-1e-6 or at>=sectionEnd-1e-6) then
			table.insert(ends,at)
			for sideIndex,side in {-1,1} do
				local prior=wanted[sideIndex][#wanted[sideIndex]]
				local change=C.CorridorRate*(at-last)
				table.insert(baseline[sideIndex],math.max(Config.Spline.Terrain.RunoffMin,incoming[sideIndex]-C.CorridorRate*(at-start)))
				table.insert(wanted[sideIndex],math.clamp(desired(at,side),prior-change,prior+change))
			end
			last=at
		end
	end
	if math.abs(ends[#ends]-sectionEnd)>1e-6 then return nil,nil,nil end
	local function width(s:number,sideIndex:number,scale:number):number
		local lo,hi=1,#ends
		while hi-lo>1 do
			local mid=(lo+hi)//2
			if ends[mid]<=s then lo=mid else hi=mid end
		end
		local u=math.clamp((s-ends[lo])/math.max(ends[hi]-ends[lo],1e-9),0,1)
		u=u*u*(3-2*u)
		local base=baseline[sideIndex]
		local want=wanted[sideIndex]
		local a=base[lo]+(want[lo]-base[lo])*scale
		local b=base[hi]+(want[hi]-base[hi])*scale
		return a+(b-a)*u
	end
	-- Precompute the two envelopes at every sample. Interpolating their reserved
	-- escape widths is conservative: max(40, width-rate*u) is a convex function.
	local params={}
	local seam=0
	for i,frame in frames do
		local at=math.min(frame.s,sectionEnd)
		local l0,l1=width(at,1,0),width(at,1,1)
		local r0,r1=width(at,2,0),width(at,2,1)
		if frame.s>sectionEnd then
			local distance=frame.s-sectionEnd
			l0,l1=Corridor.reserve(l0,distance),Corridor.reserve(l1,distance)
			r0,r1=Corridor.reserve(r0,distance),Corridor.reserve(r1,distance)
		elseif math.abs(frame.s-sectionEnd)<1e-6 then seam=i end
		params[i]={l0,l1,r0,r1}
	end
	if seam==0 then return nil,nil,nil end
	local function rowAt(i:number,left:number,right:number,reserved:boolean?):Row
		local p=params[i]
		local l0,l1,r0,r1=p[1],p[2],p[3],p[4]
		if reserved then
			l0,l1,r0,r1=Corridor.reserve(l0,0),Corridor.reserve(l1,0),Corridor.reserve(r0,0),Corridor.reserve(r1,0)
		end
		return resized(frames[i],half+l0+(l1-l0)*left,half+r0+(r1-r0)*right)
	end
	local envelopes={}
	local function envelopeAt(i:number,reserved:boolean?):Row
		local p=params[i]
		local left,right=math.max(p[1],p[2]),math.max(p[3],p[4])
		if reserved then left,right=Corridor.reserve(left,0),Corridor.reserve(right,0) end
		return resized(frames[i],half+left,half+right)
	end
	for i=1,#frames do envelopes[i]=envelopeAt(i) end
	local seamEnvelope=envelopeAt(seam,true)
	local guards,pairsGuard={},{}
	local same=Corridor.new()
	local ids:{[Cell]:number}={}
	for i=2,#frames do
		local a=if i-1==seam then seamEnvelope else envelopes[i-1]
		local envelope=Corridor.cell(a,envelopes[i],true) :: Cell
		if i%16==0 then checkpoint() end
		guards[i-1]=old:near(envelope,separation,gap)
		local peers={}
		for _,cell in same:near(envelope,separation,gap) do table.insert(peers,ids[cell]) end
		pairsGuard[i-1]=peers
		ids[envelope]=i-1
		same:add(envelope)
	end
	local function clear(left:number,right:number):boolean
		checkpoint()
		local rows={}
		for i=1,#frames do rows[i]=rowAt(i,left,right) end
		local reservedSeam=rowAt(seam,left,right,true)
		local made={}
		for i=2,#frames do
			local a=if i-1==seam then reservedSeam else rows[i-1]
			local cell=Corridor.cell(a,rows[i])
			if not cell then return false end
			for _,other in guards[i-1] do if Corridor.overlap(cell,other,gap) then return false end end
			for _,j in pairsGuard[i-1] do if Corridor.overlap(cell,made[j],gap) then return false end end
			made[i-1]=cell
		end
		return true
	end
	local left,right=1,1
	if not clear(1,1) then
		if not clear(0,0) then return nil,nil,nil end
		local lo,hi=0,1
		for _=1,C.CorridorFitIterations do local mid=(lo+hi)*.5;if clear(mid,mid) then lo=mid else hi=mid end end
		left,right=lo,lo
		lo,hi=left,1
		for _=1,C.CorridorSideIterations do local mid=(lo+hi)*.5;if clear(mid,right) then lo=mid else hi=mid end end
		left=lo
		lo,hi=right,1
		for _=1,C.CorridorSideIterations do local mid=(lo+hi)*.5;if clear(left,mid) then lo=mid else hi=mid end end
		right=lo
	end
	local tracks={{},{}}
	for i=2,#ends do
		for sideIndex,scale in {left,right} do
			table.insert(tracks[sideIndex],ends[i]-start)
			table.insert(tracks[sideIndex],baseline[sideIndex][i]+(wanted[sideIndex][i]-baseline[sideIndex][i])*scale)
		end
	end
	return tracks[1],tracks[2],{left,right}
end

return Corridor
