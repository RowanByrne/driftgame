--!strict
-- SplineRoadView: the spline road drawn round the car, chunk by chunk, on this device
-- (features/spline-road.md "The mesh, purely visual", T-135).
--
-- The server makes no road parts at all. Each client draws its own copy of the curve as
-- meshes (`Road/SplineMesh`), `ChunkLength` studs at a time, from `Behind` studs behind the
-- car to `Ahead` in front, and takes chunks down as the car leaves them. One chunk is built
-- at a time, nearest the car first, so a frame never pays for more than one.
--
-- A DEVICE THAT CANNOT MAKE A MESH still sees the road: the chunk is drawn as parts instead
-- (`Road/SplineParts`, nothing queryable, tarmac only), and `fallbacks` counts how often.
-- Either way the car drives on the maths, not on anything drawn here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(ReplicatedStorage.Shared.Road.Spline)
local SplineMesh = require(ReplicatedStorage.Shared.Road.SplineMesh)
local SplineParts = require(ReplicatedStorage.Shared.Road.SplineParts)
local SplineBoundary = require(ReplicatedStorage.Shared.Road.SplineBoundary)
local FieldView = require(script.Parent.SplineFieldView)

local SplineRoadView = {}
SplineRoadView.__index = SplineRoadView

export type View = typeof(setmetatable(
	{} :: {
		spline: Spline.Spline,
		folder: Folder,
		chunks: { [number]: Instance },
		building: number?,
		forceFallback: boolean,
		dead: boolean,
		built: number,
		fallbacks: number,
		removed: number,
		lastMs: number,
		worstMs: number,
		lastSliceMs: number, -- the most of the last build any one frame paid (T-193)
		worstSliceMs: number,
		lastSlices: number, -- frames the last build was spread over
		triangles: number,
		lastError: string?,
		closing: BasePart?,
		closingFields: Folder?,
		closingRevision: number?,
		closingFirst: number?,
		closingLaid: number?,
		closingS: number?,
		short: { [number]: number }, -- chunk -> the road's length when it was built short
		rebuilt: number,
		-- THE HILLSIDE (T-190) is drawn from every stretch of road near a chunk, and the leg
		-- below a chunk is often laid after the chunk is drawn. So: the road's length when
		-- each chunk was built, how far the road has been checked against them, and the
		-- chunks new road has come beside since (`stale`), redrawn when nothing else is wanted
		builtAt: { [number]: number },
		checkedTo: number,
		stale: { [number]: boolean },
		redrawn: number,
		fields:any,
		records:{[number]:FieldView.RoadRecord},
		sourceSerial:number,
		residentEpoch:number,
		fieldBuilding:boolean,
		fieldTarget:any,
		captureWanted:number?,
		windowLo:number,
		windowHi:number,
		hasWindow:boolean,
		peakMeshes:number,
		lastPublishMs:number,
		fieldErrorKey:string?,
		fieldRetryStamp:string?,
		chunkRetry:{[number]:string},
		windowHere:number,
		fieldRecoveries:number,
		worstPublishMs:number,
	},
	SplineRoadView
))

function SplineRoadView.new(spline: Spline.Spline, parent: Instance?): View
	local folder = Instance.new("Folder")
	folder.Name = "SplineRoad"
	folder.Parent = parent or Workspace
	return setmetatable({
		spline = spline,
		folder = folder,
		chunks = {},
		building = nil,
		forceFallback = false,
		dead = false,
		built = 0,
		fallbacks = 0,
		removed = 0,
		lastMs = 0,
		worstMs = 0,
		lastSliceMs = 0,
		worstSliceMs = 0,
		lastSlices = 0,
		triangles = 0,
		lastError = nil,
		closing = nil,
		closingFields = nil,
		closingRevision = nil,
		closingFirst = nil,
		closingLaid = nil,
		closingS = nil,
		short = {},
		rebuilt = 0,
		builtAt = {},
		checkedTo = spline.length,
		stale = {},
		redrawn = 0,
		fields=FieldView.new(spline,folder),records={},sourceSerial=0,residentEpoch=0,
		fieldBuilding=false,fieldTarget=nil,captureWanted=nil,windowLo=0,windowHi=0,
		hasWindow=false,peakMeshes=0,lastPublishMs=0,fieldErrorKey=nil,fieldRetryStamp=nil,chunkRetry={},
		windowHere=0,fieldRecoveries=0,worstPublishMs=0,
	}, SplineRoadView)
