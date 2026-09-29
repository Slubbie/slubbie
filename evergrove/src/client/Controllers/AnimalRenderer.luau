-- Renders farm animals from the server's anchor parts
-- (workspace.Farms.Lot*.Animals, one part per animal with attributes).
--
-- Movement is decided locally but deterministically: every few seconds each
-- animal picks a wander target from a hash of its id and the time window, so
-- every client sees roughly the same thing without any network traffic.
-- By day in good weather, outdoor species graze in a pen in front of their
-- building; at night, in bad weather, or for indoor species they stay inside.
-- Bees orbit their apiary, floaty species bob in the air.
--
-- Each animal gets a care prompt (pet, brush, feed, collect...), a name tag
-- up close and mood bubbles (hungry, joyful, product ready).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimalsConfig = require(Shared.Config.Animals)
local Registry = require(Shared.Lib.Registry)
local RNG = require(Shared.Lib.RNG)
local WeatherMath = require(Shared.Lib.WeatherMath)
local AnimalModels = require(Shared.Models.Animals)

local C = require(script.Parent)

local AnimalRenderer = {}

local RENDER_RANGE = 220
local ANIMATE_RANGE = 90
local WINDOW = 7

local speciesById: { [string]: any } = {}
for _, s in AnimalsConfig.List do
	speciesById[s.Id] = s
end

type Entry = {
	Anchor: BasePart,
	Aid: string,
	Model: Model?,
	Rig: any,
	Key: string,
	Position: Vector3,
	Yaw: number,
	Target: Vector3?,
	Window: number,
	Moving: boolean,
	Phase: number,
	Tag: BillboardGui?,
	Bubble: BillboardGui?,
	NextSound: number,
}

local entries: { [BasePart]: Entry } = {}
local folder: Folder

local function allele(list: { any }, id: string?): any
	for _, a in list do
		if a.Id == id then
			return a
		end
	end
	return list[1]
end

local function signature(anchor: BasePart): string
	return table.concat({
		tostring(anchor:GetAttribute("Sp")),
		tostring(anchor:GetAttribute("Coat")),
		tostring(anchor:GetAttribute("Pattern")),
		tostring(anchor:GetAttribute("Size")),
		tostring(anchor:GetAttribute("Baby")),
	}, "|")
end

-- Where the animal should be heading right now.
local function chooseTarget(entry: Entry, window: number): Vector3
	local a = entry.Anchor
	local species = speciesById[a:GetAttribute("Sp") or ""]
	local yaw = math.rad(a:GetAttribute("HomeRy") or 0)
	local w = (a:GetAttribute("HomeW") or 12)
	local d = (a:GetAttribute("HomeD") or 12)
	local rot = CFrame.Angles(0, yaw, 0)
	local h1 = RNG.Hash(entry.Aid, window, 1)
	local h2 = RNG.Hash(entry.Aid, window, 2)
	local weather = WeatherMath.Def(C.Lighting.Weather())
	local outside = a:GetAttribute("Outside") == true
		and not C.Lighting.IsNight()
		and weather.Animals >= 0
		and not weather.Hazard
	local center = a.Position
	if species and species.Id == "bee" then
		local angle = h1 * math.pi * 2 + os.clock() * 0.2
		return center + Vector3.new(math.cos(angle) * 8, 4 + h2 * 3, math.sin(angle) * 8)
	end
	if outside then
		-- A pen in front of the door (building fronts face -Z in local space).
		local pen = center + rot:VectorToWorldSpace(Vector3.new(0, 0, -(d / 2 + 9)))
		return pen + rot:VectorToWorldSpace(Vector3.new((h1 - 0.5) * (w + 4), 0, (h2 - 0.5) * 12))
	end
	return center + rot:VectorToWorldSpace(Vector3.new((h1 - 0.5) * w * 0.6, 0, (h2 - 0.5) * d * 0.6))
end

local function groundY(position: Vector3, fallback: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder, workspace:FindFirstChild("ClientCrops") :: Instance }
	local hit = workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -20, 0), params)
	return if hit then hit.Position.Y else fallback
end

