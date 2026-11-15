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

return Trial
