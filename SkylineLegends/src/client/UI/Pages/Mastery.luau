-- Movement mastery: eight technique categories, five tiers each. A tier needs
-- both points from real use and its proficiency challenge, so this page shows
-- exactly what's left for the next one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local Mastery = require(ReplicatedStorage.Shared.Config.Mastery)

local State = require(script.Parent.Parent.Parent.Core.State)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors

return {
	Id = "Mastery",
	Title = "Mastery",
	Icon = "▲",
	Order = 4,
	Sections = { "Mastery" },
	Build = function(container: Frame)
		local profile = State.Profile
		if not profile then
			return
		end
		local data = profile.Mastery or {}
		local points = data.Points or {}
		local completed = data.Challenges or {}
		local scroll = Kit.Scroll(container)
		Kit.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -8, 0, 190),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = scroll,
		})

		for index, category in Mastery.Categories do
			local have = points[category.Id] or 0
			local tier = Mastery.TierOf(category.Id, have, completed)
			local card = Kit.Panel(scroll, { BackgroundColor3 = C.PanelLight, LayoutOrder = index })
			Kit.Padding(card, 12)
			Kit.List(card, false, 4)
			Kit.Label(card, ("%s  %s"):format(category.Icon, category.Name), 17, { Font = Kit.Fonts.Black, TextColor3 = category.Color })
			Kit.Label(card, if tier > 0 then ("Tier %d · %s"):format(tier, Mastery.TierNames[tier]) else "Unranked", 14, { Font = Kit.Fonts.Bold })
			Kit.Paragraph(card, category.Blurb, 12, C.Muted)
			if tier >= 5 then
				Kit.Paragraph(card, "✓ Grandmaster. Nothing left to prove here.", 13, C.Good)
			else
				local nextTier = tier + 1
				local needed = Mastery.TierPoints[nextTier]
				local bar = Kit.Bar(card, category.Color)
				bar.Set(have / needed)
				Kit.Label(card, ("%s / %s points to %s"):format(Format.Number(have), Format.Number(needed), Mastery.TierNames[nextTier]), 12, { TextColor3 = C.Muted })
				local challenge = Mastery.ChallengeFor[category.Id] and Mastery.ChallengeFor[category.Id][nextTier]
				if challenge then
					local done = completed[challenge.Id]
					Kit.Paragraph(card, ("%s Challenge: %s — %s"):format(if done then "✓" else "◇", challenge.Name, challenge.Text), 13, if done then C.Good else C.Text)
				end
				local reward = Mastery.TierRewards[nextTier]
				if reward then
					Kit.Label(card, "Tier reward: " .. Kit.Rewards(reward), 12, { TextColor3 = C.Accent })
				end
			end
		end
	end,
}