end

-- A new station can change a face cap or meeting height without shortening its ray.
-- Invalidate any chunk whose gathered station cells gained road, including one still
-- being built. Its old mesh stays up until the replacement is complete.
function SplineRoadView._checkNewRoad(self: View)
	local spline = self.spline
	local from, to = self.checkedTo, spline.length
	if to <= from + 1e-6 then
		return
	end
	self.checkedTo = to
	local H = Config.Spline.Hill
	local L, cell = Config.Spline.Mesh.ChunkLength, spline.cell
	local fresh = {}
	for s = math.floor(from / H.StationStep) * H.StationStep, to, H.StationStep do
		local x, z = spline:planAt(s)
		table.insert(fresh, { math.floor(x / cell), math.floor(z / cell) })
	end
	local candidates: { [number]: boolean } = {}
	for i in self.chunks do
		candidates[i] = true
	end
	if self.building then
		candidates[self.building] = true
	end
	for i in candidates do
		if not self.stale[i] and self.builtAt[i] and self.builtAt[i] < to then
			local s0, s1 = i * L, math.min((i + 1) * L, to)
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			local s = s0
			while true do
				local x, z = spline:planAt(math.min(s, s1))
				minX, maxX = math.min(minX, x), math.max(maxX, x)
				minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
				if s >= s1 then
					break
				end
				s += 16
			end
			local loX, hiX = math.floor((minX - H.DrawGather) / cell), math.floor((maxX + H.DrawGather) / cell)
			local loZ, hiZ = math.floor((minZ - H.DrawGather) / cell), math.floor((maxZ + H.DrawGather) / cell)
			for _, q in fresh do
				if q[1] >= loX and q[1] <= hiX and q[2] >= loZ and q[2] <= hiZ then
					self.stale[i] = true
					break
				end
			end
		end
	end
end
-- THE CLOSING BARRIER (T-136): a wall across the road and its runoff at `s`, the piece
-- road's colour and see-through, drawn here because the server builds nothing.
-- `Drift/SplineWorld` is what makes it solid.
function SplineRoadView.SetClosing(self: View, s: number?)
	self.closingS = s
	self.closingRevision=self.spline.infieldRevision or 0
	self.closingFirst=self.spline.firstSample
	self.closingLaid=self.spline.length
	if self.closingFields then self.closingFields:Destroy();self.closingFields=nil end
	if not s then
		if self.closing then
			self.closing:Destroy()
			self.closing = nil
		end
		return
	end
	local R = Config.Road
	local base=false
	for i,panel in self.spline:closingPanels(s) do
		local p=if not panel.field then self.closing else nil
		if not p then
			p=Instance.new("Part");p.Name=if panel.field then `ClosingField_{i}` else "ClosingBarrier"
			p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
			p.Material=R.BarrierMaterial;p.Color=R.Colours.Closing;p.Transparency=R.BarrierTransparency
			if panel.field then
				if not self.closingFields then local f=Instance.new("Folder");f.Name="ClosingField";f.Parent=self.folder;self.closingFields=f end
				p.Parent=self.closingFields
			else p.Parent=self.folder;self.closing=p end
		end
		local cf,size=SplineBoundary.closingSpec(panel);p.CFrame=cf;p.Size=size
		if not panel.field then base=true end
	end
	if not base and self.closing then self.closing:Destroy();self.closing=nil end
end

-- One shared retirement worker keeps several fallback chunks from each
-- spending a full slice in the same frame. Hidden roots no longer contribute
-- source geometry while their ordinary Parts are released in small batches.
local retireQueue={}
local retiring=false
local stagedRoots=setmetatable({}, {__mode="k"})
local revealedRoots=setmetatable({}, {__mode="k"})
local queuedRoots=setmetatable({}, {__mode="k"})
local function stageRoot(root:Instance,hidden:{BasePart})stagedRoots[root]=hidden end
local function showRoot(root:Instance)
	if revealedRoots[root] then return end
	for _,p in stagedRoots[root] or {} do p.Transparency=0 end
	revealedRoots[root]=true
