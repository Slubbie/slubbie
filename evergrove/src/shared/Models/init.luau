-- Procedural models. Every placeable, resource node, crop, animal and held tool
-- in Evergrove is built from code so the game ships as plain scripts (no
-- uploaded meshes) and new content only needs a config entry that names a
-- builder plus Params.
--
--   Models.Placeable(def, record?)  → Model   (def from Config/Placeables)
--   Models.Builder(name)            → builder or nil
--   Models.Register(name, builder)  → add a builder at runtime (mods/events)
--
-- Builders have the signature (model, w, d, h, params, def) where w/d are the
-- footprint in studs and h the height; the model's pivot is ground centre.

local Kit = require(script.Kit)

local Models = {}
Models.Kit = Kit

local builders: { [string]: any } = {}

local function merge(source: { [string]: any })
	for name, fn in source do
		if type(fn) == "function" then
			builders[name] = fn
		end
	end
end

merge(require(script.Buildings))
merge(require(script.Machines))
merge(require(script.Automation))
merge(require(script.Decor))

local TILE = 4

function Models.Builder(name: string)
	return builders[name]
end

function Models.Register(name: string, builder: (Model, number, number, number, { [string]: any }, any) -> ())
	builders[name] = builder
end

-- Allowed materials by name (the build menu offers a subset per placeable).
local MATERIALS: { [string]: Enum.Material } = {
	Wood = Enum.Material.Wood,
	WoodPlanks = Enum.Material.WoodPlanks,
	Plastic = Enum.Material.SmoothPlastic,
	Cobblestone = Enum.Material.Cobblestone,
	Brick = Enum.Material.Brick,
	Slate = Enum.Material.Slate,
	Marble = Enum.Material.Marble,
	Granite = Enum.Material.Granite,
	Sandstone = Enum.Material.Sandstone,
	Metal = Enum.Material.Metal,
	Glass = Enum.Material.Glass,
	Fabric = Enum.Material.Fabric,
}
Models.Materials = MATERIALS

function Models.MaterialOf(name: string?): Enum.Material?
	return name and MATERIALS[name] or nil
end

-- Parse a stored colour ("RRGGBB") safely.
function Models.ColorOf(hex: any): Color3?
	if type(hex) ~= "string" or not string.match(hex, "^%x%x%x%x%x%x$") then
		return nil
	end
	local ok, color = pcall(Color3.fromHex, hex)
	return if ok then color else nil
end

-- Scale every part and offset in a model about its pivot.
function Models.Scale(model: Model, factor: number)
	if math.abs(factor - 1) < 1e-3 then
		return
	end
	local ok = pcall(function()
		model:ScaleTo(factor)
	end)
	if ok then
		return
	end
	-- Fallback for engines without Model:ScaleTo.
	local pivot = model:GetPivot()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			d.Size *= factor
			d.CFrame = pivot * (rel - rel.Position + rel.Position * factor)
		elseif d:IsA("PointLight") or d:IsA("SpotLight") then
			d.Range *= factor
		end
	end
end

-- Build a placeable model. `record` (optional) is the saved placed-object
-- table; its colour, material and scale are applied.
function Models.Placeable(def: any, record: any?): Model
	local model = Kit.Model(def.Id)
	local w = def.Size[1] * TILE
	local d = def.Size[2] * TILE
	local h = def.Height or 4
	local builder = builders[def.Model]
	local params = def.Params or {}
	if record and record.Tx and def.Function and def.Function.Kind == "Sign" then
		params = table.clone(params)
		params.Text = record.Tx
	end
	if builder then
		local ok, err = pcall(builder, model, w, d, h, params, def)
		if not ok then
			warn("[Evergrove] Model builder", def.Model, "failed for", def.Id, err)
		end
	else
		warn("[Evergrove] No model builder named", def.Model, "for", def.Id)
		Kit.Box(
			model,
			Vector3.new(w * 0.9, h, d * 0.9),
			CFrame.new(0, h / 2, 0),
			Kit.C.Wood,
			{ Paint = true, Mat = true }
		)
	end
	if record then
		local color = if def.Paint then Models.ColorOf(record.C) else nil
		local material = nil
		if record.Mt and def.Materials and table.find(def.Materials, record.Mt) then
			material = MATERIALS[record.Mt]
		end
		if color or material then
			Kit.Style(model, color, material)
		end
		local scale = tonumber(record.Sc)
		if scale and def.Scale then
			Models.Scale(model, math.clamp(scale, def.Scale[1], def.Scale[2]))
		end
	end
	model:SetAttribute("Placeable", def.Id)
	return model
end

-- A translucent copy for the build-mode ghost preview.
function Models.Ghost(def: any, record: any?): Model
	local model = Models.Placeable(def, record)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			if d.Transparency < 1 then
				d.Transparency = math.max(d.Transparency, 0.45)
			end
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("ProximityPrompt") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	return model
end

return Models
