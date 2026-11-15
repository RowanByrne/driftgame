--!nonstrict
-- T-211: exercise readCars, retirement and recovery together. Default: isolated
-- service and two stand-in cars. {ownedVehicle=true}: the live service reads the
-- real player's CarService belief and exercises Place/Respawn ownership resets.
-- Only geometry is a fixture; sequence/progress/window methods are production.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ServerScriptService=game:GetService("ServerScriptService")
local ServerStorage=game:GetService("ServerStorage")
assert(game:GetService("RunService"):IsStudio(),"RoadProgressTests is Studio only")
local Config=require(ReplicatedStorage.Shared.Config)
local Spline=require(ReplicatedStorage.Shared.Road.Spline)
local Biome=require(ReplicatedStorage.Shared.Road.SplineBiome)
local Tests={}

function Tests.run(_self,options)
	options=options or {}
	local owned=options.ownedVehicle==true
	local live=require(ServerScriptService.Services.RoadService)
	assert(not live:HasRoad(),"Stop the live road before the isolated progress test")
	local carService=owned and require(ServerScriptService.Services.CarService)
	local player=owned and game:GetService("Players"):GetPlayers()[1]
	local realCar=player and carService.cars[player.UserId]
	assert(not owned or realCar,"Owned-vehicle integration requires a spawned player car")
	local savedPose=realCar and realCar:GetPivot()
	local oldMode=live:Mode()
	local checks={}
	local function check(name,ok,detail)table.insert(checks,{name=name,ok=ok,detail=detail})end
	local oldGround=Config.Spline.Biomes.GroundEnabled
	Config.Spline.Biomes.GroundEnabled=true
	local isolated=Instance.new("Folder")
	isolated.Name="__RoadProgressFixture"
	isolated.Parent=ServerStorage
	local service=live
	if not owned then
		local module=ServerScriptService.Services.RoadService:Clone()
		module.Parent=isolated
		service=require(module)
	end
	local cars=workspace:FindFirstChild("Cars")
	local madeCars=cars==nil
	if not cars then cars=Instance.new("Folder");cars.Name="Cars";cars.Parent=workspace end
	local models={}
	local ok,err=xpcall(function()
		for _,direction in {1,-1} do
			service:SetMode("spline")
			service:Generate(203)
			local seq=service:DebugGenerator()
			local sp=Spline.new({x=Config.Road.Offset.X,y=Config.Road.SurfaceY,z=Config.Road.Offset.Z,yaw=0})
			sp.fall=math.pi*.5
			local sections={}
			local radius,anchor=200,200
			local turnEnd=anchor+math.pi*radius
			local function append(length,k)
				local sec={len=length,k={length,k},g={length,0},b={length,0},rl={length,80},rr={length,80},
					el={length,Spline.ROCK},er={length,Spline.CLIFF},hl={length,0},hr={length,0},tag="Progress fixture"}
				if #sections==0 then sec.bm={0,Biome.FIELD,0} end
				table.insert(sections,sec);sp:append(sec)
			end
			append(anchor,direction/radius)
			append(math.pi*radius-60,direction/radius)
			append(60,direction/radius)
			append(200,0)
			for _=1,Config.Road.BehindPieces+Config.Road.AheadPieces+12 do append(200,0) end
			-- Install deterministic geometry through the existing test-only generator
			-- access, keeping the real sequence, adoption and retirement operations.
			seq.spline=sp;seq.gen.spline=sp;seq.gen.sections=sections
			seq.first=1;seq.last=0;seq.starts={};seq.pieces={};seq.destroyed=0
			seq.furthestN=1;seq.furthestT=0;seq:_adopt()
			local trailId,leadId=if owned then player.UserId else -2032111,-2032112
			assert(service:DebugJoin(trailId) and service:DebugJoin(leadId))
			local function car(id)
				local model=Instance.new("Model");model.Name=`ProgressFixture_{id}`;model:SetAttribute("UserId",id)
				local body=Instance.new("Part");body.Anchored=true;body.CanCollide=false;body.CanQuery=false;body.Transparency=1
				body.Parent=model;model.PrimaryPart=body;model.Parent=cars
				table.insert(models,model);return model
			end
			local trailer,leader=if owned then realCar else car(trailId),car(leadId)
			local travel,lastPosition=0,nil
			if owned then
				local p=Vector3.new(sp:terrainXYZ(0,0))+Vector3.yAxis*Config.Drift.RideHeight
				assert(carService:Place(player,CFrame.new(p)))
			end
			local function put(model,s,d)
				local p=Vector3.new(sp:terrainXYZ(s,d))+Vector3.yAxis*Config.Drift.RideHeight
				if owned and model==trailer then carService:DebugBelieve(trailId,p) else model:PivotTo(CFrame.new(p)) end
				if model==trailer then
					if lastPosition then local delta=p-lastPosition;travel+=Vector2.new(delta.X,delta.Z).Magnitude end
					lastPosition=p
				end
			end
			local function runner(id)
				for _,entry in service:RunReport() do if entry.userId==id then return entry end end
				error("runner missing")
			end
			put(trailer,0,0);put(leader,0,0);service:DebugTick()
			for s=10,anchor,10 do put(trailer,s,0);put(leader,s,0);service:DebugTick() end
			travel=0
			local earned=runner(trailId)
			local earnedN,earnedT=earned.n,earned.t
			local inner=-direction*100
			put(trailer,anchor,inner);service:DebugTick()
			local target=turnEnd-1
			for s=anchor+5,target,5 do put(trailer,s,inner);service:DebugTick() end
			put(trailer,target,inner);service:DebugTick()
			local grass=runner(trailId)
			check(`{direction}: grass preserves earned asphalt progress`,grass.n==earnedN and math.abs(grass.t-earnedT)<1e-5,
				`earned piece {earnedN}, grass piece {grass.n}`)
			-- Advance the second actual car along asphalt until the ordinary window
			-- retires piece 2. The trailer's supported grass projection stays live.
			local leadN=3+Config.Road.BehindPieces
			local leadS=seq:piece(leadN).s0+20
			for s=anchor+10,leadS,10 do put(leader,s,0);service:DebugTick() end
			put(leader,leadS,0);local before=service:DebugTick()
			leader.Parent=isolated -- an absent leader must not mask the trailer's result
			put(trailer,target,0)
			local credit=seq:reentryS(anchor,travel,target)
			local rawN=select(1,seq:locateOwned(lastPosition,target,320))
			check(`{direction}: another runner retires the credited anchor while reentry stays live`,
				seq.first==3 and seq:pieceAtS(credit)==nil and rawN==3,
				`first {seq.first}; credit {credit}; first arc {seq.starts[seq.first]}; raw piece {rawN}`)
			local after=service:DebugTick()
			local refused=runner(trailId)
			check(`{direction}: unavailable credit cannot fall through to raw reentry`,
				refused.n==earnedN and math.abs(refused.t-earnedT)<1e-5,
				`earned {earnedN}/{earnedT}; after reentry {refused.n}/{refused.t}; raw {rawN}`)
			check(`{direction}: unavailable credit cannot replace leader or progress`,
				after.leaderN==before.leaderN and after.progress.n==before.progress.n and after.furthestN==before.furthestN,
				`leader {before.leaderN}->{after.leaderN}; progress {before.progress.n}->{after.progress.n}`)
			for _=1,5 do service:DebugTick() end
			local held=runner(trailId)
			check(`{direction}: waiting on asphalt earns no missing road`,held.n==earnedN and math.abs(held.t-earnedT)<1e-5,
				`after five stationary ticks {held.n}/{held.t}`)
			-- Ownership/travel were retained even though progress was refused. Once
			-- real travel reaches live credited road, normal capped progress resumes.
			for s=target+5,target+80,5 do put(trailer,s,0);service:DebugTick() end
			local resumed=runner(trailId)
			local resumedS=seq.starts[resumed.n]+resumed.t*sections[resumed.n].len
			local allowed=seq:reentryS(anchor,travel,target+80)
			check(`{direction}: genuine travel resumes at capped live credit`,
				resumed.n>=seq.first and math.abs(resumedS-allowed)<.05 and resumedS<target+79,
				`earned arc {resumedS}; allowance {allowed}; actual arc {target+80}`)
			local recovery=service:SafeStart(lastPosition,{UserId=trailId})
			local recoveryS=recovery and sp:project(recovery.X,recovery.Z,Config.Road.Width)
			local closingS=seq:startOf(before.leaderN-Config.Road.BarrierBehind) or seq:startOf(seq.first)
			check(`{direction}: recovery remains on live road ahead of closing barrier`,recoveryS~=nil and recoveryS>=closingS-.01,
				`recovery {recoveryS}; closing {closingS}`)
			if owned then
				local resetS=seq:piece(before.leaderN).s0+50
				local function roadPose(s)
					return CFrame.new(Vector3.new(sp:terrainXYZ(s,0))+Vector3.yAxis*Config.Drift.RideHeight)
				end
				local placed=carService:Place(player,roadPose(resetS))
				service:DebugTick()
				local reset=runner(trailId)
				local resetArc=seq.starts[reset.n]+reset.t*sections[reset.n].len
				check(`{direction}: actual Place resets prior shortcut debt`,placed~=nil and math.abs(resetArc-resetS)<.05,
					`placed arc {resetS}; earned after placement {resetArc}`)
				carService:DebugBelieve(trailId,roadPose(resetS+20).Position);service:DebugTick()
				local advanced=runner(trailId)
				local advancedArc=seq.starts[advanced.n]+advanced.t*sections[advanced.n].len
				check(`{direction}: normal asphalt advance follows Place`,math.abs(advancedArc-resetS-20)<.05,
					`earned arc {advancedArc}; expected {resetS+20}`)
				-- Respawn uses the actual roster-aware recovery path. Stand down its
				-- cooldown only; no placement, belief or ownership method is mocked.
				local seen=carService.seen[trailId];seen.respawnedAt=nil;seen.respawnCount=0
				carService:DebugBelieve(trailId,roadPose(resetS+20).Position-Vector3.yAxis*100)
				local respawn=carService:Respawn(player)
				service:DebugTick()
				local respawnArc=respawn and sp:project(respawn.X,respawn.Z,Config.Road.Width)
				local recovered=runner(trailId)
				local recoveredArc=seq.starts[recovered.n]+recovered.t*sections[recovered.n].len
				check(`{direction}: actual Respawn resets ownership ahead of barrier`,
					respawnArc~=nil and respawnArc>=closingS-.01 and math.abs(recoveredArc-respawnArc)<.05,
					`spawn arc {respawnArc}; earned {recoveredArc}; closing {closingS}`)
				if respawnArc then carService:DebugBelieve(trailId,roadPose(respawnArc+20).Position);service:DebugTick() end
				local nextRun=runner(trailId)
				local nextArc=seq.starts[nextRun.n]+nextRun.t*sections[nextRun.n].len
				check(`{direction}: normal asphalt advance follows Respawn`,respawnArc~=nil and math.abs(nextArc-respawnArc-20)<.05,
					`earned arc {nextArc}; spawn arc {respawnArc}`)
			end
			service:Stop()
			for _,model in models do model:Destroy() end;table.clear(models)
		end
	end,debug.traceback)
	service:Stop()
	if owned then live:SetMode(oldMode);carService:Place(player,savedPose) end
	for _,model in models do model:Destroy() end
	isolated:Destroy()
	if madeCars then cars:Destroy() end
	Config.Spline.Biomes.GroundEnabled=oldGround
	if not ok then check("integration suite completes",false,err) end
	local passed=0;for _,c in checks do if c.ok then passed+=1 end end
	return {passed=passed,total=#checks,checks=checks,ownedVehicle=owned}
end

return Tests
