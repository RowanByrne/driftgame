--!strict
--!native
-- Biome preferences inside the existing road limits, and existing K-rails on
-- exposed asphalt edges. Pure policy: the caller owns every random draw.
local Config=require(game.ReplicatedStorage.Shared.Config)
local Spline=require(script.Parent.Spline)
local Biome=require(script.Parent.SplineBiome)
local Style={}

local function roadActive(records:{number}?):boolean
	return records~=nil and Config.Spline.Biomes.GroundEnabled and Config.Spline.Biomes.Road.Enabled
end
function Style.weight(records:{number}?,s:number,name:string):number
	local values=Config.Spline.Biomes.Road.Weights[name]
	return if roadActive(records) and values then Biome.mix(records,s,values,1) else 1
end
function Style.straightChance(records:{number}?,s:number):number
	return if roadActive(records) then Biome.mix(records,s,Config.Spline.Biomes.Road.StraightChance,Config.Spline.StraightChance) else Config.Spline.StraightChance
end
function Style.switchbackChance(records:{number}?,s:number):number
	return if roadActive(records) then Biome.mix(records,s,Config.Spline.Biomes.Road.SwitchbackChance,Config.Spline.SwitchbackChance) else Config.Spline.SwitchbackChance
end

-- Section-relative tracks, evaluated from the still-unappended incoming spline.
function Style.valueAt(knots:{number},initial:number,u:number,eased:boolean):number
	local at,value=0,initial
	for i=1,#knots,2 do
		if u<=knots[i] then
			local t=math.clamp((u-at)/math.max(knots[i]-at,1e-9),0,1)
			if eased then return value+(knots[i+1]-value)*t*t*(3-2*t) end
			return value+(knots[i+1]-value)*(u-at)/math.max(knots[i]-at,1e-9)
		end
		at,value=knots[i],knots[i+1]
	end
	return value
