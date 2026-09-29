-- Talking to a villager: portrait, hearts, typewriter dialogue, and the
-- conversation menu (chat, ask about gifts, give a gift, quests to accept or
-- hand in, their shop and services). Server lines that arrive while the
-- window is open (gift reactions, heart events) are pushed in with Push().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local GameTime = require(Shared.Lib.GameTime)
local NPCs = require(Shared.Config.NPCs)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Picker = require(UI.Picker)
local Describe = require(UI.Describe)
local C = require(UI.Parent.Controllers)

local REACTION = {
	Love = { Icon = "😍", Text = "Loved it!", Key = "Good" },
	Like = { Icon = "😊", Text = "Liked it", Key = "Good" },
	Neutral = { Icon = "🙂", Text = "Thanks", Key = "SubText" },
	Dislike = { Icon = "😕", Text = "Not a fan", Key = "Warn" },
	Hate = { Icon = "😖", Text = "Hated it", Key = "Bad" },
}

-- Service → { label, handler(npcId) }.
local SERVICES: { [string]: { Label: string, Icon: string, Open: (string) -> () } } = {
	ToolUpgrade = {
		Label = "Upgrade tools",
		Icon = "⚒️",
		Open = function()
			C.Windows.Open("Tools")
		end,
	},
	CrackGeode = {
		Label = "Crack geodes",
		Icon = "🪨",
		Open = function()
			Picker.Open({
				Title = "Crack a geode",
				Filter = function(_, def)
					return def.Use == "Open" and (def.Tags.Geode == true or string.find(def.Id, "geode") ~= nil)
				end,
				Empty = "You have no geodes. Find them while mining.",
				OnPick = function(ref)
					local ok, err = Net.Request("InvUse", ref)
					if not ok then
						C.Notify.Toast(tostring(err), "Warning")
					end
				end,
			})
		end,
	},
	Land = {
		Label = "Buy land",
		Icon = "🗺️",
		Open = function()
			C.Windows.Open("Land")
		end,
	},
	House = {
		Label = "House upgrades",
		Icon = "🏠",
		Open = function()
			C.Windows.Open("House")
		end,
	},
	Animals = {
		Label = "Adopt animals",
		Icon = "🐄",
		Open = function()
			C.Windows.Open("AnimalShop")
		end,
	},
	SeedBreeding = {
		Label = "Cross-breed seeds",
		Icon = "🧬",
		Open = function()
			C.Windows.Open("SeedBreed")
		end,
	},
	GeneScan = {
		Label = "Read seed genes",
		Icon = "🔬",
		Open = function()
			C.Windows.Open("SeedBreed", { Tab = "Scan" })
		end,
	},
	Orders = {
		Label = "Special orders",
		Icon = "📋",
		Open = function()
			C.Windows.Open("Market", { Tab = "Contracts" })
		end,
	},
	Donate = {
		Label = "Museum",
		Icon = "🏛️",
		Open = function()
			C.Windows.Open("Collection", { Tab = "Museum" })
		end,
	},
	CollectorContracts = {
		Label = "Collector requests",
		Icon = "🧾",
		Open = function()
			C.Windows.Open("Market", { Tab = "Contracts" })
		end,
	},
	Maps = {
		Label = "Maps & travel",
		Icon = "🧭",
		Open = function()
			C.Windows.Open("Map")
		end,
	},
	TownProjects = {
		Label = "Town projects",
		Icon = "🏗️",
		Open = function()
			C.Windows.Open("Projects")
		end,
	},
	Festivals = {
		Label = "Festivals",
		Icon = "🎪",
		Open = function()
			C.Windows.Open("Calendar", { Tab = "Festivals" })
		end,
	},
	Export = {
		Label = "Export crates",
		Icon = "🚢",
		Open = function()
			C.Windows.Open("Market", { Tab = "Export" })
		end,
	},
}

local active: { Push: (string, any) -> () }? = nil

local Screen = {
	Id = "Dialogue",
	Title = "Conversation",
	Icon = "💬",
	Size = Vector2.new(760, 460),
}

function Screen.Push(npcId: string, payload: any)
	if active then
		active.Push(npcId, payload)
	end
