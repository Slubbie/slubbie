-- Modal panels (Bag, Upgrades, Odds, Settings). One panel is open at a time.
-- Panels.Create(name, title, icon) returns the panel's content frame; Panels.Open/Close/Toggle.

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Signal = require(game:GetService("ReplicatedStorage").Dicebound.Signal)

local C = Theme.Colors

local Panels = {}
Panels.Opened = Signal.new() -- (name, options)
Panels.Closed = Signal.new() -- (name)
Panels.Current = nil :: string?

local root: Instance
local panels: { [string]: { Frame: Frame, Content: Frame, Header: Frame } } = {}

function Panels.Init(parent: Instance)
	root = parent
end

function Panels.Create(name: string, title: string, icon: string): (Frame, Frame)
	local frame = Kit.Card({
		Name = name .. "Panel",
		Parent = root,
		Size = UDim2.new(0.92, 0, 0.84, 0),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 20,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(820, 600), Parent = frame })
	local header = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = C.PanelAlt,
		BorderSizePixel = 0,
		Parent = frame,
	})
	Kit.Corner(header)
	Kit.Label({
		Parent = header,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -80, 1, 0),
		Text = icon .. "  " .. title,
		Font = Theme.Fonts.Title,
		TextSize = 26,
	})
	Kit.Button({
		Parent = header,
		Text = "✕",
		Color = C.Red,
		Size = UDim2.fromOffset(44, 40),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 20,
		OnClick = function()
			Panels.Close()
		end,
	})
	local content = Kit.new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	Kit.Padding(content, 12)
	panels[name] = { Frame = frame, Content = content, Header = header }
	return content, header
end

function Panels.Open(name: string, options: any?)
	if Panels.Current and Panels.Current ~= name then
		Panels.Close()
	end
	local panel = panels[name]
	if not panel then
		return
	end
	Panels.Current = name
	panel.Frame.Visible = true
	if not Kit.ReducedMotion then
		local scale = panel.Frame:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = panel.Frame })
		scale.Scale = 0.94
		Kit.Tween(scale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	Panels.Opened:Fire(name, options)
end

function Panels.Close()
	local name = Panels.Current
	if not name then
		return
	end
	panels[name].Frame.Visible = false
	Panels.Current = nil
	Panels.Closed:Fire(name)
end

function Panels.Toggle(name: string, options: any?)
	if Panels.Current == name then
		Panels.Close()
	else
		Panels.Open(name, options)
	end
end

function Panels.IsOpen(name: string): boolean
	return Panels.Current == name
end

return Panels
