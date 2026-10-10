-- The living world, client-side: the observatory's turning rings, bobbing
-- crystals, swaying banners, meteor streaks across the sky, wild creatures
-- wandering Dawn Commons, and noticing when you enter a new area (title card
-- and ambience change). Purely cosmetic.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeDefinitions = require(Shared.BiomeDefinitions)
local CreatureRig = require(Shared.CreatureRig)
local UITheme = require(Shared.UITheme)
local WorldLayout = require(Shared.WorldLayout)

local AmbientController = {}

type Animated = { Model: Model, Root: BasePart, Base: CFrame, Kind: string, Phase: number }

local controllers: { [string]: any } = {}
local animated: { [Model]: Animated } = {}
local folder: Folder
local currentArea = ""

-- Wild creatures that wander the meadow.
local WILD_SPECIES = { "Pebblepuff", "Nebble", "Crumbtail", "Pebblepuff", "Nebble", "CometFox" }
local MEADOW = Vector3.new(640, WorldLayout.GroundY, 0)
type Wanderer = { Model: Model, Position: Vector3, Target: Vector3, Wait: number, Speed: number }
local wanderers: { Wanderer } = {}

local function register(model: Instance, kind: string)
	if not model:IsA("Model") or animated[model] then
		return
	end
	local root = model.PrimaryPart
	if not root then
		return
	end
	animated[model] = { Model = model, Root = root, Base = root.CFrame, Kind = kind, Phase = math.random() * 10 }
end

local function axis(name: any, angle: number): CFrame
	if name == "X" then
		return CFrame.Angles(angle, 0, 0)
	elseif name == "Z" then
		return CFrame.Angles(0, 0, angle)
	end
	return CFrame.Angles(0, angle, 0)
end

local function animateWorld(t: number, eye: Vector3)
	for model, entry in animated do
		if not model.Parent or not entry.Root.Parent then
			animated[model] = nil
			continue
		end
		if (entry.Base.Position - eye).Magnitude > 900 and entry.Kind ~= "Spinner" then
			continue
		end
		if entry.Kind == "Spinner" then
			local speed = (model:GetAttribute("SpinSpeed") :: number?) or 0.2
			entry.Root.CFrame = entry.Base * axis(model:GetAttribute("SpinAxis"), t * speed)
		elseif entry.Kind == "Bobber" then
			local amount = (model:GetAttribute("BobAmount") :: number?) or 1
			local speed = (model:GetAttribute("BobSpeed") :: number?) or 1
			local spin = (model:GetAttribute("SpinSpeed") :: number?) or 0
			entry.Root.CFrame = entry.Base
				* CFrame.new(0, math.sin(t * speed + entry.Phase) * amount, 0)
				* CFrame.Angles(0, t * spin, 0)
		elseif entry.Kind == "Sway" then
			local amount = math.rad((model:GetAttribute("SwayAmount") :: number?) or 5)
			local speed = (model:GetAttribute("SwaySpeed") :: number?) or 1
			entry.Root.CFrame = entry.Base
				* CFrame.Angles(math.sin(t * speed + entry.Phase) * amount, 0, math.sin(t * speed * 0.7) * amount * 0.3)
		end
	end
end

-- A distant meteor streak across the sky.
local function skyMeteor()
	local camera = Workspace.CurrentCamera
	local center = camera.CFrame.Position
	local a = math.random() * math.pi * 2
	local from = center + Vector3.new(math.cos(a) * 900, 450 + math.random() * 300, math.sin(a) * 900)
	local to = from + Vector3.new(math.cos(a + 2.2) * 900, -260, math.sin(a + 2.2) * 900)
	local colors = { UITheme.Colors.Gold, UITheme.Colors.Cyan, UITheme.Colors.Lavender, UITheme.Colors.Coral }
	local color = colors[math.random(1, #colors)]
	local streak = Instance.new("Part")
	streak.Name = "SkyMeteor"
	streak.Anchored = true
	streak.CanCollide = false
	streak.CanQuery = false
	streak.CanTouch = false
	streak.CastShadow = false
	streak.Shape = Enum.PartType.Ball
	streak.Material = Enum.Material.Neon
	streak.Color = color
	streak.Size = Vector3.new(5, 5, 5)
	streak.Position = from
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 2.5, 0)
	a0.Parent = streak
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -2.5, 0)
	a1.Parent = streak
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.9
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = streak
	streak.Parent = folder
	local tween = TweenService:Create(streak, TweenInfo.new(1.6, Enum.EasingStyle.Linear), { Position = to })
	tween:Play()
	tween.Completed:Once(function()
		task.delay(1, function()
			streak:Destroy()
		end)
	end)