end
local function removeChunk(chunk:Instance)
	if queuedRoots[chunk] then return end
	queuedRoots[chunk]=true
	local hidden=stagedRoots[chunk]
	if hidden then
		-- The immutable support may overlap its replacement while it drains.
		-- Only the old source-dependent scenery must disappear at this commit.
		if chunk:IsDescendantOf(Workspace) then for _,p in hidden do p.Transparency=1 end end
	else pcall(function()chunk.Parent=nil end) end
	if SplineMesh.owns(chunk) then SplineMesh.release(chunk :: Model) end
	table.insert(retireQueue,chunk)
	if retiring then return end
	retiring=true
	task.defer(function()
		local sliceStart=os.clock()
		local function drain(node:Instance)
			if SplineMesh.owns(node) then SplineMesh.destroy(node :: Model);return end
			if node:IsA("Folder") or node:IsA("Model") then for _,child in node:GetChildren() do drain(child) end end
			node:Destroy()
			stagedRoots[node]=nil
			revealedRoots[node]=nil
			if os.clock()-sliceStart>=Config.Spline.Mesh.SliceMs/1000 then task.wait();sliceStart=os.clock() end
		end
		while #retireQueue>0 do drain(table.remove(retireQueue,1)) end
		retiring=false
	end)
end

function SplineRoadView._job(self:View,i:number?,evictions:{number}?)
	local records=table.clone(self.records)
	local epoch=self.residentEpoch
	local first=self.spline.firstSample*self.spline.step
	local revision=self.spline.infieldRevision or 0
	local index=self.spline.infields
	local forced=self.forceFallback
	local function valid():boolean
		self.peakMeshes=math.max(self.peakMeshes,SplineMesh.liveMeshCount())
		if self.dead or self.folder.Parent==nil or self.residentEpoch~=epoch
			or first~=self.spline.firstSample*self.spline.step or revision~=(self.spline.infieldRevision or 0)
			or index~=self.spline.infields or forced~=self.forceFallback then return false end
		if i and self.hasWindow and (i<self.windowLo or i>self.windowHi) then return false end
		for _,removed in evictions or {} do
			if self.hasWindow and removed>=self.windowLo and removed<=self.windowHi then return false end
		end
		for id,record in records do if not self.records[id] or self.records[id].serial~=record.serial then return false end end
		for id in self.records do if not records[id] then return false end end
		return true
	end
	local sliceStart,worst,slices=os.clock(),0,0
	local function reset()sliceStart=os.clock()end
	local function flush()worst=math.max(worst,(os.clock()-sliceStart)*1000);reset()end
	local function tick()
		if not valid() then error("road field job cancelled",0) end
		if os.clock()-sliceStart>=Config.Spline.Mesh.SliceMs/1000 then
			flush();task.wait();slices+=1;reset()
			if not valid() then error("road field job cancelled",0) end
		end
	end
	return records,valid,tick,flush,reset,function()return worst,slices end
end

local function discardField(record:any)
	if not record then return end
	if record.seams and record.seams.Parent~=record.model then removeChunk(record.seams) end
	removeChunk(record.model)
end

function SplineRoadView._stamp(self:View):string
	local request=self.fields.request
	return `{self.residentEpoch}/{self.spline.length}/{self.spline.firstSample}/{self.spline.infieldRevision or 0}/{self.forceFallback}/{self.windowLo}:{self.windowHi}/{if request then request.key else ""}/{if self.fieldTarget then self.fieldTarget.key else ""}`
end

function SplineRoadView._canStart(self:View,i:number):boolean
	return self.chunkRetry[i]~=self:_stamp()
end

-- A persistent field failure must not strand the player beyond all drawn
-- asphalt. If the current chunk is missing, restart ordinary unmasked drawing;
-- field preparation may retry after the new source map is available.
function SplineRoadView._recoverFieldFailure(self:View)
	if not self.hasWindow or self.chunks[self.windowHere] or not (self.fields.live or self.fieldTarget) then return end
	local old=self.fields.live;self.fields.live=nil;self.fieldTarget=nil
	if old then discardField(old) end
	for _,peer in self.fields.peers do removeChunk(peer.folder) end
	table.clear(self.fields.peers)
	for _,chunk in self.chunks do removeChunk(chunk) end
	table.clear(self.chunks);table.clear(self.records);table.clear(self.builtAt);table.clear(self.short);table.clear(self.stale)
	self.captureWanted=nil;self.residentEpoch+=1;self.fieldRecoveries+=1
