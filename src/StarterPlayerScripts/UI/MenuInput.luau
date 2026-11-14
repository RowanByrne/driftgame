--!nonstrict
-- Input ownership is independent of being in the car. Owners release only their own block.
local GuiService = game:GetService("GuiService")
local Signal = require(game:GetService("ReplicatedStorage").Shared.Signal)
local MenuInput = { Changed = Signal.new() }
local owners = {}
function MenuInput.IsBlocked()
	return next(owners) ~= nil or GuiService.MenuIsOpen
end
function MenuInput.SetBlocked(owner, on)
	local was = MenuInput.IsBlocked()
	owners[owner] = if on then true else nil
	if was ~= MenuInput.IsBlocked() then MenuInput.Changed:Fire(MenuInput.IsBlocked()) end
end
GuiService.MenuOpened:Connect(function() MenuInput.Changed:Fire(true) end)
GuiService.MenuClosed:Connect(function() MenuInput.Changed:Fire(MenuInput.IsBlocked()) end)
return MenuInput
