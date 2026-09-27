-- Builds one evaluation room: shell, table, seats, trays, monitors, the Arbiter,
-- lighting and camera marks, then hands off to the environment's dresser in
-- World/Environments/<Id>.luau for its props and spectator space.
--
-- The whole room is one Model with ModelStreamingMode = Atomic, so a client
-- receives it all at once (no half-streamed tables).
--
-- Resulting hierarchy (names the client relies on):
--   Arena_<slot>
--     Shell, Props (models)
--     Table:  Top, Tray_<seat>, Monitor_<seat> (Fx=Integrity), Rack, Spent
--     Seats:  Anchor_<seat> (invisible), Chair_<seat>
--     Arbiter (ArbiterModel)
--     Cameras: Establish1, Establish2, Overhead, Gallery (invisible parts)
--     Puppets (folder for surrogate rigs)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Variance.Visual.Build)
local TableLayout = require(ReplicatedStorage.Variance.Visual.TableLayout)
local ArbiterModel = require(ReplicatedStorage.Variance.Visual.ArbiterModel)
local Environments = require(ReplicatedStorage.Variance.Data.Environments)
local PropKit = require(script.Parent.PropKit)

local ArenaBuilder = {}

ArenaBuilder.RoomSize = Vector3.new(48, 18, 48)

local dressers = {}
for _, module in script.Parent.Environments:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			dressers[module.Name] = result
		else
			warn("[VARIANCE/Arena] dresser " .. module.Name .. " failed to load: " .. tostring(result))
		end
	end
end

local function palette(env)
	local out = {}
	for key, rgb in env.Palette do
		out[key] = Build.rgb(rgb)
	end
	return out
end

local function buildShell(model: Model, origin: CFrame, env, colors)
	local shell = Build.model("Shell", model)
	local size = ArenaBuilder.RoomSize
	local mats = env.Materials
	local hx, hz = size.X / 2, size.Z / 2
	Build.solid(
		shell,
		Vector3.new(size.X, 1, size.Z),
		origin * CFrame.new(0, -0.5, 0),
		colors.Floor,
		mats.Floor,
		"Floor"
	)
	Build.solid(
		shell,
		Vector3.new(size.X, 1, size.Z),
		origin * CFrame.new(0, size.Y + 0.5, 0),
		colors.Ceiling,
		mats.Ceiling,
		"Ceiling"
	)
	Build.solid(
		shell,
		Vector3.new(size.X, size.Y, 1),
		origin * CFrame.new(0, size.Y / 2, -hz - 0.5),
		colors.Wall,
		mats.Wall,
		"WallN"
	)
	Build.solid(
		shell,
		Vector3.new(size.X, size.Y, 1),
		origin * CFrame.new(0, size.Y / 2, hz + 0.5),
		colors.Wall,
		mats.Wall,
		"WallS"
	)
	Build.solid(
		shell,
		Vector3.new(1, size.Y, size.Z),
		origin * CFrame.new(hx + 0.5, size.Y / 2, 0),
		colors.Wall,
		mats.Wall,
		"WallE"
	)
	Build.solid(
		shell,
		Vector3.new(1, size.Y, size.Z),
		origin * CFrame.new(-hx - 0.5, size.Y / 2, 0),
		colors.Wall,
		mats.Wall,
		"WallW"
	)
	-- Skirting and ceiling trim in the accent colour.
	for _, spec in
		{
			{ Vector3.new(size.X, 0.5, 0.2), CFrame.new(0, 0.25, -hz + 0.1) },
			{ Vector3.new(size.X, 0.5, 0.2), CFrame.new(0, 0.25, hz - 0.1) },
			{ Vector3.new(0.2, 0.5, size.Z), CFrame.new(hx - 0.1, 0.25, 0) },
			{ Vector3.new(0.2, 0.5, size.Z), CFrame.new(-hx + 0.1, 0.25, 0) },
		}
	do
		Build.box(shell, spec[1], origin * spec[2], colors.Trim, mats.Trim, "Skirting")
	end
	return shell
end

