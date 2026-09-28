-- Builds the six farm lots and dresses them for their owners.
--
-- Lot-local coordinates (studs, origin at the field's north-west corner on the
-- ground): X east 0..240, Z south 0..240 are the 5×5 parcels; the yard strip
-- Z -44..0 holds the farmhouse, shipping bin, well, workbench, mailbox and the
-- farm sign by the gate (the gate faces the Homestead Row road).
--
-- BuildLot returns (model, info) where info = { House, Bin, Well, Workbench,
-- Mailbox, Reserved } (world positions and reserved tile keys).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)
local Land = require(Shared.Config.Land)
local Kit = require(Shared.Models.Kit)
local TerrainKit = require(script.Parent.TerrainKit)

local C = Kit.C
local TILE = World.Farms.TileSize
local PARCEL = World.Farms.ParcelTiles
local PARCELS = World.Farms.Parcels
local GRID = PARCEL * PARCELS
local SIZE = GRID * TILE
local YARD = World.Farms.YardDepth

local FarmBuilder = {}

-- Yard layout (lot-local studs).
local LAYOUT = {
	House = Vector3.new(60, 0, -22),
	Bin = Vector3.new(150, 0, -12),
	Well = Vector3.new(104, 0, -12),
	Workbench = Vector3.new(178, 0, -24),
	Mailbox = Vector3.new(132, 0, -40),
	Sign = Vector3.new(108, 0, -41),
	Gate = Vector3.new(SIZE / 2, 0, -YARD),
}
FarmBuilder.Layout = LAYOUT

local HOUSE_SIZE = {
	{ 20, 16, 12 }, -- Cabin
	{ 24, 18, 14 }, -- Cottage
	{ 30, 22, 20 }, -- Farmhouse
	{ 36, 24, 24 }, -- Manor
	{ 42, 28, 28 }, -- Estate
}

local function localCF(origin: Vector3, p: Vector3, yaw: number?): CFrame
	return CFrame.new(origin + p) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

-- Reserved tile keys for a rectangle (lot-local studs, centre + size), with a margin.
local function reserve(out: { [string]: boolean }, center: Vector3, w: number, d: number, margin: number)
	local x0 = math.floor((center.X - w / 2 - margin) / TILE)
	local x1 = math.floor((center.X + w / 2 + margin) / TILE)
	local z0 = math.floor((center.Z - d / 2 - margin) / TILE)
	local z1 = math.floor((center.Z + d / 2 + margin) / TILE)
	for gx = x0, x1 do
		for gz = z0, z1 do
			out[gx .. "_" .. gz] = true
		end
	end
end

-- Farmhouse --------------------------------------------------------------------------------------------------

local SKINS = {
	Default = { Wall = Color3.fromRGB(236, 222, 196), Trim = Color3.fromRGB(120, 80, 50), Roof = Color3.fromRGB(150, 60, 50), Door = Color3.fromRGB(110, 70, 40), Material = Enum.Material.WoodPlanks },
	farmhouse_cottage = { Wall = Color3.fromRGB(250, 236, 214), Trim = Color3.fromRGB(150, 190, 150), Roof = Color3.fromRGB(205, 170, 95), Door = Color3.fromRGB(120, 170, 140), Material = Enum.Material.Plaster, Thatch = true },
	farmhouse_celestial = { Wall = Color3.fromRGB(40, 48, 90), Trim = Color3.fromRGB(200, 190, 255), Roof = Color3.fromRGB(28, 30, 60), Door = Color3.fromRGB(90, 80, 160), Material = Enum.Material.SmoothPlastic, Stars = true },
}

