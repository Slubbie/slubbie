-- Town projects at the Town Hall: fund them with coins and items to rebuild
-- the village (new shops, regions, festivals). Progress is per player — your
-- valley changes as you invest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local Format = require(Shared.Lib.Format)
local Land = require(Shared.Config.Land)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Picker = require(UI.Picker)
local C = require(UI.Parent.Controllers)

return {
	Id = "Projects",
	Title = "Town Projects",
	Icon = "🏗️",
	Size = Vector2.new(940, 620),
	Watch = { "Projects", "Coins", "Inventory", "Skills" },
	Build = function(win)
		local content = win.Content :: Frame
		local selected: string? = nil

		local function render()
			Kit.Clear(content)
			local profile = C.State.Data()
			if not profile then
				return
			end
			local estate = Stats.EstateLevel(profile)
			local left = Kit.Scroll({ Size = UDim2.new(0.42, -6, 1, 0) })
			left.Parent = content
			Kit.List(left, "Y", 6)
			for i, project in Land.Projects do
				local entry = profile.Projects[project.Id]
				local done = entry and entry.Done
				local req = project.Requires and Registry.Projects[project.Requires]
				local reqDone = not req or (profile.Projects[req.Id] and profile.Projects[req.Id].Done)
				local available = estate >= (project.Estate or 1) and reqDone
				if not selected then
					selected = project.Id
				end
				local row = Kit.new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.new(1, -8, 0, 52), LayoutOrder = i + (if done then 100 elseif available then 0 else 50), Selectable = true, Parent = left })
				Kit.Paint(row, "BackgroundColor3", if selected == project.Id then "SlotHover" else "PanelAlt")
				Kit.Corner(row, 8)
				local name = Kit.Label(project.Icon .. " " .. project.Name, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Color = if done then "Good" elseif available then "Text" else "SubText" })
				name.Position = UDim2.fromOffset(10, 4)
				name.Size = UDim2.new(1, -20, 0, 20)
				name.Parent = row
				local status = if done then "✔️ Complete" elseif not available then "🔒 " .. (if estate < (project.Estate or 1) then "Estate " .. project.Estate else "after " .. (if req then req.Name else "")) else "In progress"
				local sub = Kit.Label(status, { Size = Theme.Sizes.Tiny, Color = "SubText" })
				sub.Position = UDim2.fromOffset(10, 26)
				sub.Size = UDim2.new(1, -20, 0, 16)
				sub.Parent = row
				row.Activated:Connect(function()
					selected = project.Id
					Kit.PlaySound("UIClick")
					render()
				end)
			end
			local project = selected and Registry.Projects[selected]
			local right = Kit.Panel({ Size = UDim2.new(0.58, -6, 1, 0), Position = UDim2.new(0.42, 6, 0, 0), Color = "PanelAlt" })
			right.Parent = content
			Kit.Padding(right, 12, 14)
			if not project then
				return
			end
			local scroll = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			scroll.Parent = right
			Kit.List(scroll, "Y", 8)
			local entry = profile.Projects[project.Id] or { Coins = 0, Items = {} }
			Kit.Heading(project.Icon .. " " .. project.Name, 22).Parent = scroll
			local desc = Kit.Label(project.Description .. "\n\nUnlocks: " .. table.concat(project.Unlocks or {}, ", "), { Size = Theme.Sizes.Small, Wrap = true })
			desc.LayoutOrder = 1
			desc.Parent = scroll
			if entry.Done then
				local done = Kit.Label("✔️ Finished! Thank you for helping Evergrove grow.", { Size = Theme.Sizes.Body, Color = "Good", Wrap = true })
				done.LayoutOrder = 2
				done.Parent = scroll
				return
			end
			-- Coins
			local coinsNeeded = project.Cost - (entry.Coins or 0)
			local coinsBar = Kit.Progress({ Size = UDim2.new(1, 0, 0, 18), Color = "Accent" })
			coinsBar.Frame.LayoutOrder = 10
			coinsBar.Frame.Parent = scroll
			coinsBar.Set((entry.Coins or 0) / project.Cost, "🪙 " .. Format.Commas(entry.Coins or 0) .. " / " .. Format.Commas(project.Cost), false)
			if coinsNeeded > 0 then
				local give = Kit.Button("Donate coins", { Style = "Primary", Size = UDim2.fromOffset(160, 34), TextSize = Theme.Sizes.Small, LayoutOrder = 11, OnClick = function()
					local max = math.min(coinsNeeded, profile.Coins)
					if max < 1 then
						C.Notify.Toast("You have no coins to give", "Info")
						return
					end
					Kit.AskNumber("Donate how many coins?", max, max, function(n)
						if n then
							local ok, err = Net.Request("TownContribute", project.Id, "coins", n)
							if ok then
								C.Audio.PlayUI("Coins")
							else
								C.Notify.Toast(tostring(err), "Warning")
							end
						end
					end)
				end })
				give.Parent = scroll
			end
			-- Items
			for i, need in project.Items do
				local have = entry.Items and entry.Items[tostring(i)] or 0
				local def = Registry.Items[need[1]]
				local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 20 + i, Parent = scroll })
				local bar = Kit.Progress({ Size = UDim2.new(1, -120, 0, 18), Color = if have >= need[2] then "Good" else "Info" })
				bar.Frame.Position = UDim2.fromOffset(0, 11)
				bar.Frame.Parent = row
				bar.Set(have / need[2], (if def then def.Icon .. " " else "") .. Registry.SpecName(need[1]) .. "  " .. have .. " / " .. need[2], false)
				if have < need[2] then
					local give = Kit.Button("Give", { Style = "Secondary", Size = UDim2.fromOffset(110, 34), TextSize = Theme.Sizes.Small, OnClick = function()
						Picker.Open({
							Title = "Give " .. Registry.SpecName(need[1]),
							Filter = function(stack)
								return Registry.Matches(stack.Id, need[1]) and not stack.L
							end,
							Empty = "You don't have any " .. Registry.SpecName(need[1]) .. ".",
							OnPick = function(ref, stack)
								local count = math.min(stack.N, need[2] - have)
								local function go(n: number)
									local ok, err = Net.Request("TownContribute", project.Id, ref, n)
									if ok then
										C.Audio.PlayUI("Place")
									else
										C.Notify.Toast(tostring(err), "Warning")
									end
								end
								if count > 1 then
									Kit.AskNumber("Give how many?", count, count, function(n)
										if n then
											go(n)
										end
									end)
								else
									go(1)
								end
							end,
						})
					end })
					give.Position = UDim2.new(1, -110, 0, 3)
					give.Parent = row
				end
			end
			local note = Kit.Label("Contribute at the Town Hall board.", { Size = Theme.Sizes.Tiny, Color = "SubText" })
			note.LayoutOrder = 99
			note.Parent = scroll
			Kit.RepaintGradients(content)
		end
		render()
		return { Refresh = render }
	end,
}
