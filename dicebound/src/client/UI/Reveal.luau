-- Item reveals. Common finds pop a quick card; rarer finds add a shine, sparkles and a burst at
-- your character; Legendary and better get a short, skippable cinematic. Honors the Reduced
-- Motion and Skip Long Reveals settings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Sound = require(script.Parent.Parent.Sound)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local ItemIcon = require(script.Parent.ItemIcon)

local C = Theme.Colors

local Reveal = {}
Reveal.__index = Reveal

local CARD_TIME = { quick = 1.4, nice = 1.8, rare = 2.3, epic = 2.8, cinematic = 3.2 }
local MAX_CARDS = 3

function Reveal.new(root: Instance, anchor: GuiObject)
	local self = setmetatable({}, Reveal)
	-- Cards stack upward from just above the dice tray.
	self.Stack = Kit.new("Frame", {
		Name = "RevealStack",
		Size = UDim2.fromOffset(330, 300),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local list = Kit.List(self.Stack, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	self.Root = root
	self.Anchor = anchor
	self.Order = 0
	local function follow()
		local pos = anchor.AbsolutePosition
		local rootPos = (root :: GuiObject).AbsolutePosition
		local scale = root:FindFirstChildOfClass("UIScale")
		local s = if scale then scale.Scale else 1
		self.Stack.Position =
			UDim2.fromOffset((pos.X - rootPos.X + anchor.AbsoluteSize.X / 2) / s, (pos.Y - rootPos.Y) / s - 44)
	end
	anchor:GetPropertyChangedSignal("AbsolutePosition"):Connect(follow)
	anchor:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow)
	task.defer(follow)
	return self
end

-- Sparkle burst at the local character (Rare and up). Cleaned up automatically.
function Reveal.WorldBurst(color: Color3, amount: number)
	if Kit.ReducedMotion then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(amount)
	task.delay(1.5, function()
		attachment:Destroy()
	end)
end

local function rarityOf(itemId: string)
	local item = Config.Items.ById[itemId]
	return Config.Rarities.ById[item and item.Rarity or "Common"]
end

-- Non-blocking card above the tray.
function Reveal:Card(reward)
	local item = Config.Items.ById[reward.Id]
	if not item then
		return
	end
	local rarity = rarityOf(reward.Id)
	local color = Theme.Rarity(rarity.Id)
	self.Order += 1

	-- Keep only the newest few cards.
	local cards = {}
	for _, child in self.Stack:GetChildren() do
		if child:IsA("Frame") then
			table.insert(cards, child)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #cards >= MAX_CARDS do
		(table.remove(cards, 1) :: Instance):Destroy()
	end

	local holder = Kit.new("Frame", {
		Size = UDim2.fromOffset(320, 84),
		BackgroundTransparency = 1,
		LayoutOrder = self.Order,
		Parent = self.Stack,
	})
	local card = Kit.Card({
		Parent = holder,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Position = UDim2.fromOffset(0, if Kit.ReducedMotion then 0 else 24),
	})
	local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = color
	stroke.Thickness = if rarity.Order >= 3 then 3 else 2
	local icon = ItemIcon.Create(reward.Id, reward.Mut, 62)
	icon.Position = UDim2.fromOffset(11, 11)
	icon.Parent = card
	Kit.Label({
		Parent = card,
		Position = UDim2.fromOffset(84, 8),
		Size = UDim2.new(1, -150, 0, 24),
		Text = ItemIcon.Name(reward.Id, reward.Mut) .. (if reward.Qty > 1 then "  ×" .. reward.Qty else ""),
		Font = Theme.Fonts.Title,
		TextSize = 18,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
	})
	local chips = Kit.new("Frame", {
		Position = UDim2.fromOffset(84, 36),
		Size = UDim2.new(1, -90, 0, 20),
		BackgroundTransparency = 1,
		Parent = card,
	})
	Kit.List(chips, Enum.FillDirection.Horizontal, 4)
	Kit.Chip(chips, Theme.RarityText(rarity.Id), color, if rarity.Order >= 3 then C.White else C.Ink, 1)
	if reward.Mut then
		local mutation = Config.Economy.Mutations.ById[reward.Mut]
		Kit.Chip(
			chips,
			ItemIcon.MutationGlyph(reward.Mut) .. " " .. reward.Mut:upper() .. " ×" .. mutation.Multiplier,
			Theme.Mutation(reward.Mut),
			C.Ink,
			2
		)
	end
	if reward.New then
		Kit.Chip(chips, "NEW!", C.Red, C.White, 3)
	end
	Kit.Label({
		Parent = card,
		Position = UDim2.fromOffset(84, 58),
		Size = UDim2.new(1, -90, 0, 20),
		Text = "🪙 " .. Format.Coins(reward.Value) .. (if reward.Source ~= "Main"
			then "   · " .. reward.Source .. " bonus"
			else ""),
		TextSize = 14,
		Font = Theme.Fonts.Bold,
		TextColor3 = C.InkSoft,
	})

	if not Kit.ReducedMotion then
		Kit.Tween(card, 0.22, { Position = UDim2.new() }, Enum.EasingStyle.Back)
		if rarity.Order >= 3 then
			-- Shine sweep across the card.
			local shine = Kit.new("Frame", {
				Size = UDim2.new(0.35, 0, 1.6, 0),
				Position = UDim2.new(-0.4, 0, -0.3, 0),
				Rotation = 20,
				BackgroundColor3 = C.White,
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = card,
			})
			Kit.new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0.2),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = shine,
			})
			Kit.Tween(shine, 0.7, { Position = UDim2.new(1.1, 0, -0.3, 0) })
		end
		if rarity.Order >= 4 then
			Kit.Tween(stroke, 0.35, { Thickness = 5 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.delay(0.35, function()
				if stroke.Parent then
					Kit.Tween(stroke, 0.35, { Thickness = 3 })
				end
			end)
		end
	end

	task.delay(CARD_TIME[rarity.Reveal] or 1.6, function()
		if holder.Parent then
			Kit.Tween(card, 0.25, { BackgroundTransparency = 1 })
			for _, d in card:GetDescendants() do
				if d:IsA("TextLabel") then
					Kit.Tween(d, 0.25, { TextTransparency = 1, BackgroundTransparency = 1 })
				elseif d:IsA("Frame") then
					Kit.Tween(d, 0.25, { BackgroundTransparency = 1 })
				elseif d:IsA("UIStroke") then
					Kit.Tween(d, 0.25, { Transparency = 1 })
				end
			end
			task.wait(0.27)
			holder:Destroy()
		end
	end)
end

-- Blocking full-screen reveal for Legendary and better. Tap anywhere (or wait) to close.
function Reveal:Cinematic(reward)
	local rarity = rarityOf(reward.Id)
	local color = Theme.Rarity(rarity.Id)
	local closed = false

	local overlay = Kit.new("TextButton", {
		Name = "Cinematic",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Dim,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 50,
		Parent = self.Root,
	})
	Kit.Tween(overlay, 0.3, { BackgroundTransparency = 0.3 })

	local center = Kit.new("Frame", {
		Size = UDim2.fromOffset(420, 420),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 51,
		Parent = overlay,
	})
	-- Light rays: a few rotating bars behind the item.
	local rays = Kit.new("Frame", {
		Size = UDim2.fromOffset(360, 360),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 51,
		Parent = center,
	})
	for i = 0, 5 do
		local ray = Kit.new("Frame", {
			Size = UDim2.new(0, 26, 1, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = i * 30,
			BackgroundColor3 = color,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			ZIndex = 51,
			Parent = rays,
		})
		Kit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = 90,
			Parent = ray,
		})
	end

	local viewport = Kit.new("ViewportFrame", {
		Size = UDim2.fromOffset(220, 220),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(190, 180, 170),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-0.5, -1, -0.6),
		ZIndex = 52,
		Parent = center,
	})
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, 8), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local model = ItemIcon.Model(reward.Id, reward.Mut)
	model.Parent = viewport
	local basePivot = model:GetPivot()

	local title = Kit.Label({
		Parent = center,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 8),
		Text = Theme.RarityText(rarity.Id) .. "!",
		Font = Theme.Fonts.Title,
		TextSize = 36,
		TextColor3 = color,
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 53,
	})
	Kit.Label({
		Parent = center,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.new(0, 0, 1, -96),
		Text = ItemIcon.Name(reward.Id, reward.Mut),
		Font = Theme.Fonts.Title,
		TextSize = 28,
		TextColor3 = C.White,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 53,
	})
	local details = "🪙 " .. Format.Coins(reward.Value)
	if reward.Mut then
		details ..= "   " .. ItemIcon.MutationGlyph(reward.Mut) .. " " .. reward.Mut .. " mutation"
	end
	if reward.New then
		details ..= "   ·   NEW DISCOVERY!"
	end
	Kit.Label({
		Parent = center,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 1, -58),
		Text = details,
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = C.Gold,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 53,
	})
	Kit.Label({
		Parent = center,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -26),
		Text = "Tap anywhere to continue",
		TextSize = 14,
		TextColor3 = C.PanelDeep,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 53,
	})

	Sound.Play("RevealLegendary")
	Reveal.WorldBurst(color, 40)

	local spin: RBXScriptConnection? = nil
	if Kit.ReducedMotion then
		model:PivotTo(basePivot * CFrame.Angles(0.3, 0.6, 0))
	else
		center.Size = UDim2.fromOffset(300, 300)
		Kit.Tween(center, 0.4, { Size = UDim2.fromOffset(420, 420) }, Enum.EasingStyle.Back)
		title.TextSize = 10
		Kit.Tween(title, 0.4, { TextSize = 36 }, Enum.EasingStyle.Back)
		local started = os.clock()
		spin = RunService.RenderStepped:Connect(function()
			local t = os.clock() - started
			rays.Rotation = t * 25
			model:PivotTo(basePivot * CFrame.Angles(math.sin(t * 1.3) * 0.25, t * 1.6, 0))
		end)
	end

	overlay.Activated:Connect(function()
		closed = true
	end)
	local deadline = os.clock() + 5
	while not closed and os.clock() < deadline do
		task.wait(0.05)
	end
	if spin then
		spin:Disconnect()
	end
	overlay:Destroy()
end

-- Shows one reward with the right level of drama. Yields only for cinematics.
function Reveal:Show(reward)
	local rarity = rarityOf(reward.Id)
	if rarity.Reveal == "cinematic" and not ClientState.Settings.SkipReveals then
		self:Cinematic(reward)
		return
	end
	if rarity.Order >= 5 then
		Sound.Play("RevealLegendary")
	elseif rarity.Order == 4 then
		Sound.Play("RevealEpic")
	elseif rarity.Order == 3 then
		Sound.Play("RevealRare")
	else
		Sound.Play("RevealCommon")
	end
	if rarity.Order >= 3 then
		Reveal.WorldBurst(Theme.Rarity(rarity.Id), rarity.Order * 6)
	end
	self:Card(reward)
end

return Reveal
