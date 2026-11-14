--!nonstrict
-- Native panels and buttons: no image fetch, texture stretching or baked text.
local GuiService = game:GetService("GuiService")
local Theme = require(script.Parent:WaitForChild("Theme"))
local Create = require(script.Parent:WaitForChild("Create"))
local Glass = {}
function Glass.panel(name, parent, tile)
	local panel = Create("Frame", { Name = name, BorderSizePixel = 0, Active = false,
		BackgroundColor3 = if tile then Theme.Color.Tile else Theme.Color.Surface }, parent)
	panel:SetAttribute("GlassTransparency", if tile then Theme.TileTransparency else Theme.PaneTransparency)
	Create("UICorner", { CornerRadius = UDim.new(0, if tile then Theme.TileRadius else Theme.Radius) }, panel)
	Create("UIStroke", { Name = "Rim", Color = Theme.Color.Rim, Transparency = 0.46, Thickness = 1 }, panel)
	return panel
end
function Glass.label(name, parent, text, heading)
	return Create("TextLabel", { Name = name, Text = text, BackgroundTransparency = 1, BorderSizePixel = 0,
		FontFace = if heading then Theme.Heading else Theme.Font, TextSize = Theme.BodySize,
		TextColor3 = Theme.Color.Text, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = true, AutoLocalize = true }, parent)
end
function Glass.button(name, parent, text)
	local button = Create("TextButton", { Name = name, Text = text, BorderSizePixel = 0,
		FontFace = Theme.Font, TextSize = Theme.BodySize, AutoButtonColor = false,
		Active = true, Selectable = true, TextColor3 = Theme.Color.Text,
		BackgroundColor3 = Theme.Color.Tile, AutoLocalize = true }, parent)
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.TileRadius) }, button)
	local rim = Create("UIStroke", { Name = "Rim", Color = Theme.Color.Rim, Transparency = 0.5, Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	local selection = Create("Frame", {Name = "FocusShape", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1}, button)
	button.SelectionImageObject = selection
	local hover, focus, pressed = false, false, false
	local function paint()
		local selected = button:GetAttribute("Selected") == true
		local disabled = button:GetAttribute("Disabled") == true
		button.Interactable, button.Selectable = not disabled, not disabled
		button:SetAttribute("State", if disabled then "Disabled" elseif pressed then "Pressed" elseif focus then "Focus" elseif selected then "Selected" elseif hover then "Hover" else "Normal")
		button.BackgroundColor3 = if selected then Theme.Color.Accent else Theme.Color.Tile
		button.TextColor3 = if disabled then Theme.Color.Disabled elseif selected then Theme.Color.OnAccent else Theme.Color.Text
		rim.Color = if focus then Theme.Color.Focus elseif selected or hover then Theme.Color.Accent else Theme.Color.Rim
		rim.Thickness = if focus then 3 elseif selected then 2 else 1
		rim.Transparency = 0
	end
	button.MouseEnter:Connect(function() hover = true; paint() end)
	button.MouseLeave:Connect(function() hover, pressed = false, false; paint() end)
	button.SelectionGained:Connect(function() focus = true; paint() end)
	button.SelectionLost:Connect(function() focus = false; paint() end)
	button.MouseButton1Down:Connect(function() pressed = true; paint() end)
	button.MouseButton1Up:Connect(function() pressed = false; paint() end)
	button:GetAttributeChangedSignal("Selected"):Connect(paint)
	button:GetAttributeChangedSignal("Disabled"):Connect(paint)
	paint()
	return button
end
function Glass.preferences(root, preference)
	preference = preference or GuiService.PreferredTransparency
	for _, item in root:GetDescendants() do
		local base = item:GetAttribute("GlassTransparency")
		if base then item.BackgroundTransparency = base * preference end
	end
end
return Glass
