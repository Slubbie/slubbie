-- THE GILDED ROOM ("BACKROOM"): a decaying luxury casino backroom.
-- Velvet walls, a failing chandelier, card tables, dead slot machines, a
-- roulette wheel, a bar, and a roped-off lounge (spectator space).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Variance.Visual.Build)
local PropKit = require(script.Parent.Parent.PropKit)

local Dresser = {}

local GOLD = Color3.fromRGB(200, 160, 80)
local FELT = Color3.fromRGB(26, 70, 48)

local function cardTable(m: Instance, at: CFrame)
	local model = Build.model("CardTable", m)
	Build.column(model, 0.3, 7, at * CFrame.new(0, 2.7, 0), FELT, "Fabric", "Top")
	Build.column(model, 0.35, 7.4, at * CFrame.new(0, 2.55, 0), Color3.fromRGB(60, 34, 20), "Wood", "Rim")
	Build.column(model, 2.4, 0.8, at * CFrame.new(0, 1.2, 0), Color3.fromRGB(40, 24, 14), "Wood", "Pedestal")
	for i = 0, 5 do
		local a = i * math.pi / 3
		Build.column(model, 0.08 + (i % 3) * 0.08, 0.45, at * CFrame.new(math.cos(a) * 2, 2.9 + (i % 3) * 0.04, math.sin(a) * 2), i % 2 == 0 and Color3.fromRGB(200, 40, 40) or Color3.fromRGB(220, 220, 210), "SmoothPlastic", "Chips")
	end
	for i = 0, 3 do
		Build.box(model, Vector3.new(0.5, 0.02, 0.7), at * CFrame.new(-1 + i * 0.6, 2.87, -0.8) * CFrame.Angles(0, i * 0.3, 0), Color3.fromRGB(240, 236, 226), "SmoothPlastic", "Card")
	end
	return model
end