local function buildHouse(level: number, skinId: string?): Model
	local skin = SKINS[skinId or "Default"] or SKINS.Default
	local size = HOUSE_SIZE[math.clamp(level, 1, #HOUSE_SIZE)]
	local w, d, h = size[1], size[2], size[3]
	local model = Kit.Model("Farmhouse")
	local wallH = if level >= 3 then h * 0.62 else h * 0.55
	local wallMat = if level == 1 then Enum.Material.Wood else skin.Material
	local t = 0.8
	-- Foundation and floor
	Kit.Box(model, Vector3.new(w + 2, 1, d + 2), CFrame.new(0, 0.5, 0), C.Stone, { Material = Enum.Material.Cobblestone })
	-- Walls (door faces -Z, toward the gate)
	Kit.Box(model, Vector3.new(w, wallH, t), CFrame.new(0, 1 + wallH / 2, d / 2), skin.Wall, { Material = wallMat })
	Kit.Box(model, Vector3.new(t, wallH, d), CFrame.new(-w / 2, 1 + wallH / 2, 0), skin.Wall, { Material = wallMat })
	Kit.Box(model, Vector3.new(t, wallH, d), CFrame.new(w / 2, 1 + wallH / 2, 0), skin.Wall, { Material = wallMat })
	local doorW = 5
	local side = (w - doorW) / 2
	Kit.Box(model, Vector3.new(side, wallH, t), CFrame.new(-w / 2 + side / 2, 1 + wallH / 2, -d / 2), skin.Wall, { Material = wallMat })
	Kit.Box(model, Vector3.new(side, wallH, t), CFrame.new(w / 2 - side / 2, 1 + wallH / 2, -d / 2), skin.Wall, { Material = wallMat })
	Kit.Box(model, Vector3.new(doorW, wallH - 7, t), CFrame.new(0, 1 + 7 + (wallH - 7) / 2, -d / 2), skin.Wall, { Material = wallMat })
	local door = Kit.Box(model, Vector3.new(doorW - 0.6, 7, 0.4), CFrame.new(0, 4.5, -d / 2 - 0.2), skin.Door, { Material = Enum.Material.Wood, Name = "Door" })
	Kit.Ball(model, Vector3.new(0.4, 0.4, 0.4), CFrame.new(1.6, 4.5, -d / 2 - 0.5), C.Gold, { Collide = false })
	-- Corner trim
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.Box(model, Vector3.new(1, wallH, 1), CFrame.new(sx * w / 2, 1 + wallH / 2, sz * d / 2), skin.Trim, { Material = Enum.Material.Wood })
		end
	end
	-- Windows with warm light at night (client toggles "NightGlow").
	local windows = math.max(1, math.floor(w / 9))
	for i = 1, windows do
		local x = -w / 2 + (i - 0.5) * (w / windows)
		if math.abs(x) > doorW then
			local win = Kit.Box(model, Vector3.new(3, 3, 0.3), CFrame.new(x, 1 + wallH * 0.55, -d / 2 - 0.35), Color3.fromRGB(255, 230, 170), { Material = Enum.Material.Glass, Transparency = 0.2, Collide = false, Name = "Window" })
			win:SetAttribute("NightGlow", true)
			Kit.Box(model, Vector3.new(3.8, 0.4, 0.6), CFrame.new(x, 1 + wallH * 0.55 - 1.7, -d / 2 - 0.45), skin.Trim, { Collide = false })
			-- Flower box
			Kit.Box(model, Vector3.new(3.4, 0.8, 0.8), CFrame.new(x, 1 + wallH * 0.55 - 2.3, -d / 2 - 0.8), C.Wood, { Collide = false })
			for f = -1, 1 do
				Kit.Ball(model, Vector3.new(0.7, 0.7, 0.7), CFrame.new(x + f, 1 + wallH * 0.55 - 1.8, -d / 2 - 0.8), Color3.fromHSV(((i * 3 + f) % 7) / 7, 0.6, 1), { Collide = false })
			end
		end
	end
	-- Roof
	local roofColor = skin.Roof
	Kit.Roof(model, w, d, 1 + wallH, h - wallH, roofColor, 1.5, { Material = if skin.Thatch then Enum.Material.Fabric else Enum.Material.Slate })
	-- Chimney with smoke
	local chimney = Kit.Box(model, Vector3.new(2.5, h * 0.5, 2.5), CFrame.new(w * 0.28, 1 + wallH + (h - wallH) * 0.55, d * 0.15), C.DarkStone, { Material = Enum.Material.Brick })
	Kit.Particles(chimney, "Smoke", Color3.fromRGB(220, 220, 220), 2)
	-- Level extras
	if level >= 2 then
		-- Porch
		Kit.Box(model, Vector3.new(w * 0.6, 0.6, 5), CFrame.new(0, 1.2, -d / 2 - 2.5), C.Plank, { Material = Enum.Material.WoodPlanks })
		Kit.Wedge(model, Vector3.new(w * 0.6, 1.6, 4), CFrame.new(0, wallH * 0.75, -d / 2 - 2.2) * CFrame.Angles(0, math.rad(180), 0), roofColor, { Collide = false })
		for _, sx in { -1, 1 } do
			Kit.Box(model, Vector3.new(0.6, wallH * 0.7, 0.6), CFrame.new(sx * w * 0.28, wallH * 0.37, -d / 2 - 4.5), skin.Trim, { Material = Enum.Material.Wood })
		end
	end
	if level >= 3 then
		-- Second-floor windows and a balcony rail
		for _, sx in { -1, 1 } do
			local win = Kit.Box(model, Vector3.new(3, 2.6, 0.3), CFrame.new(sx * w * 0.25, 1 + wallH * 0.85, -d / 2 - 0.35), Color3.fromRGB(255, 230, 170), { Material = Enum.Material.Glass, Transparency = 0.2, Collide = false, Name = "Window" })
			win:SetAttribute("NightGlow", true)
		end
	end
	if level >= 4 then
		-- Side wings
		for _, sx in { -1, 1 } do
			local wingX = sx * (w / 2 + 4)
			Kit.Box(model, Vector3.new(8, wallH * 0.8, d * 0.6), CFrame.new(wingX, 1 + wallH * 0.4, d * 0.1), skin.Wall, { Material = wallMat })
			Kit.Box(model, Vector3.new(9, 0.8, d * 0.6 + 1), CFrame.new(wingX, 1 + wallH * 0.8 + 0.4, d * 0.1), roofColor, { Material = Enum.Material.Slate })
			local win = Kit.Box(model, Vector3.new(3, 3, 0.3), CFrame.new(wingX, 1 + wallH * 0.45, d * 0.1 - d * 0.3 - 0.2), Color3.fromRGB(255, 230, 170), { Material = Enum.Material.Glass, Transparency = 0.2, Collide = false, Name = "Window" })
			win:SetAttribute("NightGlow", true)
		end
	end
	if level >= 5 then
		-- Towers with flags
		for _, sx in { -1, 1 } do
			Kit.Cyl(model, h + 6, 6, CFrame.new(sx * (w / 2 + 2), (h + 6) / 2, -d / 2 + 2), skin.Wall, { Material = wallMat })
			local cone = Kit.Cyl(model, 6, 7, CFrame.new(sx * (w / 2 + 2), h + 9, -d / 2 + 2), roofColor, { Material = Enum.Material.Slate })
			cone.Shape = Enum.PartType.Ball
			Kit.Box(model, Vector3.new(0.2, 4, 0.2), CFrame.new(sx * (w / 2 + 2), h + 14, -d / 2 + 2), C.DarkMetal)
			Kit.Box(model, Vector3.new(0.1, 1.4, 2.4), CFrame.new(sx * (w / 2 + 2), h + 15.2, -d / 2 + 3.2), Color3.fromRGB(80, 150, 90), { Collide = false })
		end
	end
	if skin.Stars then
		for i = 1, 8 do
			local star = Kit.Ball(model, Vector3.new(0.5, 0.5, 0.5), CFrame.new(-w / 2 + i * w / 9, 1 + wallH + 0.8, -d / 2 - 1.2), Color3.fromRGB(255, 240, 180), { Collide = false })
			Kit.Glow(star, Color3.fromRGB(255, 240, 180))
		end
	end
	local prompt = Kit.Prompt(door, "House", "Enter", "Farmhouse", 12)
	prompt:SetAttribute("Level", level)
	model:SetAttribute("Level", level)
	return model
end

-- Yard fixtures ---------------------------------------------------------------------------------------------------

local function buildBin(): Model
	local model = Kit.Model("ShippingBin")
	local body = Kit.Box(model, Vector3.new(6, 3.2, 4), CFrame.new(0, 1.6, 0), Color3.fromRGB(140, 95, 60), { Material = Enum.Material.WoodPlanks, Name = "Body" })
	Kit.Box(model, Vector3.new(6.4, 0.4, 4.4), CFrame.new(0, 3.4, -0.3) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(110, 70, 45), { Name = "Lid" })
	for _, x in { -2.6, 2.6 } do
		Kit.Box(model, Vector3.new(0.4, 3.3, 4.1), CFrame.new(x, 1.65, 0), C.DarkMetal, { Material = Enum.Material.Metal })
	end
	local label = Kit.Box(model, Vector3.new(4, 1.2, 0.1), CFrame.new(0, 2, -2.05), C.Cream, { Collide = false })
	Kit.Label(label, "SHIPPING", Enum.NormalId.Front)
	Kit.Prompt(body, "Bin", "Ship", "Shipping Bin", 10)
	return model
end

local function buildWell(): Model
	local model = Kit.Model("Well")
	Kit.Cyl(model, 3, 6, CFrame.new(0, 1.5, 0), C.Stone, { Material = Enum.Material.Cobblestone })
	local water = Kit.Cyl(model, 0.2, 4.8, CFrame.new(0, 2.4, 0), C.Water, { Material = Enum.Material.Glass, Transparency = 0.2, Collide = false, Name = "Water" })
	water:SetAttribute("Water", "Well")
	for _, x in { -2.6, 2.6 } do
		Kit.Box(model, Vector3.new(0.6, 5, 0.6), CFrame.new(x, 5, 0), C.Wood, { Material = Enum.Material.Wood })
	end
	Kit.Roof(model, 6, 4, 7.3, 1.8, C.Red, 0.4)
	Kit.CylFlat(model, 5, 0.6, CFrame.new(0, 6.5, 0), C.DarkWood, "X")
	Kit.Box(model, Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 4.6, 0), C.Wood, { Name = "Bucket" })
	Kit.Prompt(water, "Water", "Refill", "Well", 10):SetAttribute("Water", "Well")
	return model
end

local function buildWorkbench(): Model
	local model = Kit.Model("Workbench")
	local top = Kit.Box(model, Vector3.new(7, 0.6, 3.2), CFrame.new(0, 3.2, 0), C.Plank, { Material = Enum.Material.WoodPlanks, Name = "Top" })
	for _, x in { -3, 3 } do
		for _, z in { -1.2, 1.2 } do
			Kit.Box(model, Vector3.new(0.6, 3, 0.6), CFrame.new(x, 1.5, z), C.DarkWood)
		end
	end
	Kit.Box(model, Vector3.new(1.6, 0.8, 0.8), CFrame.new(-2, 3.9, 0), C.DarkMetal, { Name = "Vise" })
	Kit.Box(model, Vector3.new(0.3, 0.3, 2), CFrame.new(1.5, 3.65, 0.4) * CFrame.Angles(0, 0.5, 0), C.Metal)
	Kit.Box(model, Vector3.new(7, 3, 0.3), CFrame.new(0, 5, 1.6), C.Wood, { Name = "Pegboard" })
	local prompt = Kit.Prompt(top, "Station", "Craft", "Workbench", 10)
	prompt:SetAttribute("Station", "Workbench")
	return model
end

local function buildMailbox(): Model
	local model = Kit.Model("Mailbox")
	Kit.Box(model, Vector3.new(0.5, 3.5, 0.5), CFrame.new(0, 1.75, 0), C.DarkWood)
	local box = Kit.Box(model, Vector3.new(1.6, 1.4, 2.4), CFrame.new(0, 4, 0), Color3.fromRGB(60, 110, 170), { Name = "Box" })
	local flag = Kit.Box(model, Vector3.new(0.1, 1, 0.4), CFrame.new(0.85, 4.6, 0.6), C.Red, { Collide = false, Name = "Flag" })
	flag:SetAttribute("Flag", true)
	Kit.Prompt(box, "Mail", "Mail", "Mailbox", 10)
	return model
end

local function buildSign(): (Model, TextLabel)
	local model = Kit.Model("FarmSign")
	for _, x in { -3.5, 3.5 } do
		Kit.Box(model, Vector3.new(0.6, 6, 0.6), CFrame.new(x, 3, 0), C.DarkWood, { Material = Enum.Material.Wood })
	end
	local board = Kit.Box(model, Vector3.new(8, 2.6, 0.4), CFrame.new(0, 5, 0), C.Plank, { Material = Enum.Material.WoodPlanks, Name = "Board" })
	local label = Kit.Label(board, "Available", Enum.NormalId.Front)
	Kit.Prompt(board, "FarmSign", "Farm", "Farm Office", 10)
	return model, label
end

local function buildGateAndFence(model: Model, origin: Vector3)
	local fenceColor = Color3.fromRGB(235, 225, 205)
	local function run(a: Vector3, b: Vector3)
		local length = (b - a).Magnitude
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(origin + mid + Vector3.new(0, 1.8, 0), origin + b + Vector3.new(0, 1.8, 0))
		Kit.Box(model, Vector3.new(0.3, 0.4, length), cf, fenceColor, { Name = "Rail" })
		Kit.Box(model, Vector3.new(0.3, 0.4, length), cf * CFrame.new(0, -1, 0), fenceColor, { Name = "Rail" })
		local posts = math.floor(length / 8)
		for i = 0, posts do
			local p = a:Lerp(b, i / math.max(1, posts))
			Kit.Box(model, Vector3.new(0.6, 3, 0.6), CFrame.new(origin + p + Vector3.new(0, 1.5, 0)), fenceColor, { Name = "Post" })
		end
	end
	local gateHalf = 8
	-- Front (yard edge) with a gap for the gate
	run(Vector3.new(0, 0, -YARD), Vector3.new(SIZE / 2 - gateHalf, 0, -YARD))
	run(Vector3.new(SIZE / 2 + gateHalf, 0, -YARD), Vector3.new(SIZE, 0, -YARD))
	-- Sides and back
	run(Vector3.new(0, 0, -YARD), Vector3.new(0, 0, SIZE))
	run(Vector3.new(SIZE, 0, -YARD), Vector3.new(SIZE, 0, SIZE))
	run(Vector3.new(0, 0, SIZE), Vector3.new(SIZE, 0, SIZE))
	-- Gate arch
	for _, x in { -gateHalf, gateHalf } do
		Kit.Box(model, Vector3.new(1, 9, 1), CFrame.new(origin + Vector3.new(SIZE / 2 + x, 4.5, -YARD)), C.DarkWood, { Material = Enum.Material.Wood })
	end
	Kit.Box(model, Vector3.new(gateHalf * 2 + 2, 1, 1), CFrame.new(origin + Vector3.new(SIZE / 2, 9, -YARD)), C.DarkWood, { Material = Enum.Material.Wood })
end

-- Lots -------------------------------------------------------------------------------------------------------------

function FarmBuilder.BuildLot(lotDef: any, root: Instance): (Model, any)
	local origin: Vector3 = lotDef.Origin
	local model = Instance.new("Model")
	model.Name = "Lot" .. lotDef.Id
	model:SetAttribute("Lot", lotDef.Id)
	model.Parent = root

	-- Ground: tidy yard dirt path to the house and gravel in front.
	TerrainKit.PaintStrip(origin + Vector3.new(SIZE / 2, 0, -YARD), origin + Vector3.new(SIZE / 2, 0, -4), 8, Enum.Material.Ground)
	TerrainKit.PaintStrip(origin + Vector3.new(SIZE / 2, 0, -24), origin + LAYOUT.House + Vector3.new(0, 0, -12), 6, Enum.Material.Ground)
	-- Parcel ponds (Riverside) as real water so fishing and can refills work.
	for row = 1, PARCELS do
		for col = 1, PARCELS do
			local ptype = Land.Types[Land.Layout[row][col]]
			if ptype and ptype.Water then
				local x0 = ((col - 1) * PARCEL + 4) * TILE
				local z0 = ((row - 1) * PARCEL + 4) * TILE
				local center = origin + Vector3.new(x0 + 2 * TILE, 0, z0 + 1.5 * TILE)
				workspace.Terrain:FillBlock(CFrame.new(center.X, -3, center.Z), Vector3.new(4 * TILE, 6, 3 * TILE), Enum.Material.Water)
				workspace.Terrain:FillBlock(CFrame.new(center.X, -7, center.Z), Vector3.new(4 * TILE + 4, 2, 3 * TILE + 4), Enum.Material.Mud)
			end
		end
	end

	local static = Instance.new("Folder")
	static.Name = "Static"
	static.Parent = model
	local fence = Instance.new("Model")
	fence.Name = "Fence"
	fence.Parent = static
	buildGateAndFence(fence, origin)

	local function place(builder: () -> Model, key: string, yaw: number?)
		local m = builder()
		m:PivotTo(localCF(origin, LAYOUT[key], yaw))
		m.Parent = static
		return m
	end
	place(buildBin, "Bin")
	place(buildWell, "Well")
	place(buildWorkbench, "Workbench")
	place(buildMailbox, "Mailbox")
	local sign, label = buildSign()
	sign:PivotTo(localCF(origin, LAYOUT.Sign, 180))
	sign.Parent = static
	label:SetAttribute("FarmLabel", true)

	local house = buildHouse(1)
	house:PivotTo(localCF(origin, LAYOUT.House, 180))
	house.Parent = model

	local reserved = {}
	local houseSize = HOUSE_SIZE[#HOUSE_SIZE]
	reserve(reserved, LAYOUT.House, houseSize[1] + 16, houseSize[2] + 10, 2)
	reserve(reserved, LAYOUT.Bin, 6, 4, 2)
	reserve(reserved, LAYOUT.Well, 6, 6, 2)
	reserve(reserved, LAYOUT.Workbench, 7, 4, 2)
	reserve(reserved, LAYOUT.Mailbox, 2, 2, 2)
	reserve(reserved, LAYOUT.Sign, 8, 1, 2)
	-- Keep the walkway from the gate clear.
	reserve(reserved, Vector3.new(SIZE / 2, 0, -YARD / 2), 8, YARD, 0)

	local parcels = Instance.new("Folder")
	parcels.Name = "Parcels"
	parcels.Parent = model

	return model, {
		House = origin + LAYOUT.House,
		Bin = origin + LAYOUT.Bin,
		Well = origin + LAYOUT.Well,
		Workbench = origin + LAYOUT.Workbench,
		Mailbox = origin + LAYOUT.Mailbox,
		Reserved = reserved,
		HouseModel = house,
		SignLabel = label,
	}
end

-- Unowned parcels show overgrowth and a For Sale sign; owned ones are tidy.
function FarmBuilder.UpdateParcels(farm: any, profile: any?)
	local folder = farm.Model:FindFirstChild("Parcels")
	if not folder then
		return
	end
	folder:ClearAllChildren()
	for row = 1, PARCELS do
		for col = 1, PARCELS do
			local key = row .. "_" .. col
			local owned = profile ~= nil and profile.Farm.Parcels[key] == true
			if not owned then
				local ptype = Land.Types[Land.Layout[row][col]]
				local parcel = Instance.new("Model")
				parcel.Name = key
				local x0 = (col - 1) * PARCEL * TILE
				local z0 = (row - 1) * PARCEL * TILE
				local center = farm.Origin + Vector3.new(x0 + PARCEL * TILE / 2, 0, z0 + PARCEL * TILE / 2)
				-- Overgrowth tufts (visual, walk-through)
				local rng = Random.new(row * 31 + col * 7)
				for _ = 1, 7 do
					local p = center + Vector3.new(rng:NextNumber(-20, 20), 0, rng:NextNumber(-20, 20))
					local tuft = Kit.Wedge(parcel, Vector3.new(0.3, rng:NextNumber(1.5, 3), 1.2), CFrame.new(p + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color3.fromRGB(110, 160, 70), { Collide = false })
					tuft:SetAttribute("Foliage", true)
				end
				-- Sale sign
				local post = Kit.Box(parcel, Vector3.new(0.4, 4, 0.4), CFrame.new(center + Vector3.new(0, 2, 0)), C.DarkWood, { Collide = false })
				local board = Kit.Box(parcel, Vector3.new(4, 2.2, 0.3), CFrame.new(center + Vector3.new(0, 4.2, 0)) * CFrame.Angles(0, math.pi, 0), C.Cream, { Name = "SaleSign" })
				Kit.Label(board, ptype.Icon .. " For Sale", Enum.NormalId.Front)
				local prompt = Kit.Prompt(board, "Parcel", "Buy Land", ptype.Name, 14)
				prompt:SetAttribute("Target", key)
				prompt:SetAttribute("Owner", farm.Owner and farm.Owner.UserId or 0)
				post:SetAttribute("Parcel", key)
				parcel:SetAttribute("Parcel", key)
				parcel:SetAttribute("Type", ptype.Id)
				parcel.Parent = folder
			end
		end
	end
end

local function skinFor(profile: any?): string?
	if profile and profile.Cosmetics and profile.Cosmetics.Equipped then
		return profile.Cosmetics.Equipped.House
	end
	return nil
end

function FarmBuilder.UpdateHouse(farm: any, level: number, profile: any?)
	local old = farm.Lot.HouseModel
	if old then
		old:Destroy()
	end
	local house = buildHouse(level, skinFor(profile))
	house:PivotTo(localCF(farm.Origin, LAYOUT.House, 180))
	house.Parent = farm.Model
	farm.Lot.HouseModel = house
end

function FarmBuilder.UpdateSign(farm: any, name: string)
	local label = farm.Lot.SignLabel
	if label then
		label.Text = name
	end
end

function FarmBuilder.ApplyOwner(farm: any, profile: any, player: Player)
	local name = if profile.Farm.Name ~= "" then profile.Farm.Name else player.DisplayName .. "'s Farm"
	FarmBuilder.UpdateSign(farm, name)
	FarmBuilder.UpdateHouse(farm, profile.Farm.House, profile)
	FarmBuilder.UpdateParcels(farm, profile)
end

-- The owner left: back to an empty, available lot.
function FarmBuilder.Clear(farm: any)
	FarmBuilder.UpdateSign(farm, "Available")
	FarmBuilder.UpdateHouse(farm, 1, nil)
	local folder = farm.Model:FindFirstChild("Parcels")
	if folder then
		folder:ClearAllChildren()
	end
	local nodes = farm.Model:FindFirstChild("Nodes")
	if nodes then
		nodes:Destroy()
	end
end

return FarmBuilder
