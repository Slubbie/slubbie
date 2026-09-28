-- Evergrove Village: shops and halls from Config/World.Buildings, the plaza,
-- festival stage, park pond, boards, villager homes, street lamps and trees.
--
-- A building's door faces its Facing yaw: door direction = (sin θ, 0, cos θ).
-- Buildings tied to a town project carry a "Project" attribute; the client
-- shows scaffolding instead until the player has finished that project.
--
-- Build(root) returns { Doors = { [buildingId] = Vector3 }, Homes = { [npcId] = Vector3 } }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)
local NPCs = require(Shared.Config.NPCs)
local Kit = require(Shared.Models.Kit)
local Models = require(Shared.Models)
local TerrainKit = require(script.Parent.TerrainKit)

local C = Kit.C

local VillageBuilder = {}

-- Special homes (everyone else gets a cottage on the outer ring).
local SPECIAL_HOMES = {
	mabel = Vector3.new(-150, 0, 164),
	luna = Vector3.new(-150, 30, -536),
	finn = Vector3.new(200, 0, 150),
	hattie = Vector3.new(-200, 0, 58),
	wisp = Vector3.new(-900, 0, 330),
}

-- Building shells ------------------------------------------------------------------------------------------------

local function windowAt(model: Model, cf: CFrame, w: number, h: number)
	local pane = Kit.Box(model, Vector3.new(w, h, 0.3), cf, Color3.fromRGB(255, 232, 180), { Material = Enum.Material.Glass, Transparency = 0.25, Collide = false, Name = "Window" })
	pane:SetAttribute("NightGlow", true)
	Kit.Box(model, Vector3.new(w + 0.6, 0.35, 0.5), cf * CFrame.new(0, -h / 2 - 0.2, -0.1), C.DarkWood, { Collide = false })
end

-- Walls around a w×d footprint (door on +Z), returns wall height used.
local function shell(model: Model, w: number, d: number, wallH: number, wall: Color3, material: Enum.Material, doorW: number)
	local t = 0.8
	Kit.Box(model, Vector3.new(w + 2, 1, d + 2), CFrame.new(0, 0.5, 0), C.Stone, { Material = Enum.Material.Cobblestone })
	Kit.Box(model, Vector3.new(w, wallH, t), CFrame.new(0, 1 + wallH / 2, -d / 2), wall, { Material = material })
	Kit.Box(model, Vector3.new(t, wallH, d), CFrame.new(-w / 2, 1 + wallH / 2, 0), wall, { Material = material })
	Kit.Box(model, Vector3.new(t, wallH, d), CFrame.new(w / 2, 1 + wallH / 2, 0), wall, { Material = material })
	local side = (w - doorW) / 2
	Kit.Box(model, Vector3.new(side, wallH, t), CFrame.new(-w / 2 + side / 2, 1 + wallH / 2, d / 2), wall, { Material = material })
	Kit.Box(model, Vector3.new(side, wallH, t), CFrame.new(w / 2 - side / 2, 1 + wallH / 2, d / 2), wall, { Material = material })
	if wallH > 8 then
		Kit.Box(model, Vector3.new(doorW, wallH - 8, t), CFrame.new(0, 1 + 8 + (wallH - 8) / 2, d / 2), wall, { Material = material })
	end
	local door = Kit.Box(model, Vector3.new(doorW - 1, 8, 0.4), CFrame.new(0, 5, d / 2 + 0.2), C.DarkWood, { Material = Enum.Material.Wood, Name = "Door" })
	-- Windows along the front and sides
	local count = math.max(1, math.floor(w / 10))
	for i = 1, count do
		local x = -w / 2 + (i - 0.5) * (w / count)
		if math.abs(x) > doorW then
			windowAt(model, CFrame.new(x, 1 + wallH * 0.55, d / 2 + 0.3), 3.2, 3.4)
		end
	end
	for _, sx in { -1, 1 } do
		windowAt(model, CFrame.new(sx * (w / 2 + 0.3), 1 + wallH * 0.55, 0) * CFrame.Angles(0, sx * math.pi / 2, 0), 3.2, 3.4)
	end
	return door
