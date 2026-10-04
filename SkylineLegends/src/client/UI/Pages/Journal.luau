-- The quest journal: the story by chapter, side quests and expert trials,
-- daily objectives and weekly expeditions, your contract, and the lost
-- letters you've found. Every quest shows where it starts, what it asks and
-- what it pays before you take it on; active ones can be pinned to the HUD.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local Lore = require(ReplicatedStorage.Shared.Config.Lore)
local Net = require(ReplicatedStorage.Shared.Net)
local NPCs = require(ReplicatedStorage.Shared.Config.NPCs)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)

local State = require(script.Parent.Parent.Parent.Core.State)
local QuestClient = require(script.Parent.Parent.Parent.Gameplay.QuestClient)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors
local tab = "Story"

local function questCard(parent: Instance, quest: Quests.Quest, profile: any)
	local active = profile.Quests.Active[quest.Id]
	local done = profile.Quests.Completed[quest.Id]
	local available = QuestClient.IsAvailable(quest)
	local card = Kit.Card(parent)
	local mark = if done then "✓" elseif active then "▶" elseif available then "!" else "🔒"
	local color = if done then C.Good elseif active then C.Accent elseif available then C.Signal else C.Faint
	Kit.Label(card, ("%s  %s"):format(mark, quest.Name), 17, { Font = Kit.Fonts.Bold, TextColor3 = color })
	Kit.Paragraph(card, quest.Summary, 14, C.Text)
	if active then
		for index, step in quest.Steps do
			local stepMark = if index < active.Step then "✓" elseif index == active.Step then "▶" else "·"
			Kit.Paragraph(
				card,
				("%s %s"):format(stepMark, step.Text),
				13,
				if index == active.Step then C.Text else C.Muted
			)
		end
		local row = Kit.Row(card, 38, 8)
		local pinned = table.find(profile.Quests.Pinned or {}, quest.Id) ~= nil
		Kit.Button(row, if pinned then "📌 Pinned" else "Pin", function()
			QuestClient.Pin(quest.Id, not pinned)
		end, if pinned then "Primary" else "Secondary", { Size = UDim2.fromOffset(120, 34) })
		if quest.Type ~= "Main" then
			Kit.Button(row, "Abandon", function()
				QuestClient.Abandon(quest.Id)
			end, "Ghost", { Size = UDim2.fromOffset(110, 34) })
		end
	elseif not done then
		local giver = NPCs.ById[quest.Giver]
		Kit.Paragraph(
			card,
			"Start: " .. quest.Start .. (if giver then (" (" .. giver.Name .. ")") else ""),
			13,
			C.Muted
		)
		local steps = {}
		for _, step in quest.Steps do
			table.insert(steps, step.Text)
		end
		Kit.Paragraph(card, "Asks: " .. table.concat(steps, " → "), 13, C.Muted)
		if quest.Type == "Expert" and available then
			local note = Kit.Paragraph(card, "", 13, C.Bad)
			Kit.Button(card, "Take on this trial", function()
				task.spawn(function()
					local ok, reason = QuestClient.Accept(quest.Id)
					if not ok then
						note.Text = reason or "Not available"
					end
				end)
			end, "Primary", { Size = UDim2.fromOffset(190, 34) })
		end
	end
	Kit.Label(card, "Rewards: " .. Kit.Rewards(quest.Rewards), 13, { TextColor3 = C.Accent })
end

local function story(parent: Instance, profile: any)
	local chapters: { [number]: { Quests.Quest } } = {}
	for _, quest in Quests.List do
		if quest.Type == "Main" and quest.Chapter then
			chapters[quest.Chapter] = chapters[quest.Chapter] or {}
			table.insert(chapters[quest.Chapter], quest)
		end
	end
	for chapter = 0, 7 do
		local list = chapters[chapter]
		if list then
			local total, done = #list, 0
			local anyVisible = false
			for _, quest in list do
				if profile.Quests.Completed[quest.Id] then
					done += 1
				end
				if
					profile.Quests.Completed[quest.Id]
					or profile.Quests.Active[quest.Id]
					or QuestClient.IsAvailable(quest)
				then
					anyVisible = true
				end
			end
			Kit.Label(
				parent,
				("%s  ·  %d/%d"):format(Quests.ChapterNames[chapter] or ("Chapter " .. chapter), done, total),
				18,
				{
					Font = Kit.Fonts.Black,
					TextColor3 = if done == total then C.Good elseif anyVisible then C.Accent else C.Faint,
				}
			)
			if anyVisible then
				for _, quest in list do
					if
						profile.Quests.Completed[quest.Id]
						or profile.Quests.Active[quest.Id]
						or QuestClient.IsAvailable(quest)
					then
						questCard(parent, quest, profile)
					end
				end
			else
				Kit.Paragraph(parent, "Continue the story to open this chapter.", 13, C.Faint)
			end
		end
	end
end

local function sideQuests(parent: Instance, profile: any)
	for _, kind in { "Side", "Expert" } do
		Kit.Label(
			parent,
			if kind == "Side" then "Side quests" else "Expert trials",
			18,
			{ Font = Kit.Fonts.Black, TextColor3 = C.Accent }
		)
		local shown = 0
		for _, quest in Quests.List do
			if
				quest.Type == kind
				and (
					profile.Quests.Completed[quest.Id]
					or profile.Quests.Active[quest.Id]
					or QuestClient.IsAvailable(quest)
				)
			then
				questCard(parent, quest, profile)
				shown += 1
			end
		end
		if shown == 0 then
			Kit.Paragraph(
				parent,
				if kind == "Side"
					then "Talk to the people of each district to find side work."
					else "Expert trials open once you've finished a district's chapter.",
				13,
				C.Faint
			)
		end
	end
