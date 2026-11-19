--!nonstrict
-- All geometry is in the registered word canvas. Keep the transparent margins.
local ContentProvider = game:GetService("ContentProvider")
local Registry = require(script.Parent.ScoreRankRegistry)
local Create = require(script.Parent.Create)
local Art = {}
Art.__index = Art

local white = Color3.new(1, 1, 1)
local full = UDim2.fromScale(1, 1)
local center = Vector2.new(.5, .5)

local function frame(parent, name, z)
	return Create("Frame", {Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = full, Active = false, ZIndex = z}, parent)
end

local function layer(parent, name, z, asset, color, opacity, prepared)
	if prepared then
		prepared.Name = name
		prepared.ZIndex = z
		prepared.Size = full
		prepared.ImageColor3 = color
		prepared.ImageTransparency = 1-(opacity or 1)
		prepared.Parent = parent
		return prepared
	end
	return Create("ImageLabel", {Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
		Active = false, Size = full, ZIndex = z, Image = asset.uri, ImageColor3 = color,
		ImageTransparency = 1 - (opacity or 1), ScaleType = Enum.ScaleType.Fit}, parent)
end

-- ImageRect cropping also works inside a rotated FULL SEND word. Roblox disables
-- ClipsDescendants under rotation. Set the pixel sample and its destination together.
local function slice(image, x, y, width, height, first, last)
	local left, right = math.round(first * width), math.round(last * width)
	image.Visible = right > left
	if not image.Visible then return end
	image.ImageRectOffset = Vector2.new(x + left, y)
	image.ImageRectSize = Vector2.new(right - left, height)
	image.Position = UDim2.fromScale(left / width, 0)
	image.Size = UDim2.fromScale((right - left) / width, 1)
end

