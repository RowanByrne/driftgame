--!strict
-- Natural rock feet and existing asphalt-edge rails for terrain chunks.
-- No guardrail is added at a field boundary (T-209 user correction).
local Config=require(game.ReplicatedStorage.Shared.Config)
local Spline=require(script.Parent.Spline)
local Builder=require(script.Parent.Builder)
local Boundary={}

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
 return {p,p+right*2+Vector3.yAxis*4,p+right*3}
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
    if spline:edgeAt((a+b)*.5,side)==Spline.ROCK then
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
