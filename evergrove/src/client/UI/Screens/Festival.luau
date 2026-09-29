-- The festival hub: activities (scavenger hunts, contests with a transparent
-- score preview, the fishing derby, races), token challenges, the token
-- shop and live cross-server leaderboards. Between festivals it shows what's
-- coming up.
--
-- Races run from here: RunRace draws the checkpoints and reports each one
-- as you reach it (the server checks timing and distance).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Format = require(Shared.Lib.Format)
local GameTime = require(Shared.Lib.GameTime)
local ContestMath = require(Shared.Lib.ContestMath)
local Festivals = require(Shared.Config.Festivals)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Picker = require(UI.Picker)
local Describe = require(UI.Describe)
local C = require(UI.Parent.Controllers)

local CRITERIA = { "Quality", "Size", "Rarity", "Mutations", "Care" }
local PLACE_ICON = { "🥇", "🥈", "🥉" }

local Screen = {
	Id = "Festival",
	Title = "Festival",
	Icon = "🎪",
	Size = Vector2.new(980, 620),
	Watch = { "Festival", "Tokens", "Inventory" },
}

-- Races ---------------------------------------------------------------------------------------------------------------

local race: {
	Activity: string,
	Checkpoints: { Vector3 },
	Next: number,
	Parts: { BasePart },
	Label: TextLabel?,
	Start: number,
	Conn: RBXScriptConnection?,
}? =
	nil

local function endRace()
	local r = race
	if not r then
		return
	end
	race = nil
	if r.Conn then
		r.Conn:Disconnect()
	end
	for _, p in r.Parts do
		p:Destroy()
	end
	if r.Label then
		r.Label:Destroy()
	end
end