end

-- All visible source-dependent layers switch in this non-yielding commit.
-- Parts floor batches may already be present; their immutable physical floor
-- does not depend on the candidate road's cap or mountain source version.
function SplineRoadView._publishField(self:View,field:any,peers:any)
	local old=self.fields.live
	if field~=old then
		if field then
			if field.seams then field.seams.Parent=field.model end
			if field.model.Parent~=self.folder then field.model.Parent=self.folder end
			showRoot(field.model)
		end
		self.fields.live=field
		if old then discardField(old) end
		self.fields.built+=1
	end
	local previous=self.fields.peers
	self.fields.peers=peers
	for _,peer in peers do showRoot(peer.folder) end
	for key,peer in previous do if peers[key]~=peer then removeChunk(peer.folder) end end
end

function SplineRoadView._build(self: View, i: number)
	local L=Config.Spline.Mesh.ChunkLength
	local s0,s1=math.max(i*L,self.spline.firstSample*self.spline.step),math.min((i+1)*L,self.spline.length)
	if s1-s0<1e-6 then return end
	local builtAt=self.spline.length
	local records,valid,tick,flush,reset,measure=self:_job(i)
	local cancelled=function()return not valid()end
	local staging=Instance.new("Folder")
	local chunk:Instance?=nil
	local scenery:Folder?=nil
	local candidateField:any=nil
	local createdPeers={}
	local info:any=nil
	local mesh,committed,fieldChanged=false,false,false
	local began=os.clock()
	local ok,err=xpcall(function()
		local extra=if self.fields.live or self.fieldTarget then 2 else 1
		while not self.forceFallback and SplineMesh.liveMeshCount()+extra>8 do tick();task.wait();reset() end
		local capture=(self.spline.infieldRevision or 0)>0 or self.captureWanted~=nil or self.fields.desired~=nil
		local target=self.fieldTarget
		flush()
		local model,details,hints=SplineMesh.build(self.spline,s0,s1,staging,{forceFail=self.forceFallback,
			fieldPlan=target,captureScenery=capture,cancelled=cancelled})
		reset();info=details
		if not valid() then if model then SplineMesh.destroy(model) end;error("road field job cancelled",0) end
		if model then chunk=model;mesh=true else
			self.fallbacks+=1;self.lastError=tostring(details)
			local folder=Instance.new("Folder");folder.Name=`Chunk_{math.floor(s0)}_parts`;folder:SetAttribute("Fallback",true)
			local hidden={};stageRoot(folder,hidden)
			chunk=folder;folder.Parent=self.folder
			if capture then scenery=Instance.new("Folder");scenery.Name="Scenery";scenery.Parent=folder end
			flush()
			local _,stats=SplineParts.build(self.spline,s0,s1,folder,{terrain=true,queryable=false,barriers=false,
				omitHills=hints and hints.omitHills,fieldPlan=target,captureScenery=capture,sceneryParent=scenery,
				hiddenScenery=hidden,cancelled=cancelled})
			reset();info=stats
		end
		if not valid() then error("road field job cancelled",0) end
		SplineBoundary.build(self.spline,s0,s1,chunk :: Instance,tick,not mesh,not mesh,stagedRoots[chunk :: Instance])
		self.sourceSerial+=1
		local record=table.freeze({model=chunk :: Instance,serial=self.sourceSerial,scenery=info.scenery,mask=target,s0=s0,s1=s1,mesh=mesh})
		local prospective=table.clone(records);prospective[i]=record
		self.fields.forceFallback=self.forceFallback
		local _,cover=self.fields:Coverage(prospective,target,tick)
		fieldChanged=self.fields:NeedsField(cover,prospective)
		if fieldChanged and cover then
			local why
			candidateField,why=self.fields:Build(cover,prospective,staging,tick,cancelled,{incrementalFloor=true,
				floorParent=self.folder,dispose=removeChunk,stageRoot=stageRoot,beforeBuilder=flush,afterBuilder=reset})
			if not candidateField then error(`field companion build failed: {why}`,0) end
		elseif not fieldChanged then candidateField=self.fields.live end
		if not valid() then error("road field job cancelled",0) end
		local peers=self.fields:PreparePeers(cover,prospective,self.folder,tick,cancelled,createdPeers,{stageRoot=stageRoot,beforeBuilder=flush,afterBuilder=reset})
		flush()
		if not valid() then error("road field job cancelled",0) end
		local publishStart=os.clock()
		if (chunk :: Instance).Parent~=self.folder then (chunk :: Instance).Parent=self.folder end
		showRoot(chunk :: Instance)
		local old=self.chunks[i]
		self.chunks[i]=chunk :: Instance;self.records[i]=record;self.residentEpoch+=1
		self.builtAt[i]=builtAt
		self.chunkRetry[i]=nil
		if self.captureWanted==i then self.captureWanted=nil end
		self.stale[i]=if self.spline.length>builtAt+1e-6 then true else nil
		self.short[i]=if s1<(i+1)*L-1e-6 then s1 else nil
		self:_publishField(candidateField,peers)
		if old and old~=chunk then removeChunk(old) end
		self.lastPublishMs=(os.clock()-publishStart)*1000
		self.worstPublishMs=math.max(self.worstPublishMs,self.lastPublishMs)
		committed=true
	end,debug.traceback)
	if not committed then
		if candidateField and candidateField~=self.fields.live then discardField(candidateField) end
		for _,peer in createdPeers do removeChunk(peer) end
		if chunk then removeChunk(chunk) end
	end
	removeChunk(staging)
	if not ok then if valid() then error(err,0) end;return end
	local worst,slices=measure()
	local fieldStats=if fieldChanged and candidateField then candidateField.stats else nil
	self.lastSliceMs=math.max(info.sliceMs or 0,worst,self.lastPublishMs,self.fields.peerWorst or 0,if fieldStats then fieldStats.sliceMs or 0 else 0)
	self.worstSliceMs=math.max(self.worstSliceMs,self.lastSliceMs)
	self.lastSlices=(info.slices or 1)+slices+(if fieldStats then fieldStats.slices or 1 else 0)
	self.triangles+=info.triangles or 0
	self.lastMs=(os.clock()-began)*1000;self.worstMs=math.max(self.worstMs,self.lastMs);self.built+=1
