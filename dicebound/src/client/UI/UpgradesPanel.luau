-- Upgrades: current → next value, price, and a buy button with clear affordable / too expensive /
-- maxed states. Each purchase sends the level we saw, so a double click can't buy twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Sound = require(script.Parent.Parent.Sound)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Panels = require(script.Parent.Panels)
local Toasts = require(script.Parent.Toasts)

local C = Theme.Colors

local UpgradesPanel = {}

-- Replaced with the real refresh once the panel is built.
function UpgradesPanel.Refresh() end

function UpgradesPanel.ValueText(upgrade, value: any): string
	if upgrade.Id == "AutoRoll" then
		return if value == 1 then "Unlocked" else "Locked"
	end
	if upgrade.FormatScale then
		value = math.floor(value * upgrade.FormatScale + 0.5)
	end
	return string.format(upgrade.Format, value)
end

function UpgradesPanel.new()
	local content = Panels.Create("Upgrades", "Upgrades", "🔧")
	local list = Kit.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	})
	Kit.List(list, Enum.FillDirection.Vertical, 10)
	Kit.Padding(list, 4, 4)

	local rows = {}
	local pending = false

	for _, upgrade in Config.Economy.Upgrades.List do
		if Config.IsLive(upgrade) then
			local card = Kit.Card({ Parent = list, Size = UDim2.new(1, -12, 0, 104), LayoutOrder = upgrade.Order })
			Kit.Label({
				Parent = card,
				Text = upgrade.Icon,
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.fromOffset(56, 104),
				TextSize = 40,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			local title = Kit.Label({
				Parent = card,
				Position = UDim2.fromOffset(80, 10),
				Size = UDim2.new(1, -270, 0, 26),
				Font = Theme.Fonts.Title,
				TextSize = 22,
				Text = upgrade.Name,
			})
			local change = Kit.Label({
				Parent = card,
				Position = UDim2.fromOffset(80, 40),
				Size = UDim2.new(1, -270, 0, 22),
				Font = Theme.Fonts.Bold,
				TextSize = 16,
				TextColor3 = C.GreenDark,
				Text = "",
			})
			Kit.Label({
				Parent = card,
				Position = UDim2.fromOffset(80, 64),
				Size = UDim2.new(1, -270, 0, 34),
				TextSize = 14,
				TextColor3 = C.InkSoft,
				Text = upgrade.Description,
			})
			local status = Kit.Label({
				Parent = card,
				Position = UDim2.new(1, -176, 0, 72),
				Size = UDim2.fromOffset(164, 22),
				TextSize = 13,
				TextColor3 = C.InkSoft,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = "",
			})
			local buy
			buy = Kit.Button({
				Parent = card,
				Text = "",
				Color = C.Green,
				Size = UDim2.fromOffset(164, 52),
				Position = UDim2.new(1, -176, 0, 14),
				TextSize = 20,
				OnClick = function()
					if pending then
						return
					end
					pending = true
					buy:SetEnabled(false)
					local level = ClientState.UpgradeLevel(upgrade.Id)
					local result = ClientState.Request("BuyUpgrade", upgrade.Id, level)
					pending = false
					if result.ok then
						Sound.Play("Purchase")
						Toasts.Show(upgrade.Icon .. " " .. upgrade.Name .. " upgraded!", "success", 2.5)
						if not Kit.ReducedMotion then
							local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
							stroke.Color = C.Gold
							stroke.Thickness = 5
							Kit.Tween(stroke, 0.6, { Thickness = 2, Color = C.Stroke })
						end
					else
						Sound.Play("Error")
						Toasts.Show(result.err, "error")
					end
					UpgradesPanel.Refresh()
				end,
			})
			rows[upgrade.Id] = { Upgrade = upgrade, Title = title, Change = change, Buy = buy, Status = status }
		end
	end

	function UpgradesPanel.Refresh()
		local data = ClientState.Data
		if not data then
			return
		end
		for _, row in rows do
			local upgrade = row.Upgrade
			local level = data.Upgrades[upgrade.Id] or 0
			local maxLevel = #upgrade.Levels - 1
			local current = upgrade.Levels[level + 1]
			local nextLevel = upgrade.Levels[level + 2]
			row.Title.Text = string.format("%s  ·  Lv %d/%d", upgrade.Name, level, maxLevel)
			if nextLevel then
				row.Change.Text = UpgradesPanel.ValueText(upgrade, current.Value)
					.. "  →  "
					.. UpgradesPanel.ValueText(upgrade, nextLevel.Value)
				row.Buy:SetText("🪙 " .. Format.Coins(nextLevel.Cost))
				local affordable = data.Coins >= nextLevel.Cost
				row.Buy:SetEnabled(affordable and not pending)
				row.Status.Text = if affordable
					then "Ready to buy!"
					else "Need 🪙 " .. Format.Coins(nextLevel.Cost - data.Coins) .. " more"
			else
				row.Change.Text = UpgradesPanel.ValueText(upgrade, current.Value) .. "  (max)"
				row.Buy:SetText("MAX")
				row.Buy:SetEnabled(false)
				row.Status.Text = "Fully upgraded"
			end
		end
	end

	ClientState.Changed:Connect(UpgradesPanel.Refresh)
	Panels.Opened:Connect(function(name)
		if name == "Upgrades" then
			UpgradesPanel.Refresh()
		end
	end)
end

return UpgradesPanel
