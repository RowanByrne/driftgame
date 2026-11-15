--!strict
-- Complete field coverage and seams from the road chunks actually on screen.
-- The road view owns the single job/commit lock and all chunk source serials.
local Config=require(game.ReplicatedStorage.Shared.Config)
local Infield=require(game.ReplicatedStorage.Shared.Road.SplineInfield)
local Cuts=require(game.ReplicatedStorage.Shared.Road.SplineFieldCuts)
local Mesh=require(game.ReplicatedStorage.Shared.Road.SplineMesh)
local Parts=require(game.ReplicatedStorage.Shared.Road.SplineParts)
local Boundary=require(game.ReplicatedStorage.Shared.Road.SplineBoundary)
local FieldView={}
FieldView.__index=FieldView

export type RoadRecord={model:Instance,serial:number,scenery:{any}?,mask:any,s0:number,s1:number,mesh:boolean}
export type FieldRecord={model:Model,mesh:boolean,plan:any,sources:{[number]:number},seams:Folder?,stats:any,forced:boolean}
export type View=any

function FieldView.new(spline:any,parent:Instance):View
	return setmetatable({spline=spline,parent=parent,request=nil,cachedKey=nil,cachedIndex=nil,desired=nil,
		live=nil,peers={},forceFallback=false,lastError=nil,built=0,fallbacks=0,draining=false},FieldView)
end

function FieldView.Request(self:View,s:number,position:Vector3?)
	local index=self.spline.infields
	local first=self.spline.firstSample*self.spline.step
	local p=position or Vector3.new(self.spline:surfaceXYZ(s,0))
	local C=Config.Spline.Biomes.Infield.View
	local floor=if index then Infield.sample(index,p.X,p.Z) else nil
	local key=`{math.floor(p.X/C.Cell)}:{math.floor(p.Z/C.Cell)}:{self.spline.infieldRevision or 0}:{first}:{if floor then floor.patch else ""}`
	if not self.request or self.request.key~=key or self.request.index~=index then
		self.request=table.freeze({key=key,index=index,x=p.X,z=p.Z,first=first,
			revision=self.spline.infieldRevision or 0,patch=if floor then floor.patch else nil})
	end
end

function FieldView.Select(self:View,tick:()->()):any
	local request=self.request
	if not request then return nil end
	if self.cachedKey==request.key and self.cachedIndex==request.index then return self.desired end
	local index=request.index
	if not index or not next(index.patches) then
		self.cachedKey=request.key;self.cachedIndex=index;self.desired=nil;return nil
	end
	local C=Config.Spline.Biomes.Infield.View
	local distances=Infield.nearPatches(index,request.x,request.z,C.Radius,request.first,tick)
	local ids={};for id in distances do table.insert(ids,id) end
	table.sort(ids,function(a,b)
		if (a==request.patch)~=(b==request.patch) then return a==request.patch end
		if distances[a]~=distances[b] then return distances[a]<distances[b] end
		return a<b
	end)
	local selection={};local desired=nil;local count=0
	for _,id in ids do
		if count>=C.MaxPatches then break end
		local trial=table.clone(selection);trial[id]=true
		local plan,why=Cuts.plan(index,trial,request.first,request.revision,{tick=tick})
		if plan then selection=trial;desired=plan;count+=1
		elseif id==request.patch then error(`current field coverage unavailable: {why}`) end
		tick()
	end
	self.cachedKey=request.key;self.cachedIndex=index;self.desired=desired
	return desired
end

local function equal(a:any,b:any):boolean
	return a==b or a~=nil and b~=nil and a.identity==b.identity and a.key==b.key
end
FieldView.equal=equal

-- A rolling mask change needs the union of every prospective live chunk mask.
-- Its retained first is in distance units and covers both retirement versions.
function FieldView.Coverage(self:View,records:{[number]:RoadRecord},desired:any,tick:()->()):(any,any,boolean)
	local function union(target:any):(any,string?)
		local ids={};local first=math.huge;local index=self.spline.infields;local revision=0
		local function include(plan:any)
			if not plan then return end
			assert(plan.identity==index,"field mask belongs to another road")
			first=math.min(first,plan.first);revision=math.max(revision,plan.revision)
			for id in plan.selection do ids[id]=true end
		end
		include(target);for _,record in records do include(record.mask) end
		if not next(ids) then return nil,nil end
		return Cuts.plan(index,ids,first,revision,{tick=tick})
	end
	local cover,why=union(desired)
	if why then
		-- Restore old masks first when two distant complete fields cannot share
		-- one legal-size mesh. The queued desired coverage is kept intact.
		local old,oldWhy=union(nil)
		if oldWhy then error(`live field coverage unavailable: {oldWhy}`) end
		return nil,old,true
	end
	return desired,cover,false
end

function FieldView.NeedsField(self:View,plan:any,records:{[number]:RoadRecord}):boolean
	local live=self.live
	if not equal(live and live.plan,plan) then return true end
	if not live then return false end
	if live.model and live.model.Parent~=self.parent then return true end
	if live.forced~=nil and live.forced~=self.forceFallback then return true end
	for id,record in records do if live.sources[id]~=record.serial then return true end end
	for id in live.sources do if not records[id] then return true end end
	return false
end

