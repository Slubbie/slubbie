-- The daily gift: a 28-day cycle of useful rewards. Missing a day never
-- resets your place in the cycle; streaks are tracked just for fun.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Format = require(Shared.Lib.Format)
local Social = require(Shared.Config.Social)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Describe = require(UI.Describe)
local C = require(UI.Parent.Controllers)

return {
	Id = "Daily",
	Title = "Daily Gift",
	Icon = "🎁",
	Size = Vector2.new(900, 600),
	Watch = { "Daily" },
	Build = function(win)
		local content = win.Content :: Frame
		local function render()
			Kit.Clear(content)
			local daily = C.State.Get("Daily") or { Last = -1, Index = 0, Streak = 0, Best = 0 }
			local now = workspace:GetServerTimeNow()
			local today = math.floor(now / 86400)
			local available = daily.Last ~= today
			local nextIndex = (daily.Index % #Social.Daily) + 1
			local header =
				Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), Parent = content })
			local streak = Kit.Label(
				"🔥 Streak "
					.. (daily.Streak or 0)
					.. " days  ·  best "
					.. (daily.Best or 0)
					.. (if available then "" else "  ·  next gift in " .. Format.Duration(86400 - now % 86400)),
				{ Size = Theme.Sizes.Small }
			)
			streak.Size = UDim2.new(1, -200, 1, 0)
			streak.Parent = header
			local claim = Kit.Button(if available then "🎁 Open today's gift" else "Come back tomorrow", {
				Style = if available then "Accent" else "Ghost",
				Size = UDim2.fromOffset(200, 44),
				OnClick = function()
					local ok, result = Net.Request("DailyClaim")
					if ok then
						C.Audio.PlayUI("LegendaryReveal")
						C.HUD.SetBadge("Daily", false)
						C.Notify.Banner(
							"🎁 Day " .. tostring(result.Day) .. " gift!",
							"Streak: " .. tostring(result.Streak) .. " days",
							nil,
							"Default",
							3
						)
					else
						C.Notify.Toast(tostring(result), "Info")
					end
				end,
			})
			claim.Position = UDim2.new(1, -200, 0, 2)
			claim.Parent = header
			Kit.SetEnabled(claim, available)
			local grid = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -56), Position = UDim2.fromOffset(0, 56) })
			grid.Parent = content
			local layout = Kit.new("UIGridLayout", {
				CellSize = UDim2.new(1 / 7, -6, 0, 104),
				CellPadding = UDim2.fromOffset(6, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = grid,
			})
			layout.FillDirectionMaxCells = 7
			local cycleStart = daily.Index - (daily.Index % #Social.Daily)
			for i, reward in Social.Daily do
				local claimedThisCycle = cycleStart + i <= daily.Index
				local isNext = i == nextIndex
				local cell = Kit.Panel({
					Color = if isNext and available then "HeaderA" elseif claimedThisCycle then "Inset" else "PanelAlt",
					Corner = 10,
				})
				cell.LayoutOrder = i
				cell.Parent = grid
				Kit.Padding(cell, 6, 6)
				local day = Kit.Label("Day " .. i, {
					Size = Theme.Sizes.Tiny,
					Font = Theme.Fonts.Bold,
					Align = "Center",
					Color = if isNext and available then "HeaderText" else "SubText",
				})
				day.Parent = cell
				local lines = Describe.Rewards(reward)
				local text = Kit.Label(table.concat(lines, "\n"), {
					Size = Theme.Sizes.Tiny,
					Align = "Center",
					Wrap = true,
					Color = if isNext and available then "HeaderText" else "Text",
				})
				text.Position = UDim2.fromOffset(0, 18)
				text.Parent = cell
				if claimedThisCycle then
					local tick = Kit.Label("✔", { Size = 26, Align = "Center", Color = "Good" })
					tick.Size = UDim2.new(1, 0, 0, 30)
					tick.Position = UDim2.new(0, 0, 1, -30)
					tick.Parent = cell
				end
			end
			Kit.RepaintGradients(content)
		end
		render()
		return { Refresh = render }
	end,
}
