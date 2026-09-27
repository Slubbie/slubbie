-- THE INTAKE: Halden Decision Sciences, Sublevel 0. The lobby every subject
-- walks through between Trials.
--
-- Terminals are ProximityPrompts with a "Terminal" attribute; the client opens
-- the matching screen (the HUD menu offers every terminal too, so nothing is
-- only reachable by walking). Boards with Fx attributes are filled in by the
-- server (leaderboards, live trials) or the client (personal clearance wall,
-- locker showcase).
--
--   Terminal values: Play, Solo, Private, Ranked, Locker, Practice, Tutorial,
--                    Archive, Challenges, Spectate, Record

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Variance.Visual.Build)
local ArbiterModel = require(ReplicatedStorage.Variance.Visual.ArbiterModel)
local PropKit = require(script.Parent.PropKit)
local PuppetBuilder = require(script.Parent.PuppetBuilder)
local Personalities = require(ReplicatedStorage.Variance.Core.AI.Personalities)

local LobbyBuilder = {}

local HALL = Vector3.new(124, 26, 96)
local WALL = Color3.fromRGB(176, 178, 170)
local WALL_LOW = Color3.fromRGB(82, 96, 86) -- institutional green
local FLOOR_A = Color3.fromRGB(150, 146, 136)
local FLOOR_B = Color3.fromRGB(120, 116, 108)
local TRIM = Color3.fromRGB(232, 163, 61)
local DARK = Color3.fromRGB(30, 31, 34)
local BONE = Color3.fromRGB(230, 226, 214)

local function prompt(parent: Instance, terminal: string, action: string, object: string, extra: { [string]: any }?)
	local p = Instance.new("ProximityPrompt")
	p.Name = "Prompt"
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = 11
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p:SetAttribute("Terminal", terminal)
	if extra then
		for k, v in extra do
			p:SetAttribute(k, v)
		end
	end
	p.Parent = parent
	return p
end

-- A kiosk terminal with a slanted screen facing local -Z.
local function kiosk(
	parent: Instance,
	at: CFrame,
	title: string,
	terminal: string,
	action: string,
	accent: Color3,
	extra: { [string]: any }?
)
	local model = Build.model("Terminal_" .. terminal, parent)
	Build.solid(
		model,
		Vector3.new(3.2, 3.4, 1.6),
		at * CFrame.new(0, 1.7, 0),
		Color3.fromRGB(60, 64, 62),
		"Metal",
		"Body"
	)
	local screen = Build.box(
		model,
		Vector3.new(2.8, 1.9, 0.2),
		at * CFrame.new(0, 4.1, -0.3) * CFrame.Angles(math.rad(-18), 0, 0),
		Color3.fromRGB(8, 12, 12),
		"Glass",
		"Screen"
	)
	Build.label(
		screen,
		Enum.NormalId.Front,
		title,
		accent,
		{ Font = Enum.Font.Michroma, PixelsPerStud = 60, Brightness = 1.6 }
	)
	Build.box(
		model,
		Vector3.new(3.0, 2.1, 0.25),
		at * CFrame.new(0, 4.1, -0.2) * CFrame.Angles(math.rad(-18), 0, 0),
		DARK,
		"Metal",
		"Bezel"
	)
	Build.neon(model, Vector3.new(3.24, 0.08, 0.08), at * CFrame.new(0, 3.42, -0.8), accent, "Strip")
	local glow = Build.pointLight(screen, accent, 0.9, 10, false)
	glow.Name = "Glow"
	Build.fx(screen, "Flicker", { BaseBrightness = 0.9, Soft = true })
	prompt(model:FindFirstChild("Body"), terminal, action, title, extra)
	return model
end

