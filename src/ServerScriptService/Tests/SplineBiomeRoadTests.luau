--!nonstrict
-- Actual accepted road rhythm and rail coverage, weighted by biome distance.
local RS=game:GetService("ReplicatedStorage")
local Config=require(RS.Shared.Config)
local Gen=require(RS.Shared.Road.SplineGen)
local Biome=require(RS.Shared.Road.SplineBiome)
local Spline=require(RS.Shared.Road.Spline)
local Style=require(RS.Shared.Road.SplineRoadStyle)
local Tests={}

local function metric()
	return {metres=0,heading=0,straight=0,tight=0,sweeping=0,reversals=0,eligible=0,railed=0,mandatory=0,missingMandatory=0,nonCliffRails=0,broadFieldRails=0}
end
local function buckets()
	local out={}
	for _,name in {"all","regular","required","other","opening"} do out[name]={metric(),metric(),metric()} end
	return out
end
local function weights(spline,s)
	local a,b,t=spline:biomeAt(s)
	local out={0,0,0}
	if a and b then out[a]+=1-t;out[b]+=t end
	return out
end
local function inside(runs,s)
	local lo,hi=1,#runs.a
	if hi==0 or s<runs.a[1] then return false end
	while lo<hi do local m=(lo+hi+1)//2;if runs.a[m]<=s then lo=m else hi=m-1 end end
	return s<=runs.b[lo]
end
local function add(target,source)
	for k,v in source do target[k]+=v end
end
local function summary(bucket)
	local out={}
	for i,m in bucket do
		local scale=if m.metres>0 then 1/m.metres else 0
		out[Biome.Names[i]]={metres=m.metres,headingPer1000=math.deg(m.heading)*1000*scale,
			straightShare=m.straight*scale,tightShare=m.tight*scale,sweepingShare=m.sweeping*scale,
			reversalsPer1000=m.reversals*1000*scale,eligible=m.eligible,railed=m.railed,
			railCoverage=if m.eligible>0 then m.railed/m.eligible else 0,mandatory=m.mandatory,
			missingMandatory=m.missingMandatory,
			nonCliffRails=m.nonCliffRails,broadFieldRails=m.broadFieldRails}
	end
	return out
end

-- Classify accepted steps from counters: required corrections can share a
-- Medium tag with a regular choice, so tags alone would bias this comparison.
local function generate(seed,length)
	local g=Gen.new(seed)
	local origins={[1]="other"}
	local steps=0
	while g.spline.length<length do
		local oldN,turns,corrections=#g.sections,#g.turns,g.stats.straightens
		local section=g:step()
		if not section then break end
		local origin=if #g.turns>turns or g.stats.straightens>corrections then "required"
			elseif section.tag=="Escape" then "other" else "regular"
		for i=oldN+1,#g.sections do origins[i]=origin end
		steps+=1;if steps%12==0 then task.wait() end
	end
	return g,origins
end

