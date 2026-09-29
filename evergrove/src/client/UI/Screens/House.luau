-- Your farmhouse: what this level gives you, the next upgrade, and shortcuts
-- to everything kept at home (storage, the kitchen, your showcase, mail).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local Land = require(Shared.Config.Land)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Describe = require(UI.Describe)
local C = require(UI.Parent.Controllers)

return {
	Id = "House",
	Title = "Farmhouse",
	Icon = "🏠",
	Size = Vector2.new(780, 520),
	Watch = { "Farm", "Coins", "Inventory", "Skills" },
	Build = function(win)
		local content = win.Content :: Frame
		local function render()
			Kit.Clear(content)
			local profile = C.State.Data()
			if not profile then
				return
			end
			local level = profile.Farm.House or 1
			local house = Land.House[level]
			local nextHouse = Land.House[level + 1]
			win.Title.Text = "🏠  Your " .. house.Name
			local left = Kit.Panel({ Size = UDim2.new(0.5, -6, 1, 0), Color = "PanelAlt" })
			left.Parent = content
			Kit.Padding(left, 12, 14)
			Kit.List(left, "Y", 8)
			Kit.Heading(house.Name .. "  " .. string.rep("★", level) .. string.rep("☆", #Land.House - level), 20).Parent = left
			local desc = Kit.Label(house.Description, { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
			desc.LayoutOrder = 1
			desc.Parent = left
			local perks = Kit.Label("📦 Home storage: " .. house.Storage .. " slots\n⚡ Max energy bonus: +" .. house.Energy .. "\n🍳 Kitchen: " .. (if level >= 2 then "yes" else "from the Cottage"), { Size = Theme.Sizes.Small, Wrap = true })
			perks.LayoutOrder = 2
			perks.Parent = left
			local shortcuts = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 180), LayoutOrder = 3, Parent = left })
			local grid = Kit.new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 40), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = shortcuts })
			grid.FillDirectionMaxCells = 2
			local function shortcut(order: number, text: string, enabled: boolean, fn: () -> ())
				local b = Kit.Button(text, { Style = "Secondary", TextSize = Theme.Sizes.Small, LayoutOrder = order, OnClick = fn })
				b.Parent = shortcuts
				Kit.SetEnabled(b, enabled)
			end
			shortcut(1, "📦 Storage", house.Storage > 0, function()
				C.Windows.Open("Inventory", { Container = "home" })
			end)
			shortcut(2, "🍳 Kitchen", level >= 2, function()
				C.Windows.Open("Crafting", { Station = "Kitchen" })
			end)
			shortcut(3, "🏆 Showcase", true, function()
				C.Windows.Open("Collection", { Tab = "Showcase" })
			end)
			shortcut(4, "✉️ Mail", true, function()
				C.Windows.Open("Mail")
			end)
			shortcut(5, "🗺️ Land", true, function()
				C.Windows.Open("Land")
			end)
			shortcut(6, "📊 Stats", true, function()
				C.Windows.Open("Profile", { Tab = "Stats" })
			end)
			-- Upgrade
			local right = Kit.Panel({ Size = UDim2.new(0.5, -6, 1, 0), Position = UDim2.new(0.5, 6, 0, 0), Color = "PanelAlt" })
			right.Parent = content
			Kit.Padding(right, 12, 14)
			Kit.List(right, "Y", 8)
			if not nextHouse then
				Kit.Heading("★ The grandest house in the valley", 18).Parent = right
				return
			end
			Kit.Heading("Next: " .. nextHouse.Name, 18).Parent = right
			local nd = Kit.Label(nextHouse.Description, { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
			nd.LayoutOrder = 1
			nd.Parent = right
			local price = math.floor(nextHouse.Cost * (1 - Stats.ShopDiscount(profile, "carpenter")))
			local estateOk = Stats.EstateLevel(profile) >= (nextHouse.Level or 1)
			local lines = { (if profile.Coins >= price then "✔️ " else "✖️ ") .. Kit.Money(price), (if estateOk then "✔️ " else "✖️ ") .. "Estate level " .. (nextHouse.Level or 1) .. " (you: " .. Stats.EstateLevel(profile) .. ")" }
			local haveAll = profile.Coins >= price and estateOk
			for _, mat in nextHouse.Mats do
				local def = Registry.Items[mat.Id]
				local have = Describe.CountInBag(profile, mat.Id)
				haveAll = haveAll and have >= mat.N
				table.insert(lines, (if have >= mat.N then "✔️ " else "✖️ ") .. (if def then def.Icon .. " " .. def.Name else mat.Id) .. "  " .. have .. " / " .. mat.N)
			end
			local req = Kit.Label(table.concat(lines, "\n"), { Size = Theme.Sizes.Small, Wrap = true })
			req.LayoutOrder = 2
			req.Parent = right
			local up = Kit.Button("🔨 Upgrade to " .. nextHouse.Name, { Style = "Accent", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, OnClick = function()
				Kit.Confirm("Upgrade your house?", "Gus and his crew will have your " .. nextHouse.Name .. " ready right away.", function(yes)
					if yes then
						local ok, err = Net.Request("HouseUpgrade")
						if ok then
							C.Audio.PlayUI("LevelUp")
						else
							C.Notify.Toast(tostring(err), "Warning")
						end
					end
				end, "Upgrade")
			end })
			up.Parent = right
			Kit.SetEnabled(up, haveAll)
			Kit.RepaintGradients(content)
		end
		render()
		return { Refresh = render }
	end,
}