local function hall(model: Model)
	local shell = Build.model("Shell", model)
	local hx, hz = HALL.X / 2, HALL.Z / 2
	-- Checkerboard terrazzo floor.
	for x = 0, 7 do
		for z = 0, 5 do
			local size = Vector3.new(HALL.X / 8, 1, HALL.Z / 6)
			local cx = -hx + size.X * (x + 0.5)
			local cz = -hz + size.Z * (z + 0.5)
			Build.solid(
				shell,
				size,
				CFrame.new(cx, -0.5, cz),
				((x + z) % 2 == 0) and FLOOR_A or FLOOR_B,
				"Slate",
				"Floor"
			)
		end
	end
	Build.solid(
		shell,
		Vector3.new(HALL.X, 1, HALL.Z),
		CFrame.new(0, HALL.Y + 0.5, 0),
		Color3.fromRGB(120, 122, 118),
		"Concrete",
		"Ceiling"
	)
	for _, spec in
		{
			{ Vector3.new(HALL.X, HALL.Y, 1), CFrame.new(0, HALL.Y / 2, -hz - 0.5) },
			{ Vector3.new(HALL.X, HALL.Y, 1), CFrame.new(0, HALL.Y / 2, hz + 0.5) },
			{ Vector3.new(1, HALL.Y, HALL.Z), CFrame.new(hx + 0.5, HALL.Y / 2, 0) },
			{ Vector3.new(1, HALL.Y, HALL.Z), CFrame.new(-hx - 0.5, HALL.Y / 2, 0) },
		}
	do
		Build.solid(shell, spec[1], spec[2], WALL, "Concrete", "Wall")
	end
	-- Two-tone walls: green dado band with an amber stripe.
	for _, spec in
		{
			{ Vector3.new(HALL.X, 6, 0.3), CFrame.new(0, 3, -hz + 0.15) },
			{ Vector3.new(HALL.X, 6, 0.3), CFrame.new(0, 3, hz - 0.15) },
			{ Vector3.new(0.3, 6, HALL.Z), CFrame.new(hx - 0.15, 3, 0) },
			{ Vector3.new(0.3, 6, HALL.Z), CFrame.new(-hx + 0.15, 3, 0) },
		}
	do
		Build.box(shell, spec[1], spec[2], WALL_LOW, "SmoothPlastic", "Dado")
		Build.box(
			shell,
			spec[1] * Vector3.new(1, 0, 1) + Vector3.new(0, 0.3, 0.05),
			spec[2] * CFrame.new(0, 3.15, 0),
			TRIM,
			"SmoothPlastic",
			"Stripe"
		)
	end
	-- Pillars.
	for _, x in { -40, -20, 20, 40 } do
		for _, z in { -24, 24 } do
			Build.solid(
				shell,
				Vector3.new(3, HALL.Y, 3),
				CFrame.new(x, HALL.Y / 2, z),
				Color3.fromRGB(160, 162, 156),
				"Concrete",
				"Pillar"
			)
			Build.box(shell, Vector3.new(3.2, 0.4, 3.2), CFrame.new(x, 6.2, z), TRIM, "SmoothPlastic", "PillarBand")
		end
	end
	-- Ceiling light strips (some flicker).
	for i, x in { -45, -30, -15, 0, 15, 30, 45 } do
		for j, z in { -30, -10, 10, 30 } do
			local strip = Build.box(
				shell,
				Vector3.new(8, 0.3, 1.2),
				CFrame.new(x, HALL.Y - 0.2, z),
				Color3.fromRGB(245, 240, 225),
				"Neon",
				"LightStrip"
			)
			strip.CastShadow = false
			local light = Build.pointLight(strip, Color3.fromRGB(255, 240, 215), 0.7, 26, (i + j) % 3 == 0)
			light.Name = "Light"
			if (i * 3 + j) % 5 == 0 then
				Build.fx(strip, "Flicker", { BaseBrightness = 0.7, Ambient = true })
			end
		end
	end
	return shell
end

