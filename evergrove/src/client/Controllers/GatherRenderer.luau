-- Visuals and prompts for things you pick up in the world:
--   * forage (workspace.Gatherables.<Region>, Kind=Forage, Item=<id>)
--   * bugs visiting points (Kind=Bug, Bug=<id>, Until=<unix>)
--   * dig spots (Kind=Dig, Active=true)
--   * festival collectibles (workspace.Festival, Kind=Festival)
--   * secret spots (workspace.World.Secrets): glints/runes and the trigger
--
-- Everything is per player: spots you've already collected today
-- (State.Gather.Got) or festival items you've found are hidden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Kit = require(Shared.Models.Kit)

local C = require(script.Parent)

local GatherRenderer = {}

local RANGE = 160
local player = Players.LocalPlayer

type Entry = { Anchor: BasePart, Kind: string, Model: Model?, Key: string, Phase: number }
local entries: { [BasePart]: Entry } = {}
local folder: Folder

local function makePrompt(parent: BasePart, kind: string, action: string, object: string, target: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", kind)
	prompt:SetAttribute("Target", target)
	prompt.Parent = parent
	return prompt
end

local function hidden(entry: Entry): boolean
	local a = entry.Anchor
	if entry.Kind == "Forage" or entry.Kind == "Dig" then
		local got = C.State.Get("Gather", "Got")
		if got and got[a.Name] then
			return true
		end
		if entry.Kind == "Dig" and not a:GetAttribute("Active") then
			return true
		end
		if entry.Kind == "Forage" and not a:GetAttribute("Item") then
			return true
		end
	elseif entry.Kind == "Bug" then
		if not a:GetAttribute("Bug") then
			return true
		end
		local caught = a:GetAttribute("CaughtWindow")
		if caught and caught == a:GetAttribute("Window") then
			return true
		end
	elseif entry.Kind == "Festival" then
		local found = C.State.Get("Festival", "Found")
		local activity = a:GetAttribute("Activity")
		if found and found[activity] and found[activity][tostring(a:GetAttribute("Index"))] then
			return true
		end
	end
	return false
end

local function signature(entry: Entry): string
	local a = entry.Anchor
	return table.concat({ entry.Kind, tostring(a:GetAttribute("Item")), tostring(a:GetAttribute("Bug")), tostring(a:GetAttribute("Active")), tostring(a:GetAttribute("Window")) }, "|")
end

-- Builders ---------------------------------------------------------------------------------------------------------

local function forageModel(itemId: string, spot: string): Model
	local def = Registry.Items[itemId]
	local model = Kit.Model("Forage")
	local tint = (def and def.Tint) or Color3.fromRGB(230, 200, 110)
	local tags = def and def.Tags or {}
	if tags.Mushroom then
		Kit.Cyl(model, 0.7, 0.25, CFrame.new(0, 0.35, 0), Color3.fromRGB(240, 230, 210), { Collide = false })
		Kit.Ball(model, Vector3.new(1, 0.5, 1), CFrame.new(0, 0.75, 0), tint:Lerp(Color3.fromRGB(190, 120, 70), 0.5), { Collide = false, Name = "Glint" })
	elseif tags.Flower then
		Kit.Box(model, Vector3.new(0.1, 1, 0.1), CFrame.new(0, 0.5, 0), Color3.fromRGB(90, 150, 70), { Collide = false })
		Kit.Ball(model, Vector3.new(0.6, 0.3, 0.6), CFrame.new(0, 1.05, 0), tint, { Collide = false, Name = "Glint" })
	else
		for i = 1, 3 do
			Kit.Ball(model, Vector3.new(0.45, 0.45, 0.45), CFrame.new(math.cos(i * 2) * 0.35, 0.25, math.sin(i * 2) * 0.35), tint, { Collide = false, Name = "Glint" })
		end
		Kit.Wedge(model, Vector3.new(0.1, 0.6, 0.8), CFrame.new(0, 0.3, 0), Color3.fromRGB(90, 150, 70), { Collide = false })
	end
	local glint = model:FindFirstChild("Glint") :: BasePart
	Kit.Particles(glint, "Sparkle", Color3.fromRGB(255, 250, 200), 1.5)
	makePrompt(glint, "Forage", "Pick", if def then def.Name else "Forage", spot)
	return model
end

local function bugModel(bugId: string, spot: string): Model
	local def = Registry.Bugs[bugId]
	local model = Kit.Model("Bug")
	local tint = (def and def.Tint) or Color3.fromRGB(240, 200, 90)
	local flying = def == nil or def.Flying ~= false
	local body = Kit.Ball(model, Vector3.new(0.25, 0.25, 0.6), CFrame.new(0, 0, 0), Color3.fromRGB(40, 35, 30), { Collide = false, Name = "Body" })
	if flying then
		for _, sx in { -1, 1 } do
			local wing = Kit.Wedge(model, Vector3.new(0.05, 0.7, 0.6), CFrame.new(sx * 0.35, 0.1, 0) * CFrame.Angles(0, 0, sx * 0.3), tint, { Collide = false, Name = "Wing" })
			wing:SetAttribute("Side", sx)
			wing.Transparency = 0.1
		end
	else
		Kit.Ball(model, Vector3.new(0.5, 0.35, 0.6), CFrame.new(0, 0.1, 0), tint, { Collide = false, Name = "Shell" })
	end
	if def and def.Id == "firefly" then
		Kit.Glow(body, Color3.fromRGB(230, 255, 120))
		Kit.Light(body, Color3.fromRGB(230, 255, 120), 6, 1)
	end
	model:SetAttribute("Flying", flying)
	makePrompt(body, "Bug", "Catch", if def then def.Name else "Bug", spot)
	return model
end

local function digModel(spot: string): Model
	local model = Kit.Model("DigSpot")
	Kit.Ball(model, Vector3.new(1.6, 0.4, 1.6), CFrame.new(0, 0.05, 0), Color3.fromRGB(110, 80, 55), { Collide = false, Material = Enum.Material.Ground, Name = "Mound" })
	for i = 1, 3 do
		local worm = Kit.Cyl(model, 0.7, 0.18, CFrame.new(math.cos(i * 2.1) * 0.3, 0.4, math.sin(i * 2.1) * 0.3), Color3.fromRGB(210, 140, 130), { Collide = false, Name = "Worm" })
		worm:SetAttribute("Wiggle", i)
	end
	makePrompt(model:FindFirstChild("Mound") :: BasePart, "Dig", "Dig", "Something buried", spot)
	return model
end

local FESTIVAL_SHAPES: { [string]: (Model) -> BasePart } = {
	Egg = function(m)
		local p = Kit.Ball(m, Vector3.new(0.9, 1.2, 0.9), CFrame.new(0, 0.6, 0), Color3.fromHSV(math.random(), 0.5, 1), { Collide = false, Name = "Core" })
		Kit.Box(m, Vector3.new(0.95, 0.15, 0.95), CFrame.new(0, 0.65, 0), Color3.new(1, 1, 1), { Collide = false })
		return p
	end,
	Star = function(m)
		local p = Kit.Box(m, Vector3.new(0.3, 1.2, 1.2), CFrame.new(0, 1, 0) * CFrame.Angles(math.rad(45), 0, 0), Color3.fromRGB(255, 230, 120), { Collide = false, Name = "Core" })
		Kit.Glow(p, Color3.fromRGB(255, 230, 120))
		Kit.Light(p, Color3.fromRGB(255, 230, 150), 10, 1.2)
		return p
	end,
	Apple = function(m)
		local p = Kit.Ball(m, Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, 0.45, 0), Color3.fromRGB(220, 50, 40), { Collide = false, Name = "Core" })
		Kit.Box(m, Vector3.new(0.08, 0.3, 0.08), CFrame.new(0, 1, 0), Color3.fromRGB(100, 70, 40), { Collide = false })
		return p
	end,
	Chest = function(m)
		local p = Kit.Ball(m, Vector3.new(1.6, 0.5, 1.6), CFrame.new(0, 0.1, 0), Color3.fromRGB(120, 90, 60), { Collide = false, Name = "Core", Material = Enum.Material.Ground })
		Kit.Box(m, Vector3.new(0.2, 0.9, 0.2), CFrame.new(0.4, 0.5, 0) * CFrame.Angles(0, 0, 0.5), Color3.fromRGB(200, 60, 50), { Collide = false })
		return p
	end,
	Lantern = function(m)
		local p = Kit.Box(m, Vector3.new(0.8, 1.1, 0.8), CFrame.new(0, 1.2, 0), Color3.fromRGB(255, 150, 90), { Collide = false, Name = "Core" })
		Kit.Glow(p, Color3.fromRGB(255, 160, 90))
		Kit.Light(p, Color3.fromRGB(255, 160, 90), 12, 1.3)
		return p
	end,
}