local function makeTag(entry: Entry)
	local gui = Instance.new("BillboardGui")
	gui.Name = "AnimalTag"
	gui.Size = UDim2.fromOffset(140, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
	gui.MaxDistance = 28
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	gui.Parent = folder
	entry.Tag = gui
	local bubble = Instance.new("BillboardGui")
	bubble.Name = "Mood"
	bubble.Size = UDim2.fromOffset(34, 34)
	bubble.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	bubble.MaxDistance = 60
	bubble.LightInfluence = 0
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.TextScaled = true
	icon.Font = Enum.Font.GothamBold
	icon.Parent = bubble
	bubble.Parent = folder
	entry.Bubble = bubble
end

local function updateLabels(entry: Entry)
	local a = entry.Anchor
	local body = entry.Rig and entry.Rig.Parts[1] and entry.Rig.Parts[1].Part
	if not entry.Tag or not entry.Bubble or not body then
		return
	end
	entry.Tag.Adornee = body
	entry.Bubble.Adornee = body
	local rarity = a:GetAttribute("Rare") or "Common"
	local label = entry.Tag:FindFirstChild("Name") :: TextLabel
	label.Text = (a:GetAttribute("Nm") or "")
		.. (if a:GetAttribute("Baby") then " 🍼" elseif a:GetAttribute("Preg") then " 🤰" else "")
	label.TextColor3 = if rarity ~= "Common" then C.UI.Theme.RarityColor(rarity) else Color3.new(1, 1, 1)
	local species = speciesById[a:GetAttribute("Sp") or ""]
	local icon = entry.Bubble:FindFirstChild("Icon") :: TextLabel
	local mood = a:GetAttribute("Mood")
	if a:GetAttribute("Ready") and species then
		local product = Registry.Items[species.Product]
		icon.Text = if product then product.Icon else "✨"
	elseif mood == "Hungry" then
		icon.Text = "🍽️"
	elseif mood == "Sad" then
		icon.Text = "💧"
	elseif mood == "Joyful" and (os.clock() + entry.Phase) % 12 < 2 then
		icon.Text = "💖"
	else
		icon.Text = ""
	end
end

local function makePrompt(entry: Entry)
	local body = entry.Rig.Parts[1].Part
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = "Care"
	prompt.ObjectText = entry.Anchor:GetAttribute("Nm") or "Animal"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", "Animal")
	prompt:SetAttribute("Target", entry.Aid)
	prompt:SetAttribute("Owner", entry.Anchor:GetAttribute("Owner"))
	prompt.Parent = body
end

local function build(entry: Entry)
	if entry.Model then
		entry.Model:Destroy()
		entry.Model = nil
	end
	local a = entry.Anchor
	local species = speciesById[a:GetAttribute("Sp") or ""]
	if not species then
		return
	end
	local coat = allele(species.Coats, a:GetAttribute("Coat"))
	local pattern = allele(species.Patterns, a:GetAttribute("Pattern"))
	local ok, model, rig = pcall(
		AnimalModels.Build,
		species,
		coat,
		pattern,
		a:GetAttribute("Size") or 1,
		{ Baby = a:GetAttribute("Baby") == true }
	)
	if not ok then
		warn("[Evergrove] Animal model failed:", model)
		return
	end
	model.Name = entry.Aid
	model.Parent = folder
	entry.Model = model
	entry.Rig = rig
	entry.Key = signature(a)
	makePrompt(entry)
	if not entry.Tag then
		makeTag(entry)
	end
	updateLabels(entry)
end

local function track(anchor: Instance)
	if not anchor:IsA("BasePart") or entries[anchor] then
		return
	end
	local entry: Entry = {
		Anchor = anchor,
		Aid = anchor.Name,
		Model = nil,
		Rig = nil,
		Key = "",
		Position = anchor.Position,
		Yaw = 0,
		Target = nil,
		Window = -1,
		Moving = false,
		Phase = RNG.Hash(anchor.Name) * 10,
		Tag = nil,
		Bubble = nil,
		NextSound = os.clock() + math.random(5, 30),
	}
	entries[anchor] = entry
	anchor.AttributeChanged:Connect(function()
		if entry.Model and signature(anchor) ~= entry.Key then
			build(entry)
		else
			updateLabels(entry)
		end
	end)
	anchor.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if entry.Model then
				entry.Model:Destroy()
			end
			if entry.Tag then
				entry.Tag:Destroy()
			end
			if entry.Bubble then
				entry.Bubble:Destroy()
			end
			entries[anchor] = nil
		end
	end)
end