local function sculpture(model: Model)
	-- The Probability Engine: nested rings turning at different rates over a plinth.
	local base = CFrame.new(0, 0, 0)
	Build.solid(
		model,
		Vector3.new(16, 1.2, 16),
		base * CFrame.new(0, 0.6, 0),
		Color3.fromRGB(90, 92, 88),
		"Marble",
		"Plinth"
	)
	Build.column(model, 1.3, 15, base * CFrame.new(0, 0.6, 0), Color3.fromRGB(96, 98, 94), "Marble", "PlinthRound")
	Build.neon(model, Vector3.new(15.2, 0.1, 0.3), base * CFrame.new(0, 1.26, 0), TRIM, "PlinthGlow")
	for i, spec in { { 11, 0.6, 0.35 }, { 8.4, -0.8, 0.5 }, { 6, 1.1, 0.7 } } do
		local ring = Build.model("Ring" .. i, model)
		local pivot = base * CFrame.new(0, 12, 0)
		local segments = 18
		for s = 0, segments - 1 do
			local a = s * (math.pi * 2 / segments)
			local seg = Build.box(
				ring,
				Vector3.new(0.6, 0.6, spec[1] * math.sin(math.pi / segments) * 2 + 0.1),
				pivot * CFrame.Angles(0, a, 0) * CFrame.new(spec[1], 0, 0),
				s % 6 == 0 and TRIM or Color3.fromRGB(200, 200, 195),
				s % 6 == 0 and "Neon" or "Metal",
				"Segment"
			)
			seg:SetAttribute("Rest", pivot:ToObjectSpace(seg.CFrame))
		end
		Build.fx(ring, "Spin", { Speed = spec[3], Pivot = pivot * CFrame.Angles(spec[2], 0, i * 0.4), Axis = "Y" })
	end
	-- A single oversized cell suspended in the middle.
	local core =
		Build.column(model, 3.2, 1.4, base * CFrame.new(0, 12, 0), Color3.fromRGB(58, 34, 30), "Metal", "CoreCell")
	core.CastShadow = false
	Build.neon(
		model,
		Vector3.new(1.46, 0.3, 1.46),
		base * CFrame.new(0, 12.6, 0),
		Color3.fromRGB(224, 72, 47),
		"CoreBand"
	)
	local glow = Build.pointLight(core, TRIM, 1.2, 30, false)
	glow.Name = "Light"
	PropKit.sign(
		model,
		base * CFrame.new(0, 2.6, 8.2) * CFrame.Angles(0, math.pi, 0),
		Vector2.new(9, 1.2),
		"CHANCE IS A MEASUREMENT",
		Color3.fromRGB(40, 42, 40),
		BONE
	)
end

local function surrogateGallery(model: Model)
	local wing = Build.model("SurrogateGallery", model)
	PropKit.sign(
		wing,
		CFrame.new(-61.5, 16, 0) * CFrame.Angles(0, -math.pi / 2, 0),
		Vector2.new(22, 2.4),
		"SURROGATE PROGRAMME",
		DARK,
		TRIM
	)
	local list = Personalities.selectable(true)
	for i, persona in list do
		local z = -26 + (i - 1) * 13
		local at = CFrame.new(-54, 0, z) * CFrame.Angles(0, -math.pi / 2, 0) -- faces +X (into the hall)
		local case = Build.model("Case_" .. persona.Id, wing)
		Build.solid(
			case,
			Vector3.new(8, 1.2, 8),
			at * CFrame.new(0, 0.6, 0),
			Color3.fromRGB(40, 42, 44),
			"Metal",
			"Base"
		)
		Build.solid(case, Vector3.new(8, 1, 8), at * CFrame.new(0, 11.5, 0), Color3.fromRGB(40, 42, 44), "Metal", "Top")
		for _, off in
			{
				Vector3.new(-3.9, 6, -3.9),
				Vector3.new(3.9, 6, -3.9),
				Vector3.new(-3.9, 6, 3.9),
				Vector3.new(3.9, 6, 3.9),
			}
		do
			Build.box(
				case,
				Vector3.new(0.3, 10, 0.3),
				at * CFrame.new(off),
				Color3.fromRGB(60, 62, 64),
				"Metal",
				"Post"
			)
		end
		local glass = Build.part({
			Name = "Glass",
			Size = Vector3.new(7.6, 10, 0.2),
			CFrame = at * CFrame.new(0, 6, -3.9),
			Color = Color3.fromRGB(190, 210, 215),
			Material = "Glass",
			Transparency = persona.Secret and 0.15 or 0.75,
			CanCollide = true,
			Parent = case,
		})
		glass.CastShadow = false
		local spot = Build.part({
			Name = "CaseLight",
			Size = Vector3.one,
			CFrame = at * CFrame.new(0, 11, 0),
			Transparency = 1,
			Parent = case,
		})
		Build.spotLight(
			spot,
			persona.Secret and Color3.fromRGB(255, 60, 50) or Color3.fromRGB(255, 236, 210),
			2.2,
			14,
			50,
			Enum.NormalId.Bottom,
			true
		)
		-- The surrogate itself, standing (the client adds idle breathing).
		local puppet = PuppetBuilder.build(persona.Id, at * CFrame.new(0, 4.2, 0), "Display_" .. persona.Id)
		puppet:SetAttribute("Display", true)
		puppet:SetAttribute("Secret", persona.Secret)
		puppet.Parent = case
		local plaque = Build.box(
			case,
			Vector3.new(6, 1.4, 0.2),
			at * CFrame.new(0, 1.6, -4.15),
			Color3.fromRGB(26, 28, 30),
			"Metal",
			"Plaque"
		)
		local text = persona.Secret and "SURROGATE ?? :: ACCESS RESTRICTED"
			or string.format("%s  ::  %s", persona.Name, string.upper(persona.Epithet))
		Build.label(
			plaque,
			Enum.NormalId.Front,
			text,
			persona.Secret and Color3.fromRGB(255, 80, 70) or BONE,
			{ Font = Enum.Font.Code, PixelsPerStud = 50 }
		)
		prompt(plaque, "Solo", persona.Secret and "Request" or "Challenge", persona.Name, { Surrogate = persona.Id })
	end
