-- The menu hub: every screen in one place (the main way in on gamepad and
-- phone), quick actions (build, photo, go home), emotes, and a short help
-- section for new farmers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Stats = require(Shared.Lib.Stats)
local Social = require(Shared.Config.Social)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local C = require(UI.Parent.Controllers)

local ENTRIES = {
	{ "Inventory", "🎒", "Backpack", "B" },
	{ "Quests", "📜", "Quests", "J" },
	{ "Map", "🗺️", "Map", "M" },
	{ "Skills", "🌟", "Skills", "K" },
	{ "Collection", "📖", "Collection", "C" },
	{ "Crafting", "🔨", "Crafting", "V" },
	{ "Animals", "🐄", "Animals", "" },
	{ "Land", "🏡", "Land & layouts", "L" },
	{ "Market", "📈", "Market", "" },
	{ "Mail", "✉️", "Mailbox", "N" },
	{ "Social", "👥", "Friends & co-op", "O" },
	{ "Profile", "🪪", "Profile & stats", "P" },
	{ "Calendar", "📅", "Calendar", "U" },
	{ "Achievements", "🏅", "Achievements", "Y" },
	{ "Festival", "🎪", "Festival", "" },
	{ "Daily", "🎁", "Daily gift", "" },
	{ "Store", "🛍️", "Store", "" },
	{ "Lore", "📜", "Lore pages", "" },
	{ "Settings", "⚙️", "Settings", "F1" },
}

