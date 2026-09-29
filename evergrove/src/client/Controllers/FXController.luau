-- World feedback. The server sends FX events (Net "FX" channel) with a kind and
-- payload; this turns them into floating text, particles, sounds, camera
-- shake and small animations. Everything respects Particle Density, Reduce
-- Motion and Reduce Flashing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Format = require(Shared.Lib.Format)

local C = require(script.Parent)

local FX = {}

local player = Players.LocalPlayer
local folder: Folder
local random = Random.new()

-- Helpers -----------------------------------------------------------------------------------------------------------

local function density(): number
	return C.Settings.Get("Particles") or 1
end

local function anchorAt(position: Vector3, life: number): Attachment
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	task.delay(life, function()
		att:Destroy()
	end)
	return att
end

-- Burst of particles at a point.
function FX.Burst(position: Vector3, color: Color3, count: number, kind: string?, speed: number?)
	local n = math.floor(count * density())
	if n <= 0 then
		return
	end
	local att = anchorAt(position, 3)
	local e = Instance.new("ParticleEmitter")
	e.Texture = if kind == "Smoke"
		then "rbxasset://textures/particles/smoke_main.dds"
		else "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = if kind == "Smoke" then 0 else 0.7
	e.Size = if kind == "Smoke"
		then NumberSequence.new(1.2, 3)
		else NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(if kind == "Smoke" then 0.4 else 0, 1)
	e.Speed = NumberRange.new((speed or 8) * 0.5, speed or 8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Acceleration = if kind == "Smoke" then Vector3.new(0, 2, 0) else Vector3.new(0, -12, 0)
	e.Rate = 0
	e.Parent = att
	e:Emit(n)
end

-- Rising text above a point.
function FX.Text(position: Vector3, text: string, color: Color3?, size: number?, duration: number?)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = position + Vector3.new(random:NextNumber(-0.6, 0.6), 2.5, random:NextNumber(-0.6, 0.6))
	part.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 44)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = size or 26
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	local d = duration or 1.4
	TweenService:Create(
		part,
		TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = part.Position + Vector3.new(0, 3, 0) }
	):Play()
	TweenService:Create(
		label,
		TweenInfo.new(d * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, d * 0.5),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	task.delay(d + 0.1, function()
		part:Destroy()
	end)
end

function FX.ScreenFlash(color: Color3)
	local reduced = C.Settings.Get("ReducedFlashing") == true
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(2, 2)
	frame.Position = UDim2.fromScale(-0.5, -0.5)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = if reduced then 0.85 else 0.45
	frame.BorderSizePixel = 0
	frame.ZIndex = 100
	frame.Parent = C.UI.Layer("Overlay")
	TweenService:Create(frame, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	task.delay(0.9, function()
		frame:Destroy()
	end)
end

function FX.LevelUpBurst()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		FX.Burst(root.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 220, 120), 50, nil, 14)
		FX.Burst(root.Position, Color3.fromRGB(150, 230, 150), 30, nil, 8)
	end
end

local function qualityColor(tier: number?): Color3
	return C.UI.Theme.QualityColor(tier)
end

-- Shake a model briefly (node hits).
local function jiggle(model: Model)
	if C.Settings.Get("ReducedMotion") then
		return
	end
	local pivot = model:GetPivot()
	task.spawn(function()
		for i = 1, 6 do
			local a = (if i % 2 == 0 then 1 else -1) * (0.04 - i * 0.006)
			model:PivotTo(pivot * CFrame.Angles(a, 0, a))
			task.wait(0.03)
		end
		model:PivotTo(pivot)
	end)
end

local function findNode(nid: string): Model?
	local nodes = workspace:FindFirstChild("ResourceNodes")
	local model = nodes and nodes:FindFirstChild(nid, true)
	if not model then
		local farms = workspace:FindFirstChild("Farms")
		model = farms and farms:FindFirstChild(nid, true)
	end
	return if model and model:IsA("Model") then model else nil
end

-- Drones fly from their hub to targets and back.
local function drones(from: Vector3, targets: { Vector3 })
	for i, target in targets do
		task.delay(i * 0.15, function()
			local drone = Instance.new("Part")
			drone.Anchored = true
			drone.CanCollide = false
			drone.CanQuery = false
			drone.Size = Vector3.new(1.2, 0.35, 1.2)
			drone.Color = Color3.fromRGB(220, 225, 235)
			drone.Material = Enum.Material.Metal
			drone.Parent = folder
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(120, 220, 255)
			light.Range = 6
			light.Parent = drone
			local up = from + Vector3.new(0, 10, 0)
			drone.Position = from + Vector3.new(0, 3, 0)
			local t1 = TweenService:Create(
				drone,
				TweenInfo.new(0.8, Enum.EasingStyle.Sine),
				{ Position = target + Vector3.new(0, 4, 0) }
			)
			t1:Play()
			t1.Completed:Wait()
			FX.Burst(target + Vector3.new(0, 1, 0), Color3.fromRGB(180, 240, 140), 6)
			local t2 = TweenService:Create(drone, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Position = up })
			t2:Play()
			t2.Completed:Wait()
			drone:Destroy()
		end)
	end
