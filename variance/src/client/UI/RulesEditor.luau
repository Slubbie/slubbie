-- Editor for custom rules, generated from Core/Rules.CustomSchema so the
-- interface can never offer a value the server would reject. Used by the
-- sandbox (Play > Practice) and by private-trial hosts.
--
--   local editor = RulesEditor.new(parent, custom, onChanged, readOnly)
--   editor:set(custom)   -- redraw from new values (e.g. a lobby update)
--   editor:value()       -- the current table

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Variance.Core.Rules)
local Instruments = require(ReplicatedStorage.Variance.Core.Instruments)
local Modifiers = require(ReplicatedStorage.Variance.Core.Modifiers)
local Environments = require(ReplicatedStorage.Variance.Data.Environments)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local RulesEditor = {}
RulesEditor.__index = RulesEditor

local function optionName(field, option: string): string
	if field.Key == "Environment" then
		if option == "Rotate" then
			return "ROTATE"
		end
		local env = Environments.get(option)
		return env and string.upper(env.Name or option) or string.upper(option)
	end
	return string.upper(option)
end

function RulesEditor.new(parent: Instance, custom: { [string]: any }?, onChanged: ((any) -> ())?, readOnly: boolean?)
	local self = setmetatable({}, RulesEditor)
	self.Parent = parent
	self.OnChanged = onChanged
	self.ReadOnly = readOnly == true
	self.Value = Rules.sanitizeCustom(custom)
	self.Scroll = Kit.scroll(parent, { Name = "Rules", Padding = 4 })
	self:render()
	return self
end

function RulesEditor:value()
	return self.Value
end

function RulesEditor:set(custom: { [string]: any }?, readOnly: boolean?)
	self.Value = Rules.sanitizeCustom(custom)
	if readOnly ~= nil then
		self.ReadOnly = readOnly
	end
	self:render()
end

function RulesEditor:change(key: string, value: any)
	self.Value[key] = value
	self.Value = Rules.sanitizeCustom(self.Value)
	if self.OnChanged then
		self.OnChanged(self.Value)
	end
end

function RulesEditor:render()
	local scroll = self.Scroll
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local v = self.Value
	for order, field in Rules.CustomSchema do
		local rowFrame
		if self.ReadOnly then
			local text
			if field.Type == "set" then
				text = string.format("%d selected", #(v[field.Key] or {}))
			elseif field.Type == "bool" then
				text = if v[field.Key] then "ON" else "OFF"
			elseif field.Type == "enum" then
				text = optionName(field, v[field.Key])
			else
				text = tostring(v[field.Key])
			end
			rowFrame = Kit.create(
				"Frame",
				{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order, Parent = scroll }
			) :: Frame
			Kit.label(rowFrame, {
				Text = field.Label,
				Font = "Mono",
				TextSize = "Label",
				Color = "Dim",
				Size = UDim2.new(0.55, 0, 1, 0),
			})
			Kit.label(rowFrame, {
				Text = text,
				Font = "Mono",
				TextSize = "Label",
				XAlign = "Right",
				Size = UDim2.new(0.45, 0, 1, 0),
				Position = UDim2.fromScale(0.55, 0),
			})
		elseif field.Type == "int" then
			rowFrame = Kit.slider(scroll, {
				Label = field.Label,
				Min = field.Min,
				Max = field.Max,
				Step = field.Step or 1,
				Value = v[field.Key],
				LayoutOrder = order,
				Format = function(n)
					if field.Key == "TurnTimer" and n == 0 then
						return "OFF"
					elseif (field.Key == "MaxIntegrity" and n == 0) or (field.Key == "Draws" and n == -1) then
						return "AUTO"
					end
					return tostring(math.floor(n + 0.5))
				end,
				OnChanged = function(n)
					self:change(field.Key, n)
				end,
			})
		elseif field.Type == "enum" then
			rowFrame = Kit.choice(scroll, {
				Label = field.Label,
				Options = field.Options,
				Value = v[field.Key],
				LayoutOrder = order,
				Display = function(option)
					return optionName(field, option)
				end,
				OnChanged = function(option)
					self:change(field.Key, option)
				end,
			})
		elseif field.Type == "bool" then
			rowFrame = Kit.toggle(scroll, {
				Label = field.Label,
				Value = v[field.Key] == true,
				LayoutOrder = order,
				OnChanged = function(on)
					self:change(field.Key, on)
				end,
			})
		elseif field.Type == "set" then
			rowFrame = self:setField(scroll, field, order)
		end
		if rowFrame then
			Kit.tooltip(rowFrame, field.Help)
		end
	end
end

-- A set field: a grid of chips that toggle membership.
function RulesEditor:setField(parent: Instance, field, order: number): Frame
	local block = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	}) :: Frame
	Kit.list(block, "Y", 4)
	local selected = {}
	for _, id in self.Value[field.Key] or {} do
		selected[id] = true
	end
	Kit.label(block, {
		Text = field.Label .. (field.MaxCount and string.format("  (UP TO %d)", field.MaxCount) or ""),
		Font = "Mono",
		TextSize = "Label",
		Color = "Dim",
		LayoutOrder = 1,
	})
	local grid = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = block,
	}) :: Frame
	Kit.grid(grid, UDim2.fromOffset(150, 32), 6)
	for i, id in field.Of do
		local label = id
		local tip = nil
		if field.Key == "Enabled" then
			local def = Instruments.get(id)
			label = def and def.Name or id
			tip = def and (def.Short .. " (" .. def.Rarity .. ")") or nil
		elseif field.Key == "Modifiers" then
			local m = Modifiers.get(id)
			label = m and m.Name or id
			tip = m and m.Description or nil
		end
		local chip = Kit.button(grid, {
			Text = label,
			Size = UDim2.fromOffset(150, 32),
			Style = "Ghost",
			TextSize = "Tiny",
			LayoutOrder = i,
			Tooltip = tip,
			Sound = "Tick",
			OnClick = function()
				local list = {}
				for otherId, on in selected do
					if on and otherId ~= id then
						table.insert(list, otherId)
					end
				end
				if not selected[id] then
					if field.MaxCount and #list >= field.MaxCount then
						Kit.sound("Deny")
						return
					end
					table.insert(list, id)
				end
				selected[id] = not selected[id]
				self:change(field.Key, list)
				self:render()
			end,
		})
		chip:SetAttribute("Active", selected[id] == true)
		if field.Key == "Enabled" then
			local holder = Kit.create("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(18, 18),
				Position = UDim2.new(0, 6, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				ZIndex = 3,
				Parent = chip,
			}) :: Frame
			Icons.instrument(id, holder, 18)
		end
		local mark = Kit.create("Frame", {
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(6, 6),
			Position = UDim2.new(1, -10, 0, 4),
			Visible = selected[id] == true,
			ZIndex = 3,
			Parent = chip,
		}) :: Frame
		Theme.bind(mark, "BackgroundColor3", "Accent")
	end
	return block
end

return RulesEditor
