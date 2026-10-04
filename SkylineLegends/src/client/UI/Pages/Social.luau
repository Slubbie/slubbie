-- Social pages: the race board (open races and relay teams, your lobby,
-- readying up and inviting people), your crew (members, weekly crew goal,
-- invites) and everyone in this server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)

local State = require(script.Parent.Parent.Parent.Core.State)
local Modes = require(script.Parent.Parent.Parent.Gameplay.Modes)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors
local player = Players.LocalPlayer

local function invitePicker(parent: Instance, kind: string)
	local box = Kit.Card(parent)
	Kit.Label(box, "Invite someone", 15, { Font = Kit.Fonts.Bold })
	local status = Kit.Paragraph(box, "Loading players…", 13, C.Faint)
	task.spawn(function()
		local ok, list = pcall(Net.Invoke, "Social.Players")
		if not ok or type(list) ~= "table" or not box.Parent then
			status.Text = "Couldn't list players."
			return
		end
		status.Text = ""
		local any = false
		for _, entry in list do
			if not entry.You then
				any = true
				local row = Kit.Row(box, 36, 8)
				Kit.Label(row, ("%s%s  Lv %d"):format(if entry.Friend then "★ " else "", entry.Name, entry.Level or 1), 14, { Size = UDim2.new(1, -130, 1, 0) })
				Kit.Button(row, "Invite", function()
					Net.Send("Social.Invite", entry.UserId, kind)
				end, "Secondary", { Size = UDim2.fromOffset(110, 32) })
			end
		end
		if not any then
			status.Text = "Nobody else is in this server yet. Invite friends from the Roblox menu!"
		end
	end)
end

-- Races --------------------------------------------------------------------------------------------------

