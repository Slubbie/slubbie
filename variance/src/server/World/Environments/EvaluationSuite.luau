-- EVALUATION SUITE ("THE BOARD"): a sterile corporate evaluation chamber.
-- White panels, a wall of live metrics, frosted glass with seven board members
-- behind it (spectator space), light panels and dome cameras.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Variance.Visual.Build)
local PropKit = require(script.Parent.Parent.PropKit)

local Dresser = {}

function Dresser.dress(ctx)
	local m = ctx.Model
	local c = ctx.Colors
	local at = ctx.at
	local accent = c.Accent

	-- Panel seams on the walls.
	for i = -11, 11, 2 do
		Build.box(m, Vector3.new(0.08, 17, 0.1), at(i * 2, 8.5, 23.45), Color3.fromRGB(180, 182, 180), "SmoothPlastic", "Seam")
		Build.box(m, Vector3.new(0.1, 17, 0.08), at(-23.45, 8.5, i * 2), Color3.fromRGB(180, 182, 180), "SmoothPlastic", "Seam")
	end
	-- Ceiling light panels.
	for x = -2, 2 do
		for z = -2, 2 do
			if not (x == 0 and z == 0) then
				local panel = Build.box(m, Vector3.new(3.6, 0.1, 3.6), at(x * 8, 17.9, z * 8), Color3.fromRGB(240, 246, 255), "Neon", "LightPanel")
				panel.CastShadow = false
				if (x + z) % 2 == 0 then
					local light = Build.pointLight(panel, Color3.fromRGB(235, 242, 255), 0.35, 14, false)
					light.Name = "Light"
					Build.fx(panel, "Flicker", { BaseBrightness = 0.35, Soft = true })
				end
			end
		end
	end

	-- Frosted glass wall (north) with the boardroom behind it.
	ctx.cut("N", 0, 7, 36, 11)
	PropKit.window(m, at(0, 7, -24.5), Vector2.new(36, 11), Color3.fromRGB(40, 40, 44), c.Glass, 0.55)
	Build.box(m, Vector3.new(40, 0.5, 14), at(0, -0.25, -32), Color3.fromRGB(150, 152, 150), "Marble", "BoardFloor")
	Build.box(m, Vector3.new(40, 0.5, 14), at(0, 14, -32), Color3.fromRGB(220, 222, 220), "SmoothPlastic", "BoardCeiling")
	Build.box(m, Vector3.new(40, 14, 0.5), at(0, 7, -39), Color3.fromRGB(200, 202, 200), "SmoothPlastic", "BoardBack")
	Build.box(m, Vector3.new(24, 2.8, 5), at(0, 1.4, -32), Color3.fromRGB(40, 40, 44), "Wood", "BoardTable")
	for i = 1, 7 do
		local x = -12 + (i - 1) * 4
		local s = PropKit.silhouette(m, at(x, 0, -35.5, CFrame.Angles(0, math.pi, 0)), Color3.fromRGB(16, 16, 18))
		s.Name = "Board" .. i
		Build.box(m, Vector3.new(2.4, 4, 0.4), at(x, 2.5, -37.2), Color3.fromRGB(20, 20, 22), "Leather", "ChairBack")
	end
	local boardLight = Build.part({ Name = "BoardLight", Size = Vector3.one, CFrame = at(0, 13, -32), Transparency = 1, Parent = m })
	Build.pointLight(boardLight, Color3.fromRGB(230, 236, 245), 0.9, 24, false)

	-- Metrics wall on the east side.
	local wall = at(23.2, 2, 0, CFrame.Angles(0, math.pi / 2, 0))
	for r = 0, 1 do
		for col = -2, 1 do
			PropKit.monitor(m, wall * CFrame.new(col * 4.6 + 2.3, 3 + r * 4.2, 0), Vector3.new(4.4, 4, 0.5), "METRICS", Color3.fromRGB(255, 90, 80))
		end
	end
	PropKit.sign(m, at(0, 15.5, 23.3), Vector2.new(12, 1.8), "HALDEN DECISION SCIENCES", Color3.fromRGB(240, 240, 238), Color3.fromRGB(30, 30, 34))
	Build.neon(m, Vector3.new(12, 0.1, 0.1), at(0, 14.4, 23.2), accent, "LogoUnderline")

	-- A single potted plant, a water cooler, a clock that runs a little fast.
	local plant = at(-19, 0, 19)
	Build.column(m, 2, 1.8, plant * CFrame.new(0, 1, 0), Color3.fromRGB(240, 240, 238), "SmoothPlastic", "Pot")
	for i = 0, 5 do
		local leaf = Build.ball(m, 1.2, plant * CFrame.new(math.cos(i) * 0.6, 2.6 + i * 0.35, math.sin(i) * 0.6), Color3.fromRGB(60, 110, 60), "Grass", "Leaf")
		leaf.Size = Vector3.new(1.2, 0.4, 2.2)
	end
	local cooler = at(19, 0, 19)
	Build.box(m, Vector3.new(1.6, 3.6, 1.6), cooler * CFrame.new(0, 1.8, 0), Color3.fromRGB(230, 230, 228), "SmoothPlastic", "Cooler")
	local bottle = Build.column(m, 2, 1.4, cooler * CFrame.new(0, 4.6, 0), Color3.fromRGB(160, 200, 230), "Glass", "Bottle")
	bottle.Transparency = 0.4

	-- Dome cameras and discreet speakers.
	for _, spec in { { 20, 20 }, { -20, -20 }, { 20, -20 }, { -20, 20 } } do
		local dome = at(spec[1], 17.6, spec[2])
		Build.ball(m, 1.2, dome, Color3.fromRGB(30, 30, 34), "Glass", "Dome")
	end
	PropKit.cctv(m, at(-22.5, 15, 0, CFrame.Angles(0, math.rad(-90), 0) * CFrame.Angles(math.rad(-25), 0, 0)))
	PropKit.speaker(m, at(-22.8, 13, -12, CFrame.Angles(0, -math.pi / 2, 0)))
	PropKit.vent(m, at(12, 17.6, 12, CFrame.Angles(-math.pi / 2, 0, 0)), Vector2.new(3, 2))
	PropKit.beacon(m, at(-22.8, 15, 12, CFrame.Angles(0, 0, -math.pi / 2)), Color3.fromRGB(230, 40, 40))
	PropKit.beacon(m, at(22.8, 15, -12, CFrame.Angles(0, 0, math.pi / 2)), Color3.fromRGB(230, 40, 40))
end

return Dresser
