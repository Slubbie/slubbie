-- Settings: graphics, audio, interface, accessibility and gameplay (all from
-- Config/Settings, saved to your profile), plus a controls reference for
-- keyboard, gamepad and touch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared.Config.Settings)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local C = require(UI.Parent.Controllers)

local CONTROLS = {
	{ "Move / look", "WASD + mouse", "Left stick / right stick", "Thumbstick / drag" },
	{ "Use tool / interact", "Left click · E", "RT · X", "Tap the world · ✋" },
	{ "Use held item (eat, place…)", "F", "Y", "🍎 button" },
	{ "Hotbar", "1–9 · scroll", "LB / RB", "Tap a slot" },
	{ "Tool area size", "R", "D-pad up", "⬛ button" },
	{ "Backpack", "B / Tab", "D-pad down", "🎒" },
	{ "Quests · Skills · Map", "J · K · M", "Menu", "Menu" },
	{ "Collection · Crafting · Mail", "C · V · N", "Menu", "Menu" },
	{ "Friends · Profile · Calendar", "O · P · U", "Menu", "Menu" },
	{ "Achievements · Land", "Y · L", "Menu", "Menu" },
	{ "Build mode", "H", "Menu", "🛠️" },
	{ "Photo mode", "F2", "Menu", "Menu" },
	{ "Menu", "`", "Select / View", "☰" },
	{ "Close window", "Esc", "B", "✕" },
}

return {
	Id = "Settings",
	Title = "Settings",
	Icon = "⚙️",
	Size = Vector2.new(860, 600),
	Watch = { "Settings" },
	Build = function(win, ctx)
		local content = win.Content :: Frame
		local current = (ctx.Args and ctx.Args.Tab) or SettingsConfig.Tabs[1]
		local render: () -> ()
		local tabList = {}
		local icons =
			{ Graphics = "🖥️", Audio = "🔊", Interface = "🧩", Accessibility = "♿", Gameplay = "🎮" }
		for _, tab in SettingsConfig.Tabs do
			table.insert(tabList, { Id = tab, Label = tab, Icon = icons[tab] })
		end
		table.insert(tabList, { Id = "Controls", Label = "Controls", Icon = "⌨️" })
		local tabs = Kit.Tabs(tabList, function(id)
			current = id
			render()
		end)
		tabs.Frame.Parent = content
		local body = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -46),
			Position = UDim2.fromOffset(0, 46),
			Parent = content,
		})

		local function renderControls()
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = body
			Kit.List(list, "Y", 4)
			local header =
				Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 24), Parent = list })
			for i, text in { "Action", "Keyboard & mouse", "Gamepad", "Touch" } do
				local l = Kit.Label(text, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
				l.Size = UDim2.new(0.25, 0, 1, 0)
				l.Position = UDim2.fromScale((i - 1) * 0.25, 0)
				l.Parent = header
			end
			for i, row in CONTROLS do
				local r = Kit.new("Frame", {
					BackgroundTransparency = if i % 2 == 0 then 1 else 0.85,
					Size = UDim2.new(1, -8, 0, 26),
					LayoutOrder = i,
					Parent = list,
				})
				Kit.Paint(r, "BackgroundColor3", "PanelAlt")
				Kit.Corner(r, 6)
				for j, text in row do
					local l = Kit.Label(text, { Size = Theme.Sizes.Tiny, Color = if j == 1 then "Text" else "SubText" })
					l.Size = UDim2.new(0.25, -6, 1, 0)
					l.Position = UDim2.new((j - 1) * 0.25, 6, 0, 0)
					l.Parent = r
				end
			end
			local build = Kit.Label(
				"Build mode: click to place · R rotate · T free placement · G snap · [ ] size · PgUp/PgDn lift · Ctrl+Z / Ctrl+Y undo/redo · Ctrl+D duplicate · I copy style · Delete pick up · Z/X turn camera.",
				{ Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true }
			)
			build.LayoutOrder = 100
			build.Parent = list
		end

		render = function()
			Kit.Clear(body)
			if current == "Controls" then
				renderControls()
				return
			end
			local list = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -44) })
			list.Parent = body
			Kit.List(list, "Y", 6)
			local order = 0
			for _, spec in SettingsConfig.Specs do
				if spec.Tab == current then
					order += 1
					local value = C.Settings.Get(spec.Key)
					local widget: GuiObject
					if spec.Kind == "Toggle" then
						widget = (Kit.Toggle(value == true, function(v)
							C.Settings.Set(spec.Key, v)
						end))
					elseif spec.Kind == "Slider" then
						widget = Kit.Slider(value, spec.Min, spec.Max, spec.Step, function(v)
							C.Settings.Set(spec.Key, v)
						end)
					else
						local options = spec.Options or {}
						if spec.Key == "UITheme" then
							-- Only themes you own (Grove is free).
							local owned = C.State.Get("Cosmetics", "Owned") or {}
							local available = {}
							for _, name in options do
								if name == "Grove" or owned["ui_" .. string.lower(name)] then
									table.insert(available, name)
								end
							end
							options = available
						end
						widget = Kit.Choice(options, value, function(v)
							C.Settings.Set(spec.Key, v)
						end)
					end
					local row = Kit.Row(spec.Name, widget, spec.Hint)
					row.LayoutOrder = order
					row.Parent = list
				end
			end
			local reset = Kit.Button("Reset " .. current .. " to defaults", {
				Style = "Secondary",
				Size = UDim2.fromOffset(260, 36),
				TextSize = Theme.Sizes.Small,
				OnClick = function()
					C.Settings.ResetTab(current)
					task.delay(0.1, render)
				end,
			})
			reset.Position = UDim2.new(0, 0, 1, -38)
			reset.Parent = body
			Kit.RepaintGradients(body)
		end
		tabs.Select(current)
		return nil
	end,
}