-- Replaces one wall with four pieces around a rectangular opening.
-- side: "N" | "S" | "E" | "W"; u = centre along the wall, v = centre height.
local function cutWall(shell: Instance, origin: CFrame, side: string, u: number, v: number, w: number, h: number)
	local wall = shell:FindFirstChild("Wall" .. side) :: BasePart?
	if wall == nil then
		return
	end
	local size = ArenaBuilder.RoomSize
	local color, mat = wall.Color, wall.Material
	wall:Destroy()
	local length = (side == "N" or side == "S") and size.X or size.Z
	local half = length / 2
	local function piece(a0: number, a1: number, b0: number, b1: number)
		if a1 - a0 <= 0.01 or b1 - b0 <= 0.01 then
			return
		end
		local cu, cv = (a0 + a1) / 2, (b0 + b1) / 2
		local su, sv = a1 - a0, b1 - b0
		local cf, sz
		if side == "N" then
			cf, sz = CFrame.new(cu, cv, -size.Z / 2 - 0.5), Vector3.new(su, sv, 1)
		elseif side == "S" then
			cf, sz = CFrame.new(cu, cv, size.Z / 2 + 0.5), Vector3.new(su, sv, 1)
		elseif side == "E" then
			cf, sz = CFrame.new(size.X / 2 + 0.5, cv, cu), Vector3.new(1, sv, su)
		else
			cf, sz = CFrame.new(-size.X / 2 - 0.5, cv, cu), Vector3.new(1, sv, su)
		end
		Build.solid(shell, sz, origin * cf, color, mat, "Wall" .. side)
	end
	local u0, u1 = u - w / 2, u + w / 2
	local v0, v1 = v - h / 2, v + h / 2
	piece(-half, u0, 0, size.Y)
	piece(u1, half, 0, size.Y)
	piece(u0, u1, 0, v0)
	piece(u0, u1, v1, size.Y)
end

local function buildChair(parent: Instance, origin: CFrame, seat: number, colors)
	local chair = Build.model("Chair_" .. seat, parent)
	local base = origin * TableLayout.seatCFrame(seat) * CFrame.new(0, 0, 0.25)
	local h = TableLayout.SeatHeight
	Build.box(chair, Vector3.new(2.3, 0.25, 2.1), base * CFrame.new(0, h - 0.125, 0), colors.Prop, "Metal", "Pan")
	Build.box(
		chair,
		Vector3.new(2.3, 3.4, 0.25),
		base * CFrame.new(0, h + 1.6, 1.05) * CFrame.Angles(math.rad(-6), 0, 0),
		colors.Prop,
		"Metal",
		"Back"
	)
	for _, x in { -1, 1 } do
		for _, z in { -0.9, 0.9 } do
			Build.box(
				chair,
				Vector3.new(0.18, h - 0.25, 0.18),
				base * CFrame.new(x, (h - 0.25) / 2, z),
				Color3.fromRGB(40, 40, 42),
				"Metal",
				"Leg"
			)
		end
		-- Armrests with harness straps: the subject is wired to the Arbiter's circuit.
		Build.box(
			chair,
			Vector3.new(0.3, 0.2, 1.8),
			base * CFrame.new(x * 1.2, h + 0.95, 0.05),
			colors.Prop,
			"Metal",
			"Arm"
		)
		Build.box(
			chair,
			Vector3.new(0.34, 0.24, 0.3),
			base * CFrame.new(x * 1.2, h + 1.0, -0.4),
			Color3.fromRGB(28, 28, 30),
			"Leather",
			"Strap"
		)
	end
	-- Harness cable from the chair back toward the table leg.
	PropKit.pipe(
		chair,
		(base * CFrame.new(0.9, 0.5, 1.2)).Position,
		(origin * CFrame.new(TableLayout.direction(seat) * 3.6 + Vector3.new(0.6, 0.2, 0))).Position,
		0.12,
		Color3.fromRGB(35, 35, 38)
	)
	Build.ghost(chair)
	return chair
end

