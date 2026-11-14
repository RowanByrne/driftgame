--!strict
-- Horizontal terrain checks for a detached, fully decorated candidate turn (T-190).
-- Natural rising ground on a climbing hairpin is allowed; excess rock is measured apart.
local Config = require(game.ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)
local Hill = require(script.Parent.SplineHill)
local Profile = require(script.Parent.SplineProfile)
local Fit = {}
export type Reading = {ok:boolean, score:number, view:number, cut:number, fill:number, samples:number}
function Fit.measure(sp: Spline.Spline, s0:number, s1:number, startFlip:number, flips:{{number}}): Reading
	local M, H = Config.Spline.Mountain, Config.Spline.Hill
	local ctx = Hill.context(sp, s0, s1, Profile.profile)
	local half = Config.Road.Width * .5
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
		local flip = startFlip
		for _, f in flips do if f[1]<=s then flip=f[2] end end
		local rising = math.max(0, flip * (-fx*math.sin(sp.fall or 0)-fz*math.cos(sp.fall or 0))) * H.Slope
		for _, dist in M.TurnViewDistances do
			local y,so,d = Hill.heightAt(ctx,x+fx*dist,z+fz*dist)
			if y and so and d and math.abs(d)>half+sp:runoffAt(so,if d<0 then -1 else 1) then
				view=math.max(view,y-eye-rising*dist)
			end
			samples+=1
		end
		for _,side in {-1,1} do
			local w=half+sp:runoffAt(s,side)
			local d=side*(w+M.TurnSideReach)
			local y=Hill.heightAt(ctx,x+rx*d,z+rz*d)
			if y then
				local delta=y-sp:terrainY(s,side*w)
				cut=math.max(cut,delta);fill=math.max(fill,-delta)
			end
			samples+=1
		end
	end
	local score=math.max(0,view-M.TurnViewExcess)+math.max(0,cut-M.TurnMaxCut)+math.max(0,fill-M.TurnMaxFill)+view*.01
	return {ok=view<=M.TurnViewExcess and cut<=M.TurnMaxCut and fill<=M.TurnMaxFill,score=score,view=view,cut=cut,fill=fill,samples=samples}
end
return Fit