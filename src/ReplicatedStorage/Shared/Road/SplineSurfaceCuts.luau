--!strict
-- Near-ground tessellation: fixed cross-section topology, refined along the
-- curve against the whole supported bank rather than only the asphalt edges.
local Config=require(game.ReplicatedStorage.Shared.Config)
local Spline=require(script.Parent.Spline)
local Boundary=require(script.Parent.SplineBoundary)
local Cuts={}

function Cuts.offsets(spline:Spline.Spline,s:number,across:number,grass:number):{number}
	local half=Config.Road.Width*.5
	local wl,wr=spline:runoffAt(s,-1),spline:runoffAt(s,1)
	local ll,lr=spline:lipWidthAt(s,-1),spline:lipWidthAt(s,1)
	local ds={}
	for j=0,grass-1 do table.insert(ds,-half-wl+(wl-ll)*j/grass) end
	table.insert(ds,-half-ll)
	for j=0,across do table.insert(ds,-half+2*half*j/across) end
	table.insert(ds,half+lr)
	for j=1,grass do table.insert(ds,half+lr+(wr-lr)*j/grass) end
	if spline:hasBiomeGround() then ds[1]-=Config.Spline.Hill.DrawEdgePad;ds[#ds]+=Config.Spline.Hill.DrawEdgePad end
	return ds
end

function Cuts.sections(spline:Spline.Spline,s0:number,s1:number,tolerance:number,maxStep:number,minStep:number,across:number,grass:number,yieldFn:(()->())?):{number}
	local out={s0}
	local hardMin=math.min(minStep,1/32) -- steep bank-width changes must still satisfy the row test
	local rows:{[number]:{Vector3}}={}
	local function sample(at:number):{Vector3}
		local row=rows[at]
		if not row then row=spline:terrainRow(at,Cuts.offsets(spline,at,across,grass),false);rows[at]=row end
		return row
	end
	local s=s0
	while s<s1-1e-6 do
		local b=math.min(s1,s+maxStep)
		local left=sample(s)
		while b-s>hardMin+1e-6 do
			local right=sample(b)
			local valid=true
			for _,t in {.25,.5,.75} do
				local m=s+(b-s)*t
				local middle=sample(m)
				for j=1,#middle do
					local a=left[j]
					local c=right[j]
					local p=middle[j]
					if (p-a:Lerp(c,t)).Magnitude>tolerance then valid=false;break end
				end
				if not valid then break end
			end
			if valid then break end
			b=math.max(s+hardMin,(s+b)*.5)
		end
		s=math.min(b,s1)
		table.insert(out,s)
		if yieldFn then yieldFn() end
	end
	for _,at in Boundary.points(spline,s0,s1) do table.insert(out,at) end
	table.sort(out)
	local unique={}
	for _,at in out do if #unique==0 or at-unique[#unique]>1e-6 then table.insert(unique,at) end end
	return unique
end

return Cuts