end

local function signBoard(model: Model, text: string, y: number, z: number, width: number)
	local board = Kit.Box(model, Vector3.new(width, 2.6, 0.4), CFrame.new(0, y, z), C.Plank, { Material = Enum.Material.WoodPlanks, Collide = false, Name = "Sign" })
	-- The Back face points along +Z, i.e. out of the building's front.
	Kit.Label(board, text, Enum.NormalId.Back)
	return board
end

local styles: { [string]: (Model, any) -> () } = {}

styles.Hall = function(model, b)
	local w, h, d = b.Size.X, b.Size.Y, b.Size.Z
	local wallH = h * 0.6
	shell(model, w, d, wallH, b.Wall, Enum.Material.Brick, 7)
	Kit.Roof(model, w, d, 1 + wallH, h - wallH, b.Roof, 1.5, { Material = Enum.Material.Slate })
	-- Columns and steps
	for i = -2, 2 do
		if i ~= 0 then
			Kit.Cyl(model, wallH, 1.6, CFrame.new(i * (w / 6), 1 + wallH / 2, d / 2 + 3), C.Cream, { Material = Enum.Material.Marble })
		end
	end
	Kit.Box(model, Vector3.new(w * 0.8, 1, 4), CFrame.new(0, 0.5, d / 2 + 3), C.Stone, { Material = Enum.Material.Marble })
	Kit.Box(model, Vector3.new(w * 0.85, 1, 5), CFrame.new(0, 1 + wallH, d / 2 + 3), b.Roof, { Material = Enum.Material.Slate })
	if b.Id == "TownHall" then
		local clock = Kit.Cyl(model, 0.4, 5, CFrame.new(0, 1 + wallH + (h - wallH) * 0.4, d / 2 + 1.2) * CFrame.Angles(math.pi / 2, 0, 0), C.Cream, { Collide = false, Name = "Clock" })
		clock:SetAttribute("Clock", true)
	end
end

styles.Shop = function(model, b)
	local w, h, d = b.Size.X, b.Size.Y, b.Size.Z
	local wallH = h * 0.58
	shell(model, w, d, wallH, b.Wall, Enum.Material.Plaster, 6)
	Kit.Roof(model, w, d, 1 + wallH, h - wallH, b.Roof, 1.2)
	-- Striped awning over the front
	for i = 0, 5 do
		local stripe = if i % 2 == 0 then b.Roof else C.Cream
		Kit.Wedge(model, Vector3.new(w / 6, 1.6, 4), CFrame.new(-w / 2 + (i + 0.5) * w / 6, wallH * 0.82, d / 2 + 2), stripe, { Collide = false, Material = Enum.Material.Fabric })
	end
	-- Display crates
	for i = -1, 1, 2 do
		Kit.Box(model, Vector3.new(3, 1.6, 2), CFrame.new(i * (w / 2 - 3), 0.8, d / 2 + 2.5), C.Wood, { Material = Enum.Material.WoodPlanks })
		for j = -1, 1 do
			Kit.Ball(model, Vector3.new(0.8, 0.8, 0.8), CFrame.new(i * (w / 2 - 3) + j * 0.8, 1.9, d / 2 + 2.5), Color3.fromHSV((j + 2) / 7, 0.7, 0.95), { Collide = false })
		end
	end
end