end

local function boards(model: Model)
	local north = -HALL.Z / 2 + 0.6
	local function board(name: string, x: number, title: string, fx: string, width: number)
		local frame =
			Build.box(model, Vector3.new(width + 1, 13, 0.6), CFrame.new(x, 12, north), DARK, "Metal", name .. "Frame")
		local screen = Build.box(
			model,
			Vector3.new(width, 11.8, 0.1),
			CFrame.new(x, 12, north + 0.35),
			Color3.fromRGB(8, 10, 10),
			"Glass",
			name
		)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Board"
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Brightness = 1.3
		gui:SetAttribute("Title", title)
		gui.Parent = screen
		Build.fx(screen, fx)
		frame:SetAttribute("Board", name)
		return screen
	end
	-- Screens face +Z (the hall), so their SurfaceGui sits on the Back face.
	board("StandingBoard", -34, "STANDING :: TOP SUBJECTS", "Leaderboard", 20):SetAttribute("BoardId", "Standing")
	board("WinsBoard", 34, "MOST TRIALS WON", "Leaderboard", 20):SetAttribute("BoardId", "Wins")
	local live = board("LiveBoard", 0, "LIVE TRIALS", "LiveTrials", 24)
	prompt(live, "Spectate", "Watch", "LIVE TRIALS")
end

local function lockerBooth(model: Model)
	local at = CFrame.new(50, 0, -18) * CFrame.Angles(0, math.pi / 2, 0) -- faces -X (into the hall)
	local booth = Build.model("Locker", model)
	Build.solid(
		booth,
		Vector3.new(14, 0.8, 12),
		at * CFrame.new(0, 0.4, 0),
		Color3.fromRGB(40, 36, 34),
		"Wood",
		"Floor"
	)
	Build.solid(booth, Vector3.new(14, 12, 0.6), at * CFrame.new(0, 6, 6), Color3.fromRGB(60, 40, 30), "Wood", "Back")
	PropKit.sign(
		booth,
		at * CFrame.new(0, 10.5, 5.6),
		Vector2.new(8, 1.4),
		"THE LOCKER",
		Color3.fromRGB(30, 22, 16),
		TRIM
	)
	Build.column(booth, 3, 3, at * CFrame.new(0, 2.3, 0), Color3.fromRGB(26, 26, 28), "Marble", "Pedestal")
	local pivot = at * CFrame.new(0, 5.2, 0)
	local device = ArbiterModel.build(pivot)
	device.Name = "ShowcaseArbiter"
	device.Parent = booth
	Build.ghost(device)
	Build.fx(device, "Showcase", { Pivot = pivot })
	local spot = Build.part({
		Name = "ShowcaseLight",
		Size = Vector3.one,
		CFrame = at * CFrame.new(0, 11, -2),
		Transparency = 1,
		Parent = booth,
	})
	Build.spotLight(spot, Color3.fromRGB(255, 236, 200), 3, 14, 40, Enum.NormalId.Bottom, true)
	kiosk(booth, at * CFrame.new(-4.5, 0.8, -3), "LOCKER", "Locker", "Open", TRIM)
	-- Wall of hanging gloves and finishes (decor).
	for i = -2, 2 do
		Build.box(
			booth,
			Vector3.new(1, 1.6, 0.4),
			at * CFrame.new(i * 2.2, 7, 5.5),
			Color3.fromHSV((i + 3) / 7, 0.4, 0.6),
			"Fabric",
			"Glove"
		)
	end
end

