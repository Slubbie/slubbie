-- Quest log: active quests (with tracking for the HUD), daily requests and
-- weekly challenges, the village board (community goal + quests you can pick
-- up) and a record of everything you've finished.
-- Args: { Tab = "Active" | "Daily" | "Board" | "Done", Quest = questId }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Format = require(Shared.Lib.Format)
local QuestsConfig = require(Shared.Config.Quests)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Describe = require(UI.Describe)
local C = require(UI.Parent.Controllers)

local KIND_ICON = { Story = "📖", Npc = "💬", Side = "🧭", Daily = "☀️", Weekly = "📅", Community = "🤝" }
local KIND_ORDER = { Story = 1, Npc = 2, Side = 3 }

local templateById: { [string]: any } = {}
for _, t in QuestsConfig.Daily do
	templateById[t.Id] = t
end
for _, t in QuestsConfig.Weekly do
	templateById[t.Id] = t
end

local function request(action: string, ...: any): boolean
	local ok, err = Net.Request(action, ...)
	if not ok and err then
		C.Notify.Toast(tostring(err), "Warning")
	end
	return ok
end

local function untilUtcMidnight(): number
	local now = os.time()
	return 86400 - now % 86400
end

return {
	Id = "Quests",
	Title = "Quests",
	Icon = "📜",
	Size = Vector2.new(940, 600),
	Watch = { "Quests", "Inventory", "Skills", "Friendship" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local content = win.Content :: Frame
		local body = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -46),
			Position = UDim2.fromOffset(0, 46),
			Parent = content,
		})
		local current = args.Tab or "Active"
		local selected: string? = args.Quest
		local board: any = nil
		local render: () -> ()

		local function objectiveRows(
			parent: Instance,
			objectives: { any },
			progress: { number }?,
			order: number
		): number
			local profile = C.State.Data()
			for i, objective in objectives do
				local cur, goal = Describe.Progress(profile, objective, progress and progress[i])
				local row = Kit.new("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 40),
					LayoutOrder = order + i,
					Parent = parent,
				})
				local label = Kit.Label(
					(if cur >= goal then "☑ " else "☐ ") .. Describe.Objective(objective),
					{ Size = Theme.Sizes.Small, Color = if cur >= goal then "Good" else "Text" }
				)
				label.Size = UDim2.new(1, 0, 0, 20)
				label.Parent = row
				local bar =
					Kit.Progress({ Size = UDim2.new(1, 0, 0, 12), Color = if cur >= goal then "Good" else "Accent" })
				bar.Frame.Position = UDim2.fromOffset(0, 22)
				bar.Frame.Parent = row
				bar.Set(cur / math.max(goal, 1), Format.Short(cur) .. " / " .. Format.Short(goal), false)
			end
			return order + #objectives
		end

		local function rewardRow(parent: Instance, rewards: any, order: number)
			local lines = Describe.Rewards(rewards)
			if #lines == 0 then
				return
			end
			local label = Kit.Label(
				"🎁 " .. table.concat(lines, "   "),
				{ Size = Theme.Sizes.Small, Color = "Accent", Wrap = true }
			)
			label.LayoutOrder = order
			label.Parent = parent
		end

		-- Active ---------------------------------------------------------------------------------------------------
		local function renderActive()
			local profile = C.State.Data()
			local quests = profile and profile.Quests or { Active = {}, Tracked = {} }
			local left = Kit.Scroll({ Size = UDim2.new(0.4, -6, 1, 0) })
			left.Parent = body
			Kit.List(left, "Y", 4)
			local right =
				Kit.Panel({ Size = UDim2.new(0.6, -6, 1, 0), Position = UDim2.new(0.4, 6, 0, 0), Color = "PanelAlt" })
			right.Parent = body
			Kit.Padding(right, 12, 14)
			local ids = {}
			for questId in quests.Active do
				if Registry.Quests[questId] then
					table.insert(ids, questId)
				end
			end
			table.sort(ids, function(a, b)
				local qa, qb = Registry.Quests[a], Registry.Quests[b]
				local ka, kb = KIND_ORDER[qa.Kind] or 9, KIND_ORDER[qb.Kind] or 9
				if ka ~= kb then
					return ka < kb
				end
				return qa.Name < qb.Name
			end)
			if not selected or not quests.Active[selected] then
				selected = ids[1]
			end
			if #ids == 0 then
				Kit.Empty("No active quests. Talk to villagers or check the board.").Parent = left
			end
			for i, questId in ids do
				local quest = Registry.Quests[questId]
				local state = quests.Active[questId]
				local tracked = table.find(quests.Tracked, questId) ~= nil
				local row = Kit.new("TextButton", {
					AutoButtonColor = false,
					Text = "",
					Size = UDim2.new(1, -8, 0, 48),
					LayoutOrder = i,
					Selectable = true,
					Parent = left,
				})
				Kit.Paint(row, "BackgroundColor3", if questId == selected then "SlotHover" else "PanelAlt")
				Kit.Corner(row, 8)
				local name = Kit.Label((KIND_ICON[quest.Kind] or "📜") .. " " .. quest.Name, {
					Size = Theme.Sizes.Small,
					Font = Theme.Fonts.Bold,
					Color = if state.Ready then "Good" else "Text",
				})
				name.Position = UDim2.fromOffset(10, 4)
				name.Size = UDim2.new(1, -40, 0, 20)
				name.Parent = row
				local giver = quest.Giver and Registry.Npcs[quest.Giver]
				local sub = Kit.Label(
					(if state.Ready then "✔️ Ready to hand in" else quest.Kind)
						.. (if giver then " · " .. giver.Name else ""),
					{ Size = Theme.Sizes.Tiny, Color = "SubText" }
				)
				sub.Position = UDim2.fromOffset(10, 24)
				sub.Size = UDim2.new(1, -40, 0, 16)
				sub.Parent = row
				if tracked then
					local pin = Kit.Label("📌", { Size = 14, Align = "Right" })
					pin.Size = UDim2.new(0, 26, 1, 0)
					pin.Position = UDim2.new(1, -30, 0, 0)
					pin.Parent = row
				end
				row.Activated:Connect(function()
					selected = questId
					Kit.PlaySound("UIClick")
					render()
				end)
			end
			-- Details
			if not selected then
				Kit.Label("Pick a quest to see its details.", { Color = "SubText" }).Parent = right
				return
			end
			local questId = selected :: string
			local quest = Registry.Quests[questId]
			local state = quests.Active[questId]
			local scroll = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -46) })
			scroll.Parent = right
			Kit.List(scroll, "Y", 8)
			local title = Kit.Heading((KIND_ICON[quest.Kind] or "📜") .. " " .. quest.Name, 22)
			title.Parent = scroll
			local giver = quest.Giver and Registry.Npcs[quest.Giver]
			local turnIn = quest.TurnIn and Registry.Npcs[quest.TurnIn]
			local who = Kit.Label(
				(if giver then "From " .. giver.Icon .. " " .. giver.Name else quest.Kind .. " quest")
					.. (
						if turnIn
							then "  ·  hand in to " .. turnIn.Icon .. " " .. turnIn.Name
							else "  ·  completes automatically"
					),
				{ Size = Theme.Sizes.Tiny, Color = "SubText" }
			)
			who.LayoutOrder = 1
			who.Parent = scroll
			local desc = Kit.Label(quest.Description, { Wrap = true, Size = Theme.Sizes.Small })
			desc.LayoutOrder = 2
			desc.Parent = scroll
			local order = objectiveRows(scroll, quest.Objectives, state.P, 10)
			rewardRow(scroll, quest.Rewards, order + 1)
			if state.Ready and turnIn then
				local ready = Kit.Label(
					"✔️ All done! Talk to " .. turnIn.Name .. " to hand it in.",
					{ Size = Theme.Sizes.Small, Color = "Good", Wrap = true }
				)
				ready.LayoutOrder = order + 2
				ready.Parent = scroll
			end
			local buttons = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 38),
				Position = UDim2.new(0, 0, 1, -38),
				Parent = right,
			})
			Kit.List(buttons, "X", 8)
			local tracked = table.find(quests.Tracked, questId) ~= nil
			Kit.Button(if tracked then "📌 Untrack" else "📌 Track", {
				Style = "Secondary",
				Size = UDim2.fromOffset(130, 36),
				TextSize = Theme.Sizes.Small,
				OnClick = function()
					request("QuestTrack", questId)
				end,
			}).Parent =
				buttons
			if quest.Kind ~= "Story" then
				Kit.Button("Abandon", {
					Style = "Danger",
					Size = UDim2.fromOffset(110, 36),
					TextSize = Theme.Sizes.Small,
					LayoutOrder = 2,
					OnClick = function()
						Kit.Confirm(
							"Abandon quest?",
							'Progress on "' .. quest.Name .. '" will be lost. You can pick it up again later.',
							function(yes)
								if yes then
									request("QuestAbandon", questId)
								end
							end,
							"Abandon",
							true
						)
					end,
				}).Parent =
					buttons
			end
			if not quest.TurnIn and not state.Ready then
				local hint = Kit.Label(
					"Tracked quests show on your screen (max " .. QuestsConfig.MaxTracked .. ").",
					{ Size = Theme.Sizes.Tiny, Color = "SubText" }
				)
				hint.Size = UDim2.fromOffset(260, 36)
				hint.LayoutOrder = 3
				hint.Parent = buttons
			end
		end

		-- Daily & weekly ------------------------------------------------------------------------------------------------
		local function renderDaily()
			local profile = C.State.Data()
			local scroll = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			scroll.Parent = body
			Kit.List(scroll, "Y", 8)
			local order = 0
			local function section(title: string, list: { any }, resetText: string)
				order += 1
				local h = Kit.Heading(title, 18)
				h.LayoutOrder = order
				h.Parent = scroll
				order += 1
				local sub = Kit.Label(resetText, { Size = Theme.Sizes.Tiny, Color = "SubText" })
				sub.LayoutOrder = order
				sub.Parent = scroll
				for _, entry in list do
					order += 1
					local template = templateById[entry.Id]
					local card = Kit.Card()
					card.LayoutOrder = order
					card.Parent = scroll
					Kit.List(card, "Y", 4)
					local name = Kit.Label(
						(if entry.Done then "✔️ " else "") .. (if template then template.Name else entry.Id),
						{
							Size = Theme.Sizes.Small,
							Font = Theme.Fonts.Bold,
							Color = if entry.Done then "Good" else "Text",
						}
					)
					name.Parent = card
					objectiveRows(card, { entry }, { entry.P or 0 }, 1)
					if template then
						rewardRow(card, template.Reward, 10)
					end
				end
			end
			local quests = profile and profile.Quests
			section(
				"☀️ Daily requests",
				(quests and quests.Daily and quests.Daily.List) or {},
				"New requests in " .. Format.Duration(untilUtcMidnight()) .. " (real time)"
			)
			local week = os.time() % (7 * 86400)
			section(
				"📅 Weekly challenges",
				(quests and quests.Weekly and quests.Weekly.List) or {},
				"Resets in " .. Format.Duration(7 * 86400 - week) .. " (real time)"
			)
			Kit.RepaintGradients(scroll)
		end

		-- Board ------------------------------------------------------------------------------------------------------------
		local function renderBoard()
			local scroll = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			scroll.Parent = body
			Kit.List(scroll, "Y", 8)
			if not board then
				Kit.Empty("Reading the board…").Parent = scroll
				return
			end
			local community = board.Community
			if community then
				local card = Kit.Card()
				card.Parent = scroll
				Kit.List(card, "Y", 6)
				Kit.Heading("🤝 Community goal: " .. community.Name, 18).Parent = card
				local bar =
					Kit.Progress({ Size = UDim2.new(1, 0, 0, 18), Color = if community.Done then "Good" else "Accent" })
				bar.Frame.LayoutOrder = 1
				bar.Frame.Parent = card
				bar.Set(
					community.Progress / math.max(1, community.Goal),
					Format.Commas(community.Progress) .. " / " .. Format.Commas(community.Goal),
					false
				)
				local info = Kit.Label(
					community.Contributors
						.. " farmers on this server have helped today. Everyone who contributes gets: "
						.. table.concat(Describe.Rewards(community.Reward), ", "),
					{ Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true }
				)
				info.LayoutOrder = 2
				info.Parent = card
			end
			local h = Kit.Heading("📌 Quests you can take", 18)
			h.LayoutOrder = 10
			h.Parent = scroll
			local order = 10
			for _, questId in board.Available or {} do
				local quest = Registry.Quests[questId]
				if quest and not quest.Auto then
					order += 1
					local card = Kit.Card()
					card.LayoutOrder = order
					card.Parent = scroll
					Kit.List(card, "Y", 4)
					local giver = quest.Giver and Registry.Npcs[quest.Giver]
					Kit.Label(
						(KIND_ICON[quest.Kind] or "📜")
							.. " "
							.. quest.Name
							.. (if giver then "  ·  " .. giver.Icon .. " " .. giver.Name else ""),
						{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold }
					).Parent =
						card
					local d = Kit.Label(quest.Description, { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
					d.LayoutOrder = 1
					d.Parent = card
					rewardRow(card, quest.Rewards, 2)
					Kit.Button("Accept", {
						Style = "Primary",
						Size = UDim2.fromOffset(110, 32),
						TextSize = Theme.Sizes.Small,
						LayoutOrder = 3,
						OnClick = function()
							if request("QuestAccept", questId) then
								C.Audio.PlayUI("UIConfirm")
								task.spawn(function()
									local ok, data = Net.Request("BoardGet")
									if ok then
										board = data
										render()
									end
								end)
							end
						end,
					}).Parent =
						card
				end
			end
			if order == 10 then
				local e = Kit.Label(
					"Nothing new on the board right now. Befriend villagers and grow your estate to unlock more.",
					{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
				)
				e.LayoutOrder = 11
				e.Parent = scroll
			end
			local contracts = Kit.Button("📋 Contract board", {
				Style = "Secondary",
				Size = UDim2.fromOffset(200, 36),
				TextSize = Theme.Sizes.Small,
				LayoutOrder = 999,
				OnClick = function()
					C.Windows.Open("Market", { Tab = "Contracts" })
				end,
			})
			contracts.Parent = scroll
			Kit.RepaintGradients(scroll)
		end

		-- Completed ------------------------------------------------------------------------------------------------------------
		local function renderDone()
			local profile = C.State.Data()
			local scroll = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			scroll.Parent = body
			Kit.List(scroll, "Y", 4)
			local ids = {}
			for questId, at in (profile and profile.Quests.Done) or {} do
				if Registry.Quests[questId] then
					table.insert(ids, { Id = questId, At = at })
				end
			end
			table.sort(ids, function(a, b)
				return a.At > b.At
			end)
			local total = #QuestsConfig.List
			local header = Kit.Label(
				#ids .. " of " .. total .. " quests completed",
				{ Size = Theme.Sizes.Small, Color = "SubText" }
			)
			header.Parent = scroll
			for i, entry in ids do
				local quest = Registry.Quests[entry.Id]
				local label = Kit.Label(
					"✔️ " .. (KIND_ICON[quest.Kind] or "") .. " " .. quest.Name,
					{ Size = Theme.Sizes.Small }
				)
				label.LayoutOrder = i
				label.Parent = scroll
			end
		end

		render = function()
			Kit.Clear(body)
			if current == "Active" then
				renderActive()
			elseif current == "Daily" then
				renderDaily()
			elseif current == "Board" then
				renderBoard()
			else
				renderDone()
			end
			Kit.RepaintGradients(body)
		end

		local tabs = Kit.Tabs({
			{ Id = "Active", Label = "Active", Icon = "📜" },
			{ Id = "Daily", Label = "Daily & Weekly", Icon = "☀️" },
			{ Id = "Board", Label = "Village board", Icon = "📌" },
			{ Id = "Done", Label = "Completed", Icon = "✔️" },
		}, function(id)
			current = id
			render()
			if id == "Board" then
				task.spawn(function()
					local ok, data = Net.Request("BoardGet")
					if ok then
						board = data
						if current == "Board" then
							render()
						end
					end
				end)
			end
		end)
		tabs.Frame.Parent = content
		tabs.Select(current)
		return {
			Refresh = function()
				if current ~= "Board" then
					render()
				end
			end,
		}
	end,
}