styles.Forge = function(model, b)
	local w, h, d = b.Size.X, b.Size.Y, b.Size.Z
	local wallH = h * 0.6
	shell(model, w, d, wallH, b.Wall, Enum.Material.Cobblestone, 7)
	Kit.Roof(model, w, d, 1 + wallH, h - wallH, b.Roof, 1)
	local stack = Kit.Box(model, Vector3.new(4, h + 4, 4), CFrame.new(w * 0.3, (h + 4) / 2, -d * 0.2), C.DarkStone, { Material = Enum.Material.Brick })
	Kit.Particles(stack, "Smoke", Color3.fromRGB(90, 90, 90), 4)
	local fire = Kit.Box(model, Vector3.new(3, 1, 0.3), CFrame.new(w * 0.3, 2.5, -d * 0.2 + 2.1), Color3.fromRGB(255, 120, 40), { Collide = false })
	Kit.Glow(fire, Color3.fromRGB(255, 120, 40))
	Kit.Light(fire, Color3.fromRGB(255, 150, 80), 16, 2)
	-- Anvil outside
	Kit.Box(model, Vector3.new(1.4, 1.6, 1.4), CFrame.new(-w * 0.25, 0.8, d / 2 + 4), C.DarkStone)
	Kit.Box(model, Vector3.new(3, 0.8, 1.2), CFrame.new(-w * 0.25, 2, d / 2 + 4), C.DarkMetal, { Material = Enum.Material.Metal, Name = "Anvil" })
end

styles.Market = function(model, b)
	local w, d = b.Size.X, b.Size.Z
	Kit.Box(model, Vector3.new(w, 0.6, d), CFrame.new(0, 0.3, 0), C.Stone, { Material = Enum.Material.Cobblestone })
	local colors = { Color3.fromRGB(230, 90, 80), Color3.fromRGB(245, 190, 70), Color3.fromRGB(110, 170, 220), Color3.fromRGB(120, 190, 110) }
	local i = 0
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			i += 1
			local base = CFrame.new(sx * w / 4, 0, sz * d / 4)
			Kit.Box(model, Vector3.new(8, 3, 3), base * CFrame.new(0, 1.5, 0), C.Wood, { Material = Enum.Material.WoodPlanks })
			for _, px in { -4, 4 } do
				Kit.Box(model, Vector3.new(0.5, 8, 0.5), base * CFrame.new(px, 4, -1.5), C.DarkWood)
			end
			Kit.Wedge(model, Vector3.new(9, 2, 5), base * CFrame.new(0, 8.5, 0), colors[i], { Material = Enum.Material.Fabric, Collide = false })
			for j = -2, 2 do
				Kit.Ball(model, Vector3.new(0.9, 0.9, 0.9), base * CFrame.new(j * 1.4, 3.4, 0), Color3.fromHSV(((i + j) % 6) / 6, 0.65, 1), { Collide = false })
			end
		end
	end
end

styles.Glasshouse = function(model, b)
	local w, h, d = b.Size.X, b.Size.Y, b.Size.Z
	local builder = Models.Builder("Greenhouse")
	if builder then
		builder(model, w, d, h, {}, {})
	end
	-- A proper door on +Z for the florist.
	Kit.Box(model, Vector3.new(4, 7, 0.4), CFrame.new(0, 3.5, d / 2 + 0.3), C.DarkWood, { Name = "Door", Collide = false })
end

styles.Workshop = function(model, b)
	local w, h, d = b.Size.X, b.Size.Y, b.Size.Z
	local wallH = h * 0.6
	shell(model, w, d, wallH, b.Wall, Enum.Material.CorrodedMetal, 9)
	Kit.Roof(model, w, d, 1 + wallH, h - wallH, b.Roof, 1, { Material = Enum.Material.CorrodedMetal })
	local gear = Kit.Cyl(model, 0.6, 6, CFrame.new(-w * 0.3, 1 + wallH + 2, d / 2 + 0.5) * CFrame.Angles(math.pi / 2, 0, 0), C.Copper, { Material = Enum.Material.Metal, Collide = false, Name = "Gear" })
	gear:SetAttribute("Anim", "Spinner")
	for i = 1, 3 do
		Kit.Box(model, Vector3.new(2, 2, 2), CFrame.new(w / 2 + 2, 1 + (i - 1) * 2, -d * 0.2 + i), C.Wood, { Name = "Crate" })
	end
end