return {
	Id = "Menu",
	Title = "Menu",
	Icon = "☰",
	Size = Vector2.new(900, 600),
	Build = function(win, ctx)
		local content = win.Content :: Frame
		local profile = C.State.Data()
		local grid = Kit.Scroll({ Size = UDim2.new(0.62, -6, 1, 0) })
		grid.Parent = content
		local layout = Kit.new("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -8, 0, 74),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		layout.FillDirectionMaxCells = 3
		for i, entry in ENTRIES do
			local b = Kit.new(
				"TextButton",
				{ AutoButtonColor = false, Text = "", LayoutOrder = i, Selectable = true, Parent = grid }
			)
			Kit.Paint(b, "BackgroundColor3", "PanelAlt")
			Kit.Corner(b, 10)
			Kit.Stroke(b, "Stroke", 1)
			local icon = Kit.new("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(44, 44),
				Position = UDim2.fromOffset(8, 15),
				Text = entry[2],
				TextScaled = true,
				Font = Theme.Fonts.Body,
				Parent = b,
			})
			icon.Name = "Icon"
			local name = Kit.Label(entry[3], { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
			name.Position = UDim2.fromOffset(58, 14)
			name.Size = UDim2.new(1, -62, 0, 22)
			name.Parent = b
			if entry[4] ~= "" and C.Settings.PrimaryInput() == "Keyboard" then
				local key = Kit.Label("[" .. entry[4] .. "]", { Size = Theme.Sizes.Tiny, Color = "SubText" })
				key.Position = UDim2.fromOffset(58, 38)
				key.Size = UDim2.new(1, -62, 0, 16)
				key.Parent = b
			end
			b.MouseEnter:Connect(function()
				Kit.Paint(b, "BackgroundColor3", "SlotHover")
			end)
			b.MouseLeave:Connect(function()
				Kit.Paint(b, "BackgroundColor3", "PanelAlt")
			end)
			b.Activated:Connect(function()
				Kit.PlaySound("UIClick")
				C.Windows.Open(entry[1])
			end)
		end

		local right =
			Kit.Panel({ Size = UDim2.new(0.38, -6, 1, 0), Position = UDim2.new(0.62, 6, 0, 0), Color = "PanelAlt" })
		right.Parent = content
		Kit.Padding(right, 12, 14)
		Kit.List(right, "Y", 8)
		if profile then
			local hello = Kit.Label(
				"🏡 "
					.. (if profile.Farm.Name ~= "" then profile.Farm.Name else "Your farm")
					.. "  ·  Estate "
					.. Stats.EstateLevel(profile),
				{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold }
			)
			hello.Parent = right
		end
		local actions = Kit.new(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 132), LayoutOrder = 1, Parent = right }
		)
		local g = Kit.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -4, 0, 40),
			CellPadding = UDim2.fromOffset(8, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = actions,
		})
		g.FillDirectionMaxCells = 2
		Kit.Button("🛠️ Build mode", {
			Style = "Primary",
			TextSize = Theme.Sizes.Small,
			LayoutOrder = 1,
			OnClick = function()
				ctx.Close()
				C.Build.Enter(nil)
			end,
		}).Parent =
			actions
		Kit.Button("📷 Photo mode", {
			Style = "Secondary",
			TextSize = Theme.Sizes.Small,
			LayoutOrder = 2,
			OnClick = function()
				ctx.Close()
				C.Photo.Toggle()
			end,
		}).Parent =
			actions
		Kit.Button("🏠 Go home", {
			Style = "Secondary",
			TextSize = Theme.Sizes.Small,
			LayoutOrder = 3,
			OnClick = function()
				local ok, err = Net.Request("GoHome")
				if ok then
					ctx.Close()
				else
					C.Notify.Toast(tostring(err), "Warning")
				end
			end,
		}).Parent =
			actions
		Kit.Button("🖥️ Automation", {
			Style = "Secondary",
			TextSize = Theme.Sizes.Small,
			LayoutOrder = 4,
			OnClick = function()
				C.Windows.Open("FarmControl")
			end,
		}).Parent =
			actions
		Kit.Button("⚒️ Tools", {
			Style = "Secondary",
			TextSize = Theme.Sizes.Small,
			LayoutOrder = 5,
			OnClick = function()
				C.Windows.Open("Tools")
			end,
		}).Parent =
			actions
		Kit.Button("🧬 Seed genes", {
			Style = "Secondary",
			TextSize = Theme.Sizes.Small,
			LayoutOrder = 6,
			OnClick = function()
				C.Windows.Open("SeedBreed", { Tab = "Scan" })
			end,
		}).Parent =
			actions
		-- Emotes
		local eh = Kit.Label("Emotes", { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
		eh.LayoutOrder = 2
		eh.Parent = right
		local emotes = Kit.new(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 80), LayoutOrder = 3, Parent = right }
		)
		Kit.Grid(emotes, 36, 4)
		local owned = C.State.Get("Cosmetics", "Owned") or {}
		for i, emote in Social.Emotes do
			local b = Kit.IconButton(
				emote.Icon,
				emote.Name .. (if emote.Pack and not owned["Emote:" .. emote.Id] then " (emote pack)" else ""),
				function()
					ctx.Close()
					C.Photo.Emote(emote.Id)
				end,
				36
			)
			b.LayoutOrder = i
			b.Parent = emotes
		end
		-- Help
		local help = Kit.Label(
			"New here? Till soil with the hoe, plant seeds, keep them watered and harvest when they sparkle. Sell in the shipping bin (paid at 6 AM) or to villagers. Talk to everyone — friendships unlock recipes, shops and stories. Weather matters: storms, frost and rainbows can mutate crops into something rare.",
			{ Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true }
		)
		help.LayoutOrder = 10
		help.Parent = right
		if C.State.Get("Tutorial", "Done") ~= true then
			local tut = Kit.Button("Skip the tutorial", {
				Style = "Ghost",
				Size = UDim2.new(1, 0, 0, 30),
				TextSize = Theme.Sizes.Tiny,
				LayoutOrder = 11,
				OnClick = function()
					Kit.Confirm("Skip the tutorial?", "You'll still get the starter gift.", function(yes)
						if yes then
							Net.Request("TutorialSkip")
						end
					end, "Skip")
				end,
			})
			tut.Parent = right
		end
		return nil
	end,
}