local function practiceTables(model: Model)
	for i, x in { 30, 46 } do
		local at = CFrame.new(x, 0, 18)
		local t = Build.model("PracticeTable" .. i, model)
		Build.solid(
			t,
			Vector3.new(7, 0.3, 5),
			at * CFrame.new(0, 2.35, 0),
			Color3.fromRGB(70, 72, 75),
			"DiamondPlate",
			"Top"
		)
		for _, off in
			{ Vector3.new(-3, 1.1, -2), Vector3.new(3, 1.1, -2), Vector3.new(-3, 1.1, 2), Vector3.new(3, 1.1, 2) }
		do
			Build.box(t, Vector3.new(0.4, 2.2, 0.4), at * CFrame.new(off), DARK, "Metal", "Leg")
		end
		for _, z in { -4, 4 } do
			Build.solid(
				t,
				Vector3.new(2, 1.5, 2),
				at * CFrame.new(0, 0.75, z),
				Color3.fromRGB(90, 92, 94),
				"Metal",
				"Stool"
			)
		end
		local mini = ArbiterModel.build(at * CFrame.new(0, 2.92, 0) * CFrame.Angles(0, 0, -math.pi / 2))
		mini.Parent = t
		Build.ghost(mini)
		prompt(t:FindFirstChild("Top"), "Practice", "Practice", "PRACTICE TABLE")
	end
	PropKit.sign(
		model,
		CFrame.new(38, 9, 23.4) * CFrame.Angles(0, math.pi, 0),
		Vector2.new(10, 1.3),
		"PRACTICE FLOOR",
		DARK,
		BONE
	)
end

local function doors(model: Model)
	-- Orientation (tutorial) door on the east wall.
	local at = CFrame.new(HALL.X / 2 - 0.4, 0, 34) * CFrame.Angles(0, math.pi / 2, 0) -- faces -X
	local door = Build.model("Orientation", model)
	Build.box(door, Vector3.new(8, 11, 0.6), at * CFrame.new(0, 5.5, 0), Color3.fromRGB(70, 90, 80), "Metal", "Door")
	Build.box(door, Vector3.new(9, 0.6, 0.8), at * CFrame.new(0, 11.3, 0), TRIM, "Metal", "Lintel")
	PropKit.sign(door, at * CFrame.new(0, 13, -0.3), Vector2.new(8, 1.4), "ORIENTATION", DARK, TRIM)
	local panel = Build.box(door, Vector3.new(1.2, 1.6, 0.3), at * CFrame.new(5.2, 4.5, -0.3), DARK, "Metal", "Panel")
	Build.neon(
		door,
		Vector3.new(0.8, 0.3, 0.1),
		at * CFrame.new(5.2, 4.9, -0.46),
		Color3.fromRGB(120, 255, 160),
		"PanelLed"
	)
	prompt(panel, "Tutorial", "Enter", "ORIENTATION")
	-- Sublevel 7: sealed, and never mentioned.
	local s7 = CFrame.new(HALL.X / 2 - 0.4, 0, -36) * CFrame.Angles(0, math.pi / 2, 0)
	Build.box(
		model,
		Vector3.new(7, 10, 0.6),
		s7 * CFrame.new(0, 5, 0),
		Color3.fromRGB(50, 50, 50),
		"DiamondPlate",
		"Sublevel7"
	)
	for i = -2, 2 do
		Build.box(
			model,
			Vector3.new(7.4, 0.6, 0.3),
			s7 * CFrame.new(0, 5 + i * 1.8, -0.4) * CFrame.Angles(0, 0, 0.5),
			(i % 2 == 0) and TRIM or DARK,
			"SmoothPlastic",
			"Barrier"
		)
	end
	PropKit.sign(
		model,
		s7 * CFrame.new(0, 11.5, -0.3),
		Vector2.new(7, 1.2),
		"SUBLEVEL 7 :: NO ACCESS",
		Color3.fromRGB(120, 20, 20),
		BONE
	)
end