styles.Lab = function(model, b)
	local w, h, d = b.Size.X, b.Size.Y, b.Size.Z
	local wallH = h * 0.6
	shell(model, w, d, wallH, b.Wall, Enum.Material.SmoothPlastic, 6)
	Kit.Box(model, Vector3.new(w + 1, 1, d + 1), CFrame.new(0, 1 + wallH + 0.5, 0), b.Roof)
	local dome = Kit.Ball(model, Vector3.new(w * 0.5, w * 0.5, w * 0.5), CFrame.new(0, 1 + wallH, -d * 0.1), Color3.fromRGB(200, 230, 245), { Material = Enum.Material.Glass, Transparency = 0.3 })
	dome.Name = "Dome"
	Kit.Box(model, Vector3.new(0.3, 6, 0.3), CFrame.new(w * 0.35, 1 + wallH + 3, d * 0.3), C.Metal, { Name = "Antenna" })
	local tip = Kit.Ball(model, Vector3.new(0.8, 0.8, 0.8), CFrame.new(w * 0.35, 1 + wallH + 6.2, d * 0.3), Color3.fromRGB(120, 255, 200), { Collide = false })
	Kit.Glow(tip, Color3.fromRGB(120, 255, 200))
end

styles.Barn = function(model, b)
	local builder = Models.Builder("Barn")
	if builder then
		-- The farm barn builder puts its door on -Z; turn it to face +Z.
		local inner = Kit.Model("Barn")
		builder(inner, b.Size.X, b.Size.Z, b.Size.Y, {}, {})
		inner:PivotTo(CFrame.Angles(0, math.pi, 0))
		for _, child in inner:GetChildren() do
			if child.Name ~= "Base" then
				child.Parent = model
			end
		end
		inner:Destroy()
	end
end

styles.Shack = function(model, b)
	local w, h, d = b.Size.X, b.Size.Y, b.Size.Z
	local wallH = h * 0.6
	shell(model, w, d, wallH, b.Wall, Enum.Material.WoodPlanks, 5)
	Kit.Roof(model, w, d, 1 + wallH, h - wallH, b.Roof, 1, { Material = Enum.Material.CorrodedMetal })
	Kit.Box(model, Vector3.new(w, 0.6, 5), CFrame.new(0, 1.3, d / 2 + 2.5), C.Plank, { Material = Enum.Material.WoodPlanks })
	Kit.Box(model, Vector3.new(1.2, 1.4, 1.2), CFrame.new(w / 2 - 2, 2.3, d / 2 + 3), C.Wood, { Name = "Barrel" })
end

styles.Tavern = function(model, b)
	local w, h, d = b.Size.X, b.Size.Y, b.Size.Z
	local wallH = h * 0.62
	shell(model, w, d, wallH, b.Wall, Enum.Material.Plaster, 6)
	Kit.Roof(model, w, d, 1 + wallH, h - wallH, b.Roof, 1.2)
	-- Timber framing
	for i = -2, 2 do
		Kit.Box(model, Vector3.new(0.6, wallH, 0.3), CFrame.new(i * w / 5, 1 + wallH / 2, d / 2 + 0.45), C.DarkWood, { Collide = false })
	end
	Kit.Box(model, Vector3.new(w, 0.6, 0.3), CFrame.new(0, 1 + wallH * 0.5, d / 2 + 0.45), C.DarkWood, { Collide = false })
	-- Hanging sign and barrels
	Kit.Box(model, Vector3.new(0.3, 0.3, 3), CFrame.new(w / 2 - 2, wallH * 0.8, d / 2 + 1.5), C.DarkMetal, { Name = "Bracket" })
	local hanging = Kit.Box(model, Vector3.new(0.2, 2, 2.4), CFrame.new(w / 2 - 2, wallH * 0.8 - 1.3, d / 2 + 2.2), C.Plank, { Collide = false, Name = "HangingSign" })
	hanging:SetAttribute("Sway", true)
	for i = 0, 2 do
		Kit.Cyl(model, 2.4, 2, CFrame.new(-w / 2 + 2 + i * 2.2, 1.2, d / 2 + 3), C.Wood, { Material = Enum.Material.Wood, Name = "Barrel" })
	end
end

