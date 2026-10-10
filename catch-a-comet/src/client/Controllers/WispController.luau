-- Stardust Wisps on the client. Wisps are only visible within your scanner's
-- radius (a bigger scanner reveals them from farther away). Walking close
-- asks the server to collect one; the server checks distance and timers.
-- At Scanner level 5 nearby wisps drift toward you (Wisp Magnet).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local UITheme = require(Shared.UITheme)
local UpgradeDefinitions = require(Shared.UpgradeDefinitions)

local WispController = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

type Wisp = { Id: string, Position: Vector3, Biome: string, Part: BasePart?, Pending: boolean }

local controllers: { [string]: any } = {}
local wisps: { [string]: Wisp } = {}
local availableAt: { [string]: number } = {}
local folder: Folder

local function scannerLevel(): number
	return controllers.ClientState.Equipment().ScannerLevel or 1
end

local function makePart(wisp: Wisp): BasePart
	local part = Instance.new("Part")
	part.Name = "Wisp"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.1, 1.1, 1.1)
	part.Material = Enum.Material.Neon
	part.Color = UITheme.Colors.Gold
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 0.2
	part.Position = wisp.Position
	local glow = Instance.new("ParticleEmitter")
	glow.Texture = SPARKLE
	glow.LightEmission = 1
	glow.Color = ColorSequence.new(UITheme.Colors.Gold, UITheme.Colors.Cyan)
	glow.Rate = 6 * controllers.SettingsController.Quality().Particles
	glow.Lifetime = NumberRange.new(0.8, 1.4)
	glow.Speed = NumberRange.new(0.5, 1.2)
	glow.SpreadAngle = Vector2.new(180, 180)
	glow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	glow.Parent = part
	local light = Instance.new("PointLight")
	light.Color = UITheme.Colors.Gold
	light.Range = 8
	light.Brightness = 0.8
	light.Parent = part
	part.Parent = folder
	return part
end

local function hide(wisp: Wisp)
	if wisp.Part then
		wisp.Part:Destroy()
		wisp.Part = nil
	end
end

local function collect(wisp: Wisp)
	if wisp.Pending then
		return
	end
	wisp.Pending = true
	task.spawn(function()
		local ok, result = pcall(function()
			return RemoteDefinitions.GetFunction("CollectWisp"):InvokeServer(wisp.Id)
		end)
		wisp.Pending = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.AvailableAt then
			availableAt[wisp.Id] = result.AvailableAt
		end
		if result.Ok then
			local position = if wisp.Part then wisp.Part.CFrame.Position else wisp.Position
			hide(wisp)
			controllers.EffectsController.Burst(position, UITheme.Colors.Gold, 14, "Stars")
			controllers.EffectsController.FloatingText(
				position + Vector3.new(0, 1.5, 0),
				`+{result.Stardust} ✦`,
				UITheme.Colors.Gold
			)
			controllers.AudioController.Play("Wisp", { Pitch = 2.4 + math.random() * 0.4 })
		end
	end)
end

local function step()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local here = root.Position
	local level = scannerLevel()
	local radius = UpgradeDefinitions.ScannerRadius(level)
	local magnet = UpgradeDefinitions.HasFeature("Scanner", level, "WispMagnet")
	local pickup = if magnet then GameConfig.Wisps.MagnetRadius else GameConfig.Wisps.PickupRadius
	local now = workspace:GetServerTimeNow()
	local t = os.clock()
	for _, wisp in wisps do
		local distance = (wisp.Position - here).Magnitude
		local available = (availableAt[wisp.Id] or 0) <= now
		if not available or distance > radius then
			hide(wisp)
			continue
		end
		local part = wisp.Part
		if not part then
			part = makePart(wisp)
			wisp.Part = part
		end
		assert(part)
		local bob = Vector3.new(0, math.sin(t * 2 + wisp.Position.X) * 0.4, 0)
		local fade = math.clamp((radius - distance) / 6, 0, 1)
		part.Transparency = 1 - 0.8 * fade
		if magnet and distance < pickup then
			-- Drift toward the player.
			local pull = math.clamp(1 - distance / pickup, 0, 1) * 0.6
			part.Position = wisp.Position:Lerp(here, pull) + bob
		else
			part.Position = wisp.Position + bob
		end
		if distance <= pickup then
			collect(wisp)
		end
	end
end

function WispController.Init(registry: { [string]: any })
	controllers = registry
	folder = Instance.new("Folder")
	folder.Name = "Wisps"
	folder.Parent = workspace
end

function WispController.Start()
	local data = controllers.ClientState.InitialWisps
	if data then
		for _, entry in data.List or {} do
			wisps[entry.Id] =
				{ Id = entry.Id, Position = entry.Position, Biome = entry.Biome, Part = nil, Pending = false }
		end
		for id, at in data.AvailableAt or {} do
			availableAt[id] = at
		end
	end
	local clock = 0
	RunService.Heartbeat:Connect(function(dt)
		clock += dt
		if clock >= 0.1 then
			clock = 0
			step()
		end
	end)
end

return WispController