end

-- Lightning bolt from the sky.
local function bolt(position: Vector3, rod: boolean?)
	local top = position + Vector3.new(random:NextNumber(-20, 20), 180, random:NextNumber(-20, 20))
	local points = { top }
	for i = 1, 7 do
		local t = i / 8
		table.insert(points, top:Lerp(position, t) + Vector3.new(random:NextNumber(-6, 6), 0, random:NextNumber(-6, 6)))
	end
	table.insert(points, position)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local seg = Instance.new("Part")
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.Material = Enum.Material.Neon
		seg.Color = if rod then Color3.fromRGB(255, 240, 150) else Color3.fromRGB(200, 220, 255)
		seg.Size = Vector3.new(0.5, 0.5, (b - a).Magnitude)
		seg.CFrame = CFrame.lookAt((a + b) / 2, b)
		seg.Parent = folder
		task.delay(0.25, function()
			seg:Destroy()
		end)
	end
	FX.Burst(position, Color3.fromRGB(255, 250, 200), 30, nil, 16)
	C.Lighting.Lightning(position)
end

-- Handlers ---------------------------------------------------------------------------------------------------------

local handlers: { [string]: (any) -> () } = {}

handlers.ToolResult = function(p)
	if p.Ok == 0 and p.Reason then
		C.HUD.Hint(p.Reason)
		C.Audio.PlayUI("UIError")
	end
end

handlers.HarvestChain = function(p)
	if (p.Count or 0) > 1 then
		C.HUD.Hint("🧺 Harvested " .. p.Count .. " crops")
	end
end

handlers.Harvest = function(p)
	local crop = Registry.Crops[p.Crop]
	local pos = p.Position
	local rare = p.Rare == true
	local text = "+" .. (p.Count or 1) .. " " .. (if crop then crop.Icon else "")
	local tier = C.UI.Theme.QualityTier(p.Q)
	if tier.Stars > 0 then
		text ..= " " .. tier.Glyph
	end
	FX.Text(pos, text, qualityColor(p.Q), if rare then 32 else 24)
	if p.M and #p.M > 0 then
		local names = {}
		for _, id in p.M do
			local def = ItemUtil.MutationDef(id)
			table.insert(names, (def and def.Icon or "✨") .. " " .. (def and def.Name or id))
		end
		task.delay(0.25, function()
			FX.Text(pos + Vector3.new(0, 1, 0), table.concat(names, "  "), Color3.fromRGB(200, 170, 255), 22, 2)
		end)
	end
	if p.Premium then
		task.delay(0.4, function()
			FX.Text(pos + Vector3.new(0, 2, 0), "Premium!", Color3.fromRGB(255, 215, 90), 22)
		end)
	end
	FX.Burst(
		pos + Vector3.new(0, 1, 0),
		if crop then crop.Visual.Fruit else Color3.new(1, 1, 1),
		if rare then 40 else 12
	)
	C.Audio.PlayAt(if rare then "HarvestRare" else "Harvest", pos)
	C.Audio.PlayAt("HarvestPop", pos)
	if rare and p.By == player.UserId then
		C.Camera.Shake(0.15, 0.3)
	end
end

handlers.Mutation = function(p)
	local def = ItemUtil.MutationDef(p.Id)
	FX.Text(
		p.Position,
		(def and def.Icon or "✨") .. " " .. (def and def.Name or p.Id) .. "!",
		Color3.fromRGB(210, 180, 255),
		26,
		2.2
	)
	FX.Burst(p.Position + Vector3.new(0, 1.5, 0), Color3.fromRGB(210, 180, 255), 30, nil, 10)
	C.Audio.PlayAt("HarvestRare", p.Position)
end

handlers.Combo = function(p)
	local def = ItemUtil.MutationDef(p.Id)
	FX.Text(p.Position, "🌟 " .. (def and def.Name or p.Id) .. " combo!", Color3.fromRGB(255, 220, 120), 34, 3)
	FX.Burst(p.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 220, 120), 80, nil, 18)
	C.Audio.PlayAt("HarvestRare", p.Position, 0.8)
	C.Camera.Shake(0.2, 0.4)
