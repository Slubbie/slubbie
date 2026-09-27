-- Style combos: chain moves without settling on the ground and the combo grows.
-- Stand still too long (or bank on landing) and it's cashed in for shards.
--
-- Bunny hops keep a combo alive, so skilled players can chain forever.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Sounds = require(script.Parent.Sounds)
local UI = require(script.Parent.UI)

local COMBO = Config.Combo

local Combo = {}

function Combo.Start(Movement)
	local bankRemote = Net.Event("BankCombo")

	local gui = UI.gui("Combo", 5)
	local root = UI.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -40, 0.42, 0),
		Size = UDim2.fromOffset(260, 170),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	local countLabel = UI.label(root, {
		Size = UDim2.new(1, 0, 0, 70),
		Font = UI.Fonts.Title,
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UI.Colors.Accent,
		TextStrokeTransparency = 0.5,
		Text = "x0",
	})
	local scoreLabel = UI.label(root, {
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.6,
		Text = "0 STYLE",
	})
	local moveLabel = UI.label(root, {
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, 0, 0, 30),
		Font = UI.Fonts.Title,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UI.Colors.Gold,
		TextStrokeTransparency = 0.5,
		Text = "",
	})
	local barBack = UI.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 132),
		Size = UDim2.fromOffset(160, 6),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.3,
	}, root)
	UI.corner(barBack)
	local bar = UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UI.Colors.Accent,
	}, barBack)
	UI.corner(bar)

	local count, score, groundTime, active = 0, 0, 0, false

	local function reset()
		count, score, groundTime, active = 0, 0, 0, false
		task.delay(0.6, function()
			if not active then
				root.Visible = false
			end
		end)
	end

	local function bank()
		if score >= COMBO.MinScoreToBank then
			bankRemote:FireServer(score)
			moveLabel.Text = "BANKED!"
			moveLabel.TextColor3 = UI.Colors.Good
		else
			moveLabel.Text = ""
		end
		UI.pop(moveLabel, 0.2)
		reset()
	end

	Movement.Action.Event:Connect(function(action: string)
		local points = COMBO.Points[action]
		if not points then
			return
		end
		count += 1
		-- Longer combos are worth more per move.
		score += points * (1 + math.floor(count / 5) * 0.5)
		groundTime = 0
		active = true
		root.Visible = true
		countLabel.Text = "x" .. count
		scoreLabel.Text = math.floor(score) .. " STYLE"
		moveLabel.Text = COMBO.Names[action] or action
		moveLabel.TextColor3 = UI.Colors.Gold
		countLabel.TextColor3 = if count >= 15
			then UI.Colors.Hot
			elseif count >= 7 then UI.Colors.Gold
			else UI.Colors.Accent
		UI.pop(countLabel, 0.35)
		UI.pop(moveLabel, 0.2)
	end)

	bankRemote.OnClientEvent:Connect(function(reward: number)
		UI.toast("+" .. reward .. " ◆  COMBO BANKED", UI.Colors.Gold)
		for i = 0, 2 do
			task.delay(i * 0.08, function()
				Sounds.Play(Config.Sounds.Ping, 0.4, 1.5 + i * 0.25)
			end)
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		if not active then
			return
		end
		local info = Movement.Info
		local humanoid = info.Humanoid
		if not humanoid or humanoid.Health <= 0 then
			moveLabel.Text = "DROPPED"
			moveLabel.TextColor3 = UI.Colors.Bad
			reset()
			return
		end
		if info.State == "Ground" then
			groundTime += dt
			if groundTime > COMBO.GroundGrace then
				bank()
				return
			end
		else
			groundTime = 0
		end
		bar.Size = UDim2.fromScale(1 - groundTime / COMBO.GroundGrace, 1)
	end)
end

return Combo
