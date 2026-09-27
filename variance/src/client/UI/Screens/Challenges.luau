-- DIRECTIVES: three daily challenges (easy, medium, hard) and the weekly set,
-- with progress, reset timers and claimable rewards. Directives only ask for
-- things that happen in normal play; none require buying anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Challenges = require(ReplicatedStorage.Variance.Data.Challenges)
local Format = require(ReplicatedStorage.Variance.Util.Format)
local Kit = require(script.Parent.Parent.Kit)
local Window = require(script.Parent.Parent.Window)

local ChallengesScreen = {}
ChallengesScreen.__index = ChallengesScreen

local TIER_COLOR = { Easy = "Good", Medium = "Accent", Hard = "Bad", Weekly = "Hollow" }

function ChallengesScreen.new(ui, controllers)
	local self = setmetatable({}, ChallengesScreen)
	self.UI = ui
	self.C = controllers
	self.Main = true
	self.Window =
		Window.new(ui, { Name = "Challenges", Title = "DIRECTIVES", Subtitle = "", Width = 900, Height = 600 })
	self.Frame = self.Window.Frame
	self.Opened = 0
	controllers.ProfileController.Changed:Connect(function()
		if self.Window.Visible then
			self:render()
		end
	end)
	RunService.Heartbeat:Connect(function()
		if self.Window.Visible and self.Profile then
			local c = self.Profile.Challenges
			local elapsed = os.clock() - self.Opened
			self.Window:setSubtitle(
				string.format(
					"DAILY RESET IN %s  ·  WEEKLY RESET IN %s",
					Format.duration(math.max(0, (c.DayEndsIn or 0) - elapsed)),
					Format.duration(math.max(0, (c.WeekEndsIn or 0) - elapsed))
				)
			)
		end
	end)
	return self
end

local function rewardText(tier: string): string
	local reward = Challenges.Rewards and Challenges.Rewards[tier]
	if reward == nil then
		return ""
	end
	local parts = {}
	if (reward.XP or 0) > 0 then
		table.insert(parts, "+" .. reward.XP .. " XP")
	end
	if (reward.Marks or 0) > 0 then
		table.insert(parts, "+" .. reward.Marks .. " MARKS")
	end
	return table.concat(parts, "  ·  ")
end

function ChallengesScreen:section(parent: Instance, title: string, list, period: string, order: number): number
	Kit.header(parent, title, order)
	order += 1
	for index, entry in list do
		local card = Kit.panel(parent, { Size = UDim2.new(1, -8, 0, 74), LayoutOrder = order, Color = "PanelAlt" })
		order += 1
		Kit.padding(card, 10, 14)
		Kit.label(card, {
			Text = string.upper(entry.Tier or ""),
			Font = "Mono",
			TextSize = "Tiny",
			Color = TIER_COLOR[entry.Tier or ""] or "Dim",
			Size = UDim2.fromOffset(80, 14),
		})
		Kit.label(card, {
			Text = entry.Text or "",
			Font = "Bold",
			TextSize = "Small",
			Wrap = true,
			Size = UDim2.new(1, -190, 0, 20),
			Position = UDim2.fromOffset(0, 16),
		})
		Kit.bar(card, {
			Size = UDim2.new(1, -190, 0, 6),
			Position = UDim2.fromOffset(0, 44),
			Value = (entry.Progress or 0) / math.max(entry.Goal or 1, 1),
			Color = if entry.Done then "Good" else "Accent",
		})
		Kit.label(card, {
			Text = string.format(
				"%d / %d  ·  %s",
				math.min(entry.Progress or 0, entry.Goal or 1),
				entry.Goal or 1,
				rewardText(entry.Tier or "")
			),
			Font = "Mono",
			TextSize = "Tiny",
			Color = "Dim",
			Size = UDim2.new(1, -190, 0, 14),
			Position = UDim2.fromOffset(0, 52),
		})
		local button
		if entry.Claimed then
			button = Kit.button(card, {
				Text = "CLAIMED",
				Size = UDim2.fromOffset(160, 40),
				Position = UDim2.new(1, 0, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Style = "Ghost",
			})
			Kit.setEnabled(button, false, "Already claimed.")
		elseif entry.Done then
			button = Kit.button(card, {
				Text = "CLAIM",
				Size = UDim2.fromOffset(160, 40),
				Position = UDim2.new(1, 0, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Style = "Primary",
				Sound = "Unlock",
				OnClick = function()
					local ok, err = self.C.NetworkClient:request("Challenges.Claim", period, index)
					if not ok then
						self.UI:toast("DIRECTIVES", tostring(err), "Warn")
					end
				end,
			})
		else
			button = Kit.button(card, {
				Text = "IN PROGRESS",
				Size = UDim2.fromOffset(160, 40),
				Position = UDim2.new(1, 0, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Style = "Ghost",
			})
			Kit.setEnabled(button, false, "Complete the directive first.")
		end
	end
	return order
end

function ChallengesScreen:render()
	local body = self.Window.Body
	Window.clear(body)
	local profile = self.C.ProfileController:get()
	self.Profile = profile
	if profile == nil or profile.Challenges == nil then
		Kit.label(body, { Text = "Your file is still loading.", Font = "Mono", TextSize = "Small", Color = "Dim" })
		return
	end
	local scroll = Kit.scroll(body, { Padding = 8 })
	local order = self:section(scroll, "TODAY", profile.Challenges.Daily or {}, "Daily", 1)
	self:section(scroll, "THIS WEEK", profile.Challenges.Weekly or {}, "Weekly", order + 1)
end

function ChallengesScreen:Open()
	self.Opened = os.clock()
	self.Window:open()
	self:render()
end

function ChallengesScreen:Close()
	self.Window:close()
end

return ChallengesScreen
