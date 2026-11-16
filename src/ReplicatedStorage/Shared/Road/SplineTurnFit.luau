--!strict
-- Horizontal terrain checks for a detached, fully decorated candidate turn (T-190): against
-- the mountain the road is cut into (`Road/Ground`, T-218), the only ground since T-247.
-- Natural rising ground on a climbing hairpin is allowed; excess rock is measured apart.
local Config = require(game.ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)
local Ground = require(script.Parent.Ground)
local Fit = {}
export type Reading = {ok:boolean, score:number, view:number, cut:number, fill:number, samples:number, off:number?}
-- (`startFlip` and `flips` are kept for the callers; the mountain itself says how it rises)
function Fit.measure(sp: Spline.Spline, s0:number, s1:number, startFlip:number, flips:{{number}}): Reading
	local M = Config.Spline.Mountain
	local field = sp.mountain :: Ground.Field
	assert(field, "SplineTurnFit: the road has no mountain")
	local view, cut, fill, samples = 0, 0, 0, 0
	local cross, least, diagonal = s0, math.huge, nil
	for s=s0,s1,4 do
		local across=math.abs(math.sin(sp:yawAt(s)-(sp.fall or 0)))
		if across<least then cross,least=s,across end
		if not diagonal and across<.707 then diagonal=s end
	end
	for _, s in {s0, diagonal or s0, cross} do
		local x,z = sp:planAt(s)
		local yaw = sp:yawAt(s)
		local fx,fz,rx,rz = -math.sin(yaw),-math.cos(yaw),math.cos(yaw),-math.sin(yaw)
		local eye = sp:heightAt(s)+5
		-- the mountain is not one plane (T-228): how it rises ahead, there
		local e = 60
		local rising = math.max(0, (Ground.h(field,x+fx*e,z+fz*e) - Ground.h(field,x-fx*e,z-fz*e)) / (2*e))
		for _, dist in M.TurnViewDistances do
			-- the ground as drawn, off any road and its runoff
			local y,a = Ground.query(field,sp,x+fx*dist,z+fz*dist)
			if a<1 then
				view=math.max(view,y-eye-rising*dist)
			end
			samples+=1
		end
		for _,side in {-1,1} do
			local w=sp:runoffAt(s,side)+Config.Road.Width*.5
			local d=side*(w+M.TurnSideReach)
			-- the mountain itself there, so the depth of the cut or the fill
			local delta=Ground.h(field,x+rx*d,z+rz*d)-sp:terrainY(s,side*w)
			cut=math.max(cut,delta);fill=math.max(fill,-delta)
			samples+=1
		end
	end
	local score=math.max(0,view-M.TurnViewExcess)+math.max(0,cut-M.TurnMaxCut)+math.max(0,fill-M.TurnMaxFill)+view*.01
	return {ok=view<=M.TurnViewExcess and cut<=M.TurnMaxCut and fill<=M.TurnMaxFill,score=score,view=view,cut=cut,fill=fill,samples=samples}
end
return Fit