local function lobbyCard(parent: Instance, data: any, isRelay: boolean)
	local card = Kit.Card(parent)
	Kit.Label(card, ("%s · %s"):format(if isRelay then "RELAY TEAM" else "YOUR RACE", tostring(data.CourseName)), 17, { Font = Kit.Fonts.Black, TextColor3 = Color3.fromRGB(255, 120, 220) })
	Kit.Paragraph(card, ("%d / %d runners · %s"):format(#(data.Members or {}), data.Max or 8, if data.State == "Running" then "running now" else "in the lobby"), 13, C.Muted)
	local mine = false
	for _, member in data.Members or {} do
		if member.UserId == player.UserId then
			mine = member.Ready
		end
		Kit.Label(card, ("%s %s%s"):format(if member.Ready then "✓" else "…", member.Name, if member.Host then " (host)" else ""), 14, { TextColor3 = if member.Ready then C.Good else C.Text })
	end
	if not isRelay and data.Results and #data.Results > 0 then
		Kit.Label(card, "Last race", 14, { Font = Kit.Fonts.Bold, TextColor3 = C.Accent })
		for _, result in data.Results do
			Kit.Label(card, ("%d. %s  %s"):format(result.Place, result.Name, Format.Time(result.Seconds)), 14)
		end
	end
	if data.State ~= "Running" then
		local row = Kit.Row(card, 42, 8)
		Kit.Button(row, if mine then "Not ready" else "Ready!", function()
			Net.Send(if isRelay then "Relay.Ready" else "Race.Ready", not mine)
		end, if mine then "Secondary" else "Primary", { Size = UDim2.fromOffset(140, 38) })
		Kit.Button(row, "Leave", function()
			Net.Send(if isRelay then "Relay.Leave" else "Race.Leave")
		end, "Ghost", { Size = UDim2.fromOffset(100, 38) })
		Kit.Paragraph(card, "Everyone readies up and the countdown starts. Races use standard attributes and the course's full kit.", 12, C.Faint)
		invitePicker(card, if isRelay then "Relay" else "Race")
	end
end

local function buildRaces(container: Frame)
	local scroll = Kit.Scroll(container)
	Kit.List(scroll, false, 10)
	Kit.Padding(scroll, 4)
	if Modes.Race then
		lobbyCard(scroll, Modes.Race, false)
	end
	if Modes.Relay then
		lobbyCard(scroll, Modes.Relay, true)
	end
	Kit.Label(scroll, "Open in this server", 18, { Font = Kit.Fonts.Black, TextColor3 = C.Accent })
	local openList = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = scroll })
	Kit.List(openList, false, 6)
	local status = Kit.Paragraph(openList, "Checking the board…", 13, C.Faint)
	local message = Kit.Paragraph(scroll, "", 13, C.Bad)
	task.spawn(function()
		local data = Modes.RaceList()
		if not openList.Parent then
			return
		end
		status.Text = ""
		local count = 0
		for _, entry in (if type(data) == "table" then data.Races or {} else {}) :: { any } do
			if entry.State == "Lobby" and not (Modes.Race and Modes.Race.Id == entry.Id) then
				count += 1
				local row = Kit.Row(openList, 40, 8)
				Kit.Label(row, ("Race · %s · %d/%d"):format(entry.CourseName, #entry.Members, entry.Max), 14, { Size = UDim2.new(1, -130, 1, 0) })
				Kit.Button(row, "Join", function()
					task.spawn(function()
						local ok, info = Modes.JoinRace(entry.Id)
						if not ok then
							message.Text = tostring(info)
						end
					end)
				end, "Primary", { Size = UDim2.fromOffset(110, 34) })
			end
		end
		for _, entry in (if type(data) == "table" then data.Relays or {} else {}) :: { any } do
			if entry.State == "Lobby" and not (Modes.Relay and Modes.Relay.Id == entry.Id) then
				count += 1
				local row = Kit.Row(openList, 40, 8)
				Kit.Label(row, ("Relay · %s · %d/%d"):format(entry.CourseName, #entry.Members, entry.Max), 14, { Size = UDim2.new(1, -130, 1, 0) })
				Kit.Button(row, "Join team", function()
					task.spawn(function()
						local ok, info = Modes.JoinRelay(entry.Id)
						if not ok then
							message.Text = tostring(info)
						end
					end)
				end, "Primary", { Size = UDim2.fromOffset(110, 34) })
			end
		end
		if count == 0 then
			status.Text = "No open races. Start one below!"
		end
	end)
	-- Start something.
	Kit.Label(scroll, "Start a race", 18, { Font = Kit.Fonts.Black, TextColor3 = C.Accent })
	local profile = State.Profile
	local any = false
	for _, course in Courses.List do
		local record = profile and profile.Courses and profile.Courses[course.Id]
		if (course.Kind == "Course" or course.Kind == "Relay") and record and (record.Completions or 0) > 0 or course.District == "Hub" and course.Kind ~= "Room" then
			any = true
			local row = Kit.Row(scroll, 40, 8)
			Kit.Label(row, ("%s · %s"):format(course.Name, course.District), 14, { Size = UDim2.new(1, -170, 1, 0) })
			Kit.Button(row, if course.Kind == "Relay" then "Form relay" else "Open race", function()
				task.spawn(function()
					local ok, info
					if course.Kind == "Relay" then
						ok, info = Modes.CreateRelay(course.Id)
					else
						ok, info = Modes.CreateRace(course.Id)
					end
					if not ok then
						message.Text = tostring(info)
					end
				end)
			end, "Secondary", { Size = UDim2.fromOffset(150, 34) })
		end
	end
	if not any then
		Kit.Paragraph(scroll, "Finish a course to open races on it.", 13, C.Faint)
	end
end

-- Crew -----------------------------------------------------------------------------------------------------

local function buildCrew(container: Frame)
	local scroll = Kit.Scroll(container)
	Kit.List(scroll, false, 10)
	Kit.Padding(scroll, 4)
	local status = Kit.Paragraph(scroll, "Loading crew…", 13, C.Faint)
	task.spawn(function()
		local ok, crew = pcall(Net.Invoke, "Crew.Get")
		if not scroll.Parent then
			return
		end
		status.Text = ""
		if ok and type(crew) == "table" then
			Kit.Label(scroll, ("[%s] %s"):format(crew.Tag, crew.Name), 24, { Font = Kit.Fonts.Black, TextColor3 = C.Good })
			local goal = Kit.Card(scroll)
			Kit.Label(goal, ("Weekly crew goal · resets in %s"):format(Format.Duration(crew.ResetIn or 0)), 15, { Font = Kit.Fonts.Bold })
			local top = crew.Tiers[#crew.Tiers]
			local bar = Kit.Bar(goal, C.Good)
			bar.Set((crew.Points or 0) / top)
			local tiers = {}
			for index, needed in crew.Tiers do
				table.insert(tiers, ("%s %d pts: %s"):format(if (crew.Points or 0) >= needed then "✓" else "·", needed, Kit.Rewards(crew.Rewards[index])))
			end
			Kit.Paragraph(goal, ("%d points this week (%d all time)\n%s"):format(crew.Points or 0, crew.Total or 0, table.concat(tiers, "\n")), 13, C.Muted)
			Kit.Paragraph(goal, "Every course, race, relay and Spire floor a member finishes adds points.", 12, C.Faint)
			Kit.Label(scroll, "Members", 17, { Font = Kit.Fonts.Black, TextColor3 = C.Accent })
			for _, member in crew.Members do
				local row = Kit.Row(scroll, 36, 8)
				Kit.Label(row, ("%s %s%s"):format(if member.Online then "●" else "○", member.Name, if member.Owner then " (leader)" else ""), 14, { Size = UDim2.new(1, -120, 1, 0), TextColor3 = if member.Online then C.Good else C.Muted })
				if crew.IsOwner and not member.Owner then
					Kit.Button(row, "Remove", function()
						Net.Send("Crew.Kick", member.UserId)
					end, "Ghost", { Size = UDim2.fromOffset(100, 32) })
				end
			end
			-- Invite people in this server.
			local invite = Kit.Card(scroll)
			Kit.Label(invite, "Invite runners in this server", 15, { Font = Kit.Fonts.Bold })
			task.spawn(function()
				local okPlayers, list = pcall(Net.Invoke, "Social.Players")
				if okPlayers and type(list) == "table" then
					for _, entry in list do
						if not entry.You and not entry.Crew then
							local row = Kit.Row(invite, 36, 8)
							Kit.Label(row, ("%s  Lv %d"):format(entry.Name, entry.Level or 1), 14, { Size = UDim2.new(1, -120, 1, 0) })
							Kit.Button(row, "Invite", function()
								Net.Send("Crew.Invite", entry.UserId)
							end, "Secondary", { Size = UDim2.fromOffset(100, 32) })
						end
					end
				end
			end)
			Kit.Button(scroll, "Leave crew", function()
				Net.Send("Crew.Leave")
			end, "Danger", { Size = UDim2.fromOffset(160, 38) })
			return
		end
		-- No crew: create one.
		Kit.Paragraph(scroll, "Crews are small groups of runners who share a tag on their nametags and a weekly crew goal. Create one, or accept an invite from someone in your server.", 14, C.Text)
		local form = Kit.Card(scroll)
		Kit.Label(form, "Found a crew", 16, { Font = Kit.Fonts.Bold })
		local function field(placeholder: string, max: number): TextBox
			local box = Kit.new("TextBox", {
				PlaceholderText = placeholder,
				Text = "",
				ClearTextOnFocus = false,
				BackgroundColor3 = C.Panel,
				TextColor3 = C.Text,
				PlaceholderColor3 = C.Faint,
				Font = Kit.Fonts.Medium,
				Size = UDim2.new(1, 0, 0, 38),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = form,
			})
			Kit.TextSize(box, 15)
			Kit.Corner(box, 8)
			Kit.Padding(box, 0, 10)
			box:GetPropertyChangedSignal("Text"):Connect(function()
				if #box.Text > max then
					box.Text = string.sub(box.Text, 1, max)
				end
			end)
			return box
		end
		local nameBox = field("Crew name (3-24 characters)", 24)
		local tagBox = field("Tag (2-4 letters)", 4)
		local note = Kit.Paragraph(form, "", 13, C.Bad)
		Kit.Button(form, "Create crew", function()
			note.Text = "Creating…"
			task.spawn(function()
				local okCreate, success, info = pcall(Net.Invoke, "Crew.Create", nameBox.Text, tagBox.Text)
				if okCreate and success then
					note.Text = ""
				else
					note.Text = tostring(info or "Couldn't create the crew")
				end
			end)
		end, "Primary", { Size = UDim2.fromOffset(160, 38) })
	end)
end

-- Players --------------------------------------------------------------------------------------------------

local function buildPlayers(container: Frame)
	local scroll = Kit.Scroll(container)
	Kit.List(scroll, false, 8)
	Kit.Padding(scroll, 4)
	local status = Kit.Paragraph(scroll, "Loading…", 13, C.Faint)
	task.spawn(function()
		local ok, list = pcall(Net.Invoke, "Social.Players")
		if not scroll.Parent then
			return
		end
		status.Text = ""
		if not ok or type(list) ~= "table" then
			status.Text = "Couldn't list players."
			return
		end
		table.sort(list, function(a, b)
			if a.Friend ~= b.Friend then
				return a.Friend
			end
			return (a.Level or 0) > (b.Level or 0)
		end)
		for _, entry in list do
			local card = Kit.Panel(scroll, { Size = UDim2.new(1, -8, 0, 70), BackgroundColor3 = C.PanelLight })
			Kit.Padding(card, 8, 12)
			local tag = if entry.Crew then ("[%s] "):format(entry.Crew) else ""
			Kit.Label(card, ("%s%s%s  ·  Lv %d %s"):format(if entry.Friend then "★ " else "", tag, entry.Name, entry.Level or 1, entry.Rank or ""), 16, {
				Font = Kit.Fonts.Bold,
				Size = UDim2.new(1, -250, 0, 24),
				TextColor3 = if entry.You then C.Accent else C.Text,
			})
			Kit.Label(card, ("%s%s · %s"):format(if entry.Title then ("“" .. entry.Title .. "” · ") else "", entry.District or "", entry.Activity or ""), 13, {
				Position = UDim2.fromOffset(0, 26),
				Size = UDim2.new(1, -250, 0, 20),
				TextColor3 = C.Muted,
			})
			if not entry.You then
				local actions = Kit.Row(card, 36, 6)
				actions.AnchorPoint = Vector2.new(1, 0.5)
				actions.Position = UDim2.new(1, 0, 0.5, 0)
				actions.Size = UDim2.fromOffset(240, 36)
				Kit.Button(actions, "Run together", function()
					Net.Send("Social.Invite", entry.UserId, "Join")
				end, "Secondary", { Size = UDim2.fromOffset(130, 32) })
				if Modes.Race then
					Kit.Button(actions, "Race", function()
						Net.Send("Social.Invite", entry.UserId, "Race")
					end, "Secondary", { Size = UDim2.fromOffset(90, 32) })
				end
			end
		end
	end)
end

return {
	Pages = {
		{ Id = "Races", Title = "Races & Relays", Icon = "⚐", Order = 10, Sections = { "Courses" }, Build = buildRaces },
		{ Id = "Crew", Title = "Crew", Icon = "∞", Order = 11, Sections = { "Crew" }, Build = buildCrew },
		{ Id = "Players", Title = "Players", Icon = "☺", Order = 12, Build = buildPlayers },
	},
}