local function festivalModel(anchor: BasePart): Model
	local model = Kit.Model("FestivalItem")
	local shape = FESTIVAL_SHAPES[tostring(anchor:GetAttribute("Model") or "Star")] or FESTIVAL_SHAPES.Star
	local core = shape(model)
	Kit.Particles(core, "Sparkle", Color3.fromRGB(255, 240, 200), 2)
	local prompt = makePrompt(core, "Festival", if anchor:GetAttribute("Dig") then "Dig up" else "Collect", "Festival find", tostring(anchor:GetAttribute("Activity")) .. ":" .. tostring(anchor:GetAttribute("Index")))
	prompt:SetAttribute("Activity", anchor:GetAttribute("Activity"))
	prompt:SetAttribute("Index", anchor:GetAttribute("Index"))
	return model
end

local function build(entry: Entry)
	if entry.Model then
		entry.Model:Destroy()
		entry.Model = nil
	end
	if hidden(entry) then
		return
	end
	local a = entry.Anchor
	local model
	if entry.Kind == "Forage" then
		model = forageModel(a:GetAttribute("Item"), a.Name)
	elseif entry.Kind == "Bug" then
		model = bugModel(a:GetAttribute("Bug"), a.Name)
	elseif entry.Kind == "Dig" then
		model = digModel(a.Name)
	elseif entry.Kind == "Festival" then
		model = festivalModel(a)
	end
	if model then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = d.Name == "Body" or d.Name == "Core" or d.Name == "Glint" or d.Name == "Mound"
				d.CastShadow = false
			end
		end
		model:SetAttribute("Spot", a.Name)
		model:SetAttribute("Kind", entry.Kind)
		model:PivotTo(CFrame.new(a.Position - Vector3.new(0, a.Size.Y / 2, 0)))
		model.Parent = folder
		entry.Model = model
	end
	entry.Key = signature(entry)
