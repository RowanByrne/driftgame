--!strict
-- Natural rock feet and existing asphalt-edge rails for terrain chunks.
-- No guardrail is added at a field boundary (T-209 user correction).
local Config=require(game.ReplicatedStorage.Shared.Config)
local Spline=require(script.Parent.Spline)
local Builder=require(script.Parent.Builder)
local Boundary={}

function Boundary.closingSpec(panel:Spline.ClosingPanel):(CFrame,Vector3)
	local a,b=panel.a,panel.b
	local length=math.sqrt((b[1]-a[1])^2+(b[3]-a[3])^2)
	local centre=Vector3.new((a[1]+b[1])*.5,(panel.bottom+panel.top)*.5,(a[3]+b[3])*.5)-panel.normal*(panel.depth*.5)
	return CFrame.fromMatrix(centre,Vector3.new(-panel.normal.Z,0,panel.normal.X),Vector3.yAxis,-panel.normal),
		Vector3.new(math.max(.05,length),panel.top-panel.bottom,panel.depth)
end

local function panelFrame(panel:Spline.ClosingPanel,x:number,z:number):(number,number,number,Vector3)
	local a,b=panel.a,panel.b
	local dx,dz=b[1]-a[1],b[3]-a[3]
	local rawLength=math.sqrt(dx*dx+dz*dz)
	if rawLength<1e-10 then return 0,0,0,Vector3.xAxis end
	local length=math.max(.05,rawLength)
	local tangent=Vector3.new(dx/rawLength,0,dz/rawLength)
	local ex,ez=x-a[1],z-a[3]
	return ex*tangent.X+ez*tangent.Z+(length-rawLength)*.5,ex*panel.normal.X+ez*panel.normal.Z,length,tangent
end

-- Continuous finite slab entry, including end caps. Testing only whether both
-- endpoints lie beside a front plane misses diagonal entries around an end.
function Boundary.closingSweep(panel:Spline.ClosingPanel,x0:number,z0:number,x1:number,z1:number):(number?,Vector3?)
	local u0,v0,length,tangent=panelFrame(panel,x0,z0)
	if length<1e-7 then return nil,nil end
	local u1,v1=panelFrame(panel,x1,z1)
	local inside=u0>1e-8 and u0<length-1e-8 and v0> -panel.depth+1e-8 and v0< -1e-8
	local function contains(u:number,v:number):boolean return u>=0 and u<=length and v>= -panel.depth and v<=0 end
	if inside then
		if not contains(u1,v1) then return nil,nil end
		local distances={u0,length-u0,v0+panel.depth,-v0}
		local normals={-tangent,tangent,-panel.normal,panel.normal}
		local best=1;for i=2,4 do if distances[i]<distances[best] then best=i end end
		return 0,normals[best]
	end
	local enter,leave,normal=0,1,nil :: Vector3?
	for _,axis in {{u0,u1,0,length,tangent},{v0,v1,-panel.depth,0,panel.normal}} do
		local from,to,low,high,n=axis[1] :: number,axis[2] :: number,axis[3] :: number,axis[4] :: number,axis[5] :: Vector3
		local delta=to-from
		if math.abs(delta)<1e-10 then if from<low or from>high then return nil,nil end;continue end
		local a,b=(low-from)/delta,(high-from)/delta
		local outward=-n
		if a>b then a,b=b,a;outward=n end
		if a>=enter then enter=a;normal=outward end
		leave=math.min(leave,b)
		if enter>leave then return nil,nil end
	end
	if not normal or enter<0 or enter>1 then return nil,nil end
	return enter,normal
end

function Boundary.closingPush(panel:Spline.ClosingPanel,x:number,z:number,margin:number):(number,Vector3?)
	local u,v,length,tangent=panelFrame(panel,x,z)
	if length<1e-7 or u< -margin or u>length+margin or v< -panel.depth-margin or v>margin then return 0,nil end
	local distances={u+margin,length+margin-u,v+panel.depth+margin,margin-v}
	local normals={-tangent,tangent,-panel.normal,panel.normal}
	local best=1;for i=2,4 do if distances[i]<distances[best] then best=i end end
	return distances[best],normals[best]
end

local function range(values:{number},value:number):number
 local lo,hi=1,#values
 while lo<hi do local m=(lo+hi)//2;if values[m]<value then lo=m+1 else hi=m end end
 return lo
end