end

function Screen.Build(win, ctx)
	local payload = ctx.Args or {}
	local npcId = payload.Npc :: string
	local npc = Registry.Npcs[npcId]
	local content = win.Content :: Frame
	if not npc then
		Kit.Empty("They wandered off.").Parent = content
		return nil
	end
	win.Title.Text = npc.Icon .. "  " .. npc.Name
	local hearts = payload.Hearts or 0

	-- Portrait column
	local portrait = Kit.Panel({ Size = UDim2.new(0, 190, 1, 0), Color = "PanelAlt" })
	portrait.Parent = content
	Kit.Padding(portrait, 10, 10)
	Kit.List(portrait, "Y", 6, "Center")
	local face = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(110, 110),
		Text = npc.Icon,
		TextScaled = true,
		Font = Theme.Fonts.Body,
		Parent = portrait,
	})
	face.LayoutOrder = 1
	local role = Kit.Label(npc.Role, { Size = Theme.Sizes.Small, Color = "SubText", Align = "Center", Wrap = true })
	role.LayoutOrder = 2
	role.Parent = portrait
	local heartLabel = Kit.Label("", { Size = 18, Align = "Center", Color = "Bad" })
	heartLabel.LayoutOrder = 3
	heartLabel.Parent = portrait
	local heartBar = Kit.Progress({ Size = UDim2.new(1, 0, 0, 10), Color = "Bad" })
	heartBar.Frame.LayoutOrder = 4
	heartBar.Frame.Parent = portrait
	local meta = Kit.Label("", { Size = Theme.Sizes.Tiny, Color = "SubText", Align = "Center", Wrap = true })
	meta.LayoutOrder = 5
	meta.Parent = portrait

	local function renderHearts(h: number)
		local full = math.floor(h)
		heartLabel.Text = string.rep("❤", math.min(full, NPCs.MaxHearts))
			.. string.rep("♡", math.max(0, NPCs.MaxHearts - full))
		heartLabel.TextScaled = true
		heartLabel.Size = UDim2.new(1, 0, 0, 20)
		heartBar.Set(
			h - full,
			if full >= NPCs.MaxHearts
				then "Best friends"
				else string.format("%d%% to ❤ %d", (h - full) * 100, full + 1)
		)
		local profile = C.State.Data()
		local entry = profile and profile.Friendship and profile.Friendship[npcId]
		local week = math.floor(GameTime.Info().Day / 7)
		local gifts = if entry and entry.GW == week then entry.GC or 0 else 0
		local birthday = payload.Birthday
		meta.Text = (if birthday then "🎂 Birthday today! Gifts count ×" .. NPCs.BirthdayMultiplier .. "\n" else "")
			.. "🎁 Gifts this week: "
			.. gifts
			.. " / "
			.. NPCs.GiftsPerWeek
			.. "\n🎂 Birthday: "
			.. Describe.SeasonDay(npc.Birthday[1], npc.Birthday[2])
	end
	renderHearts(hearts)

	-- Speech column
	local right = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -202, 1, 0),
		Position = UDim2.fromOffset(202, 0),
		Parent = content,
	})
	local bubble = Kit.Panel({ Size = UDim2.new(1, 0, 0, 150), Color = "Inset" })
	bubble.Parent = right
	Kit.Padding(bubble, 12, 14)
	local eventTitle = Kit.Label("", { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Color = "Accent" })
	eventTitle.Size = UDim2.new(1, 0, 0, 18)
	eventTitle.Visible = false
	eventTitle.Parent = bubble
	local speech = Kit.Label("", { Size = Theme.Sizes.Body, Wrap = true })
	speech.Size = UDim2.new(1, 0, 1, -18)
	speech.AutomaticSize = Enum.AutomaticSize.None
	speech.TextYAlignment = Enum.TextYAlignment.Top
	speech.Position = UDim2.fromOffset(0, 0)
	speech.Parent = bubble
	local more = Kit.Label("▼ click to continue", { Size = Theme.Sizes.Tiny, Color = "SubText", Align = "Right" })
	more.Size = UDim2.new(1, 0, 0, 14)
	more.Position = UDim2.new(0, 0, 1, -12)
	more.Visible = false
	more.Parent = bubble
	local advanceButton = Kit.new(
		"TextButton",
		{ BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = bubble }
	)

	local options = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -162), Position = UDim2.fromOffset(0, 162) })
	options.Parent = right
	local grid = Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -5, 0, 42),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = options,
	})
	grid.FillDirectionMaxCells = 2

	-- Typewriter queue
	local queue: { string } = {}
	local typing = false
	local skipTyping = false
	local closed = false
	local function showNext()
		local line = table.remove(queue, 1)
		if not line then
			more.Visible = false
			return
		end
		typing = true
		skipTyping = false
		more.Visible = false
		speech.Text = line
		speech.MaxVisibleGraphemes = 0
		task.spawn(function()
			local total = utf8.len(line) or #line
			local shown = 0
			local blip = 0
			while shown < total and not skipTyping and not closed do
				shown += if Kit.ReducedMotion then total else 2
				speech.MaxVisibleGraphemes = shown
				blip += 1
				if blip % 4 == 0 then
					C.Audio.PlayUI("UIHover")
				end
				task.wait(0.022)
			end
			speech.MaxVisibleGraphemes = -1
			typing = false
			more.Visible = #queue > 0
		end)
	end
	local function say(lines: { string }?)
		for _, line in ipairs(lines or {}) do
			table.insert(queue, line)
		end
		if not typing then
			showNext()
		end
	end
	advanceButton.Activated:Connect(function()
		if typing then
			skipTyping = true
		else
			showNext()
		end
	end)

	local renderOptions: () -> ()

	local function option(order: number, text: string, style: string, fn: () -> ())
		local b = Kit.Button(text, { Style = style, TextSize = Theme.Sizes.Small, LayoutOrder = order, OnClick = fn })
		b.TextWrapped = true
		b.Parent = options
		return b
	end

	renderOptions = function()
		Kit.Clear(options)
		local profile = C.State.Data()
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		-- Quests to hand in
		for questId, state in (profile and profile.Quests.Active) or {} do
			local quest = Registry.Quests[questId]
			if quest and quest.TurnIn == npcId then
				local ready = state.Ready
				if not ready then
					-- Deliver-only quests become ready when you carry the items.
					ready = true
					for i, objective in quest.Objectives do
						local cur, goal = Describe.Progress(profile, objective, state.P and state.P[i])
						if cur < goal then
							ready = false
							break
						end
					end
				end
				if ready then
					option(nextOrder(), "✔️ Hand in: " .. quest.Name, "Good", function()
						local ok, err = Net.Request("QuestTurnIn", questId)
						if ok then
							C.Audio.PlayUI("QuestComplete")
							say(quest.Finish or { "Thank you so much!" })
						else
							C.Notify.Toast(tostring(err), "Warning")
						end
						renderOptions()
					end)
				end
			end
		end
		-- Quests on offer
		for _, offer in payload.Offers or {} do
			local taken = profile and (profile.Quests.Active[offer.Id] or profile.Quests.Done[offer.Id])
			if not taken then
				option(nextOrder(), "📜 " .. offer.Name, "Accent", function()
					local quest = Registry.Quests[offer.Id]
					local rewards = Describe.Rewards(quest and quest.Rewards)
					local objectives = {}
					for _, o in (quest and quest.Objectives) or {} do
						table.insert(objectives, "• " .. Describe.Objective(o))
					end
					Kit.Confirm(
						offer.Name,
						offer.Description
							.. "\n\n"
							.. table.concat(objectives, "\n")
							.. (if #rewards > 0 then "\n\nRewards: " .. table.concat(rewards, ", ") else ""),
						function(yes)
							if yes then
								local ok, err = Net.Request("QuestAccept", offer.Id)
								if ok then
									say(quest and quest.Start or { "Wonderful, thank you!" })
								else
									C.Notify.Toast(tostring(err), "Warning")
								end
								renderOptions()
							end
						end,
						"Accept"
					)
				end)
			end
		end
		option(nextOrder(), "💬 Chat", "Secondary", function()
			local ok, result = Net.Request("NpcChoice", npcId, 1)
			if ok and result then
				say(result.Lines)
			end
		end)
		option(nextOrder(), "🎁 Give a gift", "Secondary", function()
			Picker.Open({
				Title = "A gift for " .. npc.Name,
				Filter = function(stack, def)
					return def.Category ~= "Tool" and def.Category ~= "Special" and not stack.L
				end,
				Note = function(stack, def)
					-- Only show preferences the player has discovered through gifting.
					local profile2 = C.State.Data()
					local known = profile2
						and profile2.Friendship
						and profile2.Friendship[npcId]
						and profile2.Friendship[npcId].Known
					local pref = known and known[stack.Id]
					return if pref
						then (REACTION[pref] and REACTION[pref].Icon .. " " .. pref or pref)
						else def.Category
				end,
				OnPick = function(ref)
					local ok, result = Net.Request("NpcGift", npcId, ref)
					if not ok then
						C.Notify.Toast(tostring(result), "Warning")
						return
					end
					local reaction = REACTION[result.Reaction] or REACTION.Neutral
					C.Notify.Toast(
						reaction.Icon
							.. " "
							.. npc.Name
							.. ": "
							.. reaction.Text
							.. (if result.Points > 0 then " (+" .. result.Points .. ")" else ""),
						if result.Points > 0 then "Success" else "Info"
					)
					if result.Reaction == "Love" then
						C.Audio.PlayUI("Discovery")
					end
				end,
			})
		end)
		option(nextOrder(), "❓ What do you like?", "Secondary", function()
			local ok, result = Net.Request("NpcChoice", npcId, 2)
			if ok and result then
				say(result.Lines)
			end
		end)
		if payload.Shop then
			local shop = Registry.Shops[payload.Shop]
			option(
				nextOrder(),
				(if shop then shop.Icon else "🛒")
					.. " "
					.. (if payload.Open == false then "Shop (closed)" else "Shop"),
				"Primary",
				function()
					if payload.Open == false then
						local hours = shop and shop.Hours
						C.Notify.Toast(
							"The shop is closed"
								.. (if hours then " — open " .. hours[1] .. ":00 to " .. hours[2] .. ":00" else ""),
							"Info"
						)
						return
					end
					C.Windows.Open("Shop", { Shop = payload.Shop, Npc = npcId })
				end
			)
		end
		for _, service in payload.Services or {} do
			local def = SERVICES[service]
			if def then
				option(nextOrder(), def.Icon .. " " .. def.Label, "Secondary", function()
					def.Open(npcId)
				end)
			end
		end
		option(nextOrder(), "👋 Goodbye", "Ghost", function()
			ctx.Close()
		end)
		Kit.RepaintGradients(options)
	end

	-- Opening lines
	for _, questId in payload.Completed or {} do
		local quest = Registry.Quests[questId]
		if quest then
			C.Notify.Toast("✔️ " .. quest.Name .. " complete!", "Success")
		end
	end
	if payload.Event then
		eventTitle.Text = "💞 " .. payload.Event.Title
		eventTitle.Visible = true
		speech.Position = UDim2.fromOffset(0, 20)
	end
	if payload.FirstToday then
		C.Audio.PlayUI("Notification")
	end
	say(payload.Lines or { "..." })
	renderOptions()

	-- Space / A advances.
	local connection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return then
			if typing then
				skipTyping = true
			else
				showNext()
			end
		end
	end)

	local handle = {}
	function handle.Push(fromNpc: string, extra: any)
		if fromNpc ~= npcId then
			return
		end
		if extra.Lines then
			say(extra.Lines)
		end
		local profile = C.State.Data()
		if profile then
			local Stats = require(Shared.Lib.Stats)
			renderHearts(Stats.Hearts(profile, npcId))
		end
	end
	function handle.Refresh()
		local profile = C.State.Data()
		if profile then
			local Stats = require(Shared.Lib.Stats)
			renderHearts(Stats.Hearts(profile, npcId))
		end
		renderOptions()
	end
	function handle.Destroy()
		closed = true
		connection:Disconnect()
		if active == handle then
			active = nil
		end
	end
	active = handle
	return handle
end

Screen.Watch = { "Friendship", "Quests", "Inventory" }

return Screen
