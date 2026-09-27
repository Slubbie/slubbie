-- The Intake (lobby) at runtime: builds it, keeps the leaderboards and the
-- live-trials wall current, and plays PA broadcasts to subjects in the lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lore = require(ReplicatedStorage.Variance.Data.Lore)
local Format = require(ReplicatedStorage.Variance.Util.Format)

local LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)

local LobbyWorldService = {}

local lobbyModel: Model? = nil
local liveDirty = false
local rng = Random.new()

local BONE = Color3.fromRGB(230, 226, 214)
local AMBER = Color3.fromRGB(232, 163, 61)
local DIM = Color3.fromRGB(140, 144, 140)

function LobbyWorldService:Init(services)
	self.Services = services
end

local function boardGui(name: string): SurfaceGui?
	if lobbyModel == nil then
		return nil
	end
	local part = lobbyModel:FindFirstChild(name, true)
	return part and part:FindFirstChild("Board") :: SurfaceGui?
end

-- Renders a titled list of rows onto a board's SurfaceGui.
local function render(gui: SurfaceGui, title: string, rows: { { string } }, empty: string)
	gui:ClearAllChildren()
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(8, 10, 10)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 24)
	pad.PaddingRight = UDim.new(0, 24)
	pad.PaddingTop = UDim.new(0, 18)
	pad.Parent = frame
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = frame
	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 44)
	header.Font = Enum.Font.Michroma
	header.TextScaled = true
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = AMBER
	header.Text = title
	header.LayoutOrder = 0
	header.Parent = frame
	if #rows == 0 then
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 30)
		label.Font = Enum.Font.Code
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = DIM
		label.Text = empty
		label.LayoutOrder = 1
		label.Parent = frame
		return
	end
	for i, row in rows do
		local line = Instance.new("Frame")
		line.BackgroundTransparency = i % 2 == 0 and 1 or 0.92
		line.BackgroundColor3 = BONE
		line.BorderSizePixel = 0
		line.Size = UDim2.new(1, 0, 0, 30)
		line.LayoutOrder = i
		line.Parent = frame
		local left = Instance.new("TextLabel")
		left.BackgroundTransparency = 1
		left.Size = UDim2.new(0.72, 0, 1, 0)
		left.Font = Enum.Font.Code
		left.TextScaled = true
		left.TextXAlignment = Enum.TextXAlignment.Left
		left.TextColor3 = i <= 3 and AMBER or BONE
		left.Text = row[1]
		left.Parent = line
		local right = Instance.new("TextLabel")
		right.BackgroundTransparency = 1
		right.Position = UDim2.fromScale(0.72, 0)
		right.Size = UDim2.new(0.28, 0, 1, 0)
		right.Font = Enum.Font.Code
		right.TextScaled = true
		right.TextXAlignment = Enum.TextXAlignment.Right
		right.TextColor3 = DIM
		right.Text = row[2] or ""
		right.Parent = line
	end
end

function LobbyWorldService:renderLeaderboard(board: string, entries)
	local name = board == "Standing" and "StandingBoard" or "WinsBoard"
	local gui = boardGui(name)
	if gui == nil then
		return
	end
	local rows = {}
	for i = 1, math.min(12, #entries) do
		local e = entries[i]
		table.insert(rows, { string.format("%02d  %s", e.Rank, string.upper(e.Name)), Format.thousands(e.Value) })
	end
	render(gui, gui:GetAttribute("Title") or board, rows, "NO RECORDS YET")
end

function LobbyWorldService:refreshLive()
	liveDirty = true
end

local function renderLive(self)
	local gui = boardGui("LiveBoard")
	if gui == nil then
		return
	end
	local rows = {}
	for _, entry in self.Services.SpectatorService:list() do
		table.insert(rows, {
			string.format("%s  ::  %s", entry.Mode, table.concat(entry.Names, " vs ")),
			string.format("T%d  %s", math.max(entry.Trial, 1), entry.Score),
		})
		if #rows >= 12 then
			break
		end
	end
	render(gui, "LIVE TRIALS :: PRESS E TO WATCH", rows, "NO TRIALS IN SESSION")
end

function LobbyWorldService:Start()
	-- Replace Studio's template baseplate if the place still has it.
	for _, name in { "Baseplate", "SpawnLocation" } do
		local old = workspace:FindFirstChild(name)
		if old and old:IsA("BasePart") then
			old:Destroy()
		end
	end
	local ok, model = pcall(LobbyBuilder.build)
	if ok then
		lobbyModel = model
		model.Parent = workspace
	else
		warn("[VARIANCE/Lobby] build failed: " .. tostring(model))
	end

	self.Services.LeaderboardService.Updated:Connect(function(board, entries)
		self:renderLeaderboard(board, entries)
	end)
	for _, board in { "Standing", "Wins" } do
		local cached = self.Services.LeaderboardService:get(board)
		self:renderLeaderboard(board, cached and cached.Entries or {})
	end
	renderLive(self)

	task.spawn(function()
		while true do
			task.wait(2)
			if liveDirty then
				liveDirty = false
				renderLive(self)
			end
		end
	end)

	-- Public-address broadcasts for subjects in the lobby.
	task.spawn(function()
		local order = {}
		while true do
			task.wait(rng:NextNumber(50, 95))
			if #order == 0 then
				for i = 1, #Lore.Broadcasts do
					table.insert(order, i)
				end
				for i = #order, 2, -1 do
					local j = rng:NextInteger(1, i)
					order[i], order[j] = order[j], order[i]
				end
			end
			local line = Lore.Broadcasts[table.remove(order)]
			for _, player in Players:GetPlayers() do
				if
					not self.Services.MatchService:isBusy(player) and not self.Services.SpectatorService:matchOf(player)
				then
					self.Services.NetworkService:push(player, "Broadcast", { Text = line })
				end
			end
		end
	end)

	-- Wins leaderboard submissions happen as profiles update.
	self.Services.DataService.Releasing:Connect(function(player, profile)
		self.Services.LeaderboardService:submit("Wins", player.UserId, profile.Data.Stats.Wins or 0)
	end)
end

return LobbyWorldService
