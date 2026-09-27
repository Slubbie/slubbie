-- Confirmation dialog, used only where it prevents a real mistake (selling Legendary+ items).
-- Confirm.Ask(title, body, buttons) yields and returns the chosen button id (or "cancel").

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local C = Theme.Colors

local Confirm = {}

local root: Instance

function Confirm.Init(parent: Instance)
	root = parent
end

-- buttons: { { Id = "sell", Text = "Sell", Color = Color3 }, ... } (the last one is the default focus)
function Confirm.Ask(title: string, body: string, buttons: { { Id: string, Text: string, Color: Color3? } }): string
	local choice: string? = nil
	local overlay = Kit.new("TextButton", {
		Name = "Confirm",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Dim,
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 60,
		Parent = root,
	})
	local card = Kit.Card({
		Parent = overlay,
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 61,
	})
	Kit.Padding(card, 18)
	Kit.List(card, Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Center)
	Kit.Label({
		Parent = card,
		Text = title,
		Font = Theme.Fonts.Title,
		TextSize = 24,
		Size = UDim2.new(1, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		ZIndex = 62,
	})
	Kit.Label({
		Parent = card,
		Text = body,
		TextSize = 16,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.InkSoft,
		LayoutOrder = 2,
		ZIndex = 62,
	})
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = card,
	})
	local list = Kit.List(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	list.Wraps = true
	for i, def in buttons do
		Kit.Button({
			Parent = row,
			Text = def.Text,
			Color = def.Color or C.Blue,
			Size = UDim2.fromOffset(if #buttons > 2 then 190 else 160, 46),
			TextSize = 16,
			LayoutOrder = i,
			ZIndex = 62,
			OnClick = function()
				choice = def.Id
			end,
		})
	end
	overlay.Activated:Connect(function()
		choice = choice or "cancel"
	end)
	while not choice do
		task.wait(0.05)
	end
	overlay:Destroy()
	return choice :: string
end

return Confirm
