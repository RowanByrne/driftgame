--!strict
--!native
-- Coarse hill chords must not stand through the supported bank between their
-- endpoints. Refine only unsafe spans, before caps/faces are emitted.
local Config=require(game.ReplicatedStorage.Shared.Config)
local Hill=require(script.Parent.SplineHill)
local Spline=require(script.Parent.Spline)
local Cuts={}

-- Check the parameterized patch before Mesh flips its drawn normal upwards.
-- Edge fans run the opposite way from rings and the central fan.
function Cuts.folded(a:Vector3,b:Vector3,c:Vector3,side:number,edgeFan:boolean?):boolean
	local determinant=(b.X-a.X)*(c.Z-a.Z)-(b.Z-a.Z)*(c.X-a.X)
	return determinant*side*(if edgeFan then 1 else -1)<-1e-4
end

local function bounds(points:{Vector3}):(number,number,number,number)
	local x0,x1,z0,z1=math.huge,-math.huge,math.huge,-math.huge
	for _,p in points do x0=math.min(x0,p.X);x1=math.max(x1,p.X);z0=math.min(z0,p.Z);z1=math.max(z1,p.Z) end
	return x0,x1,z0,z1
end

-- Strict overlap: a shared edge or vertex is an allowed join, not an intrusion.
function Cuts.overlap(a:Vector3,b:Vector3,c:Vector3,quad:{Vector3}):boolean
	if #quad==4 then
		return Cuts.overlap(a,b,c,{quad[1],quad[2],quad[3]}) or Cuts.overlap(a,b,c,{quad[1],quad[3],quad[4]})
	end
	local tri={a,b,c}
	local ox,oz=quad[1].X,quad[1].Z
	for _,polygon in {tri,quad} do
		for i,p in polygon do
			local q=polygon[i%#polygon+1]
			local nx,nz=-(q.Z-p.Z),q.X-p.X
			local scale=math.sqrt(nx*nx+nz*nz)
			if scale<1e-10 then continue end
			local alo,ahi,blo,bhi=math.huge,-math.huge,math.huge,-math.huge
			for _,v in tri do local d=(v.X-ox)*nx+(v.Z-oz)*nz;alo=math.min(alo,d);ahi=math.max(ahi,d) end
			for _,v in quad do local d=(v.X-ox)*nx+(v.Z-oz)*nz;blo=math.min(blo,d);bhi=math.max(bhi,d) end
			if math.min(ahi,bhi)-math.max(alo,blo)<=1e-6*scale then return false end
		end
	end
	return true
end

-- Clip in XZ, carrying the hill-plane height. The difference between two
-- triangle planes is affine, so overlap vertices give its exact maximum.
local function above(a:Vector3,b:Vector3,c:Vector3,pa:Vector3,pb:Vector3,pc:Vector3):boolean
	local bx,bz,cx,cz=pb.X-pa.X,pb.Z-pa.Z,pc.X-pa.X,pc.Z-pa.Z
	local det=bx*cz-bz*cx
	if math.abs(det)<1e-10 then return false end
	local orientation=if det>0 then 1 else -1
	local polygon={{x=a.X-pa.X,z=a.Z-pa.Z,y=a.Y-pa.Y},{x=b.X-pa.X,z=b.Z-pa.Z,y=b.Y-pa.Y},{x=c.X-pa.X,z=c.Z-pa.Z,y=c.Y-pa.Y}}
	local ground={{x=0,z=0},{x=bx,z=bz},{x=cx,z=cz}}
	for i,p in ground do
		local q=ground[i%3+1]
		local function distance(v:any):number return orientation*((q.x-p.x)*(v.z-p.z)-(q.z-p.z)*(v.x-p.x)) end
		local clipped={}
		local previous=polygon[#polygon]
		if not previous then return false end
		local dp=distance(previous)
		for _,current in polygon do
			local dc=distance(current)
			if (dp>=0)~=(dc>=0) then
				local t=dp/(dp-dc)
				table.insert(clipped,{x=previous.x+(current.x-previous.x)*t,z=previous.z+(current.z-previous.z)*t,y=previous.y+(current.y-previous.y)*t})
			end
			if dc>=0 then table.insert(clipped,current) end
			previous,dp=current,dc
		end
		polygon=clipped
	end
	if #polygon<3 then return false end
	local area=0
	for i,p in polygon do local q=polygon[i%#polygon+1];area+=p.x*q.z-p.z*q.x end
	if math.abs(area)<1e-8 then return false end
	for _,p in polygon do
		local u=(p.x*cz-p.z*cx)/det
		local v=(bx*p.z-bz*p.x)/det
		local y=u*(pb.Y-pa.Y)+v*(pc.Y-pa.Y)
		if p.y>y+1e-4 then return true end
	end
	return false
end

function Cuts.refine(spline:any,hill:any,positions:{number},rows:{{Vector3}},initial:{number},rays:any,caps:any,profile:any,tick:(()->())?):({number},any)
	local H=Config.Spline.Hill
	local cells={}
	for i=1,#rows-1 do
		local a,b=rows[i],rows[i+1]
		local quad={a[1],a[#a],b[#b],b[1]}
		local x0,x1,z0,z1=bounds(quad)
		table.insert(cells,{a=a,b=b,quad=quad,x0=x0,x1=x1,z0=z0,z1=z1})
	end
	local stats={added=0,tests=0,exact=0,terminal=0,terminalFolds=0}
	local rings:any={[-1]={},[1]={}}
	local function rayAt(k:number,side:number)
		if not rays[side][k] then
			rays[side][k]=Hill.ray(hill,positions[k],side)
			caps[side][k]=Hill.cap(rays[side][k])
		end
	end
	local function solve(k:number,side:number)
		rayAt(k,side)
		if rings[side][k] then return rings[side][k] end
		local ray=rays[side][k]
		Hill.finish(hill,ray)
		local start=Hill.faceEnd(ray)
		local span=math.max(0,ray.clip-start)
		local points={}
		for _,share in H.Rings do table.insert(points,Hill.at(ray,start+span*share)) end
		table.insert(points,Hill.at(ray,Hill.skirtEnd(spline,ray)))
		rings[side][k]=points
		return points
	end
	local function occludes(a:Vector3,b:Vector3,c:Vector3):boolean
		local x0,x1,z0,z1=bounds({a,b,c})
		for index,cell in cells do
			if tick and index%32==0 then tick() end
			if x1<=cell.x0 or cell.x1<=x0 or z1<=cell.z0 or cell.z1<=z0 then continue end
			if not Cuts.overlap(a,b,c,cell.quad) then continue end
			for j=1,#cell.a-1 do
				stats.exact+=2
				if above(a,b,c,cell.a[j],cell.a[j+1],cell.b[j]) or above(a,b,c,cell.a[j+1],cell.b[j+1],cell.b[j]) then return true end
			end
			if tick then tick() end
		end
		return false
	end
	local function unsafe(ka:number,kb:number):(boolean,boolean?)
		stats.tests+=1
		for _,side in {-1,1} do
			local kind=spline:edgeAt((positions[ka]+positions[ka+1])*.5,side)
			if kind~=Spline.ROCK and kind~=Spline.CLIFF then continue end
			local A,B=solve(ka,side),solve(kb,side)
			local faces={}
			local ca,cb=caps[side][ka],caps[side][kb]
			local function foot(k:number):Vector3
				if faces[k] then return faces[k] end
				local t=(positions[k]-positions[ka])/math.max(positions[kb]-positions[ka],1e-9)
				local cap=if ca==math.huge or cb==math.huge then (if t<.5 then ca else cb) else ca+(cb-ca)*t
				local p=profile(spline,positions[k],side,kind,cap)[5]
				faces[k]=p;return p
			end
			local middle=(ka+kb+1)//2
			for k=ka,kb-1 do
				local a,b,c=foot(k),foot(k+1),if k<middle then A[1] else B[1]
				if Cuts.folded(a,b,c,side,true) then return true,true end
				if occludes(a,b,c) then return true end
			end
			if Cuts.folded(foot(middle),A[1],B[1],side) then return true,true end
			if occludes(foot(middle),A[1],B[1]) then return true end
			for j=1,#A-1 do
				if Cuts.folded(A[j],A[j+1],B[j],side) or Cuts.folded(A[j+1],B[j+1],B[j],side) then return true,true end
				if occludes(A[j],A[j+1],B[j]) or occludes(A[j+1],B[j+1],B[j]) then return true end
			end
		end
		return false
	end
	local result={initial[1]}
	local function visit(a:number,b:number)
		local bad,folded=unsafe(a,b)
		if tick then tick() end
		if bad and b>a+1 then
			local mid=(a+b)//2;stats.added+=1
			-- Both sides interpolate caps at every accepted cut, including a side
			-- without a hill or one skipped by an early unsafe result.
			rayAt(mid,-1);rayAt(mid,1)
			visit(a,mid);visit(mid,b)
		else
			if bad then stats.terminal+=1;if folded then stats.terminalFolds+=1 end end
			table.insert(result,b)
		end
	end
	for i=1,#initial-1 do visit(initial[i],initial[i+1]) end
	return result,stats
end

return Cuts