local function slotMachine(m: Instance, at: CFrame)
	local model = Build.model("SlotMachine", m)
	Build.box(model, Vector3.new(2.6, 5, 2), at * CFrame.new(0, 2.5, 0), Color3.fromRGB(90, 24, 30), "SmoothPlastic", "Cabinet")
	Build.box(model, Vector3.new(2.7, 0.3, 2.1), at * CFrame.new(0, 5.1, 0), GOLD, "Foil", "Crown")
	PropKit.monitor(model, at * CFrame.new(0, 3.3, -0.6), Vector3.new(2, 1.3, 0.6), "INSERT COIN", Color3.fromRGB(255, 200, 120))
	Build.cylinder(model, 1.6, 0.14, at * CFrame.new(1.45, 3.4, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, "Metal", "Lever")
	Build.ball(model, 0.4, at * CFrame.new(1.45, 4.3, 0), Color3.fromRGB(200, 30, 30), "SmoothPlastic", "Knob")
	return model
end

function Dresser.dress(ctx)
	local m = ctx.Model
	local at = ctx.at

	-- Wainscoting, gold rails and damask-ish panels.
	for _, spec in {
		{ Vector3.new(46, 4, 0.3), at(0, 2, -23.3) },
		{ Vector3.new(46, 4, 0.3), at(0, 2, 23.3) },
		{ Vector3.new(0.3, 4, 46), at(23.3, 2, 0) },
		{ Vector3.new(0.3, 4, 46), at(-23.3, 2, 0) },
	} do
		Build.box(m, spec[1], spec[2], Color3.fromRGB(50, 26, 16), "Wood", "Wainscot")
	end
	for _, spec in {
		{ Vector3.new(46, 0.25, 0.4), at(0, 4.1, -23.2) },
		{ Vector3.new(46, 0.25, 0.4), at(0, 4.1, 23.2) },
		{ Vector3.new(0.4, 0.25, 46), at(23.2, 4.1, 0) },
		{ Vector3.new(0.4, 0.25, 46), at(-23.2, 4.1, 0) },
	} do
		Build.box(m, spec[1], spec[2], GOLD, "Foil", "Rail")
	end
	-- Carpet medallion under the table.
	Build.column(m, 0.04, 17, at(0, 0.02, 0), Color3.fromRGB(70, 20, 24), "Carpet", "Medallion")
	Build.column(m, 0.05, 15.5, at(0, 0.03, 0), Color3.fromRGB(46, 14, 18), "Carpet", "MedallionInner")
	for i = 0, 11 do
		local a = i * math.pi / 6
		Build.box(m, Vector3.new(0.3, 0.06, 2), at(math.cos(a) * 7.8, 0.04, math.sin(a) * 7.8) * CFrame.Angles(0, -a, 0), GOLD, "Foil", "MedallionRay")
	end

	-- The chandelier (its light flickers as the room decays).
	local top = at(0, 18, 0)
	Build.cylinder(m, 3, 0.1, top * CFrame.new(0, -1.5, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, "Metal", "Chain")
	Build.cylinder(m, 0.3, 5, top * CFrame.new(0, -3.2, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, "Foil", "Ring")
	Build.cylinder(m, 0.3, 3, top * CFrame.new(0, -4.2, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, "Foil", "Ring")
	for i = 0, 11 do
		local a = i * math.pi / 6
		local r = i % 2 == 0 and 2.4 or 1.4
		local y = i % 2 == 0 and -3.6 or -4.6
		local crystal = Build.ball(m, 0.35, top * CFrame.new(math.cos(a) * r, y, math.sin(a) * r), Color3.fromRGB(255, 240, 220), "Glass", "Crystal")
		crystal.Transparency = 0.3
		crystal.CastShadow = false
	end
	local candle = Build.ball(m, 0.8, top * CFrame.new(0, -4.6, 0), Color3.fromRGB(255, 214, 150), "Neon", "Glow")
	candle.CastShadow = false
	local glow = Build.pointLight(candle, Color3.fromRGB(255, 205, 140), 1.3, 22, true)
	glow.Name = "Light"
	Build.fx(candle, "Flicker", { BaseBrightness = 1.3 })

	-- Card tables, slot machines, roulette.
	cardTable(m, at(-15, 0, -14))
	cardTable(m, at(15, 0, 15))
	for i = -3, 3 do
		slotMachine(m, at(i * 3.2, 0, -21.5, CFrame.Angles(0, math.pi, 0)))
	end
	local wheelBase = at(16, 0, -14)
	Build.box(m, Vector3.new(5, 2.8, 5), wheelBase * CFrame.new(0, 1.4, 0), Color3.fromRGB(50, 30, 18), "Wood", "RouletteTable")
	local wheel = Build.cylinder(m, 0.4, 4, wheelBase * CFrame.new(0, 3.0, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(80, 20, 20), "Wood", "Wheel")
	local wheelModel = Build.model("Roulette", m)
	wheel.Parent = wheelModel
	for i = 0, 7 do
		local seg = Build.box(wheelModel, Vector3.new(0.3, 0.1, 1.6), wheelBase * CFrame.new(0, 3.22, 0) * CFrame.Angles(0, i * math.pi / 4, 0) * CFrame.new(0, 0, -1.05), i % 2 == 0 and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(170, 20, 20), "SmoothPlastic", "Segment")
		seg:SetAttribute("Rest", (wheelBase * CFrame.new(0, 3.0, 0)):ToObjectSpace(seg.CFrame))
	end
	wheel:SetAttribute("Rest", (wheelBase * CFrame.new(0, 3.0, 0)):ToObjectSpace(wheel.CFrame))
	Build.fx(wheelModel, "Spin", { Speed = 0.25, Pivot = wheelBase * CFrame.new(0, 3.0, 0), Axis = "Y" })

	-- The bar along the east wall.
	Build.solid(m, Vector3.new(3, 3.6, 18), at(20.5, 1.8, 4), Color3.fromRGB(56, 30, 18), "Wood", "Bar")
	Build.box(m, Vector3.new(3.2, 0.2, 18.2), at(20.5, 3.7, 4), GOLD, "Foil", "BarTop")
	for i = 0, 11 do
		local bottle = Build.column(m, 1.1, 0.35, at(23, 5 + (i % 2) * 1.8, -4 + i * 1.5), i % 3 == 0 and Color3.fromRGB(40, 90, 50) or Color3.fromRGB(120, 60, 20), "Glass", "Bottle")
		bottle.Transparency = 0.3
	end
	Build.box(m, Vector3.new(0.4, 0.2, 18), at(23.2, 4.4, 4), Color3.fromRGB(56, 30, 18), "Wood", "Shelf")
	Build.box(m, Vector3.new(0.4, 0.2, 18), at(23.2, 6.2, 4), Color3.fromRGB(56, 30, 18), "Wood", "Shelf")

	-- Velvet-rope lounge on the west side (spectator space).
	for z = -10, 10, 4 do
		Build.column(m, 3, 0.35, at(-14, 1.5, z), GOLD, "Foil", "Stanchion")
		Build.ball(m, 0.5, at(-14, 3.1, z), GOLD, "Foil", "StanchionTop")
		if z < 10 then
			Build.cylinder(m, 4, 0.2, at(-14, 2.5, z + 2) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(140, 20, 30), "Fabric", "Rope")
		end
	end
	for i, z in { -6, 2 } do
		local couch = at(-19.5, 0, z)
		Build.box(m, Vector3.new(3, 1.6, 6), couch * CFrame.new(0, 0.8, 0), Color3.fromRGB(90, 20, 28), "Fabric", "Couch")
		Build.box(m, Vector3.new(1, 3, 6), couch * CFrame.new(-1.5, 1.5, 0), Color3.fromRGB(80, 18, 26), "Fabric", "CouchBack")
		local s = PropKit.silhouette(m, couch * CFrame.new(0.2, 0, i == 1 and -1 or 1) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(10, 6, 6))
		s.Name = "Guest" .. i
	end

	-- Portraits in heavy frames.
	for i, x in { -12, -4, 4, 12 } do
		local frame = at(x, 9.5, 23.3)
		Build.box(m, Vector3.new(4.4, 5.4, 0.3), frame, GOLD, "Foil", "Frame")
		Build.box(m, Vector3.new(3.8, 4.8, 0.35), frame, Color3.fromRGB(26 + i * 4, 18, 14), "SmoothPlastic", "Canvas")
		local face = Build.ball(m, 1.6, frame * CFrame.new(0, 0.7, -0.2), Color3.fromRGB(60, 44, 36), "SmoothPlastic", "Sitter")
		face.Size = Vector3.new(1.4, 1.8, 0.3)
	end

	PropKit.sign(m, at(0, 13, -23.2, CFrame.Angles(0, math.pi, 0)), Vector2.new(9, 1.6), "THE GILDED ROOM", Color3.fromRGB(30, 10, 12), GOLD, Enum.Font.Fondamento)
	PropKit.cctv(m, at(22.5, 15, 22.5, CFrame.Angles(0, math.rad(45), 0) * CFrame.Angles(math.rad(-25), 0, 0)))
	PropKit.speaker(m, at(-22.8, 12, 16, CFrame.Angles(0, -math.pi / 2, 0)))
	PropKit.vent(m, at(-10, 17.6, 12, CFrame.Angles(-math.pi / 2, 0, 0)), Vector2.new(3, 3))
	PropKit.beacon(m, at(-22.8, 15, -16, CFrame.Angles(0, 0, -math.pi / 2)), Color3.fromRGB(255, 80, 60))
	-- Haze: slow drifting smoke near the ceiling.
	local haze = Build.part({ Name = "Haze", Size = Vector3.new(30, 1, 30), CFrame = at(0, 14, 0), Transparency = 1, Parent = m })
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Haze"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate = 1.2
	smoke.Lifetime = NumberRange.new(12, 18)
	smoke.Speed = NumberRange.new(0.3, 0.8)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 12) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.88), NumberSequenceKeypoint.new(1, 1) })
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 170, 140))
	smoke.LightInfluence = 1
	smoke.Parent = haze
	Build.fx(haze, "Haze")
end

return Dresser