end

local function groundAt(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local hit = Workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	return if hit then hit.Position else position
end

local function randomMeadowPoint(): Vector3
	local a = math.random() * math.pi * 2
	local d = math.sqrt(math.random()) * 110
	return groundAt(MEADOW + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d))
end

local function updateWanderers(dt: number, here: Vector3?)
	local near = here ~= nil and (Vector3.new(here.X, 0, here.Z) - Vector3.new(MEADOW.X, 0, MEADOW.Z)).Magnitude < 420
	if not near then
		for _, wanderer in wanderers do
			controllers.CreatureAnimator.Untrack(wanderer.Model)
			wanderer.Model:Destroy()
		end
		wanderers = {}
		return
	end
	if #wanderers == 0 then
		for _, speciesId in WILD_SPECIES do
			local model = CreatureRig.Build(speciesId, { NoEffects = true })
			CreatureRig.ScaleTo(model, 0.8)
			local start = randomMeadowPoint()
			CreatureRig.Place(model, CFrame.new(start))
			model.Parent = folder
			controllers.CreatureAnimator.Track(model, CFrame.new(start))
			table.insert(wanderers, {
				Model = model,
				Position = start,
				Target = start,
				Wait = math.random() * 3,
				Speed = 3 + math.random() * 2,
			})
		end
	end
	for _, wanderer in wanderers do
		if wanderer.Wait > 0 then
			wanderer.Wait -= dt
			if wanderer.Wait <= 0 then
				wanderer.Target = randomMeadowPoint()
			end
			continue
		end
		local delta = wanderer.Target - wanderer.Position
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude < 1 then
			wanderer.Wait = 2 + math.random() * 5
			continue
		end
		local stepSize = math.min(flat.Magnitude, wanderer.Speed * dt)
		wanderer.Position += flat.Unit * stepSize
		wanderer.Position = Vector3.new(wanderer.Position.X, wanderer.Target.Y, wanderer.Position.Z)
		local facing = CFrame.lookAt(wanderer.Position, wanderer.Position + flat.Unit)
		controllers.CreatureAnimator.SetBase(wanderer.Model, facing)
	end
end

local function areaChanged(area: any)
	local id = area.Id
	if area.Kind == "Biome" then
		local biome = BiomeDefinitions.Get(id)
		if biome then
			controllers.NotificationController.Banner(biome.DisplayName, biome.Tagline, biome.Color, 1)
		end
	elseif area.Kind == "Hub" and currentArea ~= "" then
		controllers.NotificationController.Banner(
			"Celestial Crossing",
			"The heart of the floating isles",
			UITheme.Colors.Lavender,
			1
		)
	elseif area.Kind == "Sanctuary" and area.PlotIndex == controllers.ClientState.GetSession("PlotIndex") then
		controllers.NotificationController.Banner("Your Sanctuary", "Welcome home", UITheme.Colors.Green, 1)
	end
	controllers.AudioController.SetArea(if area.Kind == "Sanctuary" then "Sanctuary" else id)
end

function AmbientController.Init(registry: { [string]: any })
	controllers = registry
	folder = Instance.new("Folder")
	folder.Name = "Ambient"
	folder.Parent = workspace
end

function AmbientController.Start()
	for _, kind in { "Spinner", "Bobber", "Sway" } do
		for _, model in CollectionService:GetTagged(kind) do
			register(model, kind)
		end
		CollectionService:GetInstanceAddedSignal(kind):Connect(function(model)
			register(model, kind)
		end)
	end
	RunService.RenderStepped:Connect(function()
		animateWorld(os.clock(), Workspace.CurrentCamera.CFrame.Position)
	end)

	local areaClock, meteorClock = 0, 4
	RunService.Heartbeat:Connect(function(dt)
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local here = if root and root:IsA("BasePart") then root.Position else nil
		updateWanderers(dt, here)
		areaClock += dt
		if areaClock > 0.5 and here then
			areaClock = 0
			local area = WorldLayout.GetArea(here)
			local key = area.Kind .. ":" .. area.Id .. ":" .. tostring(area.PlotIndex)
			if key ~= currentArea and area.Kind ~= "Wilds" then
				areaChanged(area)
				currentArea = key
			end
		end
		meteorClock -= dt
		if meteorClock <= 0 then
			local quality = controllers.SettingsController.QualityName()
			meteorClock = if quality == "Low" then 16 + math.random() * 10 else 6 + math.random() * 7
			skyMeteor()
		end
	end)
end

return AmbientController
