-- Tracks which realm you're in: shows a title banner when you arrive, and
-- switches the lighting and music mood to match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Graphics = require(script.Parent.Graphics)
local Music = require(script.Parent.Music)
local Sounds = require(script.Parent.Sounds)
local UI = require(script.Parent.UI)
local VFX = require(script.Parent.VFX)

local RealmClient = {}
RealmClient.Current = "sky"

function RealmClient.Start(Movement)
	local gui = UI.gui("RealmBanner", 8)
	local banner = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.26),
		Size = UDim2.fromOffset(600, 110),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	local subtitle = UI.label(banner, {
		Size = UDim2.new(1, 0, 0, 22),
		Font = UI.Fonts.Title,
		TextSize = 16,
		TextColor3 = UI.Colors.Muted,
		TextStrokeTransparency = 0.5,
		Text = "NOW ENTERING",
	})
	local title = UI.label(banner, {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 70),
		Font = UI.Fonts.Title,
		TextSize = 64,
		TextStrokeTransparency = 0.3,
		Text = "",
	})
	local token = 0

	local function enter(realmId: string, announce: boolean)
		local realm = Config.GetRealm(realmId)
		if not realm then
			return
		end
		RealmClient.Current = realmId
		Graphics.SetRealm(realmId)
		Music.SetRealm(realmId)
		if not announce then
			return
		end
		token += 1
		local mine = token
		title.Text = string.upper(realm.Name)
		title.TextColor3 = realm.Color
		title.TextTransparency = 0
		subtitle.TextTransparency = 0
		banner.Visible = true
		UI.pop(banner, 0.3)
		Sounds.Play(Config.Sounds.Whoosh, 0.6, 0.7)
		local root = Movement.Info.Root
		if root then
			VFX.Flash(root.Position, realm.Color, 20)
		end
		task.delay(3, function()
			if token == mine then
				UI.tween(title, 0.8, { TextTransparency = 1 })
				UI.tween(subtitle, 0.8, { TextTransparency = 1 })
				task.wait(0.8)
				if token == mine then
					banner.Visible = false
				end
			end
		end)
	end

	Net.Event("Notify").OnClientEvent:Connect(function(kind: string, data)
		if kind == "Locked" then
			UI.toast(string.format("%s unlocks at level %d", data.Name, data.Level), UI.Colors.Bad)
			Sounds.Play(Config.Sounds.Land, 0.4, 0.6)
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.4 then
			return
		end
		elapsed = 0
		local root = Movement.Info.Root
		if not root or not root.Parent then
			return
		end
		local realm = Config.RealmAt(root.Position)
		if realm.Id ~= RealmClient.Current then
			enter(realm.Id, true)
		end
	end)

	Players.LocalPlayer.CharacterAdded:Connect(function(character)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and root:IsA("BasePart") then
			enter(Config.RealmAt(root.Position).Id, false)
		end
	end)
end

return RealmClient