-- Split near-ground geometry at the existing rock/cliff span endpoints.
function Boundary.points(spline:Spline.Spline,s0:number,s1:number):{number}
 local points={s0,s1}
 for _,edge in {spline.edgeL,spline.edgeR} do
  for i=range(edge.e,s0),#edge.e do
   local s=edge.e[i]
   if s>=s1 then break end
   if s>s0 then table.insert(points,s) end
  end
 end
 -- Physical opening weights can change at an interior frozen field row.
 -- Splitting there keeps a local rock-foot dip visible instead of spanning it.
 local index=spline.infields
 if index then
  local seen={}
  for _,side in {-1,1} do for cell=math.floor(s0/index.cell),math.floor(s1/index.cell) do
   for _,opening in index.openings[`{side}:{cell}`] or {} do
    if seen[opening] or opening.last<s0 or opening.first>s1 then continue end
    seen[opening]=true
    for _,row in opening.patch.rows do
     local s=if opening.bank=="A" then row.sa else row.sb
     if s>s0 and s<s1 then table.insert(points,s) end
    end
    local rows=opening.patch.rows
    if not rows[1].floor or not rows[#rows].floor then
     local fade=math.min(64,(opening.last-opening.first)*.25)
     for _,s in {opening.first+fade,opening.last-fade} do if s>s0 and s<s1 then table.insert(points,s) end end
    end
   end
  end end
 end
 table.sort(points)
 local unique={}
 for _,s in points do if #unique==0 or s-unique[#unique]>1e-6 then table.insert(unique,s) end end
 return unique
end

function Boundary.toeRow(spline:Spline.Spline,s:number,side:number):{Vector3}
 local edge=Config.Road.Width*.5+spline:runoffAt(s,side)
 local p=Vector3.new(spline:terrainXYZ(s,side*edge))
 local yaw=spline:yawAt(s)
 local right=Vector3.new(math.cos(yaw)*side,0,-math.sin(yaw)*side)
 return {p,p+right*2+Vector3.yAxis*(4*(1-spline:infieldOpening(s,side))),p+right*3}
end

function Boundary.build(spline:Spline.Spline,s0:number,s1:number,parent:Instance,yieldFn:(()->())?,roadRails:boolean?,toeParts:boolean?):number
	local T=Config.Spline.Terrain
	local half=Config.Road.Width*.5
	local count=0
	local function plain(name:string,size:Vector3,cf:CFrame,colour:Color3)
		local p=Instance.new("Part")
		p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false
		p.Material=Enum.Material.Metal;p.Color=colour;p.Size=size;p.CFrame=cf;p.Parent=parent
		count+=1
		if yieldFn then yieldFn() end
	end
	for _,side in {-1,1} do
		-- The uphill boundary keeps a low rock foot even when the distant hill
		-- is fitted nearly flat against another leg. It marks the same four-stud
		-- solid limit and never depends on a later hillside rebuild.
  if spline:hasBiomeGround() and toeParts~=false then
   local cuts=Boundary.points(spline,s0,s1)
   for s=math.ceil(s0/4)*4,s1-1e-6,4 do if s>s0 then table.insert(cuts,s) end end
   table.sort(cuts)
   for i=1,#cuts-1 do
    local a,b=cuts[i],cuts[i+1]
    if b-a<1e-6 then continue end
    if spline:edgeAt((a+b)*.5,side)==Spline.ROCK
     and (spline:infieldOpening(a,side)<1-1e-8 or spline:infieldOpening(b,side)<1-1e-8) then
     local pa,pb=Boundary.toeRow(spline,a,side),Boundary.toeRow(spline,b,side)
     for j=1,2 do
      local made={}
      Builder.triangleSlab(`OuterRock_{side}_{a}_{j}a`,pa[j],pa[j+1],pb[j+1],.1,T.RockColour,Enum.Material.Slate,parent,made :: any)
      Builder.triangleSlab(`OuterRock_{side}_{a}_{j}b`,pa[j],pb[j+1],pb[j],.1,T.RockColour,Enum.Material.Slate,parent,made :: any)
      for _,p in made do p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;count+=1 end
      if yieldFn then yieldFn() end
     end
    end
   end
  end
		if roadRails then
			local runs=spline:kRailsIn(s0,s1,side)
			local function point(s:number,back:number,height:number):Vector3
				local edge=half
				local x,_,z=spline:terrainXYZ(s,side*(edge+back))
				return Vector3.new(x,spline:terrainY(s,side*edge)+height,z)
			end
			local tag="KRail"
			for r=1,#runs,2 do
				local first,last=math.max(s0,runs[r]),math.min(s1,runs[r+1])
				local a=first
				while a<last-.001 do
					local b=math.min(last,a+4)
					for j,height in {T.KRailHeight-.2,T.KRailHeight-T.KRailBeam+.2} do
						local pa,pb=point(a,T.KRailThickness*.5,height),point(b,T.KRailThickness*.5,height)
						local delta=pb-pa
						plain(`{tag}_{side}_{a}_{j}`,Vector3.new(T.KRailThickness,.4,delta.Magnitude+.08),CFrame.lookAt((pa+pb)*.5,pb),T.KRailColour)
					end
					a=b
				end
				for s=math.ceil(first/T.KRailPostEvery)*T.KRailPostEvery,last-.001,T.KRailPostEvery do
					plain(`{tag}Post_{side}_{s}`,Vector3.new(.3,T.KRailHeight,.3),CFrame.new(point(s,T.KRailThickness*.6,T.KRailHeight*.5)),T.KRailColour)
				end
			end
		end
	end
	return count
end

return Boundary
