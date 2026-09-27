-- The shared frame for every full screen ("terminal window"): header with a
-- title and subtitle, an optional tab strip, a body, a close button and the
-- open/close motion. Back (B / Escape via the close button) closes it.
--
--   local w = Window.new(ui, { Name, Title, Subtitle?, Width?, Height?, Tabs?, OnTab? })
--   w.Body       content frame
--   w:setSubtitle(text)
--   w:open() / w:close() / w.Visible
--   w.select(tabId)  when Tabs were given

local GuiService = game:GetService("GuiService")

local Kit = require(script.Parent.Kit)
local Motion = require(script.Parent.Motion)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local Window = {}
Window.__index = Window

export type Options = {
	Name: string,
	Title: string,
	Subtitle: string?,
	Width: number?,
	Height: number?,
	Tabs: { { Id: string, Label: string } }?,
	OnTab: ((string) -> ())?,
}

function Window.new(ui, options: Options)
	local self = setmetatable({}, Window)
	self.UI = ui
	self.Visible = false
	local width, height = options.Width or 900, options.Height or 580
	local shade = Kit.create("Frame", {
		Name = options.Name,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = ui.Screens,
	}) :: Frame
	self.Frame = shade
	local panel = Kit.panel(shade, {
		Name = "Window",
		Size = UDim2.fromOffset(width, height),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = "Panel",
		Clip = true,
	})
	self.Panel = panel
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(width, height)
	constraint.Parent = panel
	-- On small screens the window fills the view.
	local function fit()
		local compact = ui.Compact == true
		panel.Size = if compact then UDim2.new(1, -16, 1, -16) else UDim2.fromOffset(width, height)
		constraint.MaxSize = if compact then Vector2.new(math.huge, math.huge) else Vector2.new(width, height)
	end
	self.fit = fit
	fit()

	local header = Kit.create(
		"Frame",
		{ Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), Parent = panel }
	) :: Frame
	Kit.padding(header, 12, 20)
	local accent = Kit.create(
		"Frame",
		{ BorderSizePixel = 0, Size = UDim2.new(1, 40, 0, 2), Position = UDim2.new(0, -20, 0, -12), Parent = header }
	) :: Frame
	Theme.bind(accent, "BackgroundColor3", "Accent")
	self.TitleLabel = Kit.label(
		header,
		{ Text = options.Title, Font = "Display", TextSize = "Title", Color = "Text", Size = UDim2.new(1, -60, 0, 26) }
	)
	self.SubtitleLabel = Kit.label(header, {
		Text = options.Subtitle or "",
		Font = "Mono",
		TextSize = "Small",
		Color = "Dim",
		Size = UDim2.new(1, -60, 0, 18),
		Position = UDim2.fromOffset(0, 28),
	})
	local close = Kit.button(header, {
		Name = "Close",
		Text = "",
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(1, 0, 0, 2),
		AnchorPoint = Vector2.new(1, 0),
		Style = "Ghost",
		Tooltip = "Close",
		Sound = "Close",
		OnClick = function()
			ui:close(options.Name)
		end,
	})
	local icon = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = close,
	}) :: Frame
	Icons.symbol("Close", icon, 18)
	self.CloseButton = close

	local top = 64
	if options.Tabs then
		local strip, choose = Kit.tabs(panel, options.Tabs, function(id)
			self.Tab = id
			if options.OnTab then
				options.OnTab(id)
			end
		end, 34)
		strip.Position = UDim2.fromOffset(20, top)
		strip.Size = UDim2.new(1, -40, 0, 34)
		self.select = choose
		self.TabStrip = strip
		top += 44
	end
	local body = Kit.create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 1, -(top + 16)),
		Position = UDim2.fromOffset(20, top),
		Parent = panel,
	}) :: Frame
	self.Body = body
	if ui.Controllers.SettingsController:get("Scanlines") ~= false then
		Kit.scanlines(panel, 110, 0.05)
	end
	return self
end

function Window:setSubtitle(text: string)
	self.SubtitleLabel.Text = text
end

function Window:setTitle(text: string)
	self.TitleLabel.Text = text
end

function Window:open()
	self.fit()
	self.Visible = true
	local shade = self.Frame
	shade.Visible = true
	shade.BackgroundTransparency = 1
	Motion.tween(shade, 0.2, { BackgroundTransparency = 0.45 })
	self.Panel.Position = UDim2.new(0.5, 0, 0.5, 24)
	Motion.tween(self.Panel, 0.25, { Position = UDim2.fromScale(0.5, 0.5) }, "slide")
	self.UI:focus(self.CloseButton)
end

function Window:close()
	if not self.Visible then
		return
	end
	self.Visible = false
	Kit.hideTip()
	local shade = self.Frame
	Motion.tween(shade, 0.15, { BackgroundTransparency = 1 })
	Motion.tween(self.Panel, 0.15, { Position = UDim2.new(0.5, 0, 0.5, 18) }, "accel")
	task.delay(0.16, function()
		if not self.Visible then
			shade.Visible = false
		end
	end)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(shade) then
		GuiService.SelectedObject = nil
	end
end

-- Removes every child of a container except layout objects.
function Window.clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

return Window
