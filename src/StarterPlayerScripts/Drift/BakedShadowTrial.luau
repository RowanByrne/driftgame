--!strict
-- T-214 trial maths/readback only. No services, instances, uploads or game state.
local Trial = {}

function Trial.summary(values: {number})
	local sorted = table.clone(values)
	table.sort(sorted)
	local sum = 0
	for _, v in sorted do sum += v end
	return {n=#sorted, mean=if #sorted>0 then sum/#sorted else 0,
		p95=sorted[math.max(1,math.ceil(#sorted*.95))] or 0, max=sorted[#sorted] or 0}
end

-- A deliberately one-sided, notched silhouette. Its shadow distinguishes the
-- visible triangles from a bounding box. Four ordinary thin Parts form a control.
function Trial.panel()
	local points, triangles = {}, {}
	for i, height in {10,25,14,22} do
		local z = (i-1)*10-20
		local n = #points
		table.insert(points,Vector3.new(0,0,z))
		table.insert(points,Vector3.new(0,height,z))
		table.insert(points,Vector3.new(0,height,z+10))
		table.insert(points,Vector3.new(0,0,z+10))
		table.insert(triangles,{n+1,n+2,n+3})
		table.insert(triangles,{n+1,n+3,n+4})
	end
	return points, triangles
end

function Trial.snapshot(mesh: EditableMesh, tick: (() -> ())?)
	local low,high=Vector3.one*math.huge,-Vector3.one*math.huge
	local uvLow,uvHigh=Vector2.one*math.huge,-Vector2.one*math.huge
	local positions, corners, triangles={},{},{}
	for vi,id in mesh:GetVertices() do
		local p=mesh:GetPosition(id);positions[id]=p;low=low:Min(p);high=high:Max(p)
		if tick and vi%500==0 then tick()end
	end
	local normalError=0
	for fi,f in mesh:GetFaces() do
		local vs,ns,us,cs=mesh:GetFaceVertices(f),mesh:GetFaceNormals(f),mesh:GetFaceUVs(f),mesh:GetFaceColors(f)
		local triangle={}
		for i,v in vs do
			local uv=mesh:GetUV(us[i]);uvLow=Vector2.new(math.min(uvLow.X,uv.X),math.min(uvLow.Y,uv.Y));uvHigh=Vector2.new(math.max(uvHigh.X,uv.X),math.max(uvHigh.Y,uv.Y))
			local normal=mesh:GetNormal(ns[i]);normalError=math.max(normalError,math.abs(normal.Magnitude-1))
			local corner={p=positions[v],n=normal,uv=uv,c=mesh:GetColor(cs[i]),a=mesh:GetColorAlpha(cs[i])}
			table.insert(corners,corner);table.insert(triangle,corner)
		end
		table.insert(triangles,triangle)
		if tick and fi%500==0 then tick()end
	end
	return {low=low,high=high,uvLow=uvLow,uvHigh=uvHigh,normalError=normalError,
		vertices=#mesh:GetVertices(),faces=#mesh:GetFaces(),corners=corners,triangles=triangles}
end

-- IDs and shared vertex counts can change during static conversion. Compare
-- whole oriented triangle triples modulo cyclic rotation. A reversal is NOT
-- equivalent, and each baked triangle may satisfy only one source triangle.
function Trial.compare(a, b, tick: (() -> ())?)
	local bins,used={},{}
	-- A corner displacement <= .02 also moves its triangle's centroid <= .02.
	-- A .04 cell and its immediate neighbours therefore cover the full tolerance.
	local function cell(triangle)
		local p=(triangle[1].p+triangle[2].p+triangle[3].p)/3
		return math.floor(p.X/.04),math.floor(p.Y/.04),math.floor(p.Z/.04)
	end
	for fi,triangle in b.triangles do
		local x,y,z=cell(triangle);local k=`{x}:{y}:{z}`
		bins[k]=bins[k] or {};table.insert(bins[k],fi)
		if tick and fi%500==0 then tick()end
	end
	local position,normal,uv,colour,missing,matched,comparisons=0,0,0,0,0,0,0
	for fi,triangle in a.triangles do
		local x,y,z=cell(triangle)
		local best,errors,score=nil,nil,math.huge
		for dx=-1,1 do for dy=-1,1 do for dz=-1,1 do
			for _,candidate in bins[`{x+dx}:{y+dy}:{z+dz}`] or {} do
				comparisons+=1;if tick and comparisons%500==0 then tick()end
				if used[candidate] then continue end
				local other=b.triangles[candidate]
				for rotation=0,2 do
					local pe,ne,ue,ce=0,0,0,0
					for i,v in triangle do
						local w=other[(i+rotation-1)%3+1]
						pe=math.max(pe,(v.p-w.p).Magnitude)
						ne=math.max(ne,(v.n-w.n).Magnitude)
						ue=math.max(ue,(v.uv-w.uv).Magnitude)
						ce=math.max(ce,math.abs(v.c.R-w.c.R),math.abs(v.c.G-w.c.G),math.abs(v.c.B-w.c.B),math.abs(v.a-w.a))
					end
					if pe>.02 or ne>.001 or ue>.001 or ce>.005 then continue end
					local cost=pe+ne+ue+ce
					if cost<score then score,best,errors=cost,candidate,{pe,ne,ue,ce} end
				end
			end
		end end end
		if best then
			used[best]=true;matched+=1
			position=math.max(position,errors[1]);normal=math.max(normal,errors[2])
			uv=math.max(uv,errors[3]);colour=math.max(colour,errors[4])
		else missing+=1 end
		if tick and fi%500==0 then tick()end
	end
	return {facesBefore=a.faces,facesAfter=b.faces,verticesBefore=a.vertices,verticesAfter=b.vertices,
		corners=#a.corners,matchedTriangles=matched,missing=missing,missingTriangles=missing,unmatchedTriangles=#b.triangles-matched,
		position=position,normal=normal,uv=uv,colour=colour,
		bounds=math.max((a.low-b.low).Magnitude,(a.high-b.high).Magnitude),
		uvBounds=math.max((a.uvLow-b.uvLow).Magnitude,(a.uvHigh-b.uvHigh).Magnitude),
		pass=a.faces==b.faces and missing==0 and matched==#b.triangles}
end

-- One opt-in session owns its resources. A job is acquired BEFORE scheduling,
-- and holds all sources through native calls and instrumentation waits. Cancel
-- stops publication immediately; native work cannot itself be cancelled.
local Lifetime = {}
Lifetime.__index = Lifetime
local Job = {}
Job.__index = Job

function Trial.lifetime(onDrained: (() -> ())?): any
	return setmetatable({closed=false,drained=false,jobs=0,pending=0,operations={},resources={},errors={},onDrained=onDrained},Lifetime)
end

function Lifetime.own(self:any,value:any,kind:string,dispose:any,order:number?):any
	if value~=nil then
		assert(not self.drained,"trial already drained")
		local previous=self.resources[value]
		if previous then
			assert(kind=="content" and previous.kind==kind,"trial resource already owned")
			previous.references+=1 -- a native implementation may deduplicate static Content
		else self.resources[value]={value=value,kind=kind,dispose=dispose,order=order or 0,references=1} end
	end
	return value
end

function Lifetime.drop(self:any,value:any)
	local entry=self.resources[value]
	if not entry then return end
	if entry.references>1 then entry.references-=1;return end
	self.resources[value]=nil -- remove ownership before a possibly failing destructor
	if entry.dispose then
		local ok,err=pcall(entry.dispose,entry.value)
		if not ok then table.insert(self.errors,tostring(err)) end
	end
	entry.value=nil
end

function Lifetime.drain(self:any)
	if not self.closed or self.jobs~=0 or self.drained then return end
	assert(self.pending==0,"native operation outlived its job")
	local ordered={}
	for _,entry in self.resources do table.insert(ordered,entry) end
	table.sort(ordered,function(a,b)return a.order<b.order end)
	for _,entry in ordered do entry.references=1;self:drop(entry.value) end
	self.drained=true
	local callback=self.onDrained;self.onDrained=nil
	if callback then local ok,err=pcall(callback);if not ok then table.insert(self.errors,tostring(err)) end end
end

function Lifetime.cancel(self:any)
	self.closed=true
	self:drain()
end

function Lifetime.begin(self:any):any
	assert(not self.closed,"trial cancelled")
	self.jobs+=1
	return setmetatable({scope=self,finished=false},Job)
end

function Lifetime.describe(self:any):any
	local counts={}
	for _,entry in self.resources do counts[entry.kind]=(counts[entry.kind] or 0)+1 end
	return {closed=self.closed,drained=self.drained,jobs=self.jobs,pending=self.pending,operations=table.clone(self.operations),owned=counts,errors=table.clone(self.errors)}
end

function Job.check(self:any)
	assert(not self.finished and not self.scope.closed,"trial cancelled")
end

function Job.finish(self:any)
	if self.finished then return end
	self.finished=true;self.scope.jobs-=1;self.scope:drain()
end

-- `returned` identifies the owned native return (1 for mesh/part, 2 for opaque
-- content). Register it before any following wait, even on the stale path.
function Job.await(self:any,label:string,fn:any,returned:any?):...any
	self:check()
	local scope=self.scope
	scope.pending+=1
	scope.operations[label]=(scope.operations[label] or 0)+1
	local result=table.pack(pcall(fn))
	scope.pending-=1
	scope.operations[label]-=1
	if scope.operations[label]==0 then scope.operations[label]=nil end
	local value=if result[1] and returned then result[returned.index+1] else nil
	if value~=nil then scope:own(value,returned.kind,returned.dispose,returned.order) end
	if scope.closed then
		if value~=nil then scope:drop(value) end
		table.clear(result)
		error(`trial cancelled at {label}`,0)
	end
	if not result[1] then error(result[2],0) end
	return table.unpack(result,2,result.n)
end

function Trial.runJob(job:any,fn:any):(boolean,any)
	local ok,result=xpcall(function()job:check();return fn(job)end,debug.traceback)
	job:finish()
	return ok,result
end

-- The production bake sequence also runs against suspended fake native calls.
-- Neither configure nor publication can happen before the post-await guard.
function Trial.bake(job:any,api:any,content:any,inject:string?):(any,any,string?)
	local static,part
	local ok,err=xpcall(function()
		local result
		result,static=api.convert(content)
		assert(api.valid(result,static),`conversion failed: {result}`)
		job:check()
		if inject=="afterConvert" then error("trial cancelled after convert") end
		part=api.create(static)
		job:check()
		if inject=="afterCreate" then error("trial cancelled after create") end
		api.configure(part)
	end,debug.traceback)
	if not ok then
		if part then job.scope:drop(part) end
		if static then job.scope:drop(static) end
		return nil,nil,tostring(err)
	end
	return part,static,nil
end

-- No DataModel/native calls: deterministic suspended-call regressions using the
-- same lease, native-return registration and bake sequence as the controller.
function Trial.runCancellationTests():any
	local checks={}
	local function check(name:string,ok:boolean,detail:any?)
		table.insert(checks,{name=name,ok=ok,detail=detail})
	end
	local function resource(name:string):any
		return {name=name,alive=true,destroys=0}
	end
	local function destroy(value:any)
		value.destroys+=1;assert(value.destroys==1,`double destroy {value.name}`);value.alive=false
	end
	for _,stage in {"panelMesh","panelPart","sourceBuild","clone","convert","bakedPart","readback"} do
		for _,fails in {false,true} do
			local scope=Trial.lifetime();local source=resource("source");local image=resource("borrowedImage")
			scope:own(source,"editable",destroy,2)
			local output=resource("native return");local configured,published=0,0
			local job=scope:begin() -- a queued job already protects its inputs
			local thread=coroutine.create(function()
				return Trial.runJob(job,function()
					job:await(stage,function()
						coroutine.yield("pending")
						assert(source.alive and image.alive,"source freed during native await")
						if fails then error("native failure") end
						return output
					end,{index=1,kind="part",dispose=destroy,order=0})
					configured+=1;published+=1
				end)
			end)
			local started,waiting=coroutine.resume(thread)
			local visible,on=true,true;visible=false;on=false;scope:cancel();scope:cancel()
			check(`{stage} {fails}: pending source retained and immediately hidden`,started and waiting=="pending" and scope.pending==1 and source.alive and not visible and not on)
			local resumed,ok=coroutine.resume(thread)
			check(`{stage} {fails}: stale drain exactly once`,resumed and ok==false and scope.drained and scope.jobs==0 and scope.pending==0 and source.destroys==1 and output.destroys==(if fails then 0 else 1) and configured==0 and published==0 and image.destroys==0 and next(scope.resources)==nil and #scope.errors==0)
		end
	end
	for _,stopAt in {"convert","create","configureFailure","success","badStatus","createFailure"} do
		local scope=Trial.lifetime();local source=resource("source");scope:own(source,"source",destroy,1)
		local static,part=resource("content"),resource("part");local configured=0
		local job=scope:begin()
		local thread=coroutine.create(function()
			return Trial.runJob(job,function()
				local p,c,why=Trial.bake(job,{
					convert=function()
						return job:await("convert",function()
							if stopAt=="convert" then coroutine.yield("pending") end
							assert(source.alive);return stopAt~="badStatus",static
						end,{index=2,kind="content",dispose=destroy,order=3})
					end,
					create=function()
						return job:await("create",function()
							if stopAt=="create" then coroutine.yield("pending") end
							assert(source.alive and static.alive)
							if stopAt=="createFailure" then error("native failure") end
							return part
						end,{index=1,kind="part",dispose=destroy,order=0})
					end,
					valid=function(result:any)return result==true end,
					configure=function()
						assert(source.alive);configured+=1
						if stopAt=="configureFailure" then error("partial configure failure") end
					end,
				},source)
				if stopAt=="success" then assert(p==part and c==static and why==nil) else assert(p==nil and c==nil and why~=nil) end
			end)
		end)
		local resumed,waiting=coroutine.resume(thread)
		if waiting=="pending" then scope:cancel();resumed=coroutine.resume(thread) end
		scope:cancel()
		check(`bake sequence {stopAt}`,resumed and scope.drained and source.destroys==1 and static.destroys==1 and part.destroys==(if stopAt=="create" or stopAt=="configureFailure" or stopAt=="success" then 1 else 0) and configured==(if stopAt=="configureFailure" or stopAt=="success" then 1 else 0) and #scope.errors==0 and next(scope.resources)==nil)
	end
	local scope=Trial.lifetime();local source=resource("shared terrain source");scope:own(source,"source",destroy,1)
	local terrain,measure=scope:begin(),scope:begin();scope:cancel();terrain:finish()
	check("two queued/overlapping jobs retain common source until final drain",source.alive and scope.jobs==1 and not scope.drained)
	measure:finish();measure:finish();scope:cancel()
	check("queued jobs and repeated stop release once",source.destroys==1 and scope.drained and scope.jobs==0)
	local overlap=Trial.lifetime();local common=resource("overlapping source");local outputs={resource("terrain part"),resource("measure part")}
	overlap:own(common,"source",function(value:any)
		assert(not outputs[1].alive and not outputs[2].alive,"source released before consumers")
		destroy(value)
	end,1)
	local threads={}
	for i=1,2 do
		local lease=overlap:begin()
		threads[i]=coroutine.create(function()
			return Trial.runJob(lease,function()
				lease:await(`overlap{i}`,function()
					coroutine.yield("pending");assert(common.alive);return outputs[i]
				end,{index=1,kind="part",dispose=destroy,order=0})
				error("stale output escaped guard")
			end)
		end)
		assert(coroutine.resume(threads[i]))
	end
	overlap:cancel();assert(coroutine.resume(threads[1]))
	check("overlapping pending native calls retain shared source after first return",common.alive and overlap.jobs==1 and overlap.pending==1 and outputs[1].destroys==1)
	assert(coroutine.resume(threads[2]))
	check("overlapping pending native calls drain consumers before source",overlap.drained and common.destroys==1 and outputs[2].destroys==1 and #overlap.errors==0)
	local tail=Trial.lifetime();local tailSource=resource("instrument source");local tailPart=resource("instrument part")
	tail:own(tailSource,"source",destroy,1);local lease=tail:begin();local configured=0
	local thread=coroutine.create(function()
		return Trial.runJob(lease,function()
			lease:await("returned",function()return tailPart end,{index=1,kind="part",dispose=destroy,order=0})
			coroutine.yield("instrumentation");lease:check();configured+=1
		end)
	end)
	assert(coroutine.resume(thread));tail:cancel()
	check("post-native instrumentation wait retains registered output and source",tailSource.alive and tailPart.alive and tail.pending==0 and tail.jobs==1)
	assert(coroutine.resume(thread))
	check("post-native stop prevents configure and drains registered return",tail.drained and tailSource.destroys==1 and tailPart.destroys==1 and configured==0)
	local failedCleanup=Trial.lifetime(function()error("observer failure")end)
	local survivor=resource("later cleanup");failedCleanup:own(resource("throwing disposer"),"part",function()error("dispose failure")end,0)
	failedCleanup:own(survivor,"editable",destroy,2);failedCleanup:cancel()
	check("cleanup exceptions do not strand later resources or leases",failedCleanup.drained and survivor.destroys==1 and next(failedCleanup.resources)==nil and #failedCleanup.errors==2)
	local passed=0;for _,entry in checks do if entry.ok then passed+=1 end end
	return {passed=passed,checks=checks}
end

return Trial
