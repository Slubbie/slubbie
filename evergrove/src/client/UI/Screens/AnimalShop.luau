-- Hattie's ranch: adopt animals. Each species shows its home, product,
-- feed, level requirement and price; pick which building it moves into.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local Format = require(Shared.Lib.Format)
local GameTime = require(Shared.Lib.GameTime)
local Animals = require(Shared.Config.Animals)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local AnimalInfo = require(UI.AnimalInfo)
local C = require(UI.Parent.Controllers)

return {
	Id = "AnimalShop",
	Title = "Hattie's Ranch",
	Icon = "🐄",
	Size = Vector2.new(900, 600),
	Watch = { "Coins", "Farm", "Skills" },
	Build = function(win, ctx)
		local content = win.Content :: Frame
		local function render()
			Kit.Clear(content)
			local profile = C.State.Data()
			local ranching = if profile then Stats.SkillLevel(profile, "Ranching") else 1
			local discount = if profile then Stats.ShopDiscount(profile, "ranch") else 0
			local homes = AnimalInfo.Homes(profile)
			local grid = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			grid.Parent = content
			local layout = Kit.new("UIGridLayout", {
				CellSize = UDim2.new(0.5, -6, 0, 132),
				CellPadding = UDim2.fromOffset(10, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = grid,
			})
			layout.FillDirectionMaxCells = 2
			for i, species in Animals.List do
				if species.Buyable then
					local price = math.floor(species.Price * (1 - discount))
					local locked = ranching < species.Level
					local card = Kit.Card(132)
					card.LayoutOrder = i + (if locked then 100 else 0)
					card.Parent = grid
					local icon = Kit.new("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.fromOffset(64, 64),
						Text = species.Icon,
						TextScaled = true,
						Font = Theme.Fonts.Body,
						Parent = card,
					})
					icon.TextTransparency = if locked then 0.5 else 0
					local name = Kit.Label(species.Name, { Size = Theme.Sizes.Body, Font = Theme.Fonts.Bold })
					name.Position = UDim2.fromOffset(74, 0)
					name.Size = UDim2.new(1, -74, 0, 22)
					name.Parent = card
					local product = Registry.Items[species.Product]
					local feeds = {}
					for _, id in species.Feed do
						local item = Registry.Items[id]
						table.insert(feeds, if item then item.Icon else id)
					end
					local info = Kit.Label(
						"Lives in a "
							.. species.Home
							.. "\n"
							.. (if product then product.Icon .. " " .. product.Name else species.Product)
							.. " every "
							.. Format.Duration(species.Interval * GameTime.HOUR)
							.. "\nEats "
							.. table.concat(feeds, " / ")
							.. (if species.Rideable then " · 🏇 rideable" else ""),
						{ Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true }
					)
					info.Position = UDim2.fromOffset(74, 24)
					info.Size = UDim2.new(1, -74, 0, 0)
					info.Parent = card
					local free = {}
					for _, home in homes do
						if home.Def.Function.Home == species.Home and home.Residents < home.Def.Function.Capacity then
							table.insert(free, home)
						end
					end
					local status = if locked
						then "🔒 Ranching " .. species.Level
						elseif #free == 0 then "Needs a " .. species.Home .. " with room"
						else #free .. " home" .. (if #free > 1 then "s" else "") .. " with room"
					local statusLabel = Kit.Label(
						status,
						{ Size = Theme.Sizes.Tiny, Color = if locked or #free == 0 then "Warn" else "Good" }
					)
					statusLabel.Position = UDim2.new(0, 0, 1, -36)
					statusLabel.Size = UDim2.new(1, -140, 0, 16)
					statusLabel.Parent = card
					local priceLabel = Kit.Label(
						Kit.Money(price),
						{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Number, Color = "Accent" }
					)
					priceLabel.Position = UDim2.new(0, 0, 1, -18)
					priceLabel.Size = UDim2.new(1, -140, 0, 18)
					priceLabel.Parent = card
					local buy = Kit.Button("Adopt", {
						Style = "Primary",
						Size = UDim2.fromOffset(120, 36),
						TextSize = Theme.Sizes.Small,
						OnClick = function()
							local function go(homeUid: string)
								local ok, result = Net.Request("AnimalBuy", species.Id, homeUid)
								if ok then
									C.Audio.PlayUI("Discovery")
								else
									C.Notify.Toast(tostring(result), "Warning")
								end
							end
							if #free <= 1 then
								go(if free[1] then free[1].Uid else "")
								return
							end
							Kit.Confirm(
								"Which home?",
								"You have "
									.. #free
									.. " "
									.. species.Home
									.. "s with room. Your new "
									.. species.Name
									.. " will move into the first one with space — you can move it later from its care card.",
								function(yes)
									if yes then
										go(free[1].Uid)
									end
								end,
								"Adopt"
							)
						end,
					})
					buy.Position = UDim2.new(1, -120, 1, -36)
					buy.Parent = card
					Kit.SetEnabled(buy, not locked and #free > 0 and (profile and profile.Coins or 0) >= price)
				end
			end
			Kit.RepaintGradients(grid)
		end
		render()
		return { Refresh = render }
	end,
}