function Screen.RunRace(activityId: string, checkpoints: { Vector3 })
	endRace()
	local parts = {}
	for i, point in checkpoints do
		local ring = Instance.new("Part")
		ring.Name = "Checkpoint" .. i
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.Material = Enum.Material.Neon
		ring.Color = if i == #checkpoints then Color3.fromRGB(255, 210, 80) else Color3.fromRGB(120, 220, 255)
		ring.Transparency = if i == 2 then 0.3 else 0.75
		ring.Size = Vector3.new(0.6, 16, 16)
		ring.CFrame = CFrame.new(point + Vector3.new(0, 6, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = workspace:FindFirstChild("ClientFX") or workspace
		table.insert(parts, ring)
	end
	local label = Kit.Label("", { Size = 22, Font = Theme.Fonts.Heading, Align = "Center" })
	label.Size = UDim2.new(1, 0, 0, 30)
	label.Position = UDim2.new(0, 0, 0, 120)
	label.TextStrokeTransparency = 0.4
	label.Parent = C.UI.Layer("Overlay")
	local r = {
		Activity = activityId,
		Checkpoints = checkpoints,
		Next = 2,
		Parts = parts,
		Label = label,
		Start = os.clock(),
		Conn = nil :: RBXScriptConnection?,
	}
	race = r
	local busy = false
	r.Conn = RunService.Heartbeat:Connect(function()
		local character = Players.LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart or race ~= r then
			return
		end
		label.Text =
			string.format("🏁 %.2f s   ·   checkpoint %d / %d", os.clock() - r.Start, r.Next - 1, #checkpoints - 1)
		local target = checkpoints[r.Next]
		if target and not busy and (rootPart.Position - target).Magnitude < 18 then
			busy = true
			local index = r.Next
			task.spawn(function()
				local ok, result = Net.Request("FestivalAction", "Checkpoint", { Activity = activityId, Index = index })
				busy = false
				if race ~= r then
					return
				end
				if not ok then
					C.Notify.Toast(tostring(result), "Warning")
					endRace()
					return
				end
				C.Audio.PlayUI("UIConfirm")
				local ring = parts[index]
				if ring then
					ring.Transparency = 1
				end
				if result.Finished then
					C.Notify.Banner(
						"🏁 Finished!",
						string.format("%.2f seconds · best %.2f", result.Time, result.Best),
						nil,
						"Festival",
						4
					)
					endRace()
				else
					r.Next = result.Next
					local nextRing = parts[r.Next]
					if nextRing then
						nextRing.Transparency = 0.3
					end
				end
			end)
		end
	end)
end

-- Screen -----------------------------------------------------------------------------------------------------------

function Screen.Build(win, ctx)
	local content = win.Content :: Frame
	local data: any = nil
	local current = (ctx.Args and ctx.Args.Tab) or "Activities"
	local render: () -> ()
	local body = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -46),
		Position = UDim2.fromOffset(0, 46),
		Parent = content,
	})
	local tabs = Kit.Tabs({
		{ Id = "Activities", Label = "Activities", Icon = "🎪" },
		{ Id = "Challenges", Label = "Challenges", Icon = "🎟️" },
		{ Id = "Shop", Label = "Token shop", Icon = "🛍️" },
		{ Id = "Boards", Label = "Leaderboards", Icon = "🏆" },
	}, function(id)
		current = id
		render()
	end)
	tabs.Frame.Parent = content

	local function fetch()
		local ok, result = Net.Request("FestivalGet")
		if ok then
			data = result
			render()
		end
	end

	local function def(): any?
		return data and data.Active and Registry.Festivals[data.Id]
	end

	local function contestEntry(a: any)
		local acceptsAnimals = table.find(a.Accept or {}, "Animal") ~= nil
		local function showPreview(entry: any, submit: () -> ())
			local score, points = ContestMath.Score(a, entry)
			local lines = {}
			for _, key in CRITERIA do
				local weight = a.Scoring[key] or 0
				if weight > 0 then
					table.insert(lines, string.format("%s  %.1f / %d", key, points[key] or 0, weight))
				end
			end
			Kit.Confirm(
				string.format("Score: %.1f / 100", score),
				table.concat(lines, "\n")
					.. "\n\nYou can enter once. The best scores across all servers win when the festival ends.",
				function(yes)
					if yes then
						submit()
					end
				end,
				"Enter"
			)
		end
		if acceptsAnimals then
			local profile = C.State.Data()
			local animals = (profile and profile.Farm and profile.Farm.Animals) or {}
			local layer = Kit.ModalLayer
			if not layer then
				return
			end
			local shade = Kit.new("TextButton", {
				AutoButtonColor = false,
				Text = "",
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.45,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 80,
				Parent = layer,
			})
			local panel = Kit.Panel({ Size = UDim2.fromOffset(480, 420), Shadow = true })
			panel.AnchorPoint = Vector2.new(0.5, 0.5)
			panel.Position = UDim2.fromScale(0.5, 0.5)
			panel.Parent = shade
			Kit.Padding(panel, 14, 16)
			Kit.Heading("Choose your entry", 20).Parent = panel
			local list = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -76), Position = UDim2.fromOffset(0, 34) })
			list.Parent = panel
			Kit.List(list, "Y", 4)
			for aid, animal in animals do
				local species = Registry.Species[animal.Sp]
				local entry = { Kind = "Animal", Animal = animal }
				local score = ContestMath.Score(a, entry)
				local b = Kit.Button(
					string.format("%s %s  ·  %.1f pts", if species then species.Icon else "🐾", animal.Nm, score),
					{
						Style = "Secondary",
						Size = UDim2.new(1, -8, 0, 40),
						TextSize = Theme.Sizes.Small,
						OnClick = function()
							shade:Destroy()
							showPreview(entry, function()
								local ok, err = Net.Request("FestivalAction", "Enter", { Activity = a.Id, Aid = aid })
								if not ok then
									C.Notify.Toast(tostring(err), "Warning")
								end
								fetch()
							end)
						end,
					}
				)
				b.Parent = list
			end
			local cancel = Kit.Button("Cancel", {
				Style = "Ghost",
				Size = UDim2.fromOffset(120, 34),
				OnClick = function()
					shade:Destroy()
				end,
			})
			cancel.Position = UDim2.new(1, -120, 1, -34)
			cancel.Parent = panel
			return
		end
		Picker.Open({
			Title = "Enter " .. a.Name,
			Filter = function(stack)
				return ContestMath.Accepts(a, { Kind = "Item", Stack = stack })
			end,
			Note = function(stack)
				local score = ContestMath.Score(a, { Kind = "Item", Stack = stack })
				return string.format("scores %.1f / 100", score)
			end,
			Empty = "You don't have anything the judges would accept.",
			OnPick = function(ref, stack)
				showPreview({ Kind = "Item", Stack = stack }, function()
					local ok, err = Net.Request("FestivalAction", "Enter", { Activity = a.Id, Ref = ref })
					if not ok then
						C.Notify.Toast(tostring(err), "Warning")
					end
					fetch()
				end)
			end,
		})
	end

	local function renderInactive()
		local nextDef = data and data.Next and Registry.Festivals[data.Next]
		local panel = Kit.Panel({ Size = UDim2.fromScale(1, 1), Color = "PanelAlt" })
		panel.Parent = body
		Kit.Padding(panel, 20, 24)
		Kit.List(panel, "Y", 10)
		Kit.Heading("No festival today", 22).Parent = panel
		if nextDef then
			local l = Kit.Label(
				nextDef.Icon
					.. " "
					.. nextDef.Name
					.. " is "
					.. (if data.NextInDays == 0
						then "later today"
						elseif data.NextInDays == 1 then "tomorrow"
						else "in " .. data.NextInDays .. " days")
					.. " ("
					.. Describe.SeasonDay(nextDef.Season, nextDef.Day)
					.. ", "
					.. Format.Clock(nextDef.Hours[1])
					.. "–"
					.. Format.Clock(nextDef.Hours[2])
					.. ").\n"
					.. nextDef.Description,
				{ Size = Theme.Sizes.Body, Wrap = true }
			)
			l.LayoutOrder = 1
			l.Parent = panel
		end
		local all = {}
		for _, f in Festivals.List do
			table.insert(all, f.Icon .. " " .. f.Name .. " — " .. Describe.SeasonDay(f.Season, f.Day))
		end
		local list = Kit.Label(
			"This year's festivals:\n" .. table.concat(all, "\n"),
			{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
		)
		list.LayoutOrder = 2
		list.Parent = panel
	end

	local function renderActivities()
		local f = def() :: any
		local st = data.State
		local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
		list.Parent = body
		Kit.List(list, "Y", 8)
		local left = data.Ends - GameTime.Now()
		local head = Kit.Label(
			f.Description
				.. "   ·   ends in "
				.. Format.Duration(math.max(0, left))
				.. "   ·   "
				.. Kit.Money(C.State.Get("Tokens") or 0, "Tokens"),
			{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
		)
		head.Parent = list
		for i, a in f.Activities do
			local card = Kit.Card()
			card.LayoutOrder = i
			card.Parent = list
			Kit.List(card, "Y", 6)
			Kit.Label(a.Icon .. " " .. a.Name, { Size = Theme.Sizes.Body, Font = Theme.Fonts.Bold }).Parent = card
			local line: string
			if a.Kind == "Scavenger" then
				local found = 0
				for _ in (st.Found and st.Found[a.Id]) or {} do
					found += 1
				end
				line = "Find them around the village"
					.. (if a.Dig then " (dig with your shovel)" else "")
					.. ": "
					.. found
					.. " / "
					.. a.Count
					.. " · "
					.. a.Tokens
					.. " 🎟️ each"
			elseif a.Kind == "Contest" then
				local entry = st.Entries and st.Entries[a.Id]
				local weights = {}
				for _, key in CRITERIA do
					if (a.Scoring[key] or 0) > 0 then
						table.insert(weights, key .. " " .. a.Scoring[key] .. "%")
					end
				end
				line = "Judged on "
					.. table.concat(weights, ", ")
					.. (if entry then string.format("\nYour entry scored %.1f / 100", entry.Score) else "")
			elseif a.Kind == "Derby" then
				line = "Catch the biggest fish during the festival"
					.. (if st.Best and st.Best[a.Id] then " · your best: " .. st.Best[a.Id] .. " cm" else "")
			else
				line = "Ride through every checkpoint as fast as you can"
					.. (if st.Best and st.Best[a.Id] then string.format(" · your best: %.2f s", st.Best[a.Id]) else "")
			end
			local l = Kit.Label(line, { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
			l.LayoutOrder = 1
			l.Parent = card
			if a.Kind == "Contest" and not (st.Entries and st.Entries[a.Id]) then
				Kit.Button("Enter", {
					Style = "Accent",
					Size = UDim2.fromOffset(140, 34),
					TextSize = Theme.Sizes.Small,
					LayoutOrder = 2,
					OnClick = function()
						contestEntry(a)
					end,
				}).Parent =
					card
			elseif a.Kind == "Race" then
				Kit.Button(if race and race.Activity == a.Id then "Restart race" else "Start race", {
					Style = "Accent",
					Size = UDim2.fromOffset(140, 34),
					TextSize = Theme.Sizes.Small,
					LayoutOrder = 2,
					OnClick = function()
						local ok, result = Net.Request("FestivalAction", "RaceStart", { Activity = a.Id })
						if ok then
							ctx.Close()
							Screen.RunRace(a.Id, result.Checkpoints)
						else
							C.Notify.Toast(tostring(result), "Warning")
						end
					end,
				}).Parent =
					card
			end
		end
	end

	local function renderChallenges()
		local f = def() :: any
		local st = data.State
		local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
		list.Parent = body
		Kit.List(list, "Y", 6)
		for i, ch in f.Challenges do
			local have = (st.Ch and st.Ch[ch.Id]) or 0
			local done = st.Done and st.Done[ch.Id]
			local row = Kit.new(
				"Frame",
				{ BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 44), LayoutOrder = i, Parent = list }
			)
			local l = Kit.Label(
				(if done then "✔️ " else "🎟️ ") .. ch.Text .. "  (+" .. ch.Tokens .. ")",
				{ Size = Theme.Sizes.Small, Color = if done then "Good" else "Text" }
			)
			l.Size = UDim2.new(1, 0, 0, 20)
			l.Parent = row
			local bar = Kit.Progress({ Size = UDim2.new(1, 0, 0, 12), Color = if done then "Good" else "Accent" })
			bar.Frame.Position = UDim2.fromOffset(0, 24)
			bar.Frame.Parent = row
			bar.Set(have / ch.Count, have .. " / " .. ch.Count, false)
		end
	end

	local function renderShop()
		local f = def() :: any
		local st = data.State
		local grid = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
		grid.Parent = body
		local layout = Kit.new("UIGridLayout", {
			CellSize = UDim2.new(0.333, -8, 0, 110),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		layout.FillDirectionMaxCells = 3
		for i, entry in f.Shop do
			local item = Registry.Items[entry.Id]
			if item then
				local bought = (st.Bought and st.Bought[entry.Id]) or 0
				local card = Kit.Card(110)
				card.LayoutOrder = i
				card.Parent = grid
				local slot = Kit.ItemSlot(52)
				slot.Button.Active = false
				slot.Set({ Id = entry.Id, N = 1 })
				slot.Button.Parent = card
				local name = Kit.Label(item.Name, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Wrap = true })
				name.Position = UDim2.fromOffset(60, 0)
				name.Size = UDim2.new(1, -60, 0, 0)
				name.Parent = card
				local price = Kit.Label(
					Kit.Money(entry.Price, "Tokens")
						.. (if entry.Stock then "  ·  " .. (entry.Stock - bought) .. " left" else ""),
					{ Size = Theme.Sizes.Tiny, Color = "Accent" }
				)
				price.Position = UDim2.fromOffset(60, 40)
				price.Size = UDim2.new(1, -60, 0, 16)
				price.Parent = card
				local buy = Kit.Button("Buy", {
					Style = "Primary",
					Size = UDim2.new(1, 0, 0, 30),
					TextSize = Theme.Sizes.Small,
					OnClick = function()
						local ok, err = Net.Request("FestivalAction", "Buy", { Id = entry.Id, N = 1 })
						if ok then
							C.Audio.PlayUI("Coins")
							fetch()
						else
							C.Notify.Toast(tostring(err), "Warning")
						end
					end,
				})
				buy.Position = UDim2.new(0, 0, 1, -30)
				buy.Parent = card
				Kit.SetEnabled(
					buy,
					(C.State.Get("Tokens") or 0) >= entry.Price and (not entry.Stock or bought < entry.Stock)
				)
				Kit.AttachTooltip(card, function()
					return Kit.ItemTooltip({ Id = entry.Id, N = 1 })
				end)
			end
		end
	end

	local function renderBoards()
		local f = def() :: any
		local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
		list.Parent = body
		Kit.List(list, "Y", 8)
		local prizes = f.Prizes or {}
		local prizeLines = {}
		for i, place in { "First", "Second", "Third" } do
			if prizes[place] then
				table.insert(prizeLines, PLACE_ICON[i] .. " " .. table.concat(Describe.Rewards(prizes[place]), ", "))
			end
		end
		if #prizeLines > 0 then
			local p = Kit.Label(
				"Prizes (mailed when the festival ends):\n" .. table.concat(prizeLines, "\n"),
				{ Size = Theme.Sizes.Small, Color = "Accent", Wrap = true }
			)
			p.Parent = list
		end
		local order = 1
		for _, a in f.Activities do
			local board = data.Boards and data.Boards[a.Id]
			if board then
				order += 1
				local card = Kit.Card()
				card.LayoutOrder = order
				card.Parent = list
				Kit.List(card, "Y", 3)
				Kit.Label(a.Icon .. " " .. a.Name, { Size = Theme.Sizes.Body, Font = Theme.Fonts.Bold }).Parent = card
				if #board == 0 then
					local e =
						Kit.Label("No entries yet — be the first!", { Size = Theme.Sizes.Small, Color = "SubText" })
					e.LayoutOrder = 1
					e.Parent = card
				end
				for rank, row in board do
					local meta = row.Meta or {}
					local what = if meta.Item
						then " · " .. ItemUtil.DisplayName({ Id = meta.Item, N = 1, Q = meta.Q, M = meta.M })
						elseif meta.Animal then " · " .. meta.Animal
						else ""
					local value = if a.Kind == "Race"
						then string.format("%.2f s", row.Value)
						elseif a.Kind == "Derby" then tostring(row.Value) .. " cm"
						else string.format("%.1f pts", row.Value)
					local mine = row.UserId == Players.LocalPlayer.UserId
					local l = Kit.Label(
						(PLACE_ICON[rank] or ("#" .. rank))
							.. "  "
							.. tostring(meta.Name or row.UserId)
							.. what
							.. "  —  "
							.. value,
						{
							Size = Theme.Sizes.Small,
							Color = if mine then "Accent" else "Text",
							Font = if mine then Theme.Fonts.Bold else nil,
						}
					)
					l.LayoutOrder = rank
					l.Parent = card
				end
			end
		end
	end

	render = function()
		Kit.Clear(body)
		if not data then
			Kit.Empty("Loading the festival…").Parent = body
			return
		end
		local f = def()
		tabs.Frame.Visible = f ~= nil
		if not f then
			renderInactive()
			return
		end
		win.Title.Text = f.Icon .. "  " .. f.Name
		if current == "Activities" then
			renderActivities()
		elseif current == "Challenges" then
			renderChallenges()
		elseif current == "Shop" then
			renderShop()
		else
			renderBoards()
		end
		Kit.RepaintGradients(body)
	end

	tabs.Select(current)
	task.spawn(fetch)
	return {
		Refresh = function()
			task.spawn(fetch)
		end,
	}
end

return Screen
