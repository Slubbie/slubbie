-- Travel map: every region, what it takes to unlock, and one-tap travel between unlocked ones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Sound = require(script.Parent.Parent.Sound)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Panels = require(script.Parent.Panels)
local Toasts = require(script.Parent.Toasts)
local Effects = require(script.Parent.Effects)

local C = Theme.Colors

local MapPanel = {}

function MapPanel.new()
	local content = Panels.Create("Map", "Travel Map", "🗺️")
	local list = Kit.Scroll(content)
	local busy = false

	local function refresh()
		local data = ClientState.Data
		if not data or not Panels.IsOpen("Map") then
			return
		end
		Kit.Clear(list)
		local here = ClientState.CurrentRegion()
		local event = ClientState.Event()
		for _, region in Config.Regions.List do
			if Config.IsLive(region) then
				local unlocked = data.Regions[region.Id] == true
				local previous = Config.Regions.Previous(region.Id)
				local card = Kit.Card({ Parent = list, Size = UDim2.new(1, -12, 0, 112), LayoutOrder = region.Order })
				local strip = Kit.new("Frame", {
					Size = UDim2.new(0, 14, 1, 0),
					BackgroundColor3 = Format.Color(region.Palette.Banner),
					Parent = card,
				})
				Kit.Corner(strip, 12)
				local found, total = ClientState.DiscoveredIn(region.Id)
				local title = region.Name
				if here and here.Id == region.Id then
					title ..= "   📍 You are here"
				end
				if event and event.Region == region.Id then
					local def = Config.Economy.Events.ById[event.Id]
					title ..= "   " .. def.Icon .. " " .. def.Name
				end
				Kit.Label({
					Parent = card,
					Position = UDim2.fromOffset(26, 8),
					Size = UDim2.new(1, -220, 0, 26),
					Text = (if unlocked then "" else "🔒 ") .. title,
					Font = Theme.Fonts.Title,
					TextSize = 20,
				})
				Kit.Label({
					Parent = card,
					Position = UDim2.fromOffset(26, 36),
					Size = UDim2.new(1, -220, 0, 70),
					Text = region.Tagline .. "\n🔁 " .. region.RevisitReason .. "\n📖 " .. string.format(
						"Collection %d/%d",
						found,
						total
					),
					TextSize = 13,
					TextColor3 = C.InkSoft,
					TextYAlignment = Enum.TextYAlignment.Top,
				})
				local right = Kit.new("Frame", {
					Position = UDim2.new(1, -190, 0, 10),
					Size = UDim2.fromOffset(180, 96),
					BackgroundTransparency = 1,
					Parent = card,
				})
				Kit.List(right, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right)
				if unlocked then
					local travel = Kit.Button({
						Parent = right,
						Text = "✨ Travel",
						Color = C.Blue,
						Size = UDim2.fromOffset(170, 48),
						OnClick = function()
							if busy then
								return
							end
							busy = true
							local result = ClientState.Request("Travel", region.Id)
							busy = false
							if result.ok then
								Sound.Play("Windup")
								Panels.Close()
							else
								Toasts.Show(result.err, "error")
							end
						end,
					})
					travel:SetEnabled(not (here and here.Id == region.Id))
				else
					local need = region.Unlock
					local prevFound = 0
					if previous then
						prevFound = ClientState.DiscoveredIn(previous.Id)
					end
					local prevOk = previous == nil or data.Regions[previous.Id] == true
					local discOk = (need.Discoveries or 0) <= prevFound
					local coinOk = data.Coins >= need.Coins
					local unlock = Kit.Button({
						Parent = right,
						Text = "Unlock 🪙 " .. Format.Coins(need.Coins),
						Color = C.Gold,
						TextColor = C.Ink,
						Size = UDim2.fromOffset(170, 44),
						TextSize = 16,
						OnClick = function()
							if busy then
								return
							end
							busy = true
							local result = ClientState.Request("UnlockRegion", region.Id)
							busy = false
							if result.ok then
								Sound.Play("Purchase")
								Effects.Confetti(70)
								Toasts.Show(
									"🎉 " .. region.Name .. " unlocked! Tap Travel to go there.",
									"success",
									4
								)
							else
								Sound.Play("Error")
								Toasts.Show(result.err, "error")
							end
						end,
					})
					unlock:SetEnabled(prevOk and discOk and coinOk)
					local lines = {}
					if not prevOk and previous then
						table.insert(lines, "✗ Unlock " .. previous.Name .. " first")
					end
					if previous and (need.Discoveries or 0) > 0 then
						table.insert(
							lines,
							string.format(
								"%s %d/%d %s finds",
								if discOk then "✓" else "✗",
								math.min(prevFound, need.Discoveries),
								need.Discoveries,
								previous.Name
							)
						)
					end
					table.insert(
						lines,
						string.format(
							"%s 🪙 %s / %s",
							if coinOk then "✓" else "✗",
							Format.Coins(data.Coins),
							Format.Coins(need.Coins)
						)
					)
					Kit.Label({
						Parent = right,
						Size = UDim2.fromOffset(170, 46),
						Text = table.concat(lines, "\n"),
						TextSize = 12,
						Font = Theme.Fonts.Bold,
						TextColor3 = C.InkSoft,
						TextXAlignment = Enum.TextXAlignment.Right,
					})
				end
			end
		end
	end

	ClientState.Changed:Connect(refresh)
	Panels.Opened:Connect(function(name)
		if name == "Map" then
			refresh()
		end
	end)
end

return MapPanel
