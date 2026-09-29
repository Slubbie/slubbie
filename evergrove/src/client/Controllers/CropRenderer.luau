-- Renders crops from farm tile parts (workspace.Farms.Lot*.Tiles).
--
-- The server only keeps compact attributes on each tilled tile (crop id C,
-- stage S, ripe R, mutations M, moisture band Wb, affliction Af, dormant Dn,
-- needs-unmet Nm ...). This controller builds the actual plant models locally,
-- within the "Crop Detail Distance" setting, and rebuilds a tile only when an
-- attribute that changes its look changes. Tiles stream in and out with
-- StreamingEnabled, which gives natural level of detail.
--
-- Status icons float over crops that need attention: 💧 dry, 🐛/🍂 pests or
-- blight, ⚠ unmet needs, 💤 dormant (out of season), ✨ ripe.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared.Lib.Registry)
local RNG = require(Shared.Lib.RNG)
local CropModels = require(Shared.Models.Crops)

local C = require(script.Parent)

local CropRenderer = {}

local VISUAL_ATTRS = { "C", "S", "R", "M", "Wb", "Dn", "Af", "Nm", "Pr" }
local ICON_RANGE = 70
local SWAY_RANGE = 55

type Entry = {
	Tile: BasePart,
	Model: Model?,
	Key: string,
	Icon: BillboardGui?,
	Dirty: boolean,
	Base: CFrame?,
	Phase: number,
}

local entries: { [BasePart]: Entry } = {}
local folder: Folder

local function mutationVisuals(list: string?): { any }
	local out = {}
	if not list or list == "" then
		return out
	end
	for id in string.gmatch(list, "[^,]+") do
		local def = Registry.Mutations[id] or Registry.Combos[id]
		if def and def.Visual then
			table.insert(out, def.Visual)
		end
	end
	return out
end

local function signature(tile: BasePart): string
	local parts = {}
	for _, name in VISUAL_ATTRS do
		table.insert(parts, tostring(tile:GetAttribute(name)))
	end
	return table.concat(parts, "|")
end

local function statusIcon(tile: BasePart): string?
	local crop = tile:GetAttribute("C")
	if not crop then
		return nil
	end
	local af = tile:GetAttribute("Af")
	if af == "Pests" then
		return "🐛"
	elseif af == "Blight" then
		return "🍂"
	elseif af then
		return "⚠️"
	end
	if tile:GetAttribute("R") then
		return "✨"
	end
	if tile:GetAttribute("Wb") == 0 then
		return "💧"
	end
	if tile:GetAttribute("Dn") then
		return "💤"
	end
	if tile:GetAttribute("Nm") then
		return "⚠️"
	end
	return nil
end

local function updateIcon(entry: Entry, near: boolean)
	local icon = if near then statusIcon(entry.Tile) else nil
	if not icon then
		if entry.Icon then
			entry.Icon:Destroy()
			entry.Icon = nil
		end
		return
	end
	if not entry.Icon then
		local gui = Instance.new("BillboardGui")
		gui.Name = "CropStatus"
		gui.Size = UDim2.fromOffset(30, 30)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0
		gui.MaxDistance = ICON_RANGE
		local label = Instance.new("TextLabel")
		label.Name = "Icon"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = gui
		gui.Adornee = entry.Tile
		gui.Parent = folder
		entry.Icon = gui
	end
	local label = (entry.Icon :: BillboardGui):FindFirstChild("Icon") :: TextLabel
	label.Text = icon
end

local function rebuild(entry: Entry)
	entry.Dirty = false
	if entry.Model then
		entry.Model:Destroy()
		entry.Model = nil
	end
	local tile = entry.Tile
	local cropId = tile:GetAttribute("C")
	local crop = cropId and Registry.Crops[cropId]
	if not crop then
		return
	end
	local ok, model = pcall(CropModels.Build, crop, tile:GetAttribute("S") or 1, {
		Mutations = mutationVisuals(tile:GetAttribute("M")),
		Dry = tile:GetAttribute("Wb") == 0,
		Dormant = tile:GetAttribute("Dn") == true,
		Seed = RNG.HashInt(tile:GetAttribute("X") or 0, tile:GetAttribute("Z") or 0),
	})
	if not ok then
		warn("[Evergrove] Crop model failed:", cropId, model)
		return
	end
	local rotation = model:GetPivot().Rotation
	local base = CFrame.new(tile.Position + Vector3.new(0, tile.Size.Y / 2, 0)) * rotation
	model:PivotTo(base)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	model.Parent = folder
	entry.Model = model
	entry.Base = base
	-- Pruned crops show a little tie.
	if tile:GetAttribute("Pr") then
		model:SetAttribute("Pruned", true)
	end