local function buildTable(model: Model, origin: CFrame, seats: { number }, colors, look)
	local tableModel = Build.model("Table", model)
	local top = TableLayout.TableTop
	local size = TableLayout.TableSize
	local topColor = look and Build.rgb(look.Top, colors.Prop) or colors.Prop
	local trimColor = look and Build.rgb(look.Trim, colors.Trim) or colors.Trim
	local topMaterial = look and look.Material or "DiamondPlate"
	local tableTop =
		Build.solid(tableModel, size, origin * CFrame.new(0, top - size.Y / 2, 0), topColor, topMaterial, "Top")
	tableTop:SetAttribute("Paint", "TableTop")
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			Build.box(
				tableModel,
				Vector3.new(0.5, top - 0.3, 0.5),
				origin * CFrame.new(x * 3.8, (top - 0.3) / 2, z * 3.8),
				Color3.fromRGB(34, 34, 36),
				"Metal",
				"Leg"
			)
		end
	end
	local rim = 0.2
	for _, spec in
		{
			{ Vector3.new(size.X + rim * 2, 0.34, rim), CFrame.new(0, top - 0.15, size.Z / 2 + rim / 2) },
			{ Vector3.new(size.X + rim * 2, 0.34, rim), CFrame.new(0, top - 0.15, -size.Z / 2 - rim / 2) },
			{ Vector3.new(rim, 0.34, size.Z), CFrame.new(size.X / 2 + rim / 2, top - 0.15, 0) },
			{ Vector3.new(rim, 0.34, size.Z), CFrame.new(-size.X / 2 - rim / 2, top - 0.15, 0) },
		}
	do
		local p = Build.box(tableModel, spec[1], origin * spec[2], trimColor, "Metal", "Rim")
		p:SetAttribute("Paint", "TableTrim")
	end
	-- Centre plate under the Arbiter.
	Build.box(
		tableModel,
		Vector3.new(5.2, 0.04, 1.6),
		origin * CFrame.new(0.35, top + 0.02, 0),
		Color3.fromRGB(20, 20, 22),
		"Metal",
		"CentrePlate"
	)
	-- Cell rack and spent-cell tray.
	local rack = Build.box(
		tableModel,
		Vector3.new(3.1, 0.12, 0.62),
		origin * TableLayout.rackCFrame(),
		Color3.fromRGB(28, 29, 31),
		"Metal",
		"Rack"
	)
	Build.neon(
		tableModel,
		Vector3.new(3.1, 0.03, 0.05),
		origin * TableLayout.rackCFrame() * CFrame.new(0, 0.07, 0.28),
		trimColor,
		"RackStrip"
	)
	rack:SetAttribute("Fx", "Rack")
	Build.box(
		tableModel,
		Vector3.new(1.4, 0.1, 1.0),
		origin * TableLayout.spentCFrame(),
		Color3.fromRGB(24, 24, 26),
		"Metal",
		"Spent"
	)
	for _, seat in seats do
		local tray = Build.box(
			tableModel,
			Vector3.new(5.6, 0.05, 2.0),
			origin * TableLayout.trayCFrame(seat) * CFrame.new(0, 0.025, -0.05),
			Color3.fromRGB(22, 23, 25),
			"SmoothPlastic",
			"Tray_" .. seat
		)
		tray:SetAttribute("Seat", seat)
		-- Integrity monitor: two screens, one facing the subject, one facing the table.
		local monitor = Build.box(
			tableModel,
			Vector3.new(1.5, 0.95, 0.3),
			origin * TableLayout.monitorCFrame(seat),
			Color3.fromRGB(40, 41, 43),
			"Metal",
			"Monitor_" .. seat
		)
		Build.fx(monitor, "Integrity", { Seat = seat })
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local gui = Instance.new("SurfaceGui")
			gui.Name = face == Enum.NormalId.Front and "Owner" or "Public"
			gui.Face = face
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 80
			gui.LightInfluence = 0
			gui.Brightness = 1.6
			gui.Parent = monitor
		end
		local stand = Build.box(
			tableModel,
			Vector3.new(0.3, 0.45, 0.3),
			origin * TableLayout.monitorCFrame(seat) * CFrame.new(0, -0.62, 0.1),
			Color3.fromRGB(34, 34, 36),
			"Metal",
			"MonitorStand"
		)
		stand.CastShadow = false
	end
	return tableModel
end