end

handlers.Affliction = function(p)
	FX.Text(p.Position, if p.Id == "Pests" then "🐛 Pests!" else "🍂 Blight!", Color3.fromRGB(230, 140, 90), 24, 2)
end

for _, hazard in { "Hail", "Scorch", "Frost", "Flood", "Wind", "Meteor" } do
	handlers[hazard] = function(p)
		FX.Burst(p.Position + Vector3.new(0, 1, 0), Color3.fromRGB(220, 230, 255), 16, "Smoke", 6)
		FX.Text(p.Position, hazard .. "!", Color3.fromRGB(230, 200, 160), 20)
		if hazard == "Meteor" then
			C.Audio.PlayAt("RockBreak", p.Position)
			C.Camera.Shake(0.3, 0.5)
			FX.Burst(p.Position, Color3.fromRGB(255, 180, 90), 60, nil, 20)
		end
	end
end

handlers.Lightning = function(p)
	bolt(p.Position, p.Rod)
end

handlers.Offline = function(p)
	local lines = { "You were away for " .. Format.Duration(p.Seconds or 0) .. "." }
	if (p.Ripened or 0) > 0 then
		table.insert(lines, "🌾 " .. p.Ripened .. " crops ripened.")
	end
	if p.Mutations and #p.Mutations > 0 then
		table.insert(lines, "✨ " .. #p.Mutations .. " new mutations appeared!")
	end
	if (p.Afflicted or 0) > 0 then
		table.insert(lines, "🐛 " .. p.Afflicted .. " crops need care.")
	end
	C.Notify.Banner("Welcome back!", table.concat(lines, "  "), "🏡", "Default", 6)
end

handlers.DailyAvailable = function(p)
	C.HUD.SetBadge("Daily", true)
	C.Notify.Toast("🎁 Your daily gift (day " .. (p.Index or 1) .. ") is ready!", "Success")
end

handlers.Eat = function(p)
	local def = Registry.Items[p.Id]
	C.Notify.Toast((def and def.Icon or "🍽️") .. " +" .. (p.Energy or 0) .. " energy", "Success")
	C.Audio.PlayUI("Eat")
end

handlers.Open = function(p)
	local names = {}
	for _, stack in p.Items or {} do
		local def = Registry.Items[stack.Id]
		table.insert(
			names,
			(def and def.Icon or "") .. " " .. (stack.N or 1) .. "× " .. (def and def.Name or stack.Id)
		)
	end
	local container = Registry.Items[p.Id]
	C.Notify.Banner(
		(container and container.Icon or "🎁") .. " Opened " .. (container and container.Name or "it") .. "!",
		table.concat(names, "   "),
		nil,
		"Discovery",
		4
	)
end

handlers.LevelUp = function(p)
	FX.Text(p.Position, "⬆ Level " .. (p.Level or "?"), Color3.fromRGB(255, 220, 120), 28, 2)
	FX.Burst(p.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 220, 120), 40, nil, 12)
end

handlers.Lore = function(p)
	C.Windows.Open("Lore", { Id = p.Id, Title = p.Title, Text = p.Text })
end

handlers.Animal = function(p)
	local pos = C.Animals.Position(p.Aid) or p.Position
	local icon = ({ Hearts = "💕", Sparkle = "✨", Munch = "😋", Collect = "🧺" })[p.Kind] or "💕"
	FX.Text(pos, icon, nil, 30)
	if p.Kind == "Hearts" then
		FX.Burst(pos + Vector3.new(0, 1.5, 0), Color3.fromRGB(255, 130, 170), 10, nil, 5)
		C.Audio.PlayAt("Pet", pos)
	end
	if p.Sound then
		C.Audio.PlayAt(p.Sound, pos)
	end
end

handlers.Build = function(p)
	FX.Burst(p.Position, Color3.fromRGB(210, 190, 150), 20, "Smoke", 5)
	C.Audio.PlayAt("Place", p.Position)
end

handlers.Unbuild = function(p)
	FX.Burst(p.Position, Color3.fromRGB(210, 190, 150), 14, "Smoke", 5)
	C.Audio.PlayAt("Remove", p.Position)
end

handlers.MachineLoad = function(p)
	C.Audio.PlayAt("MachineStart", p.Position)
	FX.Burst(p.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 240, 200), 8)
end