end

local function track(tile: Instance)
	if not tile:IsA("BasePart") or entries[tile] then
		return
	end
	local entry: Entry = {
		Tile = tile,
		Model = nil,
		Key = "",
		Icon = nil,
		Dirty = true,
		Base = nil,
		Phase = ((tile:GetAttribute("X") or 0) :: number) * 0.37 + ((tile:GetAttribute("Z") or 0) :: number) * 0.61,
	}
	entries[tile] = entry
	tile.AttributeChanged:Connect(function(name)
		if table.find(VISUAL_ATTRS, name) then
			entry.Dirty = true
		end
	end)
	tile.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if entry.Model then
				entry.Model:Destroy()
			end
			if entry.Icon then
				entry.Icon:Destroy()
			end
			entries[tile] = nil
		end
	end)
end

local function watchLot(lot: Instance)
	local function hook(tiles: Instance)
		for _, tile in tiles:GetChildren() do
			track(tile)
		end
		tiles.ChildAdded:Connect(track)
	end
	local tiles = lot:FindFirstChild("Tiles")
	if tiles then
		hook(tiles)
	end
	lot.ChildAdded:Connect(function(child)
		if child.Name == "Tiles" then
			hook(child)
		end
	end)
end

-- Level of detail and dirty rebuilds, spread across frames.
local function lodPass()
	local camPos = workspace.CurrentCamera.CFrame.Position
	local detail = C.Settings.Get("CropDetail") or 160
	local budget = 40
	for tile, entry in entries do
		local dist = (tile.Position - camPos).Magnitude
		local visible = dist <= detail
		if visible then
			local sig = signature(tile)
			if (entry.Dirty or entry.Key ~= sig or not entry.Model) and tile:GetAttribute("C") and budget > 0 then
				entry.Key = sig
				budget -= 1
				rebuild(entry)
			elseif not tile:GetAttribute("C") and entry.Model then
				entry.Model:Destroy()
				entry.Model = nil
			end
		elseif entry.Model then
			entry.Model:Destroy()
			entry.Model = nil
			entry.Key = ""
		end
		updateIcon(entry, dist <= ICON_RANGE)
	end
end

-- Gentle sway and rainbow hue for nearby crops.
local function animate()
	local camPos = workspace.CurrentCamera.CFrame.Position
	local t = os.clock()
	local weather = C.Lighting.Weather()
	local wind = 0.03
	if weather == "Windy" or weather == "Thunderstorm" or weather == "Sandstorm" then
		wind = 0.12
	elseif weather == "Rain" or weather == "Blizzard" then
		wind = 0.07
	end
	if C.Settings.Get("ReducedMotion") then
		wind *= 0.3
	end
	for tile, entry in entries do
		local model = entry.Model
		if model and entry.Base and (tile.Position - camPos).Magnitude < SWAY_RANGE then
			local sway = math.sin(t * 1.6 + entry.Phase) * wind
			model:PivotTo(entry.Base * CFrame.Angles(sway * 0.6, 0, sway))
			for _, d in model:GetChildren() do
				if d:IsA("BasePart") and d:GetAttribute("HueCycle") then
					d.Color = Color3.fromHSV((t * 0.15 + entry.Phase) % 1, 0.6, 1)
				end
			end
		end
	end
end

-- Current crops near a position (for tooltips and targeting helpers).
function CropRenderer.TileAt(position: Vector3): BasePart?
	local best, bestD = nil, 3
	for tile in entries do
		local d = (Vector3.new(tile.Position.X, 0, tile.Position.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
		if d < bestD and math.abs(tile.Position.Y - position.Y) < 8 then
			best, bestD = tile, d
		end
	end
	return best
end

function CropRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientCrops"
	folder.Parent = workspace
end

function CropRenderer.Start()
	local farms = workspace:WaitForChild("Farms")
	for _, lot in farms:GetChildren() do
		watchLot(lot)
	end
	farms.ChildAdded:Connect(watchLot)
	task.spawn(function()
		while true do
			pcall(lodPass)
			task.wait(0.25)
		end
	end)
	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator >= 1 / 20 then
			accumulator = 0
			pcall(animate)
		end
	end)
end

return CropRenderer
