-- Social: farmers on this server (profile, visit, trade, gift), who may do
-- what on your farm (visitor permissions), and your farming cooperative.
-- Args: { Tab = "Players" | "Permissions" | "Coop" }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Format = require(Shared.Lib.Format)
local Social = require(Shared.Config.Social)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Picker = require(UI.Picker)
local C = require(UI.Parent.Controllers)

local PERM = Social.Permissions

local function request(action: string, ...: any): (boolean, any)
	local ok, result = Net.Request(action, ...)
	if not ok and result then
		C.Notify.Toast(tostring(result), "Warning")
	end
	return ok, result
end

local function levelNames(includeTrusted: boolean): ({ string }, { [string]: string })
	local names, byName = {}, {}
	for _, id in PERM.Order do
		if includeTrusted or id ~= "Trusted" then
			local def = PERM.Levels[id]
			local name = def.Icon .. " " .. def.Name
			table.insert(names, name)
			byName[name] = id
		end
	end
	return names, byName
end

local function nameOf(level: string): string
	local def = PERM.Levels[level]
	return if def then def.Icon .. " " .. def.Name else level
end

return {
	Id = "Social",
	Title = "Friends & Co-op",
	Icon = "👥",
	Size = Vector2.new(940, 600),
	Watch = { "Guild", "Farm" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local content = win.Content :: Frame
		local current = args.Tab or "Players"
		local perms: any = nil
		local guild: any = nil
		local guildLoaded = false
		local searchResults: { any }? = nil
		local render: () -> ()
		local tabs = Kit.Tabs({
			{ Id = "Players", Label = "Farmers here", Icon = "🧑‍🌾" },
			{ Id = "Permissions", Label = "Farm access", Icon = "🔑" },
			{ Id = "Coop", Label = "Co-op", Icon = "🤝" },
		}, function(id)
			current = id
			render()
			if id == "Permissions" then
				task.spawn(function()
					local ok, result = Net.Request("PermGet")
					if ok then
						perms = result
						render()
					end
				end)
			elseif id == "Coop" and not guildLoaded then
				task.spawn(function()
					local ok, result = Net.Request("GuildInfo")
					if ok then
						guild = result
						guildLoaded = true
						render()
					end
				end)
			end
		end)
		tabs.Frame.Parent = content
		local body = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -46),
			Position = UDim2.fromOffset(0, 46),
			Parent = content,
		})

		local function renderPlayers()
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = body
			Kit.List(list, "Y", 6)
			local others = {}
			for _, other in Players:GetPlayers() do
				if other ~= Players.LocalPlayer then
					table.insert(others, other)
				end
			end
			if #others == 0 then
				Kit.Empty(
					"You're the only farmer on this server right now. Invite friends — they can visit, help out and trade."
				).Parent =
					list
			end
			for i, other in others do
				local card = Kit.Card(64)
				card.LayoutOrder = i
				card.Parent = list
				local estate = other:GetAttribute("Estate")
				local title = other:GetAttribute("Title")
				local farm = other:GetAttribute("FarmName")
				local name = Kit.Label(
					other.DisplayName .. (if title then "  ·  " .. tostring(title) else ""),
					{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold }
				)
				name.Size = UDim2.new(1, -420, 0, 22)
				name.Parent = card
				local sub = Kit.Label(
					"@"
						.. other.Name
						.. (if estate then "  ·  Estate " .. tostring(estate) else "")
						.. (if farm and farm ~= "" then "  ·  " .. tostring(farm) else ""),
					{ Size = Theme.Sizes.Tiny, Color = "SubText" }
				)
				sub.Position = UDim2.fromOffset(0, 24)
				sub.Size = UDim2.new(1, -420, 0, 16)
				sub.Parent = card
				local buttons = Kit.new("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(410, 40),
					Position = UDim2.new(1, -410, 0, 4),
					Parent = card,
				})
				Kit.List(buttons, "X", 6, "Right")
				Kit.Button("Profile", {
					Style = "Secondary",
					Size = UDim2.fromOffset(90, 36),
					TextSize = Theme.Sizes.Tiny,
					OnClick = function()
						C.Windows.Open("Profile", { UserId = other.UserId })
					end,
				}).Parent =
					buttons
				Kit.Button("🏡 Visit", {
					Style = "Primary",
					Size = UDim2.fromOffset(90, 36),
					TextSize = Theme.Sizes.Tiny,
					LayoutOrder = 1,
					OnClick = function()
						local ok, result = request("VisitFarm", other.UserId)
						if ok then
							ctx.Close()
							C.Notify.Toast(
								"Visiting " .. other.DisplayName .. "'s farm — you can: " .. nameOf(result.Level),
								"Info"
							)
							C.Tutorial.Hint("Visit")
						end
					end,
				}).Parent =
					buttons
				Kit.Button("🤝 Trade", {
					Style = "Secondary",
					Size = UDim2.fromOffset(90, 36),
					TextSize = Theme.Sizes.Tiny,
					LayoutOrder = 2,
					OnClick = function()
						if request("TradeRequest", other.UserId) then
							C.Notify.Toast("Trade request sent to " .. other.DisplayName, "Info")
						end
					end,
				}).Parent =
					buttons
				Kit.Button("🎁 Gift", {
					Style = "Secondary",
					Size = UDim2.fromOffset(80, 36),
					TextSize = Theme.Sizes.Tiny,
					LayoutOrder = 3,
					OnClick = function()
						if request("StoreGiftTarget", other.UserId) then
							C.Windows.Open("Store", { GiftTo = other.UserId, GiftName = other.DisplayName })
						end
					end,
				}).Parent =
					buttons
			end
		end

		local function renderPermissions()
			if not perms then
				Kit.Empty("Loading…").Parent = body
				return
			end
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = body
			Kit.List(list, "Y", 8)
			Kit.Heading("Default for visitors", 18).Parent = list
			local names, byName = levelNames(false)
			local defaultRow = Kit.Row(
				"Everyone",
				Kit.Choice(names, nameOf(perms.Default), function(name)
					if request("PermSet", "Default", byName[name]) then
						perms.Default = byName[name]
					end
				end),
				PERM.Levels[perms.Default] and PERM.Levels[perms.Default].Description
			)
			defaultRow.LayoutOrder = 1
			defaultRow.Parent = list
			local friends = Kit.Label(
				"Your Roblox friends start at " .. nameOf(PERM.FriendDefault) .. ". Set anyone individually below.",
				{ Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true }
			)
			friends.LayoutOrder = 2
			friends.Parent = list
			local h = Kit.Heading("Farmers on this server", 18)
			h.LayoutOrder = 3
			h.Parent = list
			local allNames, allByName = levelNames(true)
			local order = 3
			for _, entry in perms.Online or {} do
				order += 1
				local row = Kit.Row(
					entry.Name,
					Kit.Choice(allNames, nameOf(entry.Level), function(name)
						request("PermSet", entry.UserId, allByName[name])
					end)
				)
				row.LayoutOrder = order
				row.Parent = list
			end
			if #(perms.Online or {}) == 0 then
				order += 1
				local e = Kit.Label("Nobody else is here right now.", { Size = Theme.Sizes.Small, Color = "SubText" })
				e.LayoutOrder = order
				e.Parent = list
			end
			order += 1
			local legend = Kit.Label("", { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true, Rich = false })
			local lines = {}
			for _, id in PERM.Order do
				local def = PERM.Levels[id]
				table.insert(lines, def.Icon .. " " .. def.Name .. " — " .. def.Description)
			end
			legend.Text = "Each level includes everything above it:\n" .. table.concat(lines, "\n")
			legend.LayoutOrder = order + 100
			legend.Parent = list
		end

		local function renderCoop()
			if not guildLoaded then
				Kit.Empty("Loading…").Parent = body
				return
			end
			if not guild then
				local left = Kit.Panel({ Size = UDim2.new(0.5, -6, 1, 0), Color = "PanelAlt" })
				left.Parent = body
				Kit.Padding(left, 12, 14)
				Kit.List(left, "Y", 8)
				Kit.Heading("Start a co-op", 18).Parent = left
				local info = Kit.Label(
					"Co-ops share weekly goals and a bank for upgrades. Up to "
						.. Social.Guilds.MaxMembers
						.. " members, across servers. Founding costs "
						.. Kit.Money(Social.Guilds.CreateCost)
						.. " (needs the Cooperative Hall project).",
					{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
				)
				info.LayoutOrder = 1
				info.Parent = left
				local box = Kit.TextBox("Co-op name", { MaxLength = Social.Guilds.NameMax })
				box.LayoutOrder = 2
				box.Parent = left
				Kit.Button("Found co-op", {
					Style = "Accent",
					Size = UDim2.new(1, 0, 0, 40),
					LayoutOrder = 3,
					OnClick = function()
						local ok = request("GuildCreate", box.Text)
						if ok then
							guildLoaded = false
							tabs.Select("Coop")
						end
					end,
				}).Parent =
					left
				local right = Kit.Panel({
					Size = UDim2.new(0.5, -6, 1, 0),
					Position = UDim2.new(0.5, 6, 0, 0),
					Color = "PanelAlt",
				})
				right.Parent = body
				Kit.Padding(right, 12, 14)
				Kit.Heading("Join one", 18).Parent = right
				local search = Kit.TextBox("🔍 Search co-ops…", { Size = UDim2.new(1, -90, 0, 34) })
				search.Position = UDim2.fromOffset(0, 32)
				search.Parent = right
				local go = Kit.Button("Search", {
					Style = "Secondary",
					Size = UDim2.fromOffset(84, 34),
					TextSize = Theme.Sizes.Small,
					OnClick = function()
						local ok, result = request("GuildSearch", search.Text)
						if ok then
							searchResults = result
							render()
						end
					end,
				})
				go.Position = UDim2.new(1, -84, 0, 32)
				go.Parent = right
				local results = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -76), Position = UDim2.fromOffset(0, 76) })
				results.Parent = right
				Kit.List(results, "Y", 4)
				for i, entry in ipairs(searchResults or {}) do
					local card = Kit.Card(44)
					card.LayoutOrder = i
					card.Parent = results
					local l = Kit.Label(
						"🤝 " .. tostring(entry.Name) .. "  ·  " .. tostring(entry.Members or "?") .. " members",
						{ Size = Theme.Sizes.Small }
					)
					l.Size = UDim2.new(1, -90, 1, 0)
					l.Parent = card
					local join = Kit.Button("Join", {
						Style = "Primary",
						Size = UDim2.fromOffset(80, 30),
						TextSize = Theme.Sizes.Tiny,
						OnClick = function()
							if request("GuildJoin", entry.Id) then
								guildLoaded = false
								tabs.Select("Coop")
							end
						end,
					})
					join.Position = UDim2.new(1, -80, 0, 2)
					join.Parent = card
				end
				if searchResults and #searchResults == 0 then
					Kit.Empty("No co-ops found.").Parent = results
				end
				return
			end
			local g = guild.Guild
			local left = Kit.Scroll({ Size = UDim2.new(0.5, -6, 1, 0) })
			left.Parent = body
			Kit.List(left, "Y", 8)
			Kit.Heading((if g.Upgrades and g.Upgrades.emblem then "🏅 " else "🤝 ") .. g.Name, 22).Parent = left
			local count = 0
			for _ in g.Members do
				count += 1
			end
			local bank = Kit.Label(
				"🏦 Bank "
					.. Kit.Money(g.Bank or 0)
					.. "   ·   ⭐ "
					.. Format.Commas(g.Points or 0)
					.. " points   ·   "
					.. count
					.. " / "
					.. Social.Guilds.MaxMembers
					.. " members",
				{ Size = Theme.Sizes.Small }
			)
			bank.LayoutOrder = 1
			bank.Parent = left
			local donate = Kit.Button("Contribute coins", {
				Style = "Primary",
				Size = UDim2.fromOffset(180, 34),
				TextSize = Theme.Sizes.Small,
				LayoutOrder = 2,
				OnClick = function()
					local coins = C.State.Get("Coins") or 0
					if coins < 1 then
						return
					end
					Kit.AskNumber("Contribute how many coins?", coins, math.min(coins, 1000), function(n)
						if n and request("GuildContribute", "coins", n) then
							guildLoaded = false
							tabs.Select("Coop")
						end
					end)
				end,
			})
			donate.Parent = left
			local donateItems = Kit.Button("Contribute items", {
				Style = "Secondary",
				Size = UDim2.fromOffset(180, 34),
				TextSize = Theme.Sizes.Small,
				LayoutOrder = 3,
				OnClick = function()
					Picker.Open({
						Title = "Contribute to the co-op bank",
						Filter = function(stack)
							return not stack.L
						end,
						OnPick = function(ref, stack)
							Kit.AskNumber("How many?", stack.N, stack.N, function(n)
								if n and request("GuildContribute", ref, n) then
									guildLoaded = false
									tabs.Select("Coop")
								end
							end)
						end,
					})
				end,
			})
			donateItems.Parent = left
			local wh = Kit.Heading("This week", 16)
			wh.LayoutOrder = 10
			wh.Parent = left
			for i, goal in guild.Weekly or {} do
				local progress = (g.Weekly and g.Weekly.Week == guild.Week and g.Weekly.Progress[goal.Id]) or 0
				local done = g.Weekly and g.Weekly.Week == guild.Week and g.Weekly.Done[goal.Id]
				local bar = Kit.Progress({ Size = UDim2.new(1, -8, 0, 18), Color = if done then "Good" else "Accent" })
				bar.Frame.LayoutOrder = 10 + i
				bar.Frame.Parent = left
				bar.Set(
					progress / goal.Goal,
					goal.Text .. "  " .. Format.Short(progress) .. "/" .. Format.Short(goal.Goal),
					false
				)
			end
			local uh = Kit.Heading("Upgrades", 16)
			uh.LayoutOrder = 30
			uh.Parent = left
			local myRole = g.Members[tostring(Players.LocalPlayer.UserId)]
				and g.Members[tostring(Players.LocalPlayer.UserId)].Role
			for i, upgrade in guild.Upgrades or {} do
				local owned = g.Upgrades and g.Upgrades[upgrade.Id]
				local card = Kit.Card(56)
				card.LayoutOrder = 30 + i
				card.Parent = left
				local l = Kit.Label(
					upgrade.Icon
						.. " "
						.. upgrade.Name
						.. (if owned then "  ✔" else "  ·  " .. Kit.Money(upgrade.Cost)),
					{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold }
				)
				l.Size = UDim2.new(1, -90, 0, 20)
				l.Parent = card
				local d = Kit.Label(upgrade.Description, { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
				d.Position = UDim2.fromOffset(0, 20)
				d.Size = UDim2.new(1, -90, 0, 0)
				d.Parent = card
				if not owned and (myRole == "Leader" or myRole == "Officer") then
					local buy = Kit.Button("Buy", {
						Style = "Accent",
						Size = UDim2.fromOffset(80, 30),
						TextSize = Theme.Sizes.Tiny,
						OnClick = function()
							if request("GuildContribute", "upgrade:" .. upgrade.Id, 1) then
								guildLoaded = false
								tabs.Select("Coop")
							end
						end,
					})
					buy.Position = UDim2.new(1, -80, 0, 4)
					buy.Parent = card
					Kit.SetEnabled(buy, (g.Bank or 0) >= upgrade.Cost)
				end
			end
			local right = Kit.Scroll({ Size = UDim2.new(0.5, -6, 1, -44), Position = UDim2.new(0.5, 6, 0, 0) })
			right.Parent = body
			Kit.List(right, "Y", 4)
			Kit.Heading("Members", 16).Parent = right
			local members = {}
			for uid, m in g.Members do
				table.insert(members, { Uid = uid, M = m })
			end
			table.sort(members, function(a, b)
				return (a.M.Points or 0) > (b.M.Points or 0)
			end)
			for i, entry in members do
				local online = Players:GetPlayerByUserId(tonumber(entry.Uid) :: number)
				local l = Kit.Label(
					(if online then "🟢 " else "⚪ ")
						.. tostring(entry.M.Name)
						.. "  ·  "
						.. tostring(entry.M.Role)
						.. "  ·  ⭐ "
						.. Format.Commas(entry.M.Points or 0),
					{ Size = Theme.Sizes.Small }
				)
				l.LayoutOrder = i
				l.Parent = right
			end
			local leave = Kit.Button("Leave co-op", {
				Style = "Danger",
				Size = UDim2.fromOffset(160, 36),
				TextSize = Theme.Sizes.Small,
				OnClick = function()
					Kit.Confirm("Leave " .. g.Name .. "?", "Your contributions stay with the co-op.", function(yes)
						if yes and request("GuildLeave") then
							guild = nil
							render()
						end
					end, "Leave", true)
				end,
			})
			leave.Position = UDim2.new(0.5, 6, 1, -38)
			leave.Parent = body
		end

		render = function()
			Kit.Clear(body)
			if current == "Players" then
				renderPlayers()
			elseif current == "Permissions" then
				renderPermissions()
			else
				renderCoop()
			end
			Kit.RepaintGradients(body)
		end
		tabs.Select(current)
		local conns = {
			Players.PlayerAdded:Connect(function()
				if current == "Players" then
					render()
				end
			end),
			Players.PlayerRemoving:Connect(function()
				task.defer(function()
					if current == "Players" then
						render()
					end
				end)
			end),
		}
		return {
			Refresh = function()
				if current == "Players" then
					render()
				end
			end,
			Destroy = function()
				for _, c in conns do
					c:Disconnect()
				end
			end,
		}
	end,
}