local function buildBuilding(def: any): (Model, Vector3)
	local model = Kit.Model(def.Id)
	local style = styles[def.Style] or styles.Shop
	style(model, def)
	if def.Sign then
		signBoard(model, def.Sign, def.Size.Y * 0.62 * 0.85 + 1, def.Size.Z / 2 + 0.7, math.min(def.Size.X * 0.6, 16))
	end
	local yaw = math.rad(def.Facing)
	model:PivotTo(CFrame.new(def.Position) * CFrame.Angles(0, yaw, 0))
	model:SetAttribute("Building", def.Id)
	if def.Project then
		model:SetAttribute("Project", def.Project)
	end
	if def.Shop then
		model:SetAttribute("Shop", def.Shop)
	end
	local dir = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	local door = def.Position + dir * (def.Size.Z / 2 + 7)
	return model, door
end

-- Village furniture ---------------------------------------------------------------------------------------------

local function lamp(parent: Instance, position: Vector3)
	local model = Kit.Model("StreetLamp")
	Kit.Cyl(model, 9, 0.6, CFrame.new(0, 4.5, 0), C.DarkMetal, { Material = Enum.Material.Metal })
	local bulb = Kit.Ball(model, Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, 9.2, 0), Color3.fromRGB(255, 225, 160), { Collide = false, Name = "Bulb" })
	bulb:SetAttribute("NightGlow", true)
	local light = Kit.Light(bulb, Color3.fromRGB(255, 210, 150), 22, 1.5, false)
	light:SetAttribute("NightLight", true)
	light.Enabled = false
	model:PivotTo(CFrame.new(position))
	model.Parent = parent
end

local function board(parent: Instance, position: Vector3, yaw: number, kind: string, title: string, action: string)
	local model = Kit.Model(kind .. "Board")
	for _, x in { -2.5, 2.5 } do
		Kit.Box(model, Vector3.new(0.5, 6, 0.5), CFrame.new(x, 3, 0), C.DarkWood)
	end
	local panel = Kit.Box(model, Vector3.new(6, 4, 0.4), CFrame.new(0, 4.5, 0), C.Plank, { Material = Enum.Material.WoodPlanks, Name = "Panel" })
	Kit.Label(panel, title, Enum.NormalId.Back)
	for i = 1, 4 do
		Kit.Box(model, Vector3.new(1.2, 1.4, 0.05), CFrame.new(-2 + (i - 1) * 1.3, 4.3 + (i % 2) * 0.4, 0.25), C.Cream, { Collide = false })
	end
	Kit.Prompt(panel, kind, action, title, 10)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
	model.Parent = parent
end

local function stage(parent: Instance, position: Vector3)
	local model = Kit.Model("FestivalStage")
	Kit.Box(model, Vector3.new(26, 2.4, 12), CFrame.new(0, 1.2, 0), C.Plank, { Material = Enum.Material.WoodPlanks })
	Kit.Box(model, Vector3.new(26, 12, 0.8), CFrame.new(0, 8.4, 6), Color3.fromRGB(150, 50, 60), { Material = Enum.Material.Fabric, Name = "Backdrop" })
	for _, x in { -13, 13 } do
		Kit.Box(model, Vector3.new(1, 14, 1), CFrame.new(x, 7, 6), C.DarkWood)
	end
	for i = 0, 4 do
		Kit.Wedge(model, Vector3.new(26 / 5, 1, 1.2), CFrame.new(-13 + (i + 0.5) * 26 / 5, 1.6, -6.2), C.Plank, { Material = Enum.Material.WoodPlanks })
	end
	local bunting = Kit.Box(model, Vector3.new(26, 0.2, 0.2), CFrame.new(0, 14.2, 5.5), C.Cream, { Collide = false, Name = "Bunting" })
	bunting:SetAttribute("FestivalOnly", true)
	model:SetAttribute("FestivalDecor", true)
	model:PivotTo(CFrame.new(position))
	model.Parent = parent
end

