--!nonstrict
-- Safety of the plan strip used to protect finite fields (T-203), not a renderer test.
assert(game:GetService("RunService"):IsStudio(), "SplineCorridorTests is Studio only")
local Corridor=require(game.ReplicatedStorage.Shared.Road.SplineCorridor)
local Config=require(game.ReplicatedStorage.Shared.Config)
local Tests={}
local function straight(s,x,z,yaw,left,right)
	local a=Corridor.row(s,x,z,yaw,0,left,right)
	local b=Corridor.row(s+8,x-8*math.sin(yaw),z-8*math.cos(yaw),yaw,0,left,right)
	return Corridor.cell(a,b)
end
function Tests.run()
	local checks={}
	local function check(name,ok,detail) table.insert(checks,{name=name,ok=ok,detail=detail}) end
	local field=straight(0,0,0,0,105,105)
	local near=straight(1000,150,0,0,65,65)
	local far=straight(1000,210,0,0,65,65)
	check("a later road cannot enter a previously supported field",Corridor.overlap(field,near,20),"150-stud centre distance is insufficient on the facing sides")
	check("a genuine outer-boundary gap stays clear",not Corridor.overlap(field,far,20),"210-stud centre distance leaves40studs beyond both strips")
	local function arc(s,angle)
		return Corridor.row(s,75*(math.cos(angle)-1),-75*math.sin(angle),angle,1/75,105,105)
	end
	local start=Corridor.cell(arc(0,0),arc(4,4/75))
	local finish=Corridor.cell(arc(math.pi*75-4,math.pi-4/75),arc(math.pi*75,math.pi))
	check("actual offset widths preserve the current tight hairpin",not Corridor.overlap(start,finish,20),"radius75: inward edges45fromtheircentres,60-stud gap; outward fields do not count inward")
	local crossing=straight(2000,0,0,math.pi*.5,25,25)
	check("rotated crossing strips still overlap",Corridor.overlap(field,crossing,0),"separating-axis test includes both polygons")
	local index=Corridor.new()
	index:add(field)
	local clear=index:clear(near,236,20)
	check("frozen cells protect retired road without curve samples",not clear,"query uses stored world corners only")
	local neighbour=straight(100,0,-8,0,105,105)
	check("connected neighbour cells retain the existing separation exemption",index:clear(neighbour,236,20),"adjacent parts of one supported road remain connected")
	local query=straight(5000,300,0,0,25,25)
	local _,_,before=index:clear(query,236,20)
	for n=1,10000 do
		index:add(straight(n*8,10000+n*9,20000,0,105,105))
		if n%500==0 then task.wait() end
	end
	local _,_,after=index:clear(query,236,20)
	check("local lookup work does not scan an endless road history",after==before,`visited before {before}, after {after} with10,000remote cells`)
	local frames={}
	for s=0,464,8 do table.insert(frames,Corridor.row(s,0,-s,0,0,65,65)) end
	local old=Corridor.new()
	old:add(straight(10000,165,-300,0,65,65))
	local left,right=Corridor.fit(frames,200,{40,40},function()return 80 end,old,236)
	check("an outgoing field reserves its own actual continuation",left~=nil and right~=nil and right[#right]<74,
		if right then `outgoing right runoff {right[#right]} instead of unsafe80` else "minimum continuation did not fit")
	-- Both sides may clear the opposite minimum strip while the final widened
	-- fields still overlap. Exercise the complete connected U-turn, not two discs.
	frames={}
	local radius=100
	for s=0,1120,8 do
		local x,z,yaw,k
		if s<=300 then x,z,yaw,k=0,-s,0,0
		elseif s<300+math.pi*radius then
			local angle=(s-300)/radius
			x,z,yaw,k=radius*(math.cos(angle)-1),-300-radius*math.sin(angle),angle,1/radius
		else x,z,yaw,k=-200,-300+(s-300-math.pi*radius),math.pi,0 end
		table.insert(frames,Corridor.row(s,x,z,yaw,k,65,65))
	end
	left,right=Corridor.fit(frames,800,{40,40},function()return 80 end,Corridor.new(),236)
	check("final widened fields are checked against each other",left~=nil and right~=nil and (left[#left]<79 or right[#right]<79),
		if left and right then `outgoing widths {left[#left]}, {right[#right]}` else "connected footprint did not fit")
	local passed=0
	for _,c in checks do if c.ok then passed+=1 end end
	return {passed=passed,total=#checks,checks=checks}
end

-- This stage checks stable fitted footprints; shared surface and renderer checks
-- are separate. The construction flag is restored even if a candidate fails.
function Tests.generation(selfOrLength,requestedLength,profile)
	local length=if type(selfOrLength)=="number" then selfOrLength else requestedLength
	local old=Config.Spline.Biomes.GroundEnabled
	Config.Spline.Biomes.GroundEnabled=true
	local ok,result=xpcall(function()
		local Gen=require(game.ReplicatedStorage.Shared.Road.SplineGen)
		local checks={}
		local function check(name,pass,detail) table.insert(checks,{name=name,ok=pass,detail=detail}) end
		local minimum,maximum,stalls,clashes,cells,worst=math.huge,0,0,0,0,0
		local worstTag=""
		local phases={}
		for _,seed in {101,2024,31337} do
			local g=Gen.new(seed)
			if profile then
				for _,name in {"_groundClear","_fitGround","_registerGround","_fitTurn"} do
					local original=g[name]
					g[name]=function(self,...)
						local t0=os.clock()
						local result=table.pack(original(self,...))
						local elapsed=(os.clock()-t0)*1000
						local phase=phases[name] or {max=0,total=0,calls=0}
						phase.max,phase.total,phase.calls=math.max(phase.max,elapsed),phase.total+elapsed,phase.calls+1
						phases[name]=phase
						return table.unpack(result,1,result.n)
					end
				end
			end
			while g.spline.length<(length or 8000) do
				local before=g.stats.worstMs
				local sec=g:step()
				if g.stats.worstMs>before and g.stats.worstMs>worst then worstTag=`seed{seed} {sec and sec.tag} {sec and sec.len}` end
				if not sec then break end
			end
			if g.stats.stalled then stalls+=1 end
			worst=math.max(worst,g.stats.worstMs)
			for _,bucket in g.corridors.buckets do
				for _,cell in bucket do
					cells+=1
					if not g.corridors:clear(cell,g.separation,Config.Spline.ClearanceGap) then clashes+=1 end
				end
			end
			for s=0,g.spline.length,8 do
				for _,side in {-1,1} do
					local width=g.spline:runoffAt(s,side)
					minimum,maximum=math.min(minimum,width),math.max(maximum,width)
				end
			end
			task.wait()
		end
		check("fitted fields retain an escape on the sampled roads",stalls==0,`{stalls} stalled seeds; {cells} frozen cells`)
		check("supported strips never overlap a separate road leg",clashes==0,`{clashes} conflicts at the full {Config.Spline.ClearanceGap}-stud gap`)
		check("fields can widen while tight bends retain local clipping",maximum>70 and minimum<25,`widths {minimum} to {maximum}`)
		check("fitted generation remains inside the current step budget",worst<20,`worst step {worst} ms ({worstTag})`)
		local passed=0
		for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks,phases=phases}
	end,debug.traceback)
	Config.Spline.Biomes.GroundEnabled=old
	if not ok then return {passed=0,total=1,checks={{name="fitted generation completes",ok=false,detail=result}}} end
	return result
end

function Tests.turns()
	local old=Config.Spline.Biomes.GroundEnabled
	Config.Spline.Biomes.GroundEnabled=true
	local ok,result=xpcall(function()return require(script.Parent.SplineTurnTests).run()end,debug.traceback)
	Config.Spline.Biomes.GroundEnabled=old
	if not ok then return {passed=0,total=1,checks={{name="fitted turn preflight completes",ok=false,detail=result}}} end
	return result
end
return Tests