end

function SplineRoadView._fieldJob(self:View,evictions:{number})
	local records,valid,tick,flush,reset,measure=self:_job(nil,evictions)
	local cancelled=function()return not valid()end
	local prospective=table.clone(records)
	for _,i in evictions do prospective[i]=nil end
	local staging=Instance.new("Folder")
	local candidateField:any=nil
	local createdPeers={}
	local committed,changed=false,false
	local ok,err=xpcall(function()
		self.fields.forceFallback=self.forceFallback
		local desired=self.fields:Select(tick)
		local target,cover,draining=self.fields:Coverage(prospective,desired,tick)
		if cover then
			for i,record in prospective do
				if not record.scenery then self.captureWanted=i;return end
			end
		end
		changed=self.fields:NeedsField(cover,prospective)
		if changed and cover then
			while not self.forceFallback and SplineMesh.liveMeshCount()+1>8 do tick();task.wait();reset() end
			local why
			candidateField,why=self.fields:Build(cover,prospective,staging,tick,cancelled,{incrementalFloor=true,
				floorParent=self.folder,dispose=removeChunk,stageRoot=stageRoot,beforeBuilder=flush,afterBuilder=reset})
			if not candidateField then error(`field companion build failed: {why}`,0) end
		elseif not changed then candidateField=self.fields.live end
		if not valid() then error("road field job cancelled",0) end
		local peers=self.fields:PreparePeers(cover,prospective,self.folder,tick,cancelled,createdPeers,{stageRoot=stageRoot,beforeBuilder=flush,afterBuilder=reset})
		flush()
		if not valid() then error("road field job cancelled",0) end
		local publishStart=os.clock()
		self.fieldTarget=target;self.fields.draining=draining
		self:_publishField(candidateField,peers)
		for _,i in evictions do
			local chunk=self.chunks[i]
			self.chunks[i]=nil;self.records[i]=nil;self.short[i]=nil;self.builtAt[i]=nil;self.stale[i]=nil
			if self.captureWanted==i then self.captureWanted=nil end
			if chunk then removeChunk(chunk);self.removed+=1 end
		end
		if #evictions>0 then self.residentEpoch+=1 end
		self.lastPublishMs=(os.clock()-publishStart)*1000
		self.worstPublishMs=math.max(self.worstPublishMs,self.lastPublishMs)
		committed=true
	end,debug.traceback)
	if not committed then
		if candidateField and candidateField~=self.fields.live then discardField(candidateField) end
		for _,peer in createdPeers do removeChunk(peer) end
	end
	removeChunk(staging)
	if not ok then if valid() then error(err,0) end;return end
	if committed then
		local worst,slices=measure()
		local stats=if changed and candidateField then candidateField.stats else nil
		self.lastSliceMs=math.max(worst,self.lastPublishMs,self.fields.peerWorst or 0,if stats then stats.sliceMs or 0 else 0)
		self.worstSliceMs=math.max(self.worstSliceMs,self.lastSliceMs)
		self.lastSlices=slices+(if stats then stats.slices or 1 else 0)
	end
