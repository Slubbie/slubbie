-- Short messages at the top of the screen: errors, rewards, announcements. At most a few at once.

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local C = Theme.Colors

local Toasts = {}

local STYLES = {
	info = { Back = C.Panel, Text = C.Ink, Stroke = C.Stroke },
	success = { Back = Color3.fromRGB(226, 246, 214), Text = C.GreenDark, Stroke = C.Green },
	error = { Back = Color3.fromRGB(255, 226, 220), Text = C.RedDark, Stroke = C.Red },
	reward = { Back = Color3.fromRGB(255, 244, 210), Text = C.GoldDark, Stroke = C.Gold },
	announce = { Back = Color3.fromRGB(240, 228, 255), Text = Color3.fromRGB(90, 50, 150), Stroke = C.Purple },
}
local MAX = 3

local container: Frame
local order = 0

function Toasts.Init(root: Instance)
	container = Kit.new("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(460, 200),
		Position = UDim2.new(0.5, 0, 0, 58),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 40,
		Parent = root,
	})
	Kit.List(container, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
end

function Toasts.Show(text: string, kind: string?, seconds: number?)
	if not container then
		return
	end
	local style = STYLES[kind or "info"] or STYLES.info
	local existing = {}
	for _, child in container:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(existing, child)
		end
	end
	table.sort(existing, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #existing >= MAX do
		table.remove(existing, 1):Destroy()
	end
	order += 1
	local toast = Kit.Label({
		Parent = container,
		Text = text,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = style.Back,
		TextColor3 = style.Text,
		Font = Theme.Fonts.Bold,
		TextSize = 16,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = order,
		ZIndex = 40,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(440, math.huge), Parent = toast })
	toast.TextWrapped = true
	Kit.Corner(toast, 10)
	Kit.Stroke(toast, style.Stroke, 2)
	Kit.Padding(toast, 8, 14)
	task.delay(seconds or 3, function()
		if toast.Parent then
			Kit.Tween(toast, 0.3, { TextTransparency = 1, BackgroundTransparency = 1 })
			local stroke = toast:FindFirstChildOfClass("UIStroke")
			if stroke then
				Kit.Tween(stroke, 0.3, { Transparency = 1 })
			end
			task.wait(0.32)
			toast:Destroy()
		end
	end)
end

return Toasts