end

local function track(anchor: Instance)
	if not anchor:IsA("BasePart") or entries[anchor] then
		return
	end
	local kind = anchor:GetAttribute("Kind")
	if kind ~= "Forage" and kind ~= "Bug" and kind ~= "Dig" and kind ~= "Festival" then
		return
	end
	local entry: Entry = { Anchor = anchor, Kind = kind, Model = nil, Key = "", Phase = math.random() * 10 }
	entries[anchor] = entry
	anchor.AttributeChanged:Connect(function()
		entry.Key = ""
	end)
	anchor.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if entry.Model then
				entry.Model:Destroy()
			end
			entries[anchor] = nil
		end
	end)
end

-- Mark a bug caught/fled locally so it disappears right away.
function GatherRenderer.BugGone(spot: string)
	for anchor, entry in entries do
		if anchor.Name == spot and entry.Kind == "Bug" then
			anchor:SetAttribute("CaughtWindow", anchor:GetAttribute("Window"))
			entry.Key = ""
		end
	end
end

local function refreshAll()
	for _, entry in entries do
		entry.Key = ""
	end
end

-- Secrets --------------------------------------------------------------------------------------------------------

local secretParts: { BasePart } = {}
local secretCooldown: { [string]: number } = {}

local function dressSecret(part: BasePart)
	table.insert(secretParts, part)
	local visible = part:GetAttribute("Visible")
	local found = C.State.Get("Secrets")
	if found and found[part.Name] then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = part.Position
	anchor.Name = "SecretFX_" .. part.Name
	if visible == "Glint" then
		local e = Kit.Particles(anchor, "Sparkle", Color3.fromRGB(255, 255, 220), 0.8)
		e.Lifetime = NumberRange.new(1.5, 2.5)
	elseif visible == "Rune" then
		local rune = Instance.new("Part")
		rune.Anchored = true
		rune.CanCollide = false
		rune.Material = Enum.Material.Neon
		rune.Color = Color3.fromRGB(120, 230, 255)
		rune.Transparency = 0.6
		rune.Size = Vector3.new(3, 0.1, 3)
		rune.CFrame = CFrame.new(part.Position - Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, math.rad(45), 0)
		rune.Parent = anchor
	elseif visible == "Shrine" then
		Kit.Particles(anchor, "Sparkle", Color3.fromRGB(200, 170, 255), 1)
	end
	anchor.Parent = folder
end

