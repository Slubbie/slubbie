-- Player input: tool use, targeting, hotbar, area size and every keybind.
--
-- Targeting ("Auto-target Tiles" setting):
--   Pointer  the tile / node / spot under the mouse or touch point
--   Facing   the tile in front of your character (gamepad / touch default)
-- Holding the use button repeats the action at the tool's pace, so sweeping
-- across a field works naturally. The targeted area is outlined; hovering a
-- crop shows its growth, moisture, quality and needs ("Farm Info Mode").
--
-- Default keys
--   Use tool: Left mouse / R2 / tap          Use item (eat, open): F / Y
--   Hotbar: 1-9, 0, mouse wheel / LB-RB      Area size: R / D-pad up
--   Inventory B or Tab · Quests J · Skills K · Map M · Collection C · Crafting V
--   Mail N · Social O · Profile P · Build H · Calendar U · Achievements Y(key)
--   Menu hub: ` / Select · Settings F1 · Photo mode F2 · Admin F8

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tools = require(Shared.Config.Tools)
local Crops = require(Shared.Config.Crops)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local GameTime = require(Shared.Lib.GameTime)
local Format = require(Shared.Lib.Format)
local ItemUtil = require(Shared.Lib.ItemUtil)

local C = require(script.Parent)
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UIFolder.Kit)
local Theme = require(UIFolder.Theme)

local InputController = {}

local player = Players.LocalPlayer
local TILE = 4
local HOTBAR_SIZE = 9 -- inventory slots 1-9 (matches the server)

local areaSize = 0 -- 0 = use the default (max unless set to 1x1)
local holding = false
local lastUse = 0
local highlight: Folder
local boxes: { SelectionBox } = {}
local hoverTile: BasePart? = nil

local WINDOW_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.B] = "Inventory",
	[Enum.KeyCode.Tab] = "Inventory",
	[Enum.KeyCode.J] = "Quests",
	[Enum.KeyCode.K] = "Skills",
	[Enum.KeyCode.M] = "Map",
	[Enum.KeyCode.C] = "Collection",
	[Enum.KeyCode.V] = "Crafting",
	[Enum.KeyCode.N] = "Mail",
	[Enum.KeyCode.O] = "Social",
	[Enum.KeyCode.P] = "Profile",
	[Enum.KeyCode.U] = "Calendar",
	[Enum.KeyCode.Y] = "Achievements",
	[Enum.KeyCode.Backquote] = "Menu",
	[Enum.KeyCode.L] = "Land",
	[Enum.KeyCode.F1] = "Settings",
}

-- Held item ---------------------------------------------------------------------------------------------------------

function InputController.HeldStack(): (any?, string?)
	local slot = C.State.Get("Hotbar")
	if not slot or slot == 0 then
		return nil, nil
	end
	local stack = C.State.Get("Inventory", "Slots", tostring(slot))
	return stack, "inv:" .. slot
end

local function familyOf(stack: any?): string?
	local def = stack and Registry.Items[stack.Id]
	return def and def.Tool
end

local function tierDef(family: string)
	local tier = C.State.Get("Tools", family) or 1
	local fam = Registry.ToolFamilies[family]
	return fam and fam.Tiers[math.clamp(tier, 1, #fam.Tiers)]
end

function InputController.MaxArea(): number
	local stack = InputController.HeldStack()
	local family = familyOf(stack)
	if family then
		local def = tierDef(family)
		return def and def.MaxArea or 1
	end
	local def = stack and Registry.Items[stack.Id]
	if def and (def.Plants or def.Fertilizer) then
		local seeder = tierDef("seeder")
		return seeder and seeder.MaxArea or 1
	end
	return 1
end

function InputController.AreaSize(): number
	local max = InputController.MaxArea()
	if areaSize == 0 then
		return if C.Settings.Get("ToolArea") == "1x1" then 1 else max
	end
	return math.clamp(areaSize, 1, max)
end

function InputController.CycleArea()
	local max = InputController.MaxArea()
	local current = InputController.AreaSize()
	local nextSize = current + 2
	if nextSize > max then
		nextSize = 1
	end
	areaSize = nextSize
	C.HUD.Hint("Area: " .. nextSize .. "×" .. nextSize)
	C.Audio.PlayUI("UIClick")
end

-- Targeting ----------------------------------------------------------------------------------------------------------

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { workspace.CurrentCamera }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	for _, name in { "ClientCrops", "ClientAnimals", "ClientFX", "ClientSky", "ClientBuild" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(exclude, f)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = false
	return params
end

export type Target = { Position: Vector3, Node: string?, Spot: string?, SpotKind: string?, Water: boolean, Tile: BasePart? }

local function pointerRay(): (Vector3, Vector3)
	local location = UserInputService:GetMouseLocation()
	local ray = workspace.CurrentCamera:ViewportPointToRay(location.X, location.Y)
	return ray.Origin, ray.Direction
end

function InputController.Target(): Target?
	local mode = C.Settings.Get("AutoTarget") or "Auto"
	if mode == "Auto" then
		mode = if C.Settings.PrimaryInput() == "Keyboard" then "Pointer" else "Facing"
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local origin, direction
	if mode == "Pointer" then
		origin, direction = pointerRay()
		direction *= 300
	else
		local ahead = root.Position + root.CFrame.LookVector * 5
		origin, direction = ahead + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0)
	end
	local hit = workspace:Raycast(origin, direction, rayParams())
	if not hit then
		return nil
	end
	local target: Target = { Position = hit.Position, Water = hit.Material == Enum.Material.Water, Tile = nil }
	local inst: Instance? = hit.Instance
	while inst and inst ~= workspace do
		if inst:IsA("Model") then
			if inst:GetAttribute("Nid") then
				target.Node = inst:GetAttribute("Nid") :: string?
				break
			end
		end
		if inst:IsA("BasePart") and inst.Parent and inst.Parent.Name == "Tiles" then
			target.Tile = inst
		end
		if inst:IsA("BasePart") and inst:GetAttribute("Water") then
			target.Water = true
		end
		inst = inst.Parent
	end
	-- Gather spots are client models; check what's near the hit point.
	local gather = workspace:FindFirstChild("ClientGather")
	if gather then
		for _, model in gather:GetChildren() do
			if model:IsA("Model") and (model:GetPivot().Position - hit.Position).Magnitude < 3 then
				target.Spot = model:GetAttribute("Spot")
				target.SpotKind = model:GetAttribute("Kind")
				break
			end
		end
	end
	if not target.Tile then
		target.Tile = C.Crops.TileAt(hit.Position)
	end
	return target
end

-- Use --------------------------------------------------------------------------------------------------------------

local ACTION_FOR_FAMILY = { hoe = "Till", can = "Water", sickle = "Harvest", pruners = "Prune", shovel = "Dig", axe = "Chop", pickaxe = "Mine", net = "Net", rod = "Cast", seeder = "Plant" }

local function cooldownFor(stack: any?): number
	local family = familyOf(stack)
	local speed = 1
	if family then
		local def = tierDef(family)
		speed = def and def.Speed or 1
	end
	return Tools.Cooldown * speed
end

function InputController.Use()
	if C.Windows.IsOpen() or C.Build.Active() or C.Fishing.Busy() or C.Photo.Active() then
		return
	end
	local stack = InputController.HeldStack()
	if not stack then
		return
	end
	local now = os.clock()
	if now - lastUse < cooldownFor(stack) then
		return
	end
	lastUse = now
	local def = Registry.Items[stack.Id]
	if not def then
		return
	end
	local target = InputController.Target()
	-- Placeables open build mode with the item.
	if def.Placeable then
		C.Build.Enter(stack.Id)
		return
	end
	-- Food, potions, boxes: use directly.
	if not def.Tool and not def.Powered and not def.Plants and not def.Fertilizer and def.Use ~= "Spray" and def.Use ~= "Amend" and def.Use ~= "Plant" then
		InputController.UseItem()
		return
	end
	if not target then
		return
	end
	local family = def.Tool
	if family == "rod" then
		C.Fishing.Cast(target.Position)
		return
	end
	if family == "net" and target.SpotKind == "Bug" then
		C.Prompts.Run("Bug", target.Spot)
		return
	end
	local opts: { [string]: any } = { Size = InputController.AreaSize() }
	if target.Node then
		opts.Node = target.Node
	end
	if family == "shovel" and target.SpotKind == "Dig" then
		opts.Spot = target.Spot
	end
	if def.Powered then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		opts.Dir = if root then root.CFrame.LookVector else nil
	end
	local position = if target.Tile then target.Tile.Position else target.Position
	Net.Send("ToolUse", stack.Id, position, opts)
	local action = ACTION_FOR_FAMILY[family or ""] or (if def.Plants then "Plant" elseif def.Fertilizer then "Fertilize" else "Spray")
	C.Animation.Play(action)
	local sounds = { Till = "Till", Water = "Water", Harvest = "Harvest", Plant = "Plant", Fertilize = "Fertilize", Chop = "Chop", Mine = "Mine", Dig = "Dig", Net = "NetSwing", Prune = "Harvest", Spray = "Water" }
	if sounds[action] and action ~= "Chop" and action ~= "Mine" then
		C.Audio.PlayAt(sounds[action], position)
	end
end

-- Eat/drink/open/read the held item.
function InputController.UseItem()
	local stack, ref = InputController.HeldStack()
	if not stack or not ref then
		return
	end
	local def = Registry.Items[stack.Id]
	if def and def.Placeable then
		C.Build.Enter(stack.Id)
		return
	end
	local ok, result = Net.Request("InvUse", ref)
	if not ok then
		C.Notify.Toast(tostring(result), "Warning")
	elseif result == "Build" then
		C.Build.Enter(stack.Id)
	else
		C.Animation.Play("Eat")
	end
end

function InputController.SelectHotbar(slot: number)
	Net.Send("Hotbar", slot)
	areaSize = 0
	C.HUD.SelectHotbar(slot)
end

-- Highlights & farm info ---------------------------------------------------------------------------------------------

-- The grid origin of the farm lot containing a position (lots carry an Origin attribute).
function InputController.LotOrigin(position: Vector3): Vector3?
	local farms = workspace:FindFirstChild("Farms")
	if not farms then
		return nil
	end
	for _, lot in farms:GetChildren() do
		local origin = lot:GetAttribute("Origin")
		if typeof(origin) == "Vector3" then
			local rel = position - origin
			if rel.X >= -2 and rel.X <= 242 and rel.Z >= -46 and rel.Z <= 242 then
				return origin
			end
		end
	end
	return nil
end

local function ensureBoxes(n: number)
	while #boxes < n do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = Vector3.new(TILE - 0.2, 0.3, TILE - 0.2)
		part.Parent = highlight
		local box = Instance.new("SelectionBox")
		box.Adornee = part
		box.LineThickness = 0.05
		box.SurfaceTransparency = 0.85
		box.Parent = part
		table.insert(boxes, box)
	end
end

local function hideBoxes()
	for _, box in boxes do
		box.Visible = false
	end
end

local function tileInfo(tile: BasePart): { any }
	local lines = {}
	local cropId = tile:GetAttribute("C")
	local crop = cropId and Registry.Crops[cropId]
	local detailed = C.Settings.Get("FarmInfo") == "Detailed" and not Kit.SimpleUI
	local soil = tostring(tile:GetAttribute("Soil") or "")
	local w, h, n, p, k = string.match(soil, "(%d+),(%d+),(%d+),(%d+),(%d+)")
	if crop then
		local stage = tile:GetAttribute("S") or 1
		table.insert(lines, { Text = crop.Icon .. " " .. crop.Name .. " · " .. Crops.StageNames[stage], Bold = true, Size = Theme.Sizes.Body, Color = Theme.RarityColor(crop.Rarity) })
		if tile:GetAttribute("R") then
			table.insert(lines, { Text = "✨ Ready to harvest!", Color = "Good" })
		else
			local eta = tile:GetAttribute("E")
			local pct = math.floor(((tile:GetAttribute("P") or 0) :: number) * 100)
			local remain = if eta and eta > 0 then Format.Duration(math.max(0, eta - GameTime.Now())) else "stalled"
			table.insert(lines, { Text = string.format("🌱 %d%% grown · ripe in %s", pct, remain), Color = "Text" })
		end
		local q = tile:GetAttribute("Q")
		if q then
			local tier = Theme.QualityTier(q)
			table.insert(lines, { Text = "Quality on track: " .. (tier.Glyph ~= "" and tier.Glyph .. " " or "") .. tier.Name .. (if detailed then " (" .. tostring(tile:GetAttribute("Qs")) .. ")" else ""), Color = tier.Color })
		end
		local m = tile:GetAttribute("M")
		if m then
			local names = {}
			for id in string.gmatch(m, "[^,]+") do
				local def = ItemUtil.MutationDef(id)
				table.insert(names, (def and def.Icon or "✨") .. " " .. (def and def.Name or id))
			end
			table.insert(lines, { Text = table.concat(names, ", "), Color = "Info" })
		end
		if tile:GetAttribute("Af") then
			table.insert(lines, { Text = "⚠️ " .. tostring(tile:GetAttribute("Af")) .. " — treat it!", Color = "Bad" })
		end
		if tile:GetAttribute("Dn") then
			table.insert(lines, { Text = "💤 Out of season: barely growing outdoors", Color = "Warn" })
		end
		local needs = tile:GetAttribute("Nm")
		if needs then
			table.insert(lines, { Text = "⚠️ Needs " .. tostring(needs), Color = "Warn" })
		end
	else
		table.insert(lines, { Text = "🟫 Tilled soil", Bold = true })
	end
	local wb = tile:GetAttribute("Wb")
	table.insert(lines, { Text = (if wb == 0 then "💧 Dry — water me!" elseif wb == 2 then "💦 Soaked" else "💧 Moist") .. (if w then " (" .. w .. "%)" else ""), Color = if wb == 0 then "Warn" else "Info" })
	if detailed and h then
		table.insert(lines, { Text = string.format("Soil health %s · N %s · P %s · K %s", h, n, p, k), Color = "SubText", Size = Theme.Sizes.Tiny })
	end
	if tile:GetAttribute("Spr") then
		table.insert(lines, { Text = "💦 Covered by a sprinkler", Color = "SubText", Size = Theme.Sizes.Tiny })
	end
	if tile:GetAttribute("Ind") then
		table.insert(lines, { Text = "🏠 Indoors", Color = "SubText", Size = Theme.Sizes.Tiny })
	end
	return lines
end

local function updateHighlight()
	if C.Windows.IsOpen() or C.Build.Active() or C.Photo.Active() then
		hideBoxes()
		if hoverTile then
			Kit.HideTooltip(nil)
			hoverTile = nil
		end
		return
	end
	local stack = InputController.HeldStack()
	local target = InputController.Target()
	local def = stack and Registry.Items[stack.Id]
	local farmTool = def and (def.Tool == "hoe" or def.Tool == "can" or def.Tool == "sickle" or def.Tool == "pruners" or def.Tool == "shovel" or def.Plants or def.Fertilizer or def.Use == "Spray" or def.Use == "Amend")
	if target and farmTool then
		local size = InputController.AreaSize()
		local half = math.floor(size / 2)
		local center = if target.Tile then target.Tile.Position else target.Position
		-- Snap to the farm tile grid of the lot under the target (tiles are 4 studs from each lot's corner).
		local origin = InputController.LotOrigin(center) or Vector3.zero
		local gx = math.floor((center.X - origin.X) / TILE)
		local gz = math.floor((center.Z - origin.Z) / TILE)
		ensureBoxes(size * size)
		local i = 0
		for dx = -half, half do
			for dz = -half, half do
				i += 1
				local box = boxes[i]
				local part = box.Adornee :: BasePart
				part.Position = Vector3.new(origin.X + (gx + dx + 0.5) * TILE, center.Y + 0.2, origin.Z + (gz + dz + 0.5) * TILE)
				box.Color3 = Color3.fromRGB(255, 240, 150)
				box.SurfaceColor3 = Color3.fromRGB(255, 240, 150)
				box.Visible = true
			end
		end
		for j = i + 1, #boxes do
			boxes[j].Visible = false
		end
	else
		hideBoxes()
	end
	-- Crop info card
	local info = C.Settings.Get("FarmInfo") or "Compact"
	local tile = target and target.Tile
	if info ~= "Off" and tile and tile.Parent and not GuiService.MenuIsOpen then
		hoverTile = tile
		Kit.ShowTooltip(tileInfo(tile), nil)
	elseif hoverTile then
		hoverTile = nil
		Kit.HideTooltip(nil)
	end
end

-- Keybinds -------------------------------------------------------------------------------------------------------------

local function onInput(input: InputObject, processed: boolean)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	local key = input.KeyCode
	-- Primary action
	if not processed and (input.UserInputType == Enum.UserInputType.MouseButton1 or key == Enum.KeyCode.ButtonR2) then
		holding = true
		InputController.Use()
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch and not processed then
		holding = true
		InputController.Use()
		return
	end
	if processed then
		-- Gamepad menu keys still work while a UI element has focus.
		if key == Enum.KeyCode.ButtonSelect then
			C.Windows.Toggle("Menu")
		end
		return
	end
	-- Hotbar numbers
	local n = key.Value - Enum.KeyCode.One.Value + 1
	if n >= 1 and n <= HOTBAR_SIZE then
		InputController.SelectHotbar(n)
		return
	end
	if key == Enum.KeyCode.ButtonL1 or key == Enum.KeyCode.ButtonR1 then
		local current = C.State.Get("Hotbar") or 1
		local nextSlot = (current - 1 + (if key == Enum.KeyCode.ButtonR1 then 1 else -1)) % HOTBAR_SIZE + 1
		InputController.SelectHotbar(nextSlot)
	elseif key == Enum.KeyCode.R or key == Enum.KeyCode.DPadUp then
		InputController.CycleArea()
	elseif key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonY then
		InputController.UseItem()
	elseif key == Enum.KeyCode.H then
		C.Build.Toggle()
	elseif key == Enum.KeyCode.F2 then
		C.Photo.Toggle()
	elseif key == Enum.KeyCode.F8 then
		if player:GetAttribute("Admin") then
			C.Windows.Toggle("Admin")
		end
	elseif key == Enum.KeyCode.ButtonSelect or key == Enum.KeyCode.DPadDown then
		C.Windows.Toggle(if key == Enum.KeyCode.DPadDown then "Inventory" else "Menu")
	elseif WINDOW_KEYS[key] then
		C.Windows.Toggle(WINDOW_KEYS[key])
	end
end

function InputController.Init()
	highlight = Instance.new("Folder")
	highlight.Name = "ClientBuild"
	highlight.Parent = workspace
end

function InputController.Start()
	UserInputService.InputBegan:Connect(onInput)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 or input.UserInputType == Enum.UserInputType.Touch then
			holding = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			local max = InputController.MaxArea()
			areaSize = math.clamp(InputController.AreaSize() + (if input.Position.Z > 0 then 2 else -2), 1, max)
			C.HUD.Hint("Area: " .. areaSize .. "×" .. areaSize)
		elseif C.Camera.Mode() ~= "Farm" and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			local current = C.State.Get("Hotbar") or 1
			InputController.SelectHotbar((current - 1 - math.sign(input.Position.Z)) % HOTBAR_SIZE + 1)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if holding then
			InputController.Use()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			pcall(updateHighlight)
		end
	end)
end

return InputController