-- Pose one animal (walk cycle etc.) at its current position.
local function pose(entry: Entry, t: number, moving: boolean)
	local rig = entry.Rig
	local root = CFrame.new(entry.Position) * CFrame.Angles(0, entry.Yaw, 0)
	local species = speciesById[tostring(entry.Anchor:GetAttribute("Sp") or "")]
	local hover = species and species.Model.Hover
	local bob = if hover
		then math.sin(t * 2 + entry.Phase) * 0.3
		else (if moving then math.abs(math.sin(t * 10)) * 0.08 else 0)
	root *= CFrame.new(0, bob, 0)
	local walk = if moving then math.sin(t * 10 + entry.Phase) * 0.6 else 0
	local grazing = not moving and (t + entry.Phase) % 9 < 3
	for _, p in rig.Parts do
		local cf = root * p.Offset
		if p.Role == "Leg" and p.Pivot then
			local dir = if p.Index % 2 == 0 then 1 else -1
			local pivotWorld = root * p.Pivot
			cf = pivotWorld * CFrame.Angles(walk * dir, 0, 0) * pivotWorld:ToObjectSpace(root * p.Offset)
		elseif p.Role == "Head" or p.Role == "Neck" or p.Role == "Ear" then
			-- Grazing dips the head; otherwise a gentle idle nod.
			local nod = if grazing then 0.35 else math.sin(t * 1.5 + entry.Phase) * 0.05
			cf = root * p.Offset * CFrame.new(0, -nod * 0.6, 0) * CFrame.Angles(nod, 0, 0)
		elseif p.Role == "Tail" then
			cf = cf * CFrame.Angles(0, math.sin(t * 6 + entry.Phase) * 0.3, 0)
		elseif p.Role == "Wing" then
			local flap = if moving and species and (hover or species.Model.Beak) then math.sin(t * 20) * 0.5 else 0
			cf = cf * CFrame.Angles(0, 0, flap * (p.Side or 1))
		end
		p.Part.CFrame = cf
	end
end

local function step(dt: number)
	local camPos = workspace.CurrentCamera.CFrame.Position
	local t = os.clock()
	local window = math.floor(workspace:GetServerTimeNow() / WINDOW)
	for anchor, entry in entries do
		local dist = (anchor.Position - camPos).Magnitude
		if dist > RENDER_RANGE then
			if entry.Model then
				entry.Model:Destroy()
				entry.Model = nil
			end
		else
			if not entry.Model then
				build(entry)
				entry.Position = chooseTarget(entry, window)
			end
			if entry.Model and entry.Rig then
				if entry.Window ~= window then
					entry.Window = window
					entry.Target = chooseTarget(entry, window + RNG.HashInt(entry.Aid) % 3)
				end
				local target = entry.Target or entry.Position
				local delta = Vector3.new(target.X - entry.Position.X, 0, target.Z - entry.Position.Z)
				local species = speciesById[anchor:GetAttribute("Sp") or ""]
				local speed = if species and species.Id == "bee" then 6 else 3.5
				local moving = delta.Magnitude > 0.6
				if moving then
					local stepVec = delta.Unit * math.min(delta.Magnitude, speed * dt)
					entry.Position += stepVec
					local wantYaw = math.atan2(-delta.X, -delta.Z)
					local diff = (wantYaw - entry.Yaw + math.pi) % (math.pi * 2) - math.pi
					entry.Yaw += diff * math.min(1, dt * 6)
				end
				if species and species.Id == "bee" then
					entry.Position = Vector3.new(entry.Position.X, target.Y, entry.Position.Z)
				elseif dist < ANIMATE_RANGE then
					entry.Position = Vector3.new(
						entry.Position.X,
						groundY(entry.Position, anchor.Position.Y) + 0.05,
						entry.Position.Z
					)
				end
				if dist < ANIMATE_RANGE or moving then
					pose(entry, t, moving)
				end
				-- Occasional voice
				if dist < 60 and t >= entry.NextSound and species then
					entry.NextSound = t + math.random(12, 40)
					C.Audio.PlayAt(species.Sounds[1], entry.Position)
				end
			end
		end
	end
end

function AnimalRenderer.Position(aid: string): Vector3?
	for _, entry in entries do
		if entry.Aid == aid then
			return entry.Position
		end
	end
	return nil
end

-- Animals near a point (for the care menu and FX).
function AnimalRenderer.Model(aid: string): Model?
	for _, entry in entries do
		if entry.Aid == aid then
			return entry.Model
		end
	end
	return nil
end

function AnimalRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientAnimals"
	folder.Parent = workspace
end

function AnimalRenderer.Start()
	local farms = workspace:WaitForChild("Farms")
	local function watchLot(lot: Instance)
		local function hook(f: Instance)
			for _, a in f:GetChildren() do
				track(a)
			end
			f.ChildAdded:Connect(track)
		end
		local f = lot:FindFirstChild("Animals")
		if f then
			hook(f)
		end
		lot.ChildAdded:Connect(function(child)
			if child.Name == "Animals" then
				hook(child)
			end
		end)
	end
	for _, lot in farms:GetChildren() do
		watchLot(lot)
	end
	farms.ChildAdded:Connect(watchLot)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[Evergrove] Animal step failed:", err)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, entry in entries do
				updateLabels(entry)
			end
		end
	end)
end

return AnimalRenderer
