-- SETTINGS, generated from Data/SettingsSchema (the server validates the same
-- schema). Changes apply immediately and save automatically. Controls lists
-- every rebindable keyboard action; gamepad and touch layouts are fixed so all
-- platforms share the same actions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SettingsSchema = require(ReplicatedStorage.Variance.Data.SettingsSchema)
local Kit = require(script.Parent.Parent.Kit)
local Window = require(script.Parent.Parent.Window)

local Settings = {}
Settings.__index = Settings

local PRETTY_KEYS = {
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
	Zero = "0",
	LeftShift = "L-SHIFT",
	RightShift = "R-SHIFT",
	LeftControl = "L-CTRL",
	RightControl = "R-CTRL",
	LeftAlt = "L-ALT",
	RightAlt = "R-ALT",
}

local function pretty(key: string?): string
	if key == nil or key == "" then
		return "UNBOUND"
	end
	return PRETTY_KEYS[key] or string.upper(key)
end

function Settings.new(ui, controllers)
	local self = setmetatable({}, Settings)
	self.UI = ui
	self.C = controllers
	self.Main = true
	local tabs = {}
	for _, category in SettingsSchema.Categories do
		table.insert(tabs, { Id = category.Id, Label = category.Name })
	end
	self.Window = Window.new(ui, {
		Name = "Settings",
		Title = "SETTINGS",
		Subtitle = "CHANGES APPLY IMMEDIATELY AND SAVE AUTOMATICALLY",
		Width = 820,
		Height = 600,
		Tabs = tabs,
		OnTab = function(id)
			self:show(id)
		end,
	})
	self.Frame = self.Window.Frame
	return self
end

function Settings:show(category: string)
	self.Category = category
	self.Capturing = nil
	local body = self.Window.Body
	Window.clear(body)
	local holder =
		Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -50), Parent = body }) :: Frame
	local scroll = Kit.scroll(holder, { Padding = 4 })
	local settings = self.C.SettingsController
	local order = 0
	for _, field in SettingsSchema.Fields do
		if field.Category == category then
			order += 1
			local value = settings:get(field.Key)
			if field.Type == "slider" then
				local isPercent = field.Max <= 1 and field.Min >= 0
				Kit.slider(scroll, {
					Label = field.Label,
					Min = field.Min,
					Max = field.Max,
					Step = field.Step,
					Value = value,
					LayoutOrder = order,
					Format = function(v)
						if isPercent then
							return string.format("%d%%", math.floor(v * 100 + 0.5))
						elseif field.Step < 1 then
							return string.format("%.2f", v)
						end
						return tostring(math.floor(v + 0.5))
					end,
					OnChanged = function(v)
						settings:set(field.Key, v)
					end,
				})
			elseif field.Type == "toggle" then
				Kit.toggle(scroll, {
					Label = field.Label,
					Value = value == true,
					LayoutOrder = order,
					OnChanged = function(on)
						settings:set(field.Key, on)
					end,
				})
			elseif field.Type == "choice" then
				Kit.choice(scroll, {
					Label = field.Label,
					Options = field.Options,
					Value = value,
					LayoutOrder = order,
					OnChanged = function(option)
						settings:set(field.Key, option)
					end,
				})
			elseif field.Type == "binds" then
				self:binds(scroll, order)
			end
		end
	end
	if category == "Controls" then
		Kit.label(scroll, {
			Text = "GAMEPAD  ·  X fire at self  ·  Y fire at opponent  ·  LB/RB choose instrument  ·  A use  ·  D-pad left/right target  ·  D-pad down log  ·  D-pad up emote  ·  Select menu\nTOUCH  ·  on-screen buttons  ·  drag on empty screen to look",
			Font = "Mono",
			TextSize = "Tiny",
			Color = "Dim",
			Wrap = true,
			AutoY = true,
			LayoutOrder = 999,
			Size = UDim2.new(1, -8, 0, 0),
		})
	end
	Kit.button(body, {
		Text = "RESET " .. string.upper(category) .. " TO DEFAULTS",
		Style = "Ghost",
		Size = UDim2.fromOffset(300, 38),
		Position = UDim2.new(1, 0, 1, 0),
		AnchorPoint = Vector2.new(1, 1),
		OnClick = function()
			if Kit.confirm("RESET SETTINGS", "Restore the defaults for " .. string.upper(category) .. "?", "RESET") then
				settings:reset(category)
				self:show(category)
			end
		end,
	})
end

function Settings:binds(scroll: Instance, order: number)
	local settings = self.C.SettingsController
	for i, action in SettingsSchema.Actions do
		local rowFrame = Kit.create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, 36),
			LayoutOrder = order * 100 + i,
			Parent = scroll,
		}) :: Frame
		Kit.label(rowFrame, {
			Text = string.upper(action.Label),
			Font = "Mono",
			TextSize = "Label",
			Color = "Dim",
			Size = UDim2.new(0.6, 0, 1, 0),
		})
		local button
		button = Kit.button(rowFrame, {
			Text = pretty(settings:bind(action.Id)),
			Size = UDim2.new(0.4, 0, 0, 30),
			Position = UDim2.new(0.6, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Tooltip = "Click, then press a key. Escape cancels.",
			OnClick = function()
				self:capture(action.Id, button)
			end,
		})
	end
end

-- Waits for the next key and binds it (swapping with any action that had it).
function Settings:capture(actionId: string, button: TextButton)
	if self.Capturing then
		return
	end
	self.Capturing = actionId
	Kit.setText(button, "PRESS A KEY...")
	local connection
	connection = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		connection:Disconnect()
		self.Capturing = nil
		local key = input.KeyCode.Name
		local settings = self.C.SettingsController
		if key == "Escape" then
			Kit.setText(button, pretty(settings:bind(actionId)))
			return
		end
		if SettingsSchema.ReservedKeys[key] then
			self.UI:toast("KEY RESERVED", pretty(key) .. " can't be bound.", "Warn")
			Kit.setText(button, pretty(settings:bind(actionId)))
			return
		end
		local binds = {}
		for _, action in SettingsSchema.Actions do
			binds[action.Id] = settings:bind(action.Id)
		end
		local previous = binds[actionId]
		for id, bound in binds do
			if bound == key and id ~= actionId then
				binds[id] = previous -- swap
			end
		end
		binds[actionId] = key
		settings:set("Binds", binds)
		self:show("Controls")
	end)
end

function Settings:Open()
	self.Window:open()
	if self.Window.select then
		self.Window.select(self.Category or "Audio")
	end
end

function Settings:Close()
	self.Capturing = nil
	self.Window:close()
end

return Settings
