-- The Dreamline: a floating lobby far above the city where endless runs begin.
-- EndlessService builds each runner's lane of sections on demand, starting
-- from the lane pads laid out here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)

local Dreamline = {}

Dreamline.LaneSpacing = 160
Dreamline.Lanes = 12

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Start CFrame of an endless lane (top-surface point facing along the lane).
function Dreamline.LaneStart(index: number): CFrame
	local origin = Districts.Dreamline
	local x = (index - (Dreamline.Lanes + 1) / 2) * Dreamline.LaneSpacing
	local p = origin + Vector3.new(x, 0, -60)
	return CFrame.lookAt(p, p + Vector3.new(0, 0, -1))
end

function Dreamline.BuildGate(world: Instance): CFrame
	local origin = Districts.Dreamline
	local B = Kit.new(world, "Dreamline", { Signal = rgb(255, 160, 240) })
	local base = CFrame.new(origin)
	-- Lobby: a wide translucent platform with lane pads along its far edge.
	B:Box(base * CFrame.new(0, -1, -20), Vector3.new(Dreamline.Lanes * Dreamline.LaneSpacing, 2, 80), rgb(60, 50, 90), Enum.Material.Glass, { Name = "DreamLobby", Transparency = 0.2 })
	for index = 1, Dreamline.Lanes do
		local start = Dreamline.LaneStart(index)
		local pad = B:Box(start * CFrame.new(0, 0.1, 8), Vector3.new(10, 0.2, 10), rgb(255, 160, 240), Enum.Material.Neon, { Name = "LanePad", CanCollide = false })
		pad.Transparency = 0.4
		Props.Arch(B, start * CFrame.new(0, 0, 2), 10, 12, rgb(170, 150, 220), Enum.Material.Marble)
	end
	for i = 1, 30 do
		local p = origin + Vector3.new(B:Rand(-900, 900), B:Rand(-200, 300), B:Rand(-1500, 200))
		Props.Crystal(B, p, B:Rand(4, 14), B:Pick({ rgb(255, 160, 240), rgb(140, 160, 255), rgb(150, 255, 230) }))
	end
	local sign = B:Detail(base * CFrame.new(0, 14, 18), Vector3.new(40, 5, 0.5), rgb(30, 24, 50), Enum.Material.SmoothPlastic)
	B:Text(sign, Enum.NormalId.Front, "THE DREAMLINE", { Color = rgb(255, 180, 245) })
	B:Text(sign, Enum.NormalId.Back, "THE DREAMLINE", { Color = rgb(255, 180, 245) })
	local exit = B:Box(base * CFrame.new(0, 6, 16), Vector3.new(10, 12, 1), rgb(255, 214, 150), Enum.Material.ForceField, { Name = "DreamExit", CanCollide = false })
	B:Prompt(exit, "Return", "Guildhall", { Name = "DreamExitPrompt", Distance = 14, Attrs = { Board = "ReturnHub" } })
	B:Volume(base * CFrame.new(0, -220, -400), Vector3.new(4000, 10, 4000), Tags.KillZone, { District = "Dreamline" })
	return CFrame.lookAt(origin + Vector3.new(0, 3.5, 6), origin + Vector3.new(0, 3.5, -60))
end

return Dreamline
