-- Light, self-cleaning UI effects: coins flying to the counter, confetti, a small camera shake.
-- All skipped (or reduced) with the Reduced Motion setting.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Effects = {}

local root: GuiObject
local coinTarget: GuiObject

function Effects.Init(parent: GuiObject, target: GuiObject)
	root = parent
	coinTarget = target
end

local function toRoot(screen: Vector2): UDim2
	local scale = root:FindFirstChildOfClass("UIScale")
	local s = if scale then scale.Scale else 1
	local offset = root.AbsolutePosition
	return UDim2.fromOffset((screen.X - offset.X) / s, (screen.Y - offset.Y) / s)
end

-- A few coins fly from `from` (screen position, default bottom-center) into the coin counter.
function Effects.Coins(count: number, from: Vector2?)
	if Kit.ReducedMotion or not root or not coinTarget then
		return
	end
	local start = from
		or Vector2.new(
			root.AbsolutePosition.X + root.AbsoluteSize.X / 2,
			root.AbsolutePosition.Y + root.AbsoluteSize.Y - 160
		)
	local target = coinTarget.AbsolutePosition + Vector2.new(20, coinTarget.AbsoluteSize.Y / 2)
	for i = 1, math.clamp(count, 1, 10) do
		local coin = Kit.Label({
			Parent = root,
			Text = "🪙",
			TextSize = 26,
			Size = UDim2.fromOffset(30, 30),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = toRoot(start + Vector2.new(math.random(-60, 60), math.random(-30, 30))),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 45,
		})
		task.delay(i * 0.05, function()
			local tween = TweenService:Create(
				coin,
				TweenInfo.new(0.55 + math.random() * 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = toRoot(target), TextTransparency = 0.3 }
			)
			tween:Play()
			tween.Completed:Wait()
			coin:Destroy()
		end)
	end
end

-- Confetti shower for big moments (region unlocks, crafts, jackpots).
function Effects.Confetti(amount: number?)
	if Kit.ReducedMotion or not root then
		return
	end
	local colors = { Theme.Colors.Gold, Theme.Colors.Red, Theme.Colors.Blue, Theme.Colors.Green, Theme.Colors.Purple }
	for _ = 1, amount or 50 do
		local piece = Kit.new("Frame", {
			Size = UDim2.fromOffset(math.random(6, 12), math.random(10, 18)),
			BackgroundColor3 = colors[math.random(1, #colors)],
			BorderSizePixel = 0,
			Rotation = math.random(0, 360),
			Position = UDim2.new(math.random(), 0, 0, -20),
			ZIndex = 70,
			Parent = root,
		})
		local fall = TweenService:Create(
			piece,
			TweenInfo.new(1.6 + math.random() * 1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.1, 0),
				Rotation = piece.Rotation + math.random(-540, 540),
			}
		)
		fall:Play()
		fall.Completed:Connect(function()
			piece:Destroy()
		end)
	end
end

-- Short camera shake (Jackpots).
function Effects.Shake(strength: number, seconds: number)
	if Kit.ReducedMotion then
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	task.spawn(function()
		local ends = os.clock() + seconds
		while os.clock() < ends do
			local left = (ends - os.clock()) / seconds
			humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * strength * left
			task.wait(0.03)
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

return Effects
