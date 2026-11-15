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
		local ya,yb=sp:yawAt(sa),sp:yawAt(sb)
		if math.cos(ya-yb)>C.HeadingDot then return nil end
		local sideA=if d<0 then -1 else 1
		local ax,az=sp:planAt(sa)
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
	local ctx=Hill.context(sp,a0,b1,Profile.draw,nil,true)
	local pending=Infield.new()
	for _,backward in chains do
		local rows={}
		for i=#backward,1,-1 do table.insert(rows,backward[i]) end
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
					if Corridor.overlap(cell,old,0) then clear=false;break end
				end
			end
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
