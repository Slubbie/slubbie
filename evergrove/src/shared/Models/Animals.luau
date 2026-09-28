-- Procedural animal models built from Config/Animals species Model data and
-- the animal's expressed coat and pattern.
--
-- Animals.Build(species, coat, pattern, size, opts) → Model, rig
--   rig = { Root = part, Parts = { { Part, Offset: CFrame, Role } } }
-- Roles: Body, Head, Leg (with Index/Side), Tail, Wing, Ear, Pattern. The
-- client AnimalRenderer poses parts from their offsets every frame (walk
-- cycles, head bobs, tail wags, wing flaps) without physics.

local Kit = require(script.Parent.Kit)

local Animals = {}

local function add(rig: any, model: Model, kind: string, size: Vector3, offset: CFrame, color: Color3, role: string, material: Enum.Material?, extra: { [string]: any }?): BasePart
	local p: BasePart
	if kind == "Ball" then
		p = Kit.Ball(model, size, offset, color, { Collide = false, Name = role })
	elseif kind == "Wedge" then
		p = Kit.Wedge(model, size, offset, color, { Collide = false, Name = role })
	elseif kind == "Cyl" then
		p = Kit.Cyl(model, size.Y, size.X, offset, color, { Collide = false, Name = role })
	else
		p = Kit.Box(model, size, offset, color, { Collide = false, Name = role })
	end
	p.CanQuery = role == "Body" or role == "Head"
	p.Material = material or Enum.Material.SmoothPlastic
	local entry = { Part = p, Offset = p.CFrame, Role = role }
	for k, v in pairs(extra or {}) do
		entry[k] = v
	end
	table.insert(rig.Parts, entry)
	return p
end