end

function SplineRoadView._startField(self:View,evictions:{number}?)
	if self.building or self.fieldBuilding or self.dead or self.fieldRetryStamp==self:_stamp() then return false end
	local stamp=self:_stamp()
	self.fieldBuilding=true
	task.spawn(function()
		local ok,err=pcall(self._fieldJob,self,evictions or {})
		if not ok and not self.dead then
			self.lastError=tostring(err)
			self.fieldRetryStamp=stamp
			self:_recoverFieldFailure()
			if self.fieldErrorKey~=self.lastError then warn(`[SplineRoadView] field failed: {err}`);self.fieldErrorKey=self.lastError end
		end
		self.fieldBuilding=false
	end)
	return true
end

-- Keep the chunks round `s` (the car's distance along the road) and no others.
function SplineRoadView.Update(self: View, s: number?,position:Vector3?)
	if self.dead then
		return
	end
	if self.closingRevision~=(self.spline.infieldRevision or 0) or self.closingFirst~=self.spline.firstSample
		or (self.closingS and (self.closingLaid or 0)<self.closingS and self.spline.length>=self.closingS) then self:SetClosing(self.closingS) end
	local M = Config.Spline.Mesh
	local L = M.ChunkLength
	local at = s or 0
	local last = math.max(0, math.ceil(self.spline.length / L) - 1)
	local lo=math.clamp(math.max(math.floor((at-M.Behind)/L),math.floor(self.spline.firstSample*self.spline.step/L)),0,last)
	local hi=math.max(lo,math.clamp(math.floor((at+M.Ahead)/L),0,last))
	self.windowLo=lo;self.windowHi=hi;self.hasWindow=true
	self.windowHere=math.clamp(math.floor(at/L),lo,hi)
	local index=self.spline.infields
	if index and next(index.patches) or self.fields.live or self.fieldTarget then self.fields:Request(at,position) end
	self.fields.forceFallback=self.forceFallback
	self:_checkNewRoad()
	if self.building or self.fieldBuilding then return end
	local evictions={};local masked=false
	for i in self.chunks do if i<lo or i>hi then table.insert(evictions,i) end end
	for _,record in self.records do if record.mask then masked=true;break end end
	if #evictions>0 then
		if self.fields.live or masked then self:_startField(evictions);return end
		for _,i in evictions do
			removeChunk(self.chunks[i]);self.chunks[i]=nil;self.records[i]=nil;self.short[i]=nil;self.builtAt[i]=nil;self.stale[i]=nil
			self.removed+=1
		end
		self.residentEpoch+=1
	end
	-- nearest the car first: the chunk it is in, then ahead, then behind
	local here = math.clamp(math.floor(at / L), lo, hi)
	local want: number? = nil
	for i = here, hi do
		if not self.chunks[i] and self:_canStart(i) then
			want = i
			break
		end
	end
	if not want then
		for i = here - 1, lo, -1 do
			if not self.chunks[i] and self:_canStart(i) then
				want = i
				break
			end
		end
	end
	if want then
		self:_start(want :: number)
		return
	end
	local capture=self.captureWanted
	if capture then
		if self.records[capture] and not self.records[capture].scenery then
			if self:_canStart(capture) then self:_start(capture);return end
		else self.captureWanted=nil end
	end
	local request=self.fields.request
	if request and (self.fields.cachedKey~=request.key or self.fields.cachedIndex~=request.index) then
		if self:_startField() then return end
	end
	local maskStale:number?=nil
	for i,record in self.records do
		if not FieldView.equal(record.mask,self.fieldTarget) and self:_canStart(i)
			and (not maskStale or math.abs(i-here)<math.abs(maskStale-here)) then maskStale=i end
	end
	if maskStale then self:_start(maskStale);return end
	local live=self.fields.live
	if request and (self.fields.cachedKey~=request.key or self.fields.cachedIndex~=request.index
		or not FieldView.equal(self.fields.desired,self.fieldTarget)
		or self.fields:NeedsField(live and live.plan,self.records)) then
		if self:_startField() then return end
	end
	-- A short chunk grows only after its complete paired replacement is ready.
	for i,builtTo in self.short do
		if self.spline.length>builtTo+1e-6 and self.chunks[i] and self:_canStart(i) then
			self.rebuilt+=1;self:_start(i);return
		end
	end
	-- nothing missing: redraw a chunk new road has come beside (T-190), nearest the car
	-- first. The old one stays up until the new one is whole
	-- (not one still far ahead: more road will come beside it before the car does, and it
	-- would be redrawn for each stretch of it)
	local best: number? = nil
	for i in self.stale do
		if self.chunks[i] and self:_canStart(i) and i * L <= at + M.RedrawWithin and (not best or math.abs(i - here) < math.abs(best - here)) then
			best = i
		end
	end
	if best then
		self.redrawn += 1
		self:_start(best)
	end
end

-- Build chunk `i` in its own thread: it takes a few frames (T-193).
function SplineRoadView._start(self: View, i: number)
	if self.dead or self.building or self.fieldBuilding or not self:_canStart(i) then return false end
	local stamp=self:_stamp()
	self.building = i
	task.spawn(function()
		local ok, err = pcall(self._build, self, i)
		if not ok then
			self.lastError = tostring(err)
			self.chunkRetry[i]=stamp
			if not self.dead then self:_recoverFieldFailure() end
			warn(`[SplineRoadView] chunk {i} failed: {err}`)
		end
		self.building = nil
	end)
	return true
end

function SplineRoadView.Destroy(self: View)
	self.dead = true
	self.closing = nil
	table.clear(self.chunks)
	table.clear(self.records)
	self.fields.live=nil;table.clear(self.fields.peers)
	local folder=self.folder
	-- A stopped/replaced run cannot leave the old run's support visible. This
	-- full teardown is distinct from same-spline, immutable-support replacement.
	folder.Parent=nil
	-- Give the next view its EditableMesh slots before any fallback drain yields.
	for _,child in folder:GetChildren() do removeChunk(child) end
	stageRoot(folder,{});removeChunk(folder)
end

function SplineRoadView.DebugState(self: View)
	local n, meshes, parts = 0, 0, 0
	for _, chunk in self.chunks do
		n += 1
		if chunk:IsA("Model") then
			meshes += 1
		else
			parts += #chunk:GetDescendants()
		end
	end
	return {
		fieldBuilding=self.fieldBuilding,
		fieldRecoveries=self.fieldRecoveries,
		fieldMeshes=if self.fields.live and self.fields.live.mesh then 1 else 0,
		fieldBuilt=self.fields.built,
		fieldFallbacks=self.fields.fallbacks,
		fieldDraining=self.fields.draining,
		fieldTarget=self.fieldTarget and self.fieldTarget.key,
		fieldCoverage=self.fields.live and self.fields.live.plan.key,
		liveMeshes=SplineMesh.liveMeshCount(),peakMeshes=self.peakMeshes,
		lastPublishMs=self.lastPublishMs,worstPublishMs=self.worstPublishMs,
		retiringRoots=#retireQueue+(if retiring then 1 else 0),
		chunks = n,
		meshChunks = meshes,
		fallbackParts = parts,
		built = self.built,
		removed = self.removed,
		fallbacks = self.fallbacks,
		building = self.building,
		lastMs = self.lastMs,
		worstMs = self.worstMs,
		lastSliceMs = self.lastSliceMs,
		worstSliceMs = self.worstSliceMs,
		lastSlices = self.lastSlices,
		trianglesBuilt = self.triangles,
		forceFallback = self.forceFallback,
		lastError = self.lastError,
		closingS = self.closingS,
		rebuilt = self.rebuilt,
		redrawn = self.redrawn, -- chunks redrawn because new road came beside them (T-190)
		length = self.spline.length,
	}
end

return SplineRoadView