function Tests.measureRoads(_self,options)
	assert(game:GetService("RunService"):IsStudio())
	local opts=options or {}
	local length=opts.length or 20000
	local totals=buckets()
	local roads={}
	local stalled,escapes,relaxed,rejected,tries,worst=0,0,0,0,0,0
	for _,seed in opts.seeds or {31337,101,2024} do
		local gen,origins=generate(seed,length)
		local spline=gen.spline
		local by=buckets()
		local endS=math.min(length,spline.length)
		local s0=0
		local priorSign,priorGroup=0,"other"
		for n,sec in gen.sections do
			local s1=math.min(endS,s0+sec.len)
			local a=s0
			while a<s1-1e-6 do
				local b=math.min(s1,a+8)
				for j=1,#sec.k,2 do if s0+sec.k[j]>a+1e-6 then b=math.min(b,s0+sec.k[j]);break end end
				local s=(a+b)*.5
				local ds=b-a
				local k=spline:curvatureAt(s)
				local absK=math.abs(k)
				local w=weights(spline,s)
				local group=if s<1500 then "opening" else origins[n] or "other"
				local sign=if absK>1e-5 then (if k>0 then 1 else -1) else 0
				local reversal=sign~=0 and priorSign~=0 and sign~=priorSign and group=="regular" and priorGroup=="regular"
				local eligible,rail,mandatory,missingMandatory,nonCliff,broad=0,0,0,0,0,0
				for _,side in {-1,1} do
					local cliff=spline:edgeAt(s,side)==Spline.CLIFF
					local width=spline:runoffAt(s,side)
					local hasRail=spline:kRailAt(s,side)~=nil
					if cliff and width<Config.Spline.Biomes.Rails.Reach and not inside(spline:groves(side),s) then eligible+=ds;if hasRail then rail+=ds end end
					if hasRail and not cliff then nonCliff+=ds end
					if hasRail and width>=Config.Spline.Biomes.Rails.Reach-1e-6 and w[1]>.99 then broad+=ds end
					for j=1,#(sec.gl or {}),3 do
						if sec.gl[j+2]==side and s>=s0+sec.gl[j] and s<=s0+sec.gl[j+1] then
							mandatory+=ds;if not hasRail then missingMandatory+=ds end
						end
					end
				end
				for kind=1,3 do
					local m={metres=ds*w[kind],heading=absK*ds*w[kind],straight=if absK<1/10000 then ds*w[kind] else 0,
						tight=if absK>=1/170 then ds*w[kind] else 0,sweeping=if absK>=1/10000 and absK<=1/340 then ds*w[kind] else 0,
						reversals=if reversal then w[kind] else 0,eligible=eligible*w[kind],railed=rail*w[kind],mandatory=mandatory*w[kind],
						missingMandatory=missingMandatory*w[kind],
						nonCliffRails=nonCliff*w[kind],broadFieldRails=broad*w[kind]}
					add(by.all[kind],m);add(by[group][kind],m)
				end
				if group~="regular" then priorSign=0 elseif sign~=0 then priorSign=sign end
				priorGroup=group;a=b
			end
			s0+=sec.len
			if s0>=endS then break end
		end
		for name,bucket in by do for kind,m in bucket do add(totals[name][kind],m) end end
		local report={seed=seed,length=endS,regular=summary(by.regular),all=summary(by.all),required=summary(by.required),opening=summary(by.opening),
			sections=#gen.sections,stalled=gen.stats.stalled,escapes=gen.stats.escapes,relaxed=gen.stats.hillRelaxed,worstMs=gen.stats.worstMs}
		table.insert(roads,report)
		if gen.stats.stalled then stalled+=1 end
		escapes+=gen.stats.escapes;relaxed+=gen.stats.hillRelaxed;rejected+=gen.stats.rejectedCrowded+gen.stats.rejectedHeading;tries+=gen.stats.tries
		worst=math.max(worst,gen.stats.worstMs)
		task.wait()
	end
	local pooled={}
	for name,bucket in totals do pooled[name]=summary(bucket) end
	return {roads=roads,pooled=pooled,stalled=stalled,escapes=escapes,relaxed=relaxed,rejectionShare=if tries>0 then rejected/tries else 0,worstMs=worst}
end

local function same(a,b)
	if type(a)~=type(b) then return false end
	if type(a)~="table" then return a==b end
	for k,v in a do if not same(v,b[k]) then return false end end
	for k in b do if a[k]==nil then return false end end
	return true
end
local function covers(runs,a,b,side)
	local at=a
	for i=1,#runs,3 do
		if runs[i+2]==side and runs[i]<=at+1e-6 and runs[i+1]>=at then at=math.max(at,runs[i+1]) end
	end
	return at>=b-1e-6
end

function Tests.run()
	assert(game:GetService("RunService"):IsStudio())
	local C=Config.Spline.Biomes
	local saved={ground=C.GroundEnabled,road=C.Road.Enabled,rails=C.Rails.Enabled,density=C.Rails.Density,chance=C.Rails.Chance}
	C.GroundEnabled=true;C.Road.Enabled=true;C.Rails.Enabled=true
	local checks={}
	local function check(name,ok,detail)table.insert(checks,{name=name,ok=ok,detail=detail})end
	local ok,err=xpcall(function()
		local records={0,Biome.FIELD,0,400,Biome.STEEP,180}
		local previous=Style.weight(records,0,"Tight")
		local monotone,largest=true,0
		for s=1,700 do
			local now=Style.weight(records,s,"Tight")
			monotone=monotone and now>=previous-1e-12;largest=math.max(largest,math.abs(now-previous));previous=now
		end
		check("bend preferences blend across road-section interiors",monotone and largest<.011 and math.abs(Style.weight(records,309,"Tight")-C.Road.Weights.Tight[1])<1e-12,
			`largest per-stud preference change {largest}`)
		C.Road.Enabled=false
		check("disabled or legacy preferences preserve existing probabilities",Style.weight(records,600,"Tight")==1
			and Style.straightChance(records,600)==Config.Spline.StraightChance
			and Style.switchbackChance(nil,600)==Config.Spline.SwitchbackChance,"existing limits and legacy choices remain available")
		C.Road.Enabled=true
		local prefix={len=300,k={150,.002,300,-.001},g={300,0},b={300,0},rl={300,45},rr={300,25},
			el={300,Spline.ROCK},er={300,Spline.CLIFF},bm={0,Biome.STEEP,0}}
		local sp=Spline.new({x=0,y=0,z=0,yaw=0});sp:append(prefix)
		local sec={len=600,k={120,.005,380,-.006,600,.002},g={600,0},b={600,0},
			rl={180,90,360,20,600,90},rr={200,15,400,100,600,55},
			el={160,Spline.CLIFF,240,Spline.ROCK,600,Spline.CLIFF},er={300,Spline.CLIFF,380,Spline.ROCK,600,Spline.CLIFF}}
		local replay=Spline.new({x=0,y=0,z=0,yaw=0});replay:append(prefix);replay:append(sec)
		local gap,badIntervals=0,0
		for _,side in {-1,1} do
			local spans=Style.cliffIntervals(sp,sec,side,C.Rails.Reach)
			for u=.25,sec.len-.25,.5 do
				gap=math.max(gap,math.abs(Style.runoff(sp,sec,side,u)-replay:runoffAt(300+u,side)),
					math.abs(Style.curvature(sp,sec,u)-replay:curvatureAt(300+u)))
				local eligible=replay:edgeAt(300+u,side)==Spline.CLIFF and replay:runoffAt(300+u,side)<C.Rails.Reach-1e-7
				local included=false;for _,span in spans do if u>span[1] and u<span[2] then included=true end end
				if eligible~=included then badIntervals+=1 end
			end
		end
		check("unappended rail policy uses the emitted widths and curvature",gap<1e-8,`largest sampled difference {gap}`)
		check("cliff intervals split at edge swaps, fitted widths and inside caps",badIntervals==0,`{badIntervals} mismatches against appended ground`)
		local base=Spline.new({x=0,y=0,z=0,yaw=0})
		base:append({len=200,k={200,0},g={200,0},b={200,0},rl={200,20},rr={200,20},bm={0,Biome.STEEP,0}})
		local railSec={len=600,k={600,0},g={600,0},b={600,0},rl={600,20},rr={600,20},
			el={600,Spline.CLIFF},er={600,Spline.CLIFF},gl={40,140,-1,100,180,-1,400,500,1}}
		local draws={0,.4,.2,.7,0,.4,.2,.7}
		C.Rails.Density=0
		local mandatory=Style.rails(base,railSec,{0,Biome.STEEP,0},{},draws)
		check("zero discretionary density keeps every mandatory gravel span",#mandatory==6 and covers(mandatory,40,180,-1) and covers(mandatory,400,500,1),
			"overlapping mandatory runs merge without losing coverage")
		railSec.gl=nil;C.Rails.Density=100
		local high=Style.rails(base,railSec,{0,Biome.STEEP,0},{},draws)
		check("exposed cliffs can receive only existing asphalt-edge rail runs",#high==6 and high[1]>=0 and high[2]<=railSec.len
			and high[4]>=0 and high[5]<=railSec.len,"at most one discretionary run per side")
		check("groves suppress discretionary rails",#Style.rails(base,railSec,{0,Biome.STEEP,0},{[-1]=1,[1]=1},draws)==0,"mandatory protection has a separate source")
		local broad=Spline.new({x=0,y=0,z=0,yaw=0})
		broad:append({len=200,k={200,0},g={200,0},b={200,0},rl={200,80},rr={200,80},bm={0,Biome.FIELD,0}})
		local broadSec=table.clone(railSec);broadSec.rl={600,80};broadSec.rr={600,80}
		check("a broad field has no discretionary rails even at high density",#Style.rails(broad,broadSec,{0,Biome.FIELD,0},{},draws)==0,"actual fitted cliff distance determines eligibility")
		C.Rails.Chance={0,0,1};C.Rails.Density=1
		-- The same narrow cliff interval straddles a long field/steep blend.
		-- Its first placed run lies entirely in the zero-chance field portion.
		local localDraws={0,0,0,0,0,0,0,0}
		local blend={0,Biome.FIELD,0,600,Biome.STEEP,180}
		check("a distant steep portion cannot donate rail chance to a field",#Style.rails(base,railSec,blend,{},localDraws)==0,
			"both placed run centres precede the blend despite a later exposed steep portion")
		C.Rails.Chance=saved.chance
		local function fingerprint(g)
			local out={}
			for _,name in {"rng","prng","trng","grng","xrng","crng","rrng"} do out[name]=g[name]:Clone():NextNumber() end
			out.length=g.biomes.lengthRng:Clone():NextNumber();out.choice=g.biomes.choiceRng:Clone():NextNumber()
			return out
		end
		local changed,expected,missing,unsafe,replayGap,roads=0,0,0,0,0,0
		for _,seed in {203,2024} do
			C.Rails.Enabled=true;C.Rails.Density=0;local low=generate(seed,30000)
			C.Rails.Density=4;local dense=generate(seed,30000)
			C.Rails.Enabled=false;local legacy=generate(seed,30000)
			local geometry=#low.sections==#dense.sections and #low.sections==#legacy.sections
			for n,section in low.sections do
				local function withoutRails(value)local copy=table.clone(value);copy.kr=nil;return copy end
				geometry=geometry and same(withoutRails(section),withoutRails(dense.sections[n] or {}))
					and same(withoutRails(section),withoutRails(legacy.sections[n] or {}))
				if not same(section.kr,dense.sections[n] and dense.sections[n].kr) then changed+=1 end
			end
			check(`seed {seed}: rail density never changes the road or scenery streams`,geometry and same(fingerprint(low),fingerprint(dense))
				and same(fingerprint(low),fingerprint(legacy)),"all section fields except kr and all nine RNG streams match, including the disabled legacy-rail path")
			C.Rails.Enabled=true
			local client=Gen.replay(dense.sections,nil,dense.fall)
			local s0=0
			for _,section in dense.sections do
				for j=1,#(section.gl or {}),3 do
					expected+=1;if not covers(section.kr or {},section.gl[j],section.gl[j+1],section.gl[j+2]) then missing+=1 end
				end
				for j=1,#(section.kr or {}),3 do
					local a,b,side=section.kr[j],section.kr[j+1],section.kr[j+2]
					for u=a+1e-4,b-1e-4,1 do
						local s=s0+u
						if dense.spline:edgeAt(s,side)~=Spline.CLIFF or dense.spline:runoffAt(s,side)>=C.Rails.Reach+1e-5 then unsafe+=1 end
						if client:kRailAt(s,side)==nil then replayGap+=1 end
					end
				end
				s0+=section.len
			end
			roads+=1
		end
		check("density changes visible rails while retaining all mandatory protection",changed>0 and expected>0 and missing==0,
			`{changed} changed sections; {expected} mandatory runs; {missing} uncovered`)
		check("generated rails stay on eligible cliffs and replay exactly",roads==2 and unsafe==0 and replayGap==0,
			`{unsafe} ineligible samples; {replayGap} replay gaps across two 30000-stud roads`)
	end,debug.traceback)
	C.GroundEnabled=saved.ground;C.Road.Enabled=saved.road;C.Rails.Enabled=saved.rails;C.Rails.Density=saved.density;C.Rails.Chance=saved.chance
	if not ok then check("road and rail policy suite completes",false,err) end
	local passed=0;for _,c in checks do if c.ok then passed+=1 end end
	return {passed=passed,total=#checks,checks=checks}
end

function Tests.contacts()
	assert(game:GetService("RunService"):IsStudio())
	local C,D,T=Config.Spline.Biomes,Config.Drift,Config.Spline.Terrain
	local saved={ground=C.GroundEnabled,rails=C.Rails.Enabled,density=C.Rails.Density}
	C.GroundEnabled=true;C.Rails.Enabled=true;C.Rails.Density=1
	local checks={}
	local function check(name,ok,detail)table.insert(checks,{name=name,ok=ok,detail=detail})end
	local ok,err=xpcall(function()
		local folder=game:GetService("StarterPlayer").StarterPlayerScripts.Drift
		local World=require(folder.SplineWorld);local Sim=require(folder.Sim)
		local g=generate(2024,30000);local sp=g.spline
		local targets={};local s0=0
		for _,sec in g.sections do
			if sec.gl and not targets.mandatory then targets.mandatory={s=s0+(sec.gl[1]+sec.gl[2])*.5,side=sec.gl[3]} end
			if not sec.gl and not targets.discretionary then
				for i=1,#(sec.kr or {}),3 do
					local a,b,side=s0+sec.kr[i],s0+sec.kr[i+1],sec.kr[i+2]
					if b-a>D.BodyLength*2+30 then targets.discretionary={s=(a+b)*.5,side=side};break end
				end
			end
			s0+=sec.len
		end
		local half=Config.Road.Width*.5
		for _,kind in {"mandatory","discretionary"} do
			local target=targets[kind]
			check(`an actual generated {kind} rail is available`,target~=nil,"seed2024; 30000studs; ordinary configured density")
			if not target then continue end
			local s,side=target.s,target.side
			local world=World.new(sp);world.hint=s
			local yaw=sp:yawAt(s)-side*math.pi*.5
			local function pose(u,d)return Vector3.new(sp:terrainXYZ(u,side*d))+Vector3.yAxis*D.RideHeight end
			local near=pose(s,half-D.BodyLength-4)
			local far=pose(s,half+T.KRailThickness+D.BodyLength+4)
			-- Collision from behind is tested beside the actual barrier. Extending
			-- the ground's bank past a narrow cliff can put a far point above/below
			-- the rail, where a non-contact would correctly model a jump or fall.
			local railY=sp:terrainY(s,side*half)+T.KRailHeight*.5
			near=Vector3.new(near.X,railY,near.Z);far=Vector3.new(far.X,railY,far.Z)
			local before=world.stats.kRailStops
			local front=world.sweep(near,far,yaw)
			world.hint=s;local back=world.sweep(far,near,yaw+math.pi)
			check(`the {kind} rail collides from both sides`,front~=nil and back~=nil and world.stats.kRailStops-before==2,
				`{world.stats.kRailStops-before} actual rail contacts`)
			world.hint=s
			local runner=Sim.newRunner(CFrame.new(pose(s,5))*CFrame.Angles(0,yaw,0))
			runner.state.velocity=Vector3.new(-math.sin(yaw),0,-math.cos(yaw))*40;runner.state.time=10
			before=world.stats.kRailStops
			for _=1,90 do Sim.advance(runner,1/60,{steer=0,handbrake=false},world) end
			local p=runner.state.position;local _,d=sp:projectFrom(p.X,p.Z,s)
			local nose=(d or math.huge)*side+D.BodyLength*.5
			check(`a real car stops at the {kind} rail`,world.stats.kRailStops>before and nose<=half+1.5 and not runner.state.airborne,
				`nose {nose}; asphalt edge {half}; rail contacts {world.stats.kRailStops-before}`)
			local a,b=sp:kRailAt(s,side)
			local gaps=0
			for _,u in {a-D.BodyLength-5,b+D.BodyLength+5} do
				if u>0 and u<sp.length and not sp:kRailAt(u,side) and sp:edgeAt(u,side)==Spline.CLIFF then
					world.hint=u;before=world.stats.kRailStops
					local hit=world.sweep(pose(u,half-D.BodyLength-4),pose(u,half+T.KRailThickness+8),sp:yawAt(u)-side*math.pi*.5)
					check(`the open gap beyond a {kind} rail endpoint stays open`,hit==nil and world.stats.kRailStops==before,
						`crossed at arc {u}, clear of the car's body beyond rail end`)
					gaps+=1
				end
			end
			check(`a genuine endpoint gap was exercised for {kind}`,gaps>0,`{gaps} passable exposed gaps`)
			world.destroy()
		end
	end,debug.traceback)
	C.GroundEnabled=saved.ground;C.Rails.Enabled=saved.rails;C.Rails.Density=saved.density
	if not ok then check("generated rail contact suite completes",false,err) end
	local passed=0;for _,c in checks do if c.ok then passed+=1 end end
	return {passed=passed,total=#checks,checks=checks}
end

return Tests