local function lerpKeys(keys, at, stepped)
	for i = 2, #keys do
		local b, a = keys[i], keys[i - 1]
		if at <= b[1] then
			local p = math.clamp((at - a[1]) / (b[1] - a[1]), 0, 1)
			if stepped then p = math.floor(p * 2) / 2 end
			return a[2] + (b[2] - a[2]) * p, a[3] + (b[3] - a[3]) * p
		end
	end
	local b = keys[#keys]
	return b[2], b[3]
end

local scrape = {{0,-.008,-1.4},{.08,-.008,-1.4},{.17,.008,2.6},{.23,.004,1.1},
	{.30,.0065,1.8},{.54,.002,.7},{.76,0,0},{1,-.008,-1.4}}
local signalHit = {{0,0,0},{.1,.96,-1},{.26,.1,-1},{.43,.9,1},{.6,.16,1},{.77,.58,-.33},{1,0,0}}
local entryShift = {{0,4,3},{.18,-4,-2},{.32,3,0},{.49,-1,1},{1,0,0}}
local entryScale = {{0,.91,1.16},{.18,1.06,.92},{.32,1,1},{1,1,1}}
local entryTilt = {{0,-3.5,0},{.18,2,0},{.32,-1,0},{.49,0,0},{1,0,0}}
local echoPose = {{0,-4,2},{.42,6,-1},{1,12,-4}}
local echoOpacity = {{0,.65,0},{.42,.28,0},{1,0,0}}
local rearBurst = {{0,.72,.8},{.26,1.18,1},{1,1,1}}
local crownBurst = {{0,.36,.92},{.22,1.32,1.04},{.54,.93,.99},{1,.78,1}}
-- Left edge, baseline, width, vertical stretch, rotation, seconds/cel, starting cel, opacity.
local flames = {
	{.015,.83,.66,1.05,-4,.14,1,1}, {.40,.88,.57,1.06,-3,.16,2,1},
	{.32,.71,.43,1.18,0,.12,3,.85}, {.075,.31,.85,.78,0,.12,0,1},
}
local emberOrigins = {.25,.43,.71,.84}
local emberPaths = {Vector2.new(8,-15),Vector2.new(15,-22),Vector2.new(10,-12),Vector2.new(18,-15)}

-- Prefetch the next rank without retaining a second HUD or blocking scoring.
local warmed = {}
local function warmRank(rung)
	local rank = Registry[rung]
	if not rank or warmed[rung] then return end
	warmed[rung] = true
	task.spawn(function()
		local images = {}
		for _, key in {"letters","face","signal","body","detail","print","keyline","flameBody","flameCore"} do
			local asset = rank[key]
			if asset then
				local image = Instance.new("ImageLabel")
				image.Image = asset.uri
				table.insert(images, image)
			end
		end
		local succeeded = true
		local ok = pcall(function()
			ContentProvider:PreloadAsync(images, function(_, status)
				if status ~= Enum.AssetFetchStatus.Success then succeeded = false end
			end)
		end)
		for _, image in images do image:Destroy() end
		if not ok or not succeeded then warmed[rung] = nil end
	end)
end

function Art.new(parent)
	warmRank(1)
	warmRank(2)
	return setmetatable({slot = frame(parent, "WordSlot", 2), age = 0, entry = false, upcoming = {}}, Art)
end

function Art:layout(w, h)
	self.slotWidth, self.slotHeight = w, h
	self.slot.Position = UDim2.fromOffset(0, 1)
	self.slot.Size = UDim2.fromOffset(w, h)
	if self.style then
		self.width = math.min(w, h * self.face.width / self.face.height)
		self.height = self.width * self.face.height / self.face.width
		self:_charge()
		self.lastFrame = nil
		self:_paint(0, self.reduced)
	end
end

function Art:_signature(parent, name, z)
	local group = frame(parent, name, z)
	group.AnchorPoint = center
	group.Position = UDim2.fromScale(.5,.5)
	table.insert(self.signatures, group)
	return group
end

function Art:_sheet(group, name, asset, color, opacity, charged)
	local image = layer(group, name, 1 + #group:GetChildren(), asset, color, opacity)
	table.insert(self.sheets, {image = image, cellW = asset.width / 4, cellH = asset.height / 4, charged = charged})
end

function Art:_buildFire()
	local s, scene = self.style, self.scene
	layer(scene, "NavyBacking", 1, s.letters, Color3.fromHex("12223A"))
	self.flames, self.embers = {}, {}
	for i, f in flames do
		local group = frame(scene, "Flame" .. i, 2)
		group.AnchorPoint = Vector2.new(.5,1)
		group.Rotation = f[5]
		local body = layer(group,"Body",1,s.flameBody,Color3.fromHex("4276FF"),f[8])
		local core = layer(group,"Core",2,s.flameCore,Color3.fromHex("67E5FF"),f[8] * (if i == 4 then 1 else .8))
		-- Stretch only these sprites, as specified by their four independent poses.
		body.ScaleType, core.ScaleType = Enum.ScaleType.Stretch, Enum.ScaleType.Stretch
		table.insert(self.flames, {group = group, body = body, core = core})
	end
	for i = 1,4 do
		local e = frame(scene,"Ember" .. i,3)
		e.BackgroundColor3 = Color3.fromHex("B787FF")
		table.insert(self.embers,e)
	end
end

-- A fetched image can still need a render frame to become IsLoaded. Prime actual
-- face/signal ImageLabels at zero height, then move those same instances into the
-- word. This draws no pixels and holds at most two upcoming ranks.
function Art:_prepareNext(rung)
	for index, pair in self.upcoming do
		if index <= rung or index > rung+2 then
			pair.face:Destroy()
			pair.signal:Destroy()
			self.upcoming[index] = nil
		end
	end
	for index = rung+1, math.min(rung+2,#Registry) do
		if not self.upcoming[index] then
			local s = Registry[index]
			warmRank(index)
			local face = layer(self.slot,"UpcomingFace",1,s.face or s.letters,s.base)
			local signal = layer(self.slot,"UpcomingSignal",1,s.signal,s.tail)
			face.Size, signal.Size = UDim2.fromOffset(1,0), UDim2.fromOffset(1,0)
			self.upcoming[index] = {face = face, signal = signal}
		end
	end
end

function Art:setRank(rung, entry, reduced)
	self.reduced = reduced
	if self.scene then self.scene:Destroy() end
	self.style = Registry[rung]
	local s = self.style
	self.rung, self.age, self.entry, self.lastFrame = rung, 0, entry, nil
	self.promoted = entry == "gain" and not reduced
	self.waitForFace = if self.promoted then 0 else nil
	self.duration = .16 + .18*s.force + math.max(0,rung-9)*.009
	-- A subpixel kick at ×2 disappears at driving scale.
	self.impactForce = if self.promoted then .62 + .38*s.force else s.force
	local prepared = self.upcoming[rung]
	self.upcoming[rung] = nil
	self:_prepareNext(rung)
	self.scene = frame(self.slot, "RegisteredArt", 1)
	self.scene.AnchorPoint = center
	self.scene:SetAttribute("RankName", s.name)
	self.face = s.face or s.letters
	self.sheets, self.signatures = {}, {}
	self.flames, self.embers = nil, nil
	if s.flameBody then
		self:_buildFire()
	else
		local rear = self:_signature(self.scene, "RearSheets", 1)
		local rotor = rung == 11
		self:_sheet(rear,"Body",s.body, if rotor then s.base else s.exhaustInk or s.tail)
		self:_sheet(rear,"Detail",s.detail, if rotor then s.base else s.coreInk or s.accent)
		if rotor then
			local charged = self:_signature(self.scene, "ChargedRotor", 2)
			self:_sheet(charged,"Body",s.body,s.tail,1,true)
			self:_sheet(charged,"Detail",s.detail,s.accent,1,true)
		end
	end
	self.word = frame(self.scene,"Lettering",4)
	if s.keyline then layer(self.word,"Keyline",1,s.keyline,Color3.fromHex("061410")) end
	self.echo = layer(self.word,"Echo",2,self.face,s.accent,0)
	local rim = layer(self.word,"CoolRim",3,self.face,Color3.fromHex("CDDCEC"),.48)
	rim.Position = UDim2.fromOffset(0,.65)
	self.base = layer(self.word,"Unfilled",4,self.face,s.base,nil,prepared and prepared.face)
	self.lit = layer(self.word,"Charged",5,self.face,s.accent)
	self.front = layer(self.word,"Frontier",6,self.face,white)
	if s.print then
		local printGroup = self:_signature(self.scene, "FacePrint", 5)
		self:_sheet(printGroup,"Print",s.print,s.printInk,s.printOpacity)
	end
	self.signalGroup = frame(self.scene,"SignalPose",6)
	self.signal = layer(self.signalGroup,"Signal",1,s.signal,s.tail,0,prepared and prepared.signal)
	self:layout(self.slotWidth, self.slotHeight)
end

function Art:_charge()
	local width, height = self.face.width, self.face.height
	local p = self.progress or 0
	self.boundary = if p == 0 or p == 1 then p else (62 + 900*p)/1024
	slice(self.lit,0,0,width,height,0,self.boundary)
	slice(self.front,0,0,width,height,math.max(0,self.boundary - 2 / self.width),self.boundary)
	self.front.Visible = self.front.Visible and p > 0 and p < 1
end

function Art:setCharge(p)
	if self.progress == p then return end
	self.progress = p
	self:_charge()
	self.lastFrame = nil
end

function Art:_paintSheets(reduced, phase, entryLeft)
	local s = self.style
	local index = if reduced then s.still else math.floor(phase * 16)
	if index ~= self.lastFrame then
		for _, sheet in self.sheets do
			local w, h = sheet.cellW, sheet.cellH
			local last = if sheet.charged then math.clamp((self.boundary - .5)*216/256 + .5,0,1) else 1
			if sheet.charged and (self.progress == 0 or self.progress == 1) then last = self.progress end
			slice(sheet.image, index % 4 * w, math.floor(index/4)*h, w, h, 0, last)
		end
		self.lastFrame = index
	end
	local pose = s.entry
	local weight = if pose then entryLeft else 0
	local x, y, sx, sy, angle = 0, 0, 1, 1, 0
	if weight > 0 then
		x, y = pose[1]*weight, pose[2]*weight
		sx, sy, angle = 1+(pose[3]-1)*weight, 1+(pose[4]-1)*weight, pose[5]*weight
	end
	for _, group in self.signatures do
		group.Position = UDim2.new(.5,x,.5,y)
		group.Size = UDim2.fromScale(256/216*sx,112/216*self.face.width/self.face.height*sy)
		group.Rotation = angle
	end
end

function Art:_paintFire(reduced)
	local t = if self.entry and not reduced then math.min(1,self.age/.65) else 1
	local rear, opacity = lerpKeys(rearBurst,t)
	local crown, crownWidth = lerpKeys(crownBurst,t)
	for i, pair in self.flames do
		local f = flames[i]
		local index = (f[7] + (if reduced then 0 else math.floor(self.age/f[6]))) % 4
		local w, h = self.style.flameBody.width/2, self.style.flameBody.height/2
		local x, y = (index%2)*w, math.floor(index/2)*h
		local mirror = i == 2
		for _, image in {pair.body,pair.core} do
			image.ImageRectOffset = Vector2.new(if mirror then x+w else x,y)
			image.ImageRectSize = Vector2.new(if mirror then -w else w,h)
		end
		local top = i == 4
		local baseY = if top then f[2] else .83+(f[2]-.83)*rear
		local sy = if top then crown else f[4]*rear
		pair.group.Position = UDim2.fromScale(f[1]+f[3]/2,baseY)
		pair.group.Size = UDim2.fromScale(f[3]*(if top then crownWidth else 1),f[3]*h/w*self.face.width/self.face.height*sy)
		local alpha = f[8]*(if top then 1 else opacity)
		pair.body.ImageTransparency = 1-alpha
		pair.core.ImageTransparency = 1-alpha*(if top then 1 else .8)
	end
	for i, ember in self.embers do
		local p = (self.age - (i-1)*.034) / (.44+(i-1)*.052)
		ember.Visible = self.entry and not reduced and p > 0 and p < 1
		if ember.Visible then
			ember.Position = UDim2.new(emberOrigins[i],emberPaths[i].X*p,.05,emberPaths[i].Y*p)
			ember.Size = UDim2.fromOffset(3-2*p,2-p)
			ember.Rotation = -28-6*p
			ember.BackgroundTransparency = 1-math.min(p/.16,1)*(1-p)
		end
	end
end

function Art:_paint(dt, reduced)
	self.age += dt
	self.reduced = reduced
	if reduced then self.entry, self.promoted, self.waitForFace = false, false, nil end
	local s, rung = self.style, self.rung
	local hit = self.entry and not reduced and rung ~= 10
	local duration, force = self.duration, self.impactForce
	local t = if hit then math.min(1,self.age/duration) else 1
	local dx, dy = lerpKeys(entryShift,t)
	local sx, sy = lerpKeys(entryScale,t)
	self.scene.Position = UDim2.fromOffset(self.width/2+dx*force,self.slotHeight/2+dy*force)
	-- Keep fractional pixels in the scale components so short faces and tall
	-- effects share the same scale on compact screens.
	self.scene.Size = UDim2.fromScale(self.width/self.slotWidth*(1+(sx-1)*force),
		self.height/self.slotHeight*(1+(sy-1)*force))
	self.scene.Rotation = lerpKeys(entryTilt,t)*force
	-- A real gain spends its charge. Light the whole face independently of the reveal.
	local flash = if self.promoted then math.max(0,1-self.age/duration)^1.4 else 0
	self.base.ImageColor3 = s.base:Lerp(s.accent:Lerp(white,.65), flash)
	self.lit.ImageColor3 = s.accent:Lerp(white,.75*flash)
	local phase = if s.cycle then (self.age % s.cycle)/s.cycle else 0
	if self.flames then
		self:_paintFire(reduced)
		self.lastFrame = 0
	else
		local entryLeft = if hit then math.max(0,1-self.age/(.23+(rung-1)*.015))^3 else 0
		self:_paintSheets(reduced,phase,entryLeft)
	end
	local angle, xShift, yShift = 0,0,0
	local signalTime = if hit then math.min(1,self.age/(duration+.11)) else 1
	local alpha, displacement = lerpKeys(signalHit,signalTime,true)
	displacement *= 1+(rung-1)*.65
	if rung == 10 and not reduced then
		local x, rotation = lerpKeys(scrape,phase)
		angle = rotation
		local rad = math.rad(angle)
		local px, py = self.width*.38, self.height*.25
		xShift = self.width*x + px*(1-math.cos(rad))+py*math.sin(rad)
		yShift = py*(1-math.cos(rad))-px*math.sin(rad)
		if phase >= .16 and phase < .22 then alpha,displacement = .88,-.018*self.width
		elseif phase >= .22 and phase < .27 then alpha,displacement = .39,.013*self.width
		elseif phase >= .54 and phase < .59 then alpha,displacement = .58,.009*self.width
		elseif phase >= .59 and phase < .63 then alpha,displacement = .20,-.007*self.width end
	end
	self.word.Position = UDim2.fromOffset(xShift,yShift)
	self.word.Rotation = angle
	self.signalGroup.Position, self.signalGroup.Rotation = self.word.Position, angle
	self.signal.ImageTransparency = 1-alpha
	self.signal.Position = UDim2.fromOffset(displacement,0)
	self.echo.Visible = rung >= 4 and signalTime < 1
	if self.echo.Visible then
		local echoX, echoY = lerpKeys(echoPose,signalTime)
		self.echo.ImageTransparency = 1-lerpKeys(echoOpacity,signalTime)*force
		self.echo.Position = UDim2.fromOffset(echoX,echoY)
		self.echo.Size = UDim2.fromScale(1+.06*math.max(0,(signalTime-.42)/.58),1)
	end
end

function Art:step(dt, reduced)
	if self.waitForFace ~= nil and not reduced then
		self.waitForFace += dt
		-- Keep the entry's first pose until a renderable word exists. A failed
		-- fetch must never pin the rest of the HUD or block newer snapshots.
		if self.base.IsLoaded or self.waitForFace >= 1 then self.waitForFace = nil end
		dt = 0
	end
	if self.style and (not reduced or not self.reduced or self.lastFrame == nil) then
		self:_paint(dt, reduced)
	end
end

return Art
