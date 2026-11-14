--!strict
-- Visible finite-ground protection, shared by mesh and parts chunks. Existing
-- `kr` rails stay on the asphalt; these stand at the outer grass edge instead.
local Config=require(game.ReplicatedStorage.Shared.Config)
local Spline=require(script.Parent.Spline)
local Builder=require(script.Parent.Builder)
local Boundary={}

function Boundary.runs(spline:Spline.Spline,s0:number,s1:number):{number}
	local out={}
	local a=s0
	local active=spline:outerRailAt(a)
	if active then table.insert(out,a) end
	while a<s1-1e-6 do
		local b=math.min(s1,(math.floor(a/2)+1)*2)
		local nextActive=spline:outerRailAt(b)
		if active~=nextActive then
			local lo,hi=a,b
			for _=1,18 do
				local m=(lo+hi)*.5
				if spline:outerRailAt(m)==active then lo=m else hi=m end
			end
			table.insert(out,(lo+hi)*.5)
		end
		a,active=b,nextActive
	end
	if active then table.insert(out,s1) end
	return out
end

function Boundary.build(spline:Spline.Spline,s0:number,s1:number,parent:Instance,yieldFn:(()->())?,roadRails:boolean?):number
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
		if spline:hasBiomeGround() then
			local a=s0
			while a<s1-.001 do
				local b=math.min(s1,a+4)
				if spline:edgeAt((a+b)*.5,side)==Spline.ROCK and not spline:outerRailAt((a+b)*.5) then
					local function row(s:number)
						local edge=half+spline:runoffAt(s,side)
						local p=Vector3.new(spline:terrainXYZ(s,side*edge))
						local yaw=spline:yawAt(s)
						local right=Vector3.new(math.cos(yaw)*side,0,-math.sin(yaw)*side)
						return {p,p+right*2+Vector3.yAxis*4,p+right*3}
					end
					local pa,pb=row(a),row(b)
					for j=1,2 do
						local made={}
						Builder.triangleSlab(`OuterRock_{side}_{a}_{j}a`,pa[j],pa[j+1],pb[j+1],.1,T.RockColour,Enum.Material.Slate,parent,made :: any)
						Builder.triangleSlab(`OuterRock_{side}_{a}_{j}b`,pa[j],pb[j+1],pb[j],.1,T.RockColour,Enum.Material.Slate,parent,made :: any)
						for _,p in made do p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;count+=1 end
						if yieldFn then yieldFn() end
					end
				end
				a=b
			end
		end
		for _,outer in {true,false} do
			if not outer and not roadRails then continue end
			local runs=if outer then Boundary.runs(spline,s0,s1) else spline:kRailsIn(s0,s1,side)
			local function point(s:number,back:number,height:number):Vector3
				local edge=half+(if outer then spline:runoffAt(s,side) else 0)
				local x,_,z=spline:terrainXYZ(s,side*(edge+back))
				return Vector3.new(x,spline:terrainY(s,side*edge)+height,z)
			end
			local tag=if outer then "OuterRail" else "KRail"
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
