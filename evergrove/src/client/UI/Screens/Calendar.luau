-- The calendar: this season's days with festivals and villager birthdays,
-- today's date and moon, the weather forecast (the valley's weather is the
-- same on every server, so you can plan around storms and rainbows), and
-- the year's festivals.
-- Args: { Tab = "Season" | "Forecast" | "Festivals" }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared.Lib.Registry)
local GameTime = require(Shared.Lib.GameTime)
local WeatherMath = require(Shared.Lib.WeatherMath)
local Format = require(Shared.Lib.Format)
local Seasons = require(Shared.Config.Seasons)
local Festivals = require(Shared.Config.Festivals)
local NPCs = require(Shared.Config.NPCs)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Describe = require(UI.Describe)
local C = require(UI.Parent.Controllers)

return {
	Id = "Calendar",
	Title = "Calendar",
	Icon = "📅",
	Size = Vector2.new(960, 620),
	Build = function(win, ctx)
		local content = win.Content :: Frame
		local info = GameTime.Info()
		local season = info.Season
		local current = (ctx.Args and ctx.Args.Tab) or "Season"
		local selectedDay = info.DayOfSeason
		local render: () -> ()
		local tabs = Kit.Tabs({ { Id = "Season", Label = "Season", Icon = "📅" }, { Id = "Forecast", Label = "Forecast", Icon = "⛅" }, { Id = "Festivals", Label = "Festivals", Icon = "🎪" } }, function(id)
			current = id
			render()
		end)
		tabs.Frame.Parent = content
		local body = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46), Parent = content })

		local function eventsOn(seasonIndex: number, day: number): { string }
			local out = {}
			for _, f in Festivals.List do
				if f.Season == seasonIndex and f.Day == day then
					table.insert(out, f.Icon .. " " .. f.Name)
				end
			end
			for _, npc in NPCs.List do
				if npc.Birthday[1] == seasonIndex and npc.Birthday[2] == day then
					table.insert(out, "🎂 " .. npc.Name)
				end
			end
			return out
		end

		local function renderSeason()
			local s = Seasons[season]
			local header = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = body })
			local prev = Kit.Button("◀", { Style = "Secondary", Size = UDim2.fromOffset(40, 36), OnClick = function()
				season = (season - 2) % #Seasons + 1
				selectedDay = 1
				render()
			end })
			prev.Parent = header
			local title = Kit.Heading(s.Icon .. " " .. s.Name .. (if season == info.Season then "  ·  Year " .. info.Year else ""), 20)
			title.Position = UDim2.fromOffset(48, 0)
			title.Size = UDim2.new(1, -96, 1, 0)
			title.TextXAlignment = Enum.TextXAlignment.Center
			title.Parent = header
			local nextButton = Kit.Button("▶", { Style = "Secondary", Size = UDim2.fromOffset(40, 36), OnClick = function()
				season = season % #Seasons + 1
				selectedDay = 1
				render()
			end })
			nextButton.Position = UDim2.new(1, -40, 0, 0)
			nextButton.Parent = header
			local grid = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.62, 0, 1, -48), Position = UDim2.fromOffset(0, 48), Parent = body })
			local layout = Kit.new("UIGridLayout", { CellSize = UDim2.new(1 / 7, -6, 0, 70), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
			layout.FillDirectionMaxCells = 7
			for day = 1, GameTime.SEASON_DAYS do
				local events = eventsOn(season, day)
				local isToday = season == info.Season and day == info.DayOfSeason
				local cell = Kit.new("TextButton", { AutoButtonColor = false, Text = "", LayoutOrder = day, Selectable = true, Parent = grid })
				Kit.Paint(cell, "BackgroundColor3", if isToday then "HeaderA" elseif day == selectedDay then "SlotHover" else "PanelAlt")
				Kit.Corner(cell, 8)
				local number = Kit.Label(tostring(day), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Color = if isToday then "HeaderText" else "Text" })
				number.Position = UDim2.fromOffset(6, 2)
				number.Size = UDim2.new(1, -8, 0, 18)
				number.Parent = cell
				local icons = {}
				for _, e in events do
					table.insert(icons, (string.match(e, "^([^%s]+)")) or "•")
				end
				local ev = Kit.Label(table.concat(icons, ""), { Size = 18, Align = "Center" })
				ev.Position = UDim2.fromOffset(0, 24)
				ev.Size = UDim2.new(1, 0, 0, 30)
				ev.Parent = cell
				cell.Activated:Connect(function()
					selectedDay = day
					render()
				end)
			end
			local side = Kit.Panel({ Size = UDim2.new(0.38, -10, 1, -48), Position = UDim2.new(0.62, 10, 0, 48), Color = "PanelAlt" })
			side.Parent = body
			Kit.Padding(side, 12, 14)
			Kit.List(side, "Y", 8)
			Kit.Heading(Describe.SeasonDay(season, selectedDay), 18).Parent = side
			local events = eventsOn(season, selectedDay)
			local ev = Kit.Label(if #events > 0 then table.concat(events, "\n") else "Nothing special — a good day for farming.", { Size = Theme.Sizes.Small, Wrap = true })
			ev.LayoutOrder = 1
			ev.Parent = side
			local flavor = Kit.Label(s.Flavor, { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
			flavor.LayoutOrder = 2
			flavor.Parent = side
			local inSeason = {}
			for _, crop in Registry.Crops do
				if table.find(crop.Seasons, s.Id) and crop.Rarity == "Common" and #inSeason < 12 then
					table.insert(inSeason, crop.Icon)
				end
			end
			local crops = Kit.Label("In season: " .. table.concat(inSeason, " "), { Size = Theme.Sizes.Small, Wrap = true })
			crops.LayoutOrder = 3
			crops.Parent = side
			if season == info.Season then
				local today = Kit.Label("Today: " .. GameTime.DateText(info) .. " · " .. GameTime.WEEKDAYS[info.Weekday] .. "\n" .. (if info.FullMoon then "🌕 Full moon tonight — rare night crops and fish stir." else "🌙 Moon phase " .. (info.Moon + 1)), { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
				today.LayoutOrder = 4
				today.Parent = side
			end
		end

		local function renderForecast()
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = body
			Kit.List(list, "Y", 6)
			local intro = Kit.Label("The weather is the same everywhere in the valley at the same time — plan mutations, hybrids and fishing trips around it. Regions like the mountains or desert twist it their own way.", { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
			intro.Parent = list
			local region = C.Lighting.Region()
			for i, entry in WeatherMath.Forecast(12) do
				local base = WeatherMath.Def(entry.Weather)
				local local2 = WeatherMath.Def(WeatherMath.ForRegion(entry.Weather, region))
				local row = Kit.Card(46)
				row.LayoutOrder = i
				row.Parent = list
				local at = GameTime.Info(entry.Start)
				local when = Kit.Label(GameTime.WEEKDAYS[at.Weekday] .. " " .. Format.Clock(at.Hour, C.Settings.Get("Clock24")) .. " (in " .. Format.Duration(math.max(0, entry.Start - GameTime.Now())) .. ")", { Size = Theme.Sizes.Small })
				when.Size = UDim2.new(0.4, 0, 1, 0)
				when.Parent = row
				local what = Kit.Label((if base then base.Icon .. " " .. base.Name else entry.Weather) .. (if local2 and base and local2.Id ~= base.Id then "  (here: " .. local2.Icon .. " " .. local2.Name .. ")" else "") .. (if entry.Night then "  🌙" else ""), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
				what.Position = UDim2.fromScale(0.4, 0)
				what.Size = UDim2.new(0.6, 0, 1, 0)
				what.Parent = row
				if base and base.Description then
					Kit.AttachTooltip(row, function()
						return { { Text = base.Name, Bold = true }, { Text = base.Description, Color = "SubText", Size = Theme.Sizes.Small } }
					end)
				end
			end
		end

		local function renderFestivals()
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = body
			Kit.List(list, "Y", 8)
			for i, f in Festivals.List do
				local card = Kit.Card()
				card.LayoutOrder = i
				card.Parent = list
				Kit.List(card, "Y", 4)
				Kit.Label(f.Icon .. " " .. f.Name .. "  ·  " .. Describe.SeasonDay(f.Season, f.Day) .. ", " .. Format.Clock(f.Hours[1]) .. "–" .. Format.Clock(f.Hours[2]), { Size = Theme.Sizes.Body, Font = Theme.Fonts.Bold }).Parent = card
				local d = Kit.Label(f.Description, { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
				d.LayoutOrder = 1
				d.Parent = card
				local acts = {}
				for _, a in f.Activities do
					table.insert(acts, a.Icon .. " " .. a.Name)
				end
				local a = Kit.Label(table.concat(acts, "   "), { Size = Theme.Sizes.Small, Wrap = true })
				a.LayoutOrder = 2
				a.Parent = card
			end
			local nm = Festivals.NightMarket
			if nm then
				local night = Kit.Label("🌙 Night Market: every " .. GameTime.WEEKDAYS[nm.Weekday] .. " " .. Format.Clock(nm.Hours[1]) .. "–" .. Format.Clock(nm.Hours[2]) .. " — everything sells for +" .. math.floor(nm.SellBonus * 100) .. "%.", { Size = Theme.Sizes.Small, Color = "Accent", Wrap = true })
				night.LayoutOrder = 100
				night.Parent = list
			end
			local open = Kit.Button("🎪 Festival hub", { Style = "Secondary", Size = UDim2.fromOffset(180, 36), TextSize = Theme.Sizes.Small, LayoutOrder = 101, OnClick = function()
				C.Windows.Open("Festival")
			end })
			open.Parent = list
		end

		render = function()
			Kit.Clear(body)
			if current == "Season" then
				renderSeason()
			elseif current == "Forecast" then
				renderForecast()
			else
				renderFestivals()
			end
			Kit.RepaintGradients(body)
		end
		tabs.Select(current)
		return { Refresh = render }
	end,
}