handlers.NodeHit = function(p)
	local model = findNode(p.Nid)
	if model then
		jiggle(model)
	end
	local color = if p.Kind == "Tree" then Color3.fromRGB(170, 130, 80) else Color3.fromRGB(170, 170, 165)
	FX.Burst(p.Position + Vector3.new(0, 2, 0), color, if p.Crit then 18 else 8, nil, 10)
	C.Audio.PlayAt(if p.Kind == "Tree" then "Chop" else "Mine", p.Position)
	if p.Crit then
		FX.Text(p.Position, "Crit!", Color3.fromRGB(255, 200, 80), 22, 0.9)
	end
	if p.By == player.UserId then
		C.HUD.NodeHealth(p.Nid, p.HP, p.Max)
	end
end

handlers.NodeBreak = function(p)
	FX.Burst(p.Position + Vector3.new(0, 2, 0), Color3.fromRGB(200, 180, 140), 30, "Smoke", 6)
	C.Audio.PlayAt(if p.Kind == "Tree" then "TreeFall" else "RockBreak", p.Position)
	C.Camera.Shake(0.12, 0.3)
end

handlers.NodeRespawn = function(p)
	FX.Burst(p.Position + Vector3.new(0, 1, 0), Color3.fromRGB(180, 230, 150), 12, nil, 4)
end

handlers.Forage = function(p)
	FX.Burst(p.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 240, 180), 10)
	C.Audio.PlayAt("Plant", p.Position)
end

handlers.BugCatch = function(p)
	C.Gather.BugGone(p.Spot)
	FX.Burst(p.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 240, 180), 14)
	C.Audio.PlayAt("NetSwing", p.Position)
end

handlers.BugFlee = function(p)
	if p.By == player.UserId then
		C.Gather.BugGone(p.Spot)
		FX.Text(p.Position, "💨", nil, 26)
	end
end

handlers.Dig = function(p)
	FX.Burst(p.Position, Color3.fromRGB(130, 95, 65), 22, "Smoke", 6)
	C.Audio.PlayAt("Dig", p.Position)
end

handlers.Catch = function(p)
	FX.Burst(p.Position, Color3.fromRGB(170, 210, 255), 30, nil, 12)
	C.Audio.PlayAt("FishCaught", p.Position)
	local def = Registry.Items[p.Item]
	FX.Text(
		p.Position,
		(def and def.Icon or "🐟")
			.. " "
			.. (def and def.Name or "")
			.. (if p.Size then string.format("  %.1f cm", p.Size) else ""),
		qualityColor(p.Q),
		if p.Legend then 34 else 24,
		2.4
	)
	if p.Legend then
		FX.ScreenFlash(Color3.fromRGB(255, 210, 120))
	end
end

handlers.FishEscape = function(p)
	FX.Burst(p.Position, Color3.fromRGB(170, 210, 255), 12, nil, 8)
end

handlers.FestivalFind = function(p)
	FX.Burst(p.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 230, 150), 24, nil, 10)
	C.Audio.PlayAt("HarvestPop", p.Position)
end

handlers.Secret = function(p)
	FX.Burst(p.Position + Vector3.new(0, 2, 0), Color3.fromRGB(200, 180, 255), 60, nil, 14)
	C.Audio.PlayUI("Discovery")
end

handlers.Drones = function(p)
	if p.From and p.To then
		drones(p.From, p.To)
	end
end

handlers.Meteor = function(p)
	local start = p.Position + Vector3.new(120, 300, -80)
	local rock = Instance.new("Part")
	rock.Anchored = true
	rock.CanCollide = false
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.new(4, 4, 4)
	rock.Material = Enum.Material.Neon
	rock.Color = Color3.fromRGB(255, 160, 80)
	rock.Position = start
	rock.Parent = folder
	local tween = TweenService:Create(
		rock,
		TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = p.Position }
	)
	tween:Play()
	tween.Completed:Connect(function()
		rock:Destroy()
		handlers.Hail({ Position = p.Position })
		FX.Burst(p.Position, Color3.fromRGB(255, 180, 90), 60, nil, 22)
		C.Audio.PlayAt("RockBreak", p.Position)
		C.Camera.Shake(0.35, 0.6)
	end)
end

handlers.Hearts = function(p)
	FX.Text(p.Position, "💕", nil, 30)
end

function FX.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientFX"
	folder.Parent = workspace
	Net.On("FX", function(kind: string, payload: any)
		local handler = handlers[kind]
		if handler then
			local ok, err = pcall(handler, payload or {})
			if not ok then
				warn("[Evergrove] FX", kind, "failed:", err)
			end
		elseif payload and typeof(payload.Position) == "Vector3" then
			FX.Burst(payload.Position, Color3.new(1, 1, 1), 10)
		end
	end)
end

return FX
