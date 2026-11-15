--!strict
--!native
-- Read-only physical contact resolution. A token is acquired through a real
-- field connection; it never grants route progress or mutates a caller's history.
local Infield=require(script.Parent.SplineInfield)
local Config=require(game.ReplicatedStorage.Shared.Config)
local Contact={}

export type Token={s:number,patchId:string,road:any}
export type Options={limit:number?,first:number?,closing:number?,low:number?,high:number?,peer:Token?}
export type Hit={ownerS:number,contactS:number,d:number?,routeD:number,y:number,normal:Vector3,kind:number,
	peer:Token?,source:string,closingS:number?}

local function finite(x:number):boolean return x==x and math.abs(x)<math.huge end

function Contact.copy(peer:Token?):Token?
	return if peer then {s=peer.s,patchId=peer.patchId,road=peer.road} else nil
end

-- The existing road re-entry allowance, shared with the client handoff. A
-- caller must still require a real live credited piece before publishing it.
function Contact.credit(anchor:number,travel:number,target:number):number
	return math.min(target,anchor+math.max(0,travel)*1.05+8)
end

function Contact.resolve(sp:any,x:number,z:number,owner:number?,options:Options?):Hit?
	if owner==nil or not finite(owner) then return nil end
	local o=options or {}
	local limit=math.clamp(o.limit or 160,0,640)
	local first=math.max(o.first or 0,sp.firstSample*sp.step)
	if first>sp.length then return nil end
	local offRoad=Config.Road.Width*.5+1
	local index=sp.infields
	local peer=o.peer
	if peer and (peer.road~=sp or typeof(peer.s)~="number" or not finite(peer.s) or not index or not index.patches[peer.patchId]) then peer=nil end
	local initial=sp:infieldContact(x,z,owner,o.low,o.high,limit,math.max(first,o.closing or 0))
	if initial and initial.closingS and initial.closingS<first then initial=nil end
	local patch=if peer then index.patches[peer.patchId] elseif initial then index.patches[initial.patch] else nil
	local function bank(s:number):string?
		if not patch then return nil end
		local a,b=patch.rows[1],patch.rows[#patch.rows]
		local function distance(low:number,high:number):number return math.max(low-s,s-high,0) end
		local da,db=distance(a.sa,b.sa),distance(b.sb,a.sb)
		return if da==db then nil elseif da<db then "A" else "B"
	end
	local ownerBank=bank(owner)
	local function native(seed:number,history:number,owned:boolean):Hit?
		local s,d=sp:projectFrom(x,z,seed)
		if not s or not d or s<first or s>sp.length or math.abs(s-history)>limit then return nil end
		if owned and patch and bank(s)~=ownerBank then return nil end
		local kind=sp:groundKind(s,d)
		if kind==nil then return nil end
		local y=sp:terrainY(s,d)
		if (o.low and y<o.low) or (o.high and y>o.high) then return nil end
		return {ownerS=if owned then s else owner,contactS=s,d=d,routeD=if owned then d else offRoad,
			y=y,normal=if kind==sp.TARMAC then sp:normalAt(s,d) else sp:terrainNormal(s,d),kind=kind,
			peer=if not owned and peer then {s=s,patchId=peer.patchId,road=sp} else nil,source=if owned then "owned" else "peer"}
	end
	-- Exact occupied ground keeps priority at its original bank. Recognized
	-- opposite-leg Newton convergence cannot silently change route ownership.
	if owner>=first then local owned=native(owner,owner,true);if owned then return owned end end
	if peer then
		local floor=Infield.sample(index,x,z,o.low,o.high)
		if floor and floor.patch==peer.patchId and floor.closingS>=first then
			local physical=floor.contactS
			if physical<first then physical=if floor.sb>=first then floor.sb else floor.sa end
			local d=nil
			if physical>=first then local _;_,d=sp:projectFrom(x,z,physical) end
			return {ownerS=Infield.route(floor,owner,limit,patch) or owner,contactS=physical,d=d,routeD=offRoad,
				y=floor.y,normal=floor.normal,kind=sp.GRASS,peer={s=physical,patchId=peer.patchId,road=sp},source="field",closingS=floor.closingS}
		end
		-- A genuine acquisition authorizes bounded continuation along that real
		-- road, including beyond either end of the original field patch.
		local seed=math.clamp(peer.s,first,sp.length)
		local retained=native(seed,peer.s,false)
		if retained then return retained end
		if limit>128 then
			for offset=128,limit,128 do
				retained=native(math.min(seed+offset,sp.length),peer.s,false);if retained then return retained end
				retained=native(math.max(seed-offset,first),peer.s,false);if retained then return retained end
			end
		end
		-- A retained physical leg may encounter another published field before
		-- its old shortcut debt is repaid. Acquire that real connection from the
		-- physical history while keeping the original accepted owner unchanged.
		local joined=sp:infieldContact(x,z,peer.s,o.low,o.high,limit,math.max(first,o.closing or 0))
		if joined and (not joined.closingS or joined.closingS>=first) then
			return {ownerS=owner,contactS=joined.contactS,d=joined.d,routeD=offRoad,y=joined.y,normal=joined.normal,
				kind=joined.kind,peer={s=joined.contactS,patchId=joined.patch,road=sp},source="field",closingS=joined.closingS}
		end
	end
	if initial then
		return {ownerS=initial.ownerS,contactS=initial.contactS,d=initial.d,routeD=initial.routeD,
			y=initial.y,normal=initial.normal,kind=initial.kind,
			peer={s=initial.contactS,patchId=initial.patch,road=sp},source="field",closingS=initial.closingS}
	end
	-- The old bounded catch-up search remains available on the owned road, but
	-- known peer ranges cannot be acquired by those retry offsets.
	if owner>=first and limit>128 then
		for offset=128,limit,128 do
			local owned=native(math.min(owner+offset,sp.length),owner,true);if owned then return owned end
			owned=native(math.max(owner-offset,first),owner,true);if owned then return owned end
		end
	end
	return nil
end

return Contact