local function checkSecrets()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local found = C.State.Get("Secrets") or {}
	for _, part in secretParts do
		local id = part.Name
		if not found[id] and (root.Position - part.Position).Magnitude <= part.Size.X / 2 then
			if (secretCooldown[id] or 0) < os.clock() then
				secretCooldown[id] = os.clock() + 8
				task.spawn(function()
					local ok, result = Net.Request("SecretTrigger", id)
					if not ok and type(result) == "string" and result ~= "" then
						C.Notify.Toast("🔍 " .. result, "Info")
					end
				end)
			end
		end
	end
end

-- Animation --------------------------------------------------------------------------------------------------------

local function animate()
	local camPos = workspace.CurrentCamera.CFrame.Position
	local t = os.clock()
	for anchor, entry in entries do
		local near = (anchor.Position - camPos).Magnitude <= RANGE
		if near and entry.Key ~= signature(entry) then
			build(entry)
		elseif not near and entry.Model then
			entry.Model:Destroy()
			entry.Model = nil
			entry.Key = ""
		end
		local model = entry.Model
		if model and near then
			if entry.Kind == "Bug" then
				local flying = model:GetAttribute("Flying")
				local p = anchor.Position
				local offset = if flying
					then Vector3.new(math.cos(t * 0.9 + entry.Phase) * 2.5, 1.5 + math.sin(t * 1.7 + entry.Phase) * 0.8, math.sin(t * 1.1 + entry.Phase) * 2.5)
					else Vector3.new(math.cos(t * 0.3 + entry.Phase) * 1.2, -0.9, math.sin(t * 0.3 + entry.Phase) * 1.2)
				local heading = if flying then t * 1.1 + entry.Phase else t * 0.3 + entry.Phase
				model:PivotTo(CFrame.new(p + offset) * CFrame.Angles(0, -heading, 0))
				for _, d in model:GetChildren() do
					if d.Name == "Wing" and d:IsA("BasePart") then
						local side = d:GetAttribute("Side") or 1
						d.CFrame = model:GetPivot() * CFrame.new(side * 0.35, 0.1, 0) * CFrame.Angles(0, 0, side * (0.3 + math.sin(t * 30) * 0.7))
					end
				end
			elseif entry.Kind == "Dig" then
				for _, d in model:GetChildren() do
					local w = d:GetAttribute("Wiggle")
					if w and d:IsA("BasePart") then
						d.CFrame = model:GetPivot() * CFrame.new(math.cos(w * 2.1) * 0.3, 0.3 + math.abs(math.sin(t * 3 + w)) * 0.3, math.sin(w * 2.1) * 0.3) * CFrame.Angles(math.sin(t * 4 + w) * 0.4, 0, math.pi / 2)
					end
				end
			elseif entry.Kind == "Festival" then
				model:PivotTo(CFrame.new(anchor.Position - Vector3.new(0, anchor.Size.Y / 2 - math.sin(t * 2 + entry.Phase) * 0.25, 0)) * CFrame.Angles(0, t + entry.Phase, 0))
			end
		end
	end
end

function GatherRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientGather"
	folder.Parent = workspace
end

function GatherRenderer.Start()
	local function watchRoot(root: Instance)
		for _, d in root:GetDescendants() do
			track(d)
		end
		root.DescendantAdded:Connect(track)
	end
	task.spawn(function()
		watchRoot(workspace:WaitForChild("Gatherables"))
	end)
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Festival" then
			watchRoot(child)
		end
	end)
	local fest = workspace:FindFirstChild("Festival")
	if fest then
		watchRoot(fest)
	end
	task.spawn(function()
		local world = workspace:WaitForChild("World")
		local secrets = world:WaitForChild("Secrets", 60)
		if secrets then
			for _, part in secrets:GetChildren() do
				if part:IsA("BasePart") then
					dressSecret(part)
				end
			end
			secrets.ChildAdded:Connect(function(part)
				if part:IsA("BasePart") then
					dressSecret(part)
				end
			end)
		end
	end)
	C.State.Watch("Gather", refreshAll)
	C.State.Watch("Festival", refreshAll)
	C.State.Watch("Secrets", function(found)
		for id in found or {} do
			local fx = folder:FindFirstChild("SecretFX_" .. id)
			if fx then
				fx:Destroy()
			end
		end
	end)
	RunService.Heartbeat:Connect(function()
		pcall(animate)
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			pcall(checkSecrets)
		end
	end)
end

return GatherRenderer
