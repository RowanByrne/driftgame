--!strict
--!native
-- Piecewise-linear grade profiles and their exact height envelope. Curves keep
-- one signed grade; a reversal can begin only in their reserved straight tail.
local Policy={}

function Policy.ramp(initial:number,target:number,rate:number,length:number):{number}
	local delta=target-initial
	if math.abs(delta)<1e-12 then return {length,initial} end
	local needed=math.abs(delta)/rate
	if needed>=length then return {length,initial+math.sign(delta)*math.min(math.abs(delta),rate*length)} end
	return {needed,target,length,target}
end

function Policy.profile(initial:number,target:number,rate:number,protected:number,length:number,after:number?):{number}?
	local knots=Policy.ramp(initial,target,rate,protected)
	local last=knots[#knots]
	local tail=length-protected
	if tail<=1e-7 then return if after==nil or math.abs(last-after)<1e-7 then knots else nil end
	local goal=after or last
	if math.abs(goal-last)>rate*tail+1e-7 then return nil end
	for i,v in Policy.ramp(last,goal,rate,tail) do table.insert(knots,if i%2==1 then protected+v else v) end
	return knots
end

function Policy.height(initial:number,y:number,knots:{number},at:number):number
	local s,g=0,initial
	for i=1,#knots,2 do
		local finish,value=knots[i],knots[i+1]
		if at<=finish then
			local ds=math.max(0,at-s)
			local slope=(value-g)/math.max(finish-s,1e-12)
			return y+g*ds+.5*slope*ds*ds
		end
		y+=(g+value)*.5*(finish-s);s,g=finish,value
	end
	return y+g*math.max(0,at-s)
end

-- centre has at most one clamp and an optional rate change at the section end.
-- Passing both rates gives all stationary relative-height points exactly.
function Policy.bounds(initial:number,y:number,knots:{number},origin:number,centre:(number)->number,rates:{number},cuts:{number}?):(number,number)
	local points={0,knots[#knots-1]}
	for _,cut in cuts or {} do if cut>0 and cut<knots[#knots-1] then table.insert(points,cut) end end
	local s,g=0,initial
	for i=1,#knots,2 do
		local finish,value=knots[i],knots[i+1]
		table.insert(points,finish)
		if math.abs(value-g)>1e-12 then
			for _,rate in rates do
				local t=(rate-g)/(value-g)
				if t>0 and t<1 then table.insert(points,s+t*(finish-s)) end
			end
		end
		s,g=finish,value
	end
	local lo,hi=math.huge,-math.huge
	for _,at in points do
		local relative=Policy.height(initial,y,knots,at)-origin-centre(at)
		lo=math.min(lo,relative);hi=math.max(hi,relative)
	end
	return lo,hi
end

return Policy