local function cottage(parent: Instance, position: Vector3, facingYaw: number, seed: number, npcName: string): Vector3
	local rng = Random.new(seed)
	local model = Kit.Model("Home")
	local w, d, h = 14, 12, 11
	local walls = { Color3.fromRGB(245, 230, 205), Color3.fromRGB(230, 210, 240), Color3.fromRGB(215, 235, 215), Color3.fromRGB(250, 220, 200), Color3.fromRGB(220, 230, 245) }
	local roofs = { Color3.fromRGB(160, 70, 60), Color3.fromRGB(70, 110, 150), Color3.fromRGB(90, 130, 80), Color3.fromRGB(120, 90, 70), Color3.fromRGB(150, 110, 60) }
	local wall = walls[rng:NextInteger(1, #walls)]
	local roof = roofs[rng:NextInteger(1, #roofs)]
	shell(model, w, d, h * 0.55, wall, Enum.Material.Plaster, 4)
	Kit.Roof(model, w, d, 1 + h * 0.55, h * 0.45, roof, 1)
	-- Garden fence and flowers
	for i = -3, 3 do
		Kit.Ball(model, Vector3.new(0.9, 0.9, 0.9), CFrame.new(i * 1.6, 0.6, d / 2 + 3), Color3.fromHSV(rng:NextNumber(), 0.6, 1), { Collide = false })
	end
	signBoard(model, npcName, 7.4, d / 2 + 0.6, 7)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, facingYaw, 0))
	model.Parent = parent
	return position + Vector3.new(math.sin(facingYaw), 0, math.cos(facingYaw)) * (d / 2 + 5)
end

local function tree(parent: Instance, position: Vector3, seed: number)
	local builder = Models.Builder("DecorTree")
	if not builder then
		return
	end
	local rng = Random.new(seed)
	local model = Kit.Model("Tree")
	local styleNames = { "Round", "Round", "Blossom", "Maple", "Cone" }
	builder(model, 8, 8, rng:NextNumber(12, 18), { Style = styleNames[rng:NextInteger(1, #styleNames)] }, {})
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, 6), 0))
	model.Parent = parent
end

-- Signposts (fast travel) are built for every Travel point, in or out of the village.
function VillageBuilder.Signpost(parent: Instance, travel: any, position: Vector3)
	local model = Kit.Model("Signpost_" .. travel.Id)
	Kit.Box(model, Vector3.new(0.8, 9, 0.8), CFrame.new(0, 4.5, 0), C.DarkWood, { Material = Enum.Material.Wood })
	for i, yaw in { 0.4, -0.6, 1.9 } do
		local arrow = Kit.Box(model, Vector3.new(4.5, 1, 0.3), CFrame.new(0, 8.4 - i * 1.3, 0) * CFrame.Angles(0, yaw, 0) * CFrame.new(1.9, 0, 0), C.Plank, { Material = Enum.Material.WoodPlanks, Collide = false })
		arrow.Name = "Arrow"
	end
	local lanternPart = Kit.Ball(model, Vector3.new(1, 1, 1), CFrame.new(0, 9.4, 0), Color3.fromRGB(150, 220, 255), { Collide = false, Name = "Beacon" })
	Kit.Glow(lanternPart, Color3.fromRGB(150, 220, 255))
	local prompt = Kit.Prompt(lanternPart, "Travel", "Travel", travel.Name, 12)
	prompt:SetAttribute("Target", travel.Id)
	model:SetAttribute("Travel", travel.Id)
	model:PivotTo(CFrame.new(position))
	model.Parent = parent
end

-- Build -------------------------------------------------------------------------------------------------------------

function VillageBuilder.Build(root: Instance): { Doors: { [string]: Vector3 }, Homes: { [string]: Vector3 } }
	local folder = Instance.new("Folder")
	folder.Name = "Village"
	folder.Parent = root

	-- Ground: plaza, ring road already painted by WorldService; paved squares here.
	TerrainKit.PaintDisc(Vector3.new(0, 0, 18), 36, Enum.Material.Cobblestone)
	TerrainKit.PaintDisc(Vector3.new(0, 0, -40), 16, Enum.Material.Cobblestone)
	TerrainKit.PaintDisc(World.Waypoints.Market, 26, Enum.Material.Cobblestone)
	TerrainKit.Lake(Vector3.new(-128, 0, -18), 14, 6, Enum.Material.Sand)

	local doors: { [string]: Vector3 } = {}
	for _, def in World.Buildings do
		local model, door = buildBuilding(def)
		model.Parent = folder
		doors[def.Id] = door
		TerrainKit.PaintStrip(def.Position, door, 6, Enum.Material.Cobblestone)
	end

	-- Plaza: fountain, benches, boards, stage.
	local fountain = Models.Builder("Fountain")
	if fountain then
		local m = Kit.Model("PlazaFountain")
		fountain(m, 14, 14, 10, { Big = true }, {})
		m:PivotTo(CFrame.new(0, 0, -40))
		m.Parent = folder
	end
	board(folder, Vector3.new(16, 0, 26), math.rad(-150), "Board", "Village Requests", "Read")
	board(folder, doors.TownHall + Vector3.new(10, 0, 0), math.rad(180), "Projects", "Town Projects", "Contribute")
	board(folder, doors.Museum + Vector3.new(0, 0, -2), math.rad(135 + 180), "Museum", "Donations", "Donate")
	board(folder, World.Waypoints.Market + Vector3.new(0, 0, -12), 0, "Contracts", "Contracts", "Browse")
	stage(folder, Vector3.new(0, 0, 62))
	local benches = Models.Builder("Bench")
	if benches then
		for i = 0, 5 do
			local a = i * math.pi / 3 + math.pi / 6
			local m = Kit.Model("Bench")
			benches(m, 8, 4, 3, {}, {})
			m:PivotTo(CFrame.new(math.cos(a) * 26, 0, 18 + math.sin(a) * 26) * CFrame.Angles(0, -a - math.pi / 2, 0))
			m.Parent = folder
		end
	end

	-- Street lamps along the ring road and main roads.
	local ring = World.Roads[3]
	for i = 1, #ring - 1 do
		local a, b = ring[i], ring[i + 1]
		for t = 0, 0.99, 0.34 do
			local p = a:Lerp(b, t)
			local outward = Vector3.new(p.X, 0, p.Z).Unit
			lamp(folder, p + outward * 9)
		end
	end
	for _, z in { -270, -210, 90, 150, 250, 320 } do
		lamp(folder, Vector3.new(9, 0, z))
	end

	-- Homes: special ones, then the rest spaced around an outer ring.
	local homes: { [string]: Vector3 } = {}
	local ringIds = {}
	for _, npc in NPCs.List do
		if SPECIAL_HOMES[npc.Id] then
			local p = SPECIAL_HOMES[npc.Id]
			if npc.Id == "wisp" or npc.Id == "luna" then
				homes[npc.Id] = p
			else
				local yaw = math.atan2(-p.X, -p.Z)
				homes[npc.Id] = cottage(folder, p, yaw, #npc.Id * 13, npc.Name)
			end
		else
			table.insert(ringIds, npc)
		end
	end
	local ringRadius = 196
	local slots = {}
	for deg = 12, 348, 12 do
		-- Skip the four road directions and occupied sectors.
		local nearRoad = deg % 90 < 14 or deg % 90 > 76
		if not nearRoad then
			table.insert(slots, deg)
		end
	end
	for i, npc in ringIds do
		local deg = slots[((i - 1) * 3) % #slots + 1]
		local a = math.rad(deg)
		local p = Vector3.new(math.sin(a) * ringRadius, 0, math.cos(a) * ringRadius)
		local yaw = math.atan2(-p.X, -p.Z)
		homes[npc.Id] = cottage(folder, p, yaw, i * 97, npc.Name)
		TerrainKit.PaintStrip(p, p * 0.8, 5, Enum.Material.Ground)
	end

	-- Trees around the village edge (decoration, not choppable).
	for i = 1, 36 do
		local a = i / 36 * math.pi * 2 + 0.05
		local r = 214 + (i % 3) * 7
		local p = Vector3.new(math.sin(a) * r, 0, math.cos(a) * r)
		local deg = math.deg(a) % 90
		if deg > 10 and deg < 80 then
			tree(folder, p, i)
		end
	end

	return { Doors = doors, Homes = homes }
end

return VillageBuilder