local function dressing(model: Model)
	local props = Build.model("Dressing", model)
	-- Posters.
	for _, spec in
		{
			{ CFrame.new(-20, 10, HALL.Z / 2 - 0.5), "HESITATION IS ALSO A DECISION" },
			{ CFrame.new(20, 10, HALL.Z / 2 - 0.5), "THE ARBITER DOES NOT CARE" },
			{ CFrame.new(-HALL.X / 2 + 0.5, 10, 36) * CFrame.Angles(0, -math.pi / 2, 0), "REPORT ALL STAFF SIGHTINGS" },
			{ CFrame.new(HALL.X / 2 - 0.5, 10, 8) * CFrame.Angles(0, math.pi / 2, 0), "SETTLEMENT IS WITHIN REACH" },
		}
	do
		PropKit.sign(
			props,
			spec[1],
			Vector2.new(9, 4),
			spec[2],
			Color3.fromRGB(214, 206, 180),
			Color3.fromRGB(40, 36, 30),
			Enum.Font.SpecialElite
		)
	end
	-- Benches, a vending machine, a janitor's cart, a notice board.
	for _, spec in { { -14, 30 }, { 14, 30 }, { -30, -6 }, { 30, -6 } } do
		Build.solid(
			props,
			Vector3.new(7, 0.4, 2),
			CFrame.new(spec[1], 1.6, spec[2]),
			Color3.fromRGB(90, 64, 40),
			"Wood",
			"Bench"
		)
		Build.box(props, Vector3.new(0.4, 1.4, 1.8), CFrame.new(spec[1] - 3, 0.7, spec[2]), DARK, "Metal", "BenchLeg")
		Build.box(props, Vector3.new(0.4, 1.4, 1.8), CFrame.new(spec[1] + 3, 0.7, spec[2]), DARK, "Metal", "BenchLeg")
	end
	local vend = CFrame.new(-60, 0, 36) * CFrame.Angles(0, -math.pi / 2, 0)
	Build.solid(
		props,
		Vector3.new(4.4, 8, 3),
		vend * CFrame.new(0, 4, 0),
		Color3.fromRGB(140, 30, 30),
		"SmoothPlastic",
		"Vending"
	)
	local vendScreen = Build.box(
		props,
		Vector3.new(3.2, 5, 0.1),
		vend * CFrame.new(-0.3, 4.6, -1.55),
		Color3.fromRGB(200, 220, 230),
		"Glass",
		"VendGlass"
	)
	vendScreen.Transparency = 0.4
	Build.pointLight(vendScreen, Color3.fromRGB(230, 240, 255), 0.8, 8, false)
	local cart = CFrame.new(10, 0, -34) * CFrame.Angles(0, 0.4, 0)
	Build.box(
		props,
		Vector3.new(3, 2.2, 1.8),
		cart * CFrame.new(0, 1.6, 0),
		Color3.fromRGB(190, 150, 40),
		"SmoothPlastic",
		"Cart"
	)
	Build.column(
		props,
		1.4,
		1.2,
		cart * CFrame.new(2.1, 0.7, 0),
		Color3.fromRGB(60, 70, 120),
		"SmoothPlastic",
		"Bucket"
	)
	Build.box(
		props,
		Vector3.new(0.12, 4.5, 0.12),
		cart * CFrame.new(2.1, 2.9, 0) * CFrame.Angles(0, 0, 0.2),
		Color3.fromRGB(120, 90, 60),
		"Wood",
		"Mop"
	)
	local notice = Build.box(
		props,
		Vector3.new(8, 5, 0.3),
		CFrame.new(-HALL.X / 2 + 0.6, 7, -12) * CFrame.Angles(0, -math.pi / 2, 0),
		Color3.fromRGB(120, 90, 60),
		"Wood",
		"NoticeBoard"
	)
	for i = 0, 5 do
		Build.box(
			props,
			Vector3.new(1.4, 1.8, 0.05),
			notice.CFrame * CFrame.new(-3 + i * 1.2, (i % 2) * 0.6 - 0.3, -0.18) * CFrame.Angles(0, 0, (i - 2.5) * 0.06),
			Color3.fromRGB(235, 230, 215),
			"SmoothPlastic",
			"Note"
		)
	end
	-- Observation window high on the south wall, dark room behind it.
	PropKit.window(
		props,
		CFrame.new(0, 17, HALL.Z / 2 - 0.2) * CFrame.Angles(0, math.pi, 0),
		Vector2.new(30, 5),
		DARK,
		Color3.fromRGB(20, 24, 26),
		0.2
	)
	-- PA speakers and cameras.
	for _, spec in
		{
			CFrame.new(-HALL.X / 2 + 0.8, 18, -20) * CFrame.Angles(0, -math.pi / 2, 0),
			CFrame.new(HALL.X / 2 - 0.8, 18, 20) * CFrame.Angles(0, math.pi / 2, 0),
			CFrame.new(0, 20, -HALL.Z / 2 + 0.8) * CFrame.Angles(0, math.pi, 0),
		}
	do
		PropKit.speaker(props, spec)
	end
	for _, spec in
		{
			CFrame.new(-60, 20, -46) * CFrame.Angles(0, math.rad(-135), 0) * CFrame.Angles(math.rad(-30), 0, 0),
			CFrame.new(60, 20, 46) * CFrame.Angles(0, math.rad(45), 0) * CFrame.Angles(math.rad(-30), 0, 0),
			CFrame.new(60, 20, -46) * CFrame.Angles(0, math.rad(135), 0) * CFrame.Angles(math.rad(-30), 0, 0),
		}
	do
		local cam = PropKit.cctv(props, spec)
		cam:SetAttribute("Track", true)
	end
	-- A big institutional clock above the entrance.
	local clock = CFrame.new(0, 20, HALL.Z / 2 - 0.5)
	Build.cylinder(props, 0.4, 5, clock * CFrame.Angles(0, math.pi / 2, 0), BONE, "SmoothPlastic", "Clock")
	local hand = Build.box(
		props,
		Vector3.new(0.15, 2, 0.1),
		clock * CFrame.new(0, 0.8, -0.25),
		DARK,
		"SmoothPlastic",
		"ClockHand"
	)
	Build.fx(hand, "Spin", { Speed = 0.05, Pivot = clock * CFrame.new(0, 0, -0.25), Axis = "Z" })
	hand:SetAttribute("Rest", (clock * CFrame.new(0, 0, -0.25)):ToObjectSpace(hand.CFrame))
