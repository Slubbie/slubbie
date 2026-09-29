-- A modal "choose an item from your bag" picker, used wherever a screen
-- needs the player to pick a stack: loading machines, gifts, museum
-- donations, showcase slots, contest entries, stall listings, trades, bait.
--
--   Picker.Open({
--     Title = "Choose a gift",
--     Filter = function(stack, def) return true end,   -- which stacks to offer
--     Note = function(stack, def) return "Loves it!" end, -- optional line under the name
--     OnPick = function(ref, stack) end,               -- ref = "inv:<slot>"
--     Empty = "Nothing suitable in your bag.",
--   })

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Picker = {}

-- Set by the UI controller (avoids requiring controllers from UI modules).
Picker.GetProfile = function(): any
	return nil
end

export type Options = {
	Title: string,
	Filter: ((any, any) -> boolean)?,
	Note: ((any, any) -> string?)?,
	OnPick: (string, any) -> (),
	Empty: string?,
	Container: string?, -- default "inv"
}

function Picker.Open(options: Options)
	local layer = Kit.ModalLayer
	local profile = Picker.GetProfile()
	if not layer or not profile then
		return
	end
	local containerName = options.Container or "inv"
	local container = if containerName == "inv"
		then profile.Inventory
		else (profile.Storage and profile.Storage[(string.gsub(containerName, "^chest:", ""))])
	local shade = Kit.new("TextButton", {
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 80,
		Parent = layer,
	})
	local panel = Kit.Panel({ Size = UDim2.fromOffset(560, 440), Shadow = true })
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Parent = shade
	Kit.Padding(panel, 14, 16)
	local title = Kit.Heading(options.Title, 20)
	title.Size = UDim2.new(1, -50, 0, 28)
	title.Parent = panel
	local function close()
		shade:Destroy()
		Kit.HideTooltip()
	end
	local closeButton =
		Kit.Button("✕", { Style = "Danger", Size = UDim2.fromOffset(32, 32), Sound = "UIClose", OnClick = close })
	closeButton.Position = UDim2.new(1, -32, 0, -2)
	closeButton.Parent = panel
	local search = Kit.TextBox("🔍 Search…", { Size = UDim2.new(1, 0, 0, 32) })
	search.Position = UDim2.fromOffset(0, 36)
	search.Parent = panel
	local list = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -76), Position = UDim2.fromOffset(0, 76) })
	list.Parent = panel
	Kit.List(list, "Y", 4)
	local function render()
		Kit.Clear(list)
		local query = string.lower(search.Text)
		local entries = {}
		for key, stack in (container and container.Slots) or {} do
			local def = Registry.Items[stack.Id]
			if def and (not options.Filter or options.Filter(stack, def)) then
				local name = ItemUtil.DisplayName(stack)
				if query == "" or string.find(string.lower(name), query, 1, true) then
					table.insert(entries, { Key = key, Stack = stack, Def = def, Name = name })
				end
			end
		end
		table.sort(entries, function(a, b)
			if a.Name ~= b.Name then
				return a.Name < b.Name
			end
			return (a.Stack.Q or 1) > (b.Stack.Q or 1)
		end)
		if #entries == 0 then
			Kit.Empty(options.Empty or "Nothing suitable in your bag.").Parent = list
			return
		end
		for i, entry in entries do
			local row = Kit.new("TextButton", {
				AutoButtonColor = false,
				Text = "",
				Size = UDim2.new(1, -8, 0, 52),
				LayoutOrder = i,
				Selectable = true,
				Parent = list,
			})
			Kit.Paint(row, "BackgroundColor3", "PanelAlt")
			Kit.Corner(row, 8)
			local slot = Kit.ItemSlot(44)
			slot.Button.Position = UDim2.fromOffset(4, 4)
			slot.Button.Active = false
			slot.Button.Parent = row
			slot.Set(entry.Stack)
			local name = Kit.Label(
				entry.Name .. (if entry.Stack.N > 1 then "  ×" .. entry.Stack.N else ""),
				{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold }
			)
			name.Position = UDim2.fromOffset(56, 6)
			name.Size = UDim2.new(1, -64, 0, 20)
			name.TextColor3 = Theme.RarityColor(ItemUtil.Rarity(entry.Stack))
			name.Parent = row
			local note = options.Note and options.Note(entry.Stack, entry.Def)
			local sub = Kit.Label(
				note or (entry.Def.Category .. (if entry.Stack.L then "  ·  🔒 locked" else "")),
				{ Size = Theme.Sizes.Tiny, Color = "SubText" }
			)
			sub.Position = UDim2.fromOffset(56, 27)
			sub.Size = UDim2.new(1, -64, 0, 16)
			sub.Parent = row
			row.MouseEnter:Connect(function()
				Kit.Paint(row, "BackgroundColor3", "SlotHover")
			end)
			row.MouseLeave:Connect(function()
				Kit.Paint(row, "BackgroundColor3", "PanelAlt")
			end)
			Kit.AttachTooltip(row, function()
				return Kit.ItemTooltip(entry.Stack)
			end)
			row.Activated:Connect(function()
				Kit.PlaySound("UIClick")
				close()
				options.OnPick(containerName .. ":" .. entry.Key, entry.Stack)
			end)
			if i == 1 then
				GuiService.SelectedObject = row
			end
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(render)
	render()
	Kit.Pop(panel)
	Kit.RepaintGradients(panel)
	return close
end

return Picker