end

local function rolling(parent: Instance)
	local status = Kit.Paragraph(parent, "Checking the board…", 13, C.Faint)
	task.spawn(function()
		local ok, data = pcall(Net.Invoke, "Quest.Claim")
		if not ok or type(data) ~= "table" or not parent.Parent then
			status.Text = "Objectives unavailable right now."
			return
		end
		status.Text = ""
		local function section(title: string, block: any, list: { any }, resetIn: number)
			Kit.Label(
				parent,
				("%s  ·  resets in %s"):format(title, Format.Duration(resetIn)),
				18,
				{ Font = Kit.Fonts.Black, TextColor3 = C.Accent }
			)
			for _, id in block.Picks or {} do
				local template = nil
				for _, entry in list do
					if entry.Id == id then
						template = entry
					end
				end
				if template then
					local card = Kit.Card(parent)
					local done = block.Done and block.Done[id]
					local progress = block.Progress and block.Progress[id] or 0
					Kit.Label(
						card,
						(if done then "✓ " else "") .. template.Text,
						15,
						{ Font = Kit.Fonts.Bold, TextColor3 = if done then C.Good else C.Text }
					)
					local bar = Kit.Bar(card, if done then C.Good else C.Signal)
					bar.Set(if done then 1 else progress / (template.Count or 1))
					Kit.Label(card, ("%d / %d"):format(progress, template.Count or 1), 12, { TextColor3 = C.Muted })
				end
			end
		end
		section("Daily objectives", data.Daily, Quests.Daily, data.NextDay or 0)
		Kit.Paragraph(parent, "Finish all three dailies for a bonus: " .. Kit.Rewards(Quests.DailyBonus), 13, C.Muted)
		section("Weekly expeditions", data.Weekly, Quests.Weekly, data.NextWeek or 0)
		Kit.Paragraph(parent, "Each expedition pays " .. Kit.Rewards(Quests.WeeklyReward), 13, C.Muted)
	end)
end

local function contracts(parent: Instance, profile: any)
	local contract = profile.Contracts and profile.Contracts.Active
	if contract then
		local card = Kit.Card(parent)
		Kit.Label(card, "Active: " .. tostring(contract.Name), 17, { Font = Kit.Fonts.Bold, TextColor3 = C.Good })
		Kit.Paragraph(card, tostring(contract.Text), 14, C.Text)
		Kit.Label(card, "Pays " .. Kit.Rewards(contract.Reward), 13, { TextColor3 = C.Accent })
		Kit.Button(card, "Abandon contract", function()
			task.spawn(pcall, Net.Invoke, "Contract.Take", nil)
		end, "Ghost", { Size = UDim2.fromOffset(180, 34) })
	else
		Kit.Paragraph(
			parent,
			"No contract. Every district plaza has a job board with quick work for runners.",
			14,
			C.Muted
		)
	end
	Kit.Paragraph(
		parent,
		("Contracts completed: %d"):format(profile.Contracts and profile.Contracts.Completed or 0),
		13,
		C.Muted
	)
end

local function letters(parent: Instance, profile: any)
	local found = 0
	for district, list in Lore.Letters do
		Kit.Label(parent, district, 17, { Font = Kit.Fonts.Black, TextColor3 = C.Accent })
		for index, letter in list do
			local id = ("letter_%s_%d"):format(string.lower(district), index)
			if profile.Discoveries and profile.Discoveries[id] then
				found += 1
				local card = Kit.Card(parent)
				Kit.Label(card, tostring(letter.Title or ("Letter " .. index)), 15, { Font = Kit.Fonts.Bold })
				Kit.Paragraph(card, tostring(letter.Text or ""), 14, C.Text)
			else
				Kit.Paragraph(parent, "· An unread letter is still out there.", 13, C.Faint)
			end
		end
	end
	if found == 0 then
		Kit.Paragraph(
			parent,
			"Lost letters are tucked away on rooftops in every district. Each tells part of what happened to the city.",
			14,
			C.Muted
		)
	end
end

return {
	Id = "Journal",
	Title = "Journal",
	Icon = "✎",
	Order = 2,
	Sections = { "Quests", "Contracts", "Discoveries" },
	Build = function(container: Frame)
		local profile = State.Profile
		if not profile then
			return
		end
		local tabs = Kit.Row(container, 40, 8)
		local body = Kit.Scroll(container, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52) })
		Kit.List(body, false, 10)
		Kit.Padding(body, 4)
		local function render()
			Kit.Clear(body)
			if tab == "Story" then
				story(body, profile)
			elseif tab == "Side" then
				sideQuests(body, profile)
			elseif tab == "Objectives" then
				rolling(body)
			elseif tab == "Contracts" then
				contracts(body, profile)
			else
				letters(body, profile)
			end
		end
		for _, name in { "Story", "Side", "Objectives", "Contracts", "Letters" } do
			Kit.Button(
				tabs,
				name,
				function()
					tab = name
					for _, child in tabs:GetChildren() do
						if child:IsA("TextButton") then
							child.BackgroundColor3 = if child.Text == tab
								then C.Accent:Lerp(C.PanelLight, 0.5)
								else C.PanelLight
						end
					end
					render()
				end,
				"Secondary",
				{
					Size = UDim2.fromOffset(120, 36),
					BackgroundColor3 = if name == tab then C.Accent:Lerp(C.PanelLight, 0.5) else C.PanelLight,
				}
			)
		end
		render()
	end,
}
