-- Puts each player's equipped aura (crafted cosmetic) on their character, visible to everyone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)

local AuraService = {}

function AuraService.Apply(player: Player, auraId: string)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local old = root:FindFirstChild("DiceboundAura")
	if old then
		old:Destroy()
	end
	local def = Config.Crafting.Auras[auraId]
	if not def then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "DiceboundAura"
	attachment.Position = Vector3.new(0, -0.5, 0)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Format.Color(def.Color))
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, def.Size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(1, 1.8)
	emitter.Rate = def.Rate
	emitter.Speed = NumberRange.new(1, 2.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.Parent = attachment
	attachment.Parent = root
end

return AuraService
