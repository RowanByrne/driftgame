--!nonstrict
-- Detached preflight, emitted geometry and bounded terrain retries (T-190).
local RunService=game:GetService("RunService")
assert(RunService:IsStudio(),"SplineTurnTests is Studio only")
local Config=require(game.ReplicatedStorage.Shared.Config)
local Gen=require(game.ReplicatedStorage.Shared.Road.SplineGen)
local Fit=require(game.ReplicatedStorage.Shared.Road.SplineTurnFit)
local Tests={}
local function hashState(g)
	local out={g.spline.length,#g.spline.curv.s,#g.spline.grade.s,#g.spline.bank.s,#g.flips,g.uphill,g.flip,g.lastGrand}
	for _,r in {g.trng,g.grng,g.xrng,g.crng} do table.insert(out,r:Clone():NextNumber()) end
	local n,sum=0,0
	for _,bucket in g.spline.hash do for _,v in bucket do n+=1;sum+=v end end
	table.insert(out,n);table.insert(out,sum)
	return game:GetService("HttpService"):JSONEncode({summary=out,curv=g.spline.curv,grade=g.spline.grade,bank=g.spline.bank,edgeL=g.spline.edgeL,edgeR=g.spline.edgeR,runL=g.spline.runL,runR=g.spline.runR,runoff=g.runoff,inBand=g.inBand,crossAt=g.crossAt,flipDone=g.flipDone})
end
function Tests.run()
	local checks={}
	local function check(name,ok,detail) table.insert(checks,{name=name,ok=ok,detail=detail}) end
	local g=Gen.new(31337);g:extendTo(1400)
	local item={turn=true,what="turnaround",to=math.pi,dir=1,radius={75,110},tag="Hairpin"}
	local sec={len=240,k={80,.01,240,.01},g={240,-.025},b={240,0},tag="Hairpin"}
	local before=hashState(g)
	local a=g:_fitTurn(sec,item)
	local b=g:_fitTurn(sec,item)
	check("speculative terrain leaves the road and scenery streams untouched",hashState(g)==before,"tracks, hash buckets, flips, edge state and four scenery RNGs unchanged")
	check("the same detached candidate measures identically",a.view==b.view and a.cut==b.cut and a.fill==b.fill,"two previews agree")
	local measured,worst,stalls,relaxed,checked,rejected,badEnds=0,0,0,0,0,0,0
	local firstRoad
	for _,seed in {31337,101,2024} do
		g=Gen.new(seed)
		while g.spline.length<12000 do
			local n=#g.turnFits
			if not g:step() then stalls+=1;break end
			if #g.turnFits>n then
				local r=g.turnFits[#g.turnFits]
				if g.spline:curvatureAt(r.s1)~=0 or math.abs(g.spline:bankAt(r.s1))>1e-6 or g.lastDir==0 or g.lastWasBend then badEnds+=1 end
				local now=Fit.measure(g.spline,r.s0,r.s1,1,g.flips)
				worst=math.max(worst,math.abs(r.view-now.view),math.abs(r.cut-now.cut),math.abs(r.fill-now.fill))
				measured+=1
			end
		end
		checked+=g.stats.hillChecked;rejected+=g.stats.hillRejected;relaxed+=g.stats.hillRelaxed
		if not firstRoad then firstRoad=g end
	end
	check("a fitted turn includes a straight unbanked continuation",measured>0 and badEnds==0,`{measured} exits; {badEnds} bad endpoints or bend-state errors`)
	check("the accepted preview is the emitted road and hillside",measured>0 and worst<1e-4,`{measured} turns; largest measurement difference {worst}`)
	check("terrain checks retry unsuitable shapes without stopping the run",stalls==0 and rejected>0,`{checked} candidates, {rejected} outside preferred limits, {relaxed} least-obstructed fallbacks; {stalls} stalled roads`)
	local ranked=Gen.new(31337)
	local calls=0
	ranked._fitTurn=function()
		calls+=1
		return if calls==2 then {ok=true,score=.14,view=14,cut=80,fill=0} else {ok=false,score=.1,view=0,cut=90.1,fill=0}
	end
	local selected=ranked:_turn({turn=true,what="turnaround",to=math.pi,dir=1,radius={75,110},tag="Hairpin"})
	check("a valid shape always beats an invalid shape with a smaller score",type(selected)=="table" and ranked.stats.hillRelaxed==0,"passing second candidate wins over slightly over-limit first/third candidates")
	g=Gen.new(31337)
	g._fitTurn=function() return {ok=false,score=10,view=25,cut=0,fill=0} end
	item={turn=true,what="turnaround",to=math.pi,dir=1,radius={75,110},tag="Hairpin"}
	local refused=0
	for _=1,Config.Spline.Mountain.TurnLocationRetries do if g:_turn(item)==nil then refused+=1 end end
	local fallback=g:_turn(item)
	check("a universally walled location has bounded retries",refused==Config.Spline.Mountain.TurnLocationRetries and type(fallback)=="table" and g.stats.hillRelaxed==1,`{refused} refusals, then the best clear turn`)
	g=Gen.new(31337)
	g._clear=function() return false end
	g._fitTurn=function() error("unsafe curve reached terrain check") end
	check("terrain fallback never bypasses crossing and escape safety",g:_turn(item)==nil and g.stats.hillChecked==0,"no crossing-safe radius means no turn, even after terrain retries")
	local replay=Gen.replay(firstRoad.sections,nil,firstRoad.fall)
	local gap=0
	for s=0,firstRoad.spline.length,37 do gap=math.max(gap,(firstRoad.spline:surface(s,0)-replay:surface(s,0)).Magnitude) end
	check("clients replay the chosen turns exactly",gap==0,`worst road position difference {gap} studs`)
	local passed=0
	for _,c in checks do if c.ok then passed+=1 end end
	return {passed=passed,total=#checks,checks=checks}
end
return Tests