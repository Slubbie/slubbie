-- Progress pages: the achievement journal, every course by district with
-- your medals and records, and the leaderboards (global top runs and your
-- friends' times, standardized ranked runs only).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Shared.Config.Achievements)
local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Stats = require(ReplicatedStorage.Shared.Logic.Stats)

local Bus = require(script.Parent.Parent.Parent.Core.Bus)
local State = require(script.Parent.Parent.Parent.Core.State)
local CourseClient = require(script.Parent.Parent.Parent.Gameplay.CourseClient)
local Explore = require(script.Parent.Parent.Parent.Gameplay.Explore)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors

local achievementCategory = "Exploration"
local courseDistrict = "Hub"
local recordCourse: string? = nil
local recordScope = "Top"

local function tabRow(
	container: Instance,
	items: { { Id: string, Text: string } },
	selected: string,
	onPick: (string) -> ()
): ScrollingFrame
	local tabs = Kit.Scroll(container, {
		Size = UDim2.new(1, 0, 0, 44),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
	})
	Kit.List(tabs, true, 6)
	for _, item in items do
		Kit.Button(
			tabs,
			item.Text,
			function()
				onPick(item.Id)
			end,
			"Secondary",
			{
				Size = UDim2.fromOffset(150, 36),
				BackgroundColor3 = if item.Id == selected then C.Accent:Lerp(C.PanelLight, 0.5) else C.PanelLight,
			}
		)
	end
	return tabs
end

local function districtTabs(): { { Id: string, Text: string } }
	local items = {}
	for _, district in Districts.Ordered() do
		table.insert(items, { Id = district.Id, Text = district.Short })
	end
	return items
end

-- Achievements -----------------------------------------------------------------------------------------

local function buildAchievements(container: Frame)
	local profile = State.Profile
	if not profile then
		return
	end
	local items = {}
	for _, category in Achievements.Categories do
		table.insert(items, { Id = category.Id, Text = category.Icon .. " " .. category.Name })
	end
	tabRow(container, items, achievementCategory, function(id)
		achievementCategory = id
		Kit.Clear(container)
		buildAchievements(container)
	end)
	local earned, total = 0, 0
	for _, achievement in Achievements.List do
		total += 1
		if profile.Achievements[achievement.Id] then
			earned += 1
		end
	end
	Kit.Label(
		container,
		("%d of %d achievements earned"):format(earned, total),
		14,
		{ Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 20), TextColor3 = C.Muted }
	)
	local list = Kit.Scroll(container, { Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 1, -76) })
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -8, 0, 112),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	-- Cache totals for "every cache in a district" style entries.
	local cacheTotals = {}
	for _, district in Districts.Ordered() do
		local _, cacheCount = Explore.Count("Cache", district.Id)
		cacheTotals[district.Id] = cacheCount
	end
	local context = { CacheTotals = cacheTotals }
	for index, achievement in Achievements.List do
		if achievement.Category == achievementCategory then
			local got = profile.Achievements[achievement.Id]
			local card =
				Kit.Panel(list, { BackgroundColor3 = C.PanelLight, LayoutOrder = (if got then 0 else 1000) + index })
			Kit.Padding(card, 10)
			Kit.List(card, false, 3)
			local hidden = achievement.Hidden and not got
			Kit.Label(
				card,
				(if got then "🏆 " else "◇ ") .. (if hidden then "???" else achievement.Name),
				15,
				{ Font = Kit.Fonts.Bold, TextColor3 = if got then C.Accent else C.Text }
			)
			Kit.Paragraph(
				card,
				if hidden then "A hidden achievement. Keep exploring." else achievement.Text,
				12,
				C.Muted
			)
			if not got and not hidden then
				local value = Stats.Get(profile, achievement.Stat, context)
				local bar = Kit.Bar(card, C.Signal)
				bar.Set(value / achievement.Target)
				Kit.Label(
					card,
					("%s / %s"):format(
						Format.Number(math.min(value, achievement.Target)),
						Format.Number(achievement.Target)
					),
					11,
					{ TextColor3 = C.Faint }
				)
			elseif got then
				Kit.Label(card, "Earned " .. os.date("%d %b %Y", got), 11, { TextColor3 = C.Faint })
			end
			Kit.Label(
				card,
				Kit.Rewards({
					XP = achievement.XP,
					Credits = achievement.Credits,
					Prestige = achievement.Prestige,
					Items = if achievement.Item then { achievement.Item } else nil,
				}),
				11,
				{ TextColor3 = C.Accent }
			)
		end
	end
end

-- Courses ----------------------------------------------------------------------------------------------

local function buildCourses(container: Frame, args: any)
	local profile = State.Profile
	if not profile then
		return
	end
	if type(args) == "table" and type(args.District) == "string" and Districts.ById[args.District] then
		courseDistrict = args.District
	end
	tabRow(container, districtTabs(), courseDistrict, function(id)
		courseDistrict = id
		Kit.Clear(container)
		buildCourses(container, nil)
	end)
	local list = Kit.Scroll(container, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52) })
	Kit.List(list, false, 8)
	local district = Districts.ById[courseDistrict]
	Kit.Paragraph(list, district.Tagline, 14, C.Muted)
	for _, course in Courses.Of(courseDistrict) do
		local config = CourseClient.Config(course.Id)
		local record = profile.Courses[course.Id]
		local row = Kit.Panel(list, { Size = UDim2.new(1, -8, 0, 64), BackgroundColor3 = C.PanelLight })
		Kit.Padding(row, 8, 12)
		local medal = record and record.Medal or 0
		local kind = if course.Kind == "Room" then "Room" elseif course.Kind == "Relay" then "Relay" else "Course"
		Kit.Label(
			row,
			("%s  %s"):format(if medal > 0 then ({ "●", "◆", "★", "✦" })[medal] else "○", course.Name),
			16,
			{
				Font = Kit.Fonts.Bold,
				Size = UDim2.new(0.5, 0, 0, 22),
				TextColor3 = if medal > 0 then C.Medal[medal] else C.Text,
			}
		)
		local tokens = 0
		for _ in (record and record.Tokens or {}) :: { [any]: any } do
			tokens += 1
		end
		Kit.Label(
			row,
			("%s · %s · best %s · ★ %d/%d"):format(
				kind,
				Courses.DifficultyNames[course.Difficulty] or "",
				Format.Time(record and record.Best),
				tokens,
				if config then config:GetAttribute("Tokens") or 0 else 0
			),
			13,
			{ Position = UDim2.fromOffset(0, 24), Size = UDim2.new(0.6, 0, 0, 20), TextColor3 = C.Muted }
		)
		Kit.Button(
			row,
			"Preview",
			function()
				Bus.ClosePages:Fire()
				Bus.CoursePreview:Fire(course.Id)
			end,
			"Secondary",
			{ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(110, 36) }
		)
		Kit.Button(
			row,
			"Records",
			function()
				recordCourse = course.Id
				Bus.OpenPage:Fire("Records", nil)
			end,
			"Ghost",
			{
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -120, 0.5, 0),
				Size = UDim2.fromOffset(100, 36),
			}
		)
	end
end

-- Records ----------------------------------------------------------------------------------------------

local function buildRecords(container: Frame)
	local profile = State.Profile
	if not profile then
		return
	end
	local districtCourses = Courses.Of(courseDistrict, "Course")
	if not recordCourse or not Courses.ById[recordCourse] then
		recordCourse = if districtCourses[1] then districtCourses[1].Id else nil
	end
	tabRow(container, districtTabs(), courseDistrict, function(id)
		courseDistrict = id
		recordCourse = nil
		Kit.Clear(container)
		buildRecords(container)
	end)
	local controls = Kit.Row(container, 40, 8)
	controls.Position = UDim2.fromOffset(0, 50)
	local names = {}
	local ids = {}
	for _, course in Courses.Of(courseDistrict) do
		table.insert(names, course.Name)
		table.insert(ids, course.Id)
	end
	local list = Kit.Scroll(container, { Position = UDim2.fromOffset(0, 98), Size = UDim2.new(1, 0, 1, -98) })
	Kit.List(list, false, 6)
	local function load()
		Kit.Clear(list)
		local courseId = recordCourse
		if not courseId then
			Kit.Paragraph(list, "No courses here.", 14, C.Faint)
			return
		end
		local record = profile.Courses[courseId]
		Kit.Paragraph(
			list,
			("Your best %s · ranked %s · medal %s"):format(
				Format.Time(record and record.Best),
				Format.Time(record and record.RankedBest),
				Kit.MedalText(record and record.Medal or 0)
			),
			14,
			C.Text
		)
		local loading = Kit.Paragraph(list, "Loading…", 13, C.Faint)
		task.spawn(function()
			local ok, entries = pcall(Net.Invoke, "Course.Leaderboard", courseId, recordScope)
			if not list.Parent then
				return
			end
			loading.Text = ""
			if not ok or type(entries) ~= "table" or #entries == 0 then
				loading.Text = if recordScope == "Friends"
					then "No ranked times from friends yet."
					else "No ranked times yet. Be the first."
				return
			end
			for _, entry in entries do
				local mine = entry.Name == game:GetService("Players").LocalPlayer.DisplayName
				Kit.Label(list, ("%3d.   %-24s   %s"):format(entry.Rank, entry.Name, Format.Time(entry.Seconds)), 15, {
					Font = Kit.Fonts.Mono,
					TextColor3 = if mine
						then C.Accent
						elseif entry.Rank <= 3 then C.Medal[({ 3, 2, 1 })[entry.Rank]]
						else C.Text,
				})
			end
		end)
	end
	if #names > 0 then
		local currentName = names[table.find(ids, recordCourse) or 1]
		Kit.Choice(controls, names, currentName, function(name)
			recordCourse = ids[table.find(names, name) or 1]
			load()
		end).Size =
			UDim2.fromOffset(280, 36)
	end
	Kit.Choice(controls, { "Top", "Friends" }, recordScope, function(scope)
		recordScope = scope
		load()
	end)
	-- Personal mode records.
	Kit.Label(
		controls,
		("Spire floor %d · Dreamline %d gates"):format(
			profile.Tower and profile.Tower.Highest or 0,
			profile.Endless and profile.Endless.Best or 0
		),
		13,
		{
			Size = UDim2.fromOffset(300, 36),
			TextColor3 = C.Muted,
		}
	)
	load()
end

return {
	Pages = {
		{
			Id = "Achievements",
			Title = "Achievements",
			Icon = "🏆",
			Order = 7,
			Sections = { "Achievements", "Stats" },
			Build = buildAchievements,
		},
		{
			Id = "Courses",
			Title = "Courses",
			Icon = "⚑",
			Order = 8,
			Sections = { "Courses" },
			Build = buildCourses,
		},
		{
			Id = "Records",
			Title = "Records",
			Icon = "⏱",
			Order = 9,
			Sections = { "Courses" },
			Build = buildRecords,
		},
	},
}
