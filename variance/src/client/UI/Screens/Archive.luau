-- THE ARCHIVE: Halden's records, unlocked by play and read on a typewriter
-- terminal. Locked files show their reference and a hint of how to earn
-- clearance; some bodies are personalised with your own history.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lore = require(ReplicatedStorage.Variance.Data.Lore)
local Kit = require(script.Parent.Parent.Kit)
local Window = require(script.Parent.Parent.Window)

local Archive = {}
Archive.__index = Archive

local HINTS = {
	Default = "Standard issue.",
	Level = "Requires clearance level %s.",
	Matches = "Complete %s Trials.",
	Defeat = "Defeat %s.",
	Environment = "Win a Trial in a particular room.",
	Achievement = "Tied to an achievement.",
	Witness = "Witness something rare during a Trial.",
	Proctor = "Clearance withheld.",
}

function Archive.new(ui, controllers)
	local self = setmetatable({}, Archive)
	self.UI = ui
	self.C = controllers
	self.Main = true
	self.Window = Window.new(ui, { Name = "Archive", Title = "THE ARCHIVE", Subtitle = "HALDEN DECISION SCIENCES  ·  RECORDS DIVISION", Width = 1000, Height = 640 })
	self.Frame = self.Window.Frame
	controllers.ProfileController.Changed:Connect(function()
		if self.Window.Visible then
			self:renderList()
		end
	end)
	return self
end

function Archive:renderList()
	local profile = self.C.ProfileController:get()
	local unlocked = profile and profile.Lore and profile.Lore.Unlocked or {}
	local read = profile and profile.Lore and profile.Lore.Read or {}
	local list = self.List
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local total, have = 0, 0
	for i, file in Lore.Files do
		total += 1
		local open = unlocked[file.Id] == true
		if open then
			have += 1
		end
		local label = if open then string.format("%s  %s%s", file.Id, file.Title, if read[file.Id] then "" else "  •") else file.Id .. "  ████████"
		local hint = HINTS[file.Unlock.Kind] or ""
		if string.find(hint, "%%s") then
			hint = string.format(hint, tostring(file.Unlock.Value))
		end
		local b = Kit.button(list, {
			Text = label,
			Size = UDim2.new(1, -8, 0, 34),
			LayoutOrder = i,
			Style = if open then "Default" else "Ghost",
			TextSize = "Tiny",
			Tooltip = if open then file.Class .. "  ·  " .. file.Date else "LOCKED  ·  " .. hint,
			OnClick = function()
				if open then
					self:openFile(file.Id)
				else
					Kit.sound("Deny")
				end
			end,
		})
		local text = b:FindFirstChild("Text") :: TextLabel?
		if text then
			text.TextXAlignment = Enum.TextXAlignment.Left
			text.Position = UDim2.fromOffset(10, 0)
			text.Size = UDim2.new(1, -20, 1, 0)
		end
	end
	self.Window:setSubtitle(string.format("RECORDS DIVISION  ·  %d / %d FILES DECLASSIFIED", have, total))
end

function Archive:openFile(id: string)
	local reader = self.Reader
	for _, child in reader:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local status = Kit.label(reader, { Text = "RETRIEVING " .. id .. "...", Font = "Type", TextSize = "Body", Color = "Dim", Size = UDim2.new(1, 0, 0, 24) })
	task.spawn(function()
		local ok, file = self.C.NetworkClient:request("Lore.Read", id)
		if not ok or type(file) ~= "table" then
			status.Text = tostring(file or "RETRIEVAL FAILED")
			return
		end
		status:Destroy()
		local scroll = Kit.scroll(reader, { Padding = 6 })
		Kit.label(scroll, { Text = string.format("%s  ·  %s", file.Id, file.Class or ""), Font = "Mono", TextSize = "Tiny", Color = "Accent", LayoutOrder = 1 })
		Kit.label(scroll, { Text = file.Title, Font = "Type", TextSize = "Title", Wrap = true, AutoY = true, LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 0) })
		Kit.label(scroll, { Text = string.format("%s  ·  %s", file.Date or "", file.Author or ""), Font = "Mono", TextSize = "Tiny", Color = "Dim", LayoutOrder = 3 })
		Kit.divider(scroll, 4)
		local body = Kit.label(scroll, { Text = "", Font = "Type", TextSize = "Body", Wrap = true, AutoY = true, YAlign = "Top", LayoutOrder = 5, Size = UDim2.new(1, -8, 0, 0) })
		-- Typewriter reveal (skippable by reopening).
		local text = file.Body or ""
		local reduced = self.C.SettingsController:get("ReducedMotion")
		if reduced then
			body.Text = text
			return
		end
		local token = os.clock()
		self.TypeToken = token
		local shown = 0
		while shown < #text and self.TypeToken == token and body.Parent do
			shown = math.min(#text, shown + 6)
			body.Text = string.sub(text, 1, shown)
			if shown % 60 < 6 then
				self.C.AudioController:play("Tick", { Volume = 0.5 })
			end
			task.wait(0.016)
		end
		if body.Parent then
			body.Text = text
		end
	end)
end

function Archive:Open()
	self.Window:open()
	local body = self.Window.Body
	Window.clear(body)
	local listHolder = Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.38, -8, 1, 0), Parent = body }) :: Frame
	self.List = Kit.scroll(listHolder, { Padding = 4 })
	local reader = Kit.panel(body, { Size = UDim2.new(0.62, -8, 1, 0), Position = UDim2.new(0.38, 8, 0, 0), Color = "Bg" })
	Kit.padding(reader, 16, 20)
	self.Reader = reader
	Kit.label(reader, { Text = "Select a declassified file.", Font = "Type", TextSize = "Body", Color = "Dim", Size = UDim2.new(1, 0, 0, 24) })
	self:renderList()
end

function Archive:Close()
	self.TypeToken = nil
	self.Window:close()
end

return Archive
