--!nonstrict
-- Actual accepted road rhythm and rail coverage, weighted by biome distance.
local RS=game:GetService("ReplicatedStorage")
local Config=require(RS.Shared.Config)
local Gen=require(RS.Shared.Road.SplineGen)
local Biome=require(RS.Shared.Road.SplineBiome)
local Spline=require(RS.Shared.Road.Spline)
local Tests={}

local function metric()
	return {metres=0,heading=0,straight=0,tight=0,sweeping=0,reversals=0,eligible=0,railed=0,mandatory=0,nonCliffRails=0,broadFieldRails=0}
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
				local eligible,rail,mandatory,nonCliff,broad=0,0,0,0,0
				for _,side in {-1,1} do
					local cliff=spline:edgeAt(s,side)==Spline.CLIFF
					local width=spline:runoffAt(s,side)
					local hasRail=spline:kRailAt(s,side)~=nil
					if cliff and width<80 and not inside(spline:groves(side),s) then eligible+=ds;if hasRail then rail+=ds end end
					if hasRail and not cliff then nonCliff+=ds end
					if hasRail and width>=80-1e-6 and w[1]>.99 then broad+=ds end
					for j=1,#(sec.gl or {}),3 do
						if sec.gl[j+2]==side and s>=s0+sec.gl[j] and s<=s0+sec.gl[j+1] and hasRail then mandatory+=ds end
					end
				end
				for kind=1,3 do
					local m={metres=ds*w[kind],heading=absK*ds*w[kind],straight=if absK<1/10000 then ds*w[kind] else 0,
						tight=if absK>=1/170 then ds*w[kind] else 0,sweeping=if absK>=1/10000 and absK<=1/340 then ds*w[kind] else 0,
						reversals=if reversal then w[kind] else 0,eligible=eligible*w[kind],railed=rail*w[kind],mandatory=mandatory*w[kind],
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

return Tests