end
function Style.curvature(spline:Spline.Spline,sec:Spline.Section,u:number):number
	return Style.valueAt(sec.k,spline.curv.v[#spline.curv.v],u,false)
end
function Style.runoff(spline:Spline.Spline,sec:Spline.Section,side:number,u:number):number
	local widths=(if side<0 then sec.rl else sec.rr) :: {number}
	local width=Style.valueAt(widths,spline:runoffRaw(spline.length,side),u,true)
	local k=Style.curvature(spline,sec,u)
	if k~=0 and (k>0)==(side<0) then
		width=math.max(0,math.min(width,Config.Spline.Terrain.InsideShare/math.abs(k)-Config.Road.Width*.5))
	end
	return width
end

-- Width and curvature are monotone between their knots. Splitting at every
-- crossing of the reach threshold keeps a selected rail inside actual exposed
-- ground, even when a broad field begins halfway through one road section.
function Style.cliffIntervals(spline:Spline.Spline,sec:Spline.Section,side:number,reach:number):{{number}}
	local points={0,sec.len}
	local edges=(if side<0 then sec.el else sec.er) :: {number}
	local widths=(if side<0 then sec.rl else sec.rr) :: {number}
	local from,value=0,spline:runoffRaw(spline.length,side)
	for i=1,#widths,2 do
		local at,nextValue=widths[i],widths[i+1]
		table.insert(points,at)
		if (value-reach)*(nextValue-reach)<0 then
			local lo,hi=from,at
			for _=1,25 do
				local m=(lo+hi)*.5
				if (Style.valueAt(widths,spline:runoffRaw(spline.length,side),m,true)<reach)==(nextValue>value) then lo=m else hi=m end
			end
			table.insert(points,(lo+hi)*.5)
		end
		from,value=at,nextValue
	end
	local target=(if side<0 then 1 else -1)*Config.Spline.Terrain.InsideShare/(Config.Road.Width*.5+reach)
	from,value=0,spline.curv.v[#spline.curv.v]
	for i=1,#sec.k,2 do
		local at,nextValue=sec.k[i],sec.k[i+1]
		table.insert(points,at)
		if (value-target)*(nextValue-target)<0 then table.insert(points,from+(at-from)*(target-value)/(nextValue-value)) end
		from,value=at,nextValue
	end
	for i=1,#edges,2 do table.insert(points,edges[i]) end
	table.sort(points)
	local out={}
	local edgeIndex=1
	for i=1,#points-1 do
		local a,b=points[i],points[i+1]
		if b-a<1e-6 then continue end
		local mid=(a+b)*.5
		while edgeIndex<#edges-1 and edges[edgeIndex]<mid do edgeIndex+=2 end
		if edges[edgeIndex+1]==Spline.CLIFF and Style.runoff(spline,sec,side,mid)<reach-1e-7 then
			local previous=out[#out]
			if previous and math.abs(previous[2]-a)<1e-6 then previous[2]=b else table.insert(out,{a,b}) end
		end
	end
	return out
end

-- Eight fixed draws per section (four a side) are supplied even when no edge
-- qualifies. Mandatory gravel-edge rails come from gl, not legacy kr choices.
function Style.rails(spline:Spline.Spline,sec:Spline.Section,records:{number},grove:{[number]:number},draws:{number}):{number}
	local C,T=Config.Spline.Biomes.Rails,Config.Spline.Terrain
	local s0=spline.length
	local sides:{[number]:{{number}}}={[-1]={},[1]={}}
	for i=1,#(sec.gl or {}),3 do
		local gl=sec.gl :: {number}
		table.insert(sides[gl[i+2]],{gl[i],gl[i+1]})
	end
	for index,side in {-1,1} do
		if sec.tag=="Start" or grove[side] then continue end
		local offset=(index-1)*4
		local function chance(u:number):number
			local width=Style.runoff(spline,sec,side,u)
			local reach=math.clamp((C.Reach-width)/(C.Reach*.5),0,1)
			local k=Style.curvature(spline,sec,u)
			local outside=if k>0 then 1 else -1
			local factor=if math.abs(k)<1e-5 then C.StraightFactor elseif side==outside then 1 else C.InsideFactor
			return Biome.mix(records,s0+u,C.Chance,0)*reach*factor
		end
		local candidates,total={},0
		for _,span in Style.cliffIntervals(spline,sec,side,C.Reach) do
			local a,b=span[1],span[2]
			if b-a>=T.KRailRun[1] then
				local exposure=(chance(a+(b-a)*.25)+chance((a+b)*.5)+chance(a+(b-a)*.75))/3
				if exposure>0 then
					local weight=(b-a)*exposure
					table.insert(candidates,{a=a,b=b,exposure=exposure,weight=weight})
					total+=weight
				end
			end
		end
		if total<=0 then continue end
		local chosen=candidates[#candidates]
		local pick=draws[offset+3]*total
		for _,candidate in candidates do
			pick-=candidate.weight
			if pick<=0 then chosen=candidate;break end
		end
		local available=chosen.b-chosen.a
		local share=Biome.mix(records,s0+(chosen.a+chosen.b)*.5,C.RunShare,.65)
		local run=math.clamp(available*share*(.85+.15*draws[offset+2]),T.KRailRun[1],math.min(T.KRailRun[2],available))
		local start=chosen.a+(available-run)*draws[offset+4]
		-- Roll at the placed run, so a higher-chance portion of a long eligible
		-- interval cannot donate its probability to a distant field portion.
		if draws[offset+1]>=math.clamp(chance(start+run*.5)*C.Density,0,1) then continue end
		table.insert(sides[side],{start,start+run})
	end
	local rows={}
	for _,side in {-1,1} do
		local list=sides[side]
		table.sort(list,function(a,b)return a[1]<b[1]end)
		local merged={}
		for _,run in list do
			local previous=merged[#merged]
			if previous and run[1]<=previous[2]+1e-6 then previous[2]=math.max(previous[2],run[2]) else table.insert(merged,{run[1],run[2]}) end
		end
		for _,run in merged do table.insert(rows,{run[1],run[2],side}) end
	end
	table.sort(rows,function(a,b)return if a[1]==b[1] then a[3]<b[3] else a[1]<b[1] end)
	local out={}
	for _,run in rows do for _,v in run do table.insert(out,v) end end
	return out
end

return Style