end

function LobbyBuilder.build(): Model
	local model = Instance.new("Model")
	model.Name = "Intake"
	hall(model)
	sculpture(model)
	surrogateGallery(model)
	boards(model)
	lockerBooth(model)
	practiceTables(model)
	doors(model)
	dressing(model)

	-- Terminals.
	local terminals = Build.model("Terminals", model)
	kiosk(terminals, CFrame.new(-11, 0, 16) * CFrame.Angles(0, math.pi, 0), "EVALUATION", "Play", "Queue", TRIM)
	kiosk(terminals, CFrame.new(0, 0, 18) * CFrame.Angles(0, math.pi, 0), "EVALUATION", "Play", "Queue", TRIM)
	kiosk(terminals, CFrame.new(11, 0, 16) * CFrame.Angles(0, math.pi, 0), "EVALUATION", "Play", "Queue", TRIM)
	kiosk(
		terminals,
		CFrame.new(-26, 0, 24) * CFrame.Angles(0, math.pi * 0.85, 0),
		"PRIVATE TRIALS",
		"Private",
		"Open",
		Color3.fromRGB(150, 220, 215)
	)
	kiosk(
		terminals,
		CFrame.new(26, 0, 24) * CFrame.Angles(0, -math.pi * 0.85, 0),
		"STANDING",
		"Ranked",
		"Open",
		Color3.fromRGB(235, 90, 70)
	)
	kiosk(terminals, CFrame.new(-10, 0, -32), "DIRECTIVES", "Challenges", "Review", Color3.fromRGB(200, 230, 150))
	kiosk(
		terminals,
		CFrame.new(-50, 0, -40) * CFrame.Angles(0, -math.pi / 4, 0),
		"ARCHIVE",
		"Archive",
		"Access",
		Color3.fromRGB(140, 255, 170)
	)
	kiosk(terminals, CFrame.new(-40, 0, 36) * CFrame.Angles(0, math.pi, 0), "RECORDS", "Record", "Review", BONE)

	-- Spawn.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "IntakeSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.5, 40)
	spawn.Transparency = 1
	spawn.CanCollide = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = model
	Build.box(
		model,
		Vector3.new(14, 0.1, 10),
		CFrame.new(0, 0.06, 40),
		Color3.fromRGB(60, 62, 60),
		"DiamondPlate",
		"ArrivalPlate"
	)
	PropKit.sign(
		model,
		CFrame.new(0, 13, HALL.Z / 2 - 0.5),
		Vector2.new(20, 2.4),
		"HALDEN DECISION SCIENCES :: INTAKE",
		DARK,
		TRIM
	)
	return model
end

LobbyBuilder.HallSize = HALL

return LobbyBuilder