-- Builds a room. `seats` are physical seat indices (TableLayout.seatsFor).
-- `look` is the table-theme cosmetic data (optional).
function ArenaBuilder.build(
	slot: number,
	origin: CFrame,
	envId: string,
	seats: { number },
	look: { [string]: any }?
): Model
	local env = Environments.get(envId)
	local colors = palette(env)
	local model = Instance.new("Model")
	model.Name = "Arena_" .. slot
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	model:SetAttribute("Environment", env.Id)
	model:SetAttribute("Slot", slot)
	model:SetAttribute("Origin", origin)

	buildShell(model, origin, env, colors)
	buildTable(model, origin, seats, colors, look)

	local seatFolder = Build.folder("Seats", model)
	for _, seat in seats do
		local anchor = Build.part({
			Name = "Anchor_" .. seat,
			Size = Vector3.new(1, 1, 1),
			CFrame = origin * TableLayout.rootCFrame(seat),
			Transparency = 1,
			CastShadow = false,
			Parent = seatFolder,
		})
		anchor:SetAttribute("Seat", seat)
		buildChair(seatFolder, origin, seat, colors)
	end

	local device = ArbiterModel.build(origin * TableLayout.deviceRest())
	device.Parent = model
	Build.ghost(device)

	-- Key light over the table and soft fills (colours from the environment).
	local lighting = env.Lighting
	local keyMount = Build.part({
		Name = "KeyMount",
		Size = Vector3.new(0.5, 0.5, 0.5),
		CFrame = origin * CFrame.new(0, 12.5, 0),
		Transparency = 1,
		CastShadow = false,
		Parent = model,
	})
	local key = Build.spotLight(
		keyMount,
		Build.rgb(lighting.Key.Color),
		lighting.Key.Brightness,
		lighting.Key.Range + 4,
		62,
		Enum.NormalId.Bottom,
		true
	)
	key.Name = "Light"
	Build.fx(keyMount, "Key", { BaseBrightness = lighting.Key.Brightness })
	for i, pos in { Vector3.new(14, 11, 14), Vector3.new(-14, 11, -14) } do
		local fill = Build.part({
			Name = "Fill" .. i,
			Size = Vector3.new(0.5, 0.5, 0.5),
			CFrame = origin * CFrame.new(pos),
			Transparency = 1,
			CastShadow = false,
			Parent = model,
		})
		local light =
			Build.pointLight(fill, Build.rgb(lighting.Fill.Color), lighting.Fill.Brightness, lighting.Fill.Range, false)
		light.Name = "Light"
		Build.fx(fill, "Fill", { BaseBrightness = lighting.Fill.Brightness })
	end

	local cameras = Build.folder("Cameras", model)
	local function mark(name: string, cf: CFrame)
		Build.part({
			Name = name,
			Size = Vector3.one,
			CFrame = cf,
			Transparency = 1,
			CastShadow = false,
			Parent = cameras,
		})
	end
	local centre = (origin * CFrame.new(0, TableLayout.TableTop, 0)).Position
	mark("Establish1", CFrame.lookAt((origin * CFrame.new(-17, 12, 17)).Position, centre))
	mark("Establish2", CFrame.lookAt((origin * CFrame.new(12, 4.2, -6)).Position, centre + Vector3.new(0, 0.5, 0)))
	mark("Overhead", CFrame.lookAt((origin * CFrame.new(0, 15, 0.01)).Position, centre))
	mark("Gallery", CFrame.lookAt((origin * CFrame.new(-19, 9, 0)).Position, centre))

	Build.folder("Puppets", model)
	local props = Build.model("Props", model)

	local dresser = dressers[env.Id]
	if dresser then
		local ctx = {
			Model = props,
			Arena = model,
			Origin = origin,
			Env = env,
			Colors = colors,
			Seats = seats,
			Size = ArenaBuilder.RoomSize,
			at = function(x: number, y: number, z: number, rot: CFrame?)
				return origin * CFrame.new(x, y, z) * (rot or CFrame.identity)
			end,
			cut = function(side: string, u: number, v: number, w: number, h: number)
				cutWall(model:FindFirstChild("Shell"), origin, side, u, v, w, h)
			end,
		}
		local ok, err = pcall(dresser.dress, ctx)
		if not ok then
			warn("[VARIANCE/Arena] dressing " .. env.Id .. " failed: " .. tostring(err))
		end
	end
	return model
end

-- Applies a table-theme cosmetic to an existing arena's table.
function ArenaBuilder.applyTableTheme(arena: Model, data: { [string]: any }?)
	if arena == nil or data == nil then
		return
	end
	local tableModel = arena:FindFirstChild("Table")
	if tableModel == nil then
		return
	end
	for _, d in tableModel:GetDescendants() do
		if d:IsA("BasePart") then
			local paint = d:GetAttribute("Paint")
			if paint == "TableTop" then
				d.Color = Build.rgb(data.Top, d.Color)
				d.Material = Build.material(data.Material or "DiamondPlate")
			elseif paint == "TableTrim" then
				d.Color = Build.rgb(data.Trim, d.Color)
			end
		end
	end
end

return ArenaBuilder