local function merge(intervals:{any}):{any}
	table.sort(intervals,function(a,b)return a[1]<b[1] end)
	local out={}
	for _,span in intervals do
		local previous=out[#out]
		if previous and span[1]<=previous[2]+1e-6 then previous[2]=math.max(previous[2],span[2])
		else table.insert(out,{span[1],span[2]}) end
	end
	return out
end

-- Both attached arms remain visible even when their arc distance is outside
-- the main road window. Only fully published main intervals suppress a peer.
function FieldView.PeerIntervals(plan:any,records:{[number]:RoadRecord},retainedFirst:number?):{any}
	if not plan then return {} end
	local firstLive=math.max(plan.first,retainedFirst or plan.first)
	local attached={};local covered={}
	for _,item in plan.context.patches do
		local rows=item.patch.rows;local first,last=rows[1],rows[#rows]
		for _,span in {{first.sa,last.sa},{last.sb,first.sb}} do
			local a,b=math.max(span[1],firstLive),span[2]
			if b-a>1e-6 then table.insert(attached,{a,b}) end
		end
	end
	for _,record in records do table.insert(covered,{record.s0,record.s1}) end
	covered=merge(covered)
	local out={}
	for _,span in merge(attached) do
		local cursor=span[1]
		for _,main in covered do
			if main[2]<=cursor or main[1]>=span[2] then continue end
			if main[1]>cursor+1e-6 then table.insert(out,{cursor,math.min(main[1],span[2])}) end
			cursor=math.min(span[2],math.max(cursor,main[2]))
		end
		if cursor<span[2]-1e-6 then table.insert(out,{cursor,span[2]}) end
	end
	return out
end

function FieldView.PreparePeers(self:View,plan:any,records:{[number]:RoadRecord},parent:Instance,tick:()->(),cancelled:()->boolean,created:{Instance},options:any?):any
	local o=options or {}
	local prepared={}
	for _,span in FieldView.PeerIntervals(plan,records,self.spline.firstSample*self.spline.step) do
		-- Chunk-aligned ownership avoids rebuilding an entire opposite arm
		-- whenever one ordinary chunk arrives or leaves.
		local s=span[1];local length=Config.Spline.Mesh.ChunkLength
		while s<span[2]-1e-6 do
			local last=math.min(span[2],(math.floor(s/length)+1)*length)
			if last-s<1e-6 then last=math.min(span[2],last+length) end
			local key=`{s}:{last}:{self.spline.infieldRevision or 0}`
			local old=self.peers[key]
			if old and old.folder.Parent==parent then prepared[key]=old else
				local folder=Instance.new("Folder");folder.Name="FieldPeerRoad";folder:SetAttribute("S0",s);folder:SetAttribute("S1",last)
				if o.stageRoot then o.stageRoot(folder,{}) end
				table.insert(created,folder);folder.Parent=parent
				if o.beforeBuilder then o.beforeBuilder() end
				local parts,info=Parts.build(self.spline,s,last,folder,{terrain=true,groundOnly=true,cancelled=cancelled})
				if o.afterBuilder then o.afterBuilder() end
				self.peerWorst=math.max(self.peerWorst or 0,info.sliceMs or 0)
				Boundary.build(self.spline,s,last,folder,tick,true,true)
				tick()
				prepared[key]={folder=folder,s0=s,s1=last,parts=#parts,triangles=info.triangles}
			end
			s=last;tick()
		end
	end
	return prepared
end

-- Source records are immutable snapshots. A later append does not change the
-- geometry this field must meet; a later chunk publication has a new serial.
function FieldView.Build(self:View,plan:any,records:{[number]:RoadRecord},parent:Instance,tick:()->(),cancelled:()->boolean,options:any?):(FieldRecord?,string?)
	if not plan then return nil,nil end
	local o=options or {}
	local forced=self.forceFallback
	local capture=Cuts.newCapture(Cuts.forBuild(plan,tick));local sources={};local ids={}
	for id in records do table.insert(ids,id) end;table.sort(ids)
	for _,id in ids do
		local record=records[id]
		if not record.scenery then return nil,"field source capture is not ready" end
		sources[id]=record.serial
		for i,source in record.scenery do
			local p=source.points;local ok,why=Cuts.capture(capture,p[1],p[2],p[3],source.material)
			if not ok then return nil,why end
			if i%128==0 then tick() end
		end
	end
	local seams,why=Cuts.stitch(capture);if not seams then return nil,why end
	tick()
	if o.beforeBuilder then o.beforeBuilder() end
	local model,info=Mesh.buildInfield(self.spline,0,0,1,parent,{plan=plan,first=plan.first,seams=seams,
		forceFail=forced,cancelled=cancelled})
	if o.afterBuilder then o.afterBuilder() end
	local mesh=model~=nil
	local seamParent:Folder?=nil
	if not model then
		if cancelled() then return nil,"field build cancelled" end
		self.fallbacks+=1
		if o.beforeBuilder then o.beforeBuilder() end
		model,info=Parts.buildInfield(self.spline,0,0,1,o.floorParent or parent,{plan=plan,first=plan.first,seams=seams,cancelled=cancelled,
			incrementalFloor=o.incrementalFloor,hiddenSeams=o.incrementalFloor,onModel=o.stageRoot,dispose=o.dispose})
		if o.afterBuilder then o.afterBuilder() end
	end
	if not model then
		if seamParent then if o.dispose then o.dispose(seamParent) else seamParent:Destroy() end end
		return nil,tostring(info)
	end
	return {model=model,mesh=mesh,plan=plan,sources=table.freeze(sources),seams=seamParent,stats=info,forced=forced},nil
end

return FieldView