function Animals.Build(species: any, coat: any, pattern: any, size: number, opts: { Baby: boolean?, Glow: boolean? }?)
	local o = opts or {}
	local m = species.Model
	local scale = size * (if o.Baby then 0.55 else 1)
	local model = Kit.Model(species.Id)
	local rig = { Root = model.PrimaryPart, Parts = {} }
	local body = m.Body * scale
	local legLength = m.LegLength * scale
	local material = if m.Fluffy then Enum.Material.Fabric elseif m.Shell then Enum.Material.Glass else Enum.Material.SmoothPlastic
	local coatColor = coat.Color
	local darker = coatColor:Lerp(Color3.new(0, 0, 0), 0.25)
	local hover = (m.Hover or 0) * scale
	local bodyY = legLength + body.Y / 2 + hover

	-- Body (fluffy animals get puffs)
	add(rig, model, "Ball", body, CFrame.new(0, bodyY, 0), coatColor, "Body", material)
	if m.Fluffy then
		for i = 1, 5 do
			local a = i * 1.26
			add(rig, model, "Ball", body * 0.55, CFrame.new(math.cos(a) * body.X * 0.3, bodyY + body.Y * 0.2, math.sin(a) * body.Z * 0.3), coatColor:Lerp(Color3.new(1, 1, 1), 0.1), "Body", Enum.Material.Fabric)
		end
	end
	if m.Shell then
		add(rig, model, "Ball", Vector3.new(body.X * 1.1, body.Y * 0.8, body.Z * 1.05), CFrame.new(0, bodyY + body.Y * 0.2, 0), coatColor, "Body", Enum.Material.Glass, nil).Transparency = 0.2
	end

	-- Head
	local headSize = m.Head * scale
	local neck = (m.Neck or 0) * scale
	local headOffset = CFrame.new(0, bodyY + body.Y * 0.35 + neck, -body.Z * 0.5 - headSize * 0.25)
	if neck > 0 then
		add(rig, model, "Box", Vector3.new(headSize * 0.5, neck + headSize * 0.4, headSize * 0.5), CFrame.new(0, bodyY + body.Y * 0.2 + neck / 2, -body.Z * 0.45), coatColor, "Neck", material)
	end
	add(rig, model, "Ball", Vector3.new(headSize, headSize, headSize * 1.05), headOffset, coatColor, "Head", material)
	-- Eyes
	for _, sx in { -1, 1 } do
		add(rig, model, "Ball", Vector3.one * headSize * 0.18, headOffset * CFrame.new(sx * headSize * 0.28, headSize * 0.12, -headSize * 0.45), Color3.fromRGB(25, 20, 20), "Head")
	end
	if m.Beak then
		add(rig, model, "Wedge", Vector3.new(headSize * 0.3, headSize * 0.2, headSize * 0.45), headOffset * CFrame.new(0, -headSize * 0.05, -headSize * 0.62) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(245, 170, 50), "Head")
	else
		add(rig, model, "Ball", Vector3.new(headSize * 0.55, headSize * 0.4, headSize * 0.4), headOffset * CFrame.new(0, -headSize * 0.15, -headSize * 0.45), darker:Lerp(Color3.fromRGB(240, 200, 190), 0.4), "Head")
	end
	-- Ears / horns
	if m.Ears == "Long" then
		for _, sx in { -1, 1 } do
			add(rig, model, "Box", Vector3.new(headSize * 0.18, headSize * 0.9, headSize * 0.1), headOffset * CFrame.new(sx * headSize * 0.2, headSize * 0.8, 0.05) * CFrame.Angles(0, 0, sx * -0.15), coatColor, "Ear", material, { Side = sx })
		end
	elseif m.Ears == "Floppy" then
		for _, sx in { -1, 1 } do
			add(rig, model, "Box", Vector3.new(headSize * 0.15, headSize * 0.45, headSize * 0.3), headOffset * CFrame.new(sx * headSize * 0.52, headSize * 0.05, 0) * CFrame.Angles(0, 0, sx * 0.5), darker, "Ear", material, { Side = sx })
		end
	elseif m.Ears then
		for _, sx in { -1, 1 } do
			add(rig, model, "Wedge", Vector3.new(headSize * 0.12, headSize * 0.35, headSize * 0.25), headOffset * CFrame.new(sx * headSize * 0.32, headSize * 0.5, 0.05), coatColor, "Ear", material, { Side = sx })
		end
	end
	if m.Horns then
		for _, sx in { -1, 1 } do
			add(rig, model, "Wedge", Vector3.new(headSize * 0.12, headSize * 0.45, headSize * 0.12), headOffset * CFrame.new(sx * headSize * 0.28, headSize * 0.6, 0.1) * CFrame.Angles(0, 0, sx * -0.3), Color3.fromRGB(235, 225, 200), "Head")
		end
	end

	-- Legs
	local legs = m.Legs
	if legs > 0 then
		local positions = if legs == 2 then { { -0.25, 0 }, { 0.25, 0 } } else { { -0.32, -0.32 }, { 0.32, -0.32 }, { -0.32, 0.32 }, { 0.32, 0.32 } }
		for i, pos in positions do
			local legWidth = math.max(0.18, body.X * (if legs == 2 then 0.12 else 0.18))
			local color = if legs == 2 then Color3.fromRGB(240, 170, 60) else darker
			local offset = CFrame.new(pos[1] * body.X, hover + legLength / 2, pos[2] * body.Z)
			add(rig, model, "Box", Vector3.new(legWidth, legLength, legWidth), offset, color, "Leg", nil, { Index = i, Pivot = CFrame.new(pos[1] * body.X, hover + legLength, pos[2] * body.Z) })
		end
	end

	-- Wings
	if m.Wings then
		for _, sx in { -1, 1 } do
			add(rig, model, "Wedge", Vector3.new(0.15, body.Y * 0.55, body.Z * 0.6), CFrame.new(sx * body.X * 0.52, bodyY + body.Y * 0.05, 0.05) * CFrame.Angles(0, 0, sx * 0.15), darker, "Wing", material, { Side = sx })
		end
	end

	-- Tail
	local tail = m.Tail
	if tail then
		local tailBase = CFrame.new(0, bodyY + body.Y * 0.15, body.Z * 0.5)
		if tail == "Feather" or tail == "Plume" then
			for i = -1, 1 do
				add(rig, model, "Wedge", Vector3.new(0.12, body.Y * (if tail == "Plume" then 1.1 else 0.6), body.Z * 0.35), tailBase * CFrame.new(i * 0.12, body.Y * 0.3, 0.1) * CFrame.Angles(math.rad(-30), i * 0.3, 0), if tail == "Plume" then coatColor:Lerp(Color3.fromRGB(255, 220, 90), 0.4) else darker, "Tail")
			end
		elseif tail == "Curly" then
			add(rig, model, "Cyl", Vector3.new(0.18 * scale, 0.5 * scale, 0), tailBase * CFrame.new(0, 0.1, 0.2) * CFrame.Angles(math.rad(90), 0, 0), darker:Lerp(Color3.fromRGB(240, 170, 170), 0.5), "Tail")
		elseif tail == "Puff" then
			add(rig, model, "Ball", Vector3.new(0.5, 0.5, 0.5) * scale, tailBase * CFrame.new(0, 0, 0.1), Color3.new(1, 1, 1), "Tail", Enum.Material.Fabric)
		elseif tail == "Long" then
			add(rig, model, "Box", Vector3.new(0.2 * scale, 0.2 * scale, body.Z * 0.7), tailBase * CFrame.new(0, -0.2, body.Z * 0.3) * CFrame.Angles(math.rad(-35), 0, 0), darker, "Tail")
		else
			add(rig, model, "Ball", Vector3.new(0.3, 0.3, 0.3) * scale, tailBase, darker, "Tail")
		end
	end

	-- Pattern overlay
	if pattern and pattern.Id ~= "plain" then
		local rng = Random.new(#pattern.Id * 17)
		local count = if pattern.Id == "starry" then 9 else 6
		for _ = 1, count do
			local p = add(rig, model, "Ball", Vector3.new(body.X * 0.28, body.Y * 0.18, body.Z * 0.24), CFrame.new(rng:NextNumber(-0.35, 0.35) * body.X, bodyY + rng:NextNumber(0.1, 0.45) * body.Y, rng:NextNumber(-0.35, 0.35) * body.Z), pattern.Color, "Pattern")
			if pattern.Id == "starry" then
				p.Material = Enum.Material.Neon
				p.Size = p.Size * 0.4
			end
		end
	end

	-- Legendary glow
	if m.Glow or o.Glow or coat.Rarity == "Legendary" then
		local core = rig.Parts[1].Part
		Kit.Light(core, coatColor, 10, 0.8)
		Kit.Particles(core, "Sparkle", coatColor:Lerp(Color3.new(1, 1, 1), 0.4), 2)
	end
	for _, entry in rig.Parts do
		entry.Part.CastShadow = scale > 0.6
	end
	return model, rig
end

return Animals
