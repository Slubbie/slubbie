-- The dice tray: 3D dice in a ViewportFrame that wind up, tumble and land on the faces the SERVER
-- chose. The client never decides a result; it only animates the one it receives.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local DiceTray = {}
DiceTray.__index = DiceTray

local DIE_SIZE = 2
local SPACING = 3.1
local THROW_TIME = 0.95

-- Physical sides: normal, u axis, v axis. Side i shows the die's Faces[i] value.
local SIDES = {
	{ Vector3.yAxis, Vector3.xAxis, Vector3.zAxis },
	{ -Vector3.zAxis, Vector3.xAxis, Vector3.yAxis },
	{ Vector3.xAxis, Vector3.zAxis, Vector3.yAxis },
	{ -Vector3.xAxis, Vector3.zAxis, Vector3.yAxis },
	{ Vector3.zAxis, Vector3.xAxis, Vector3.yAxis },
	{ -Vector3.yAxis, Vector3.xAxis, Vector3.zAxis },
}
-- Rotation that turns side i to face up (+Y).
local SIDE_UP = {
	CFrame.identity,
	CFrame.Angles(math.rad(90), 0, 0),
	CFrame.Angles(0, 0, math.rad(90)),
	CFrame.Angles(0, 0, math.rad(-90)),
	CFrame.Angles(math.rad(-90), 0, 0),
	CFrame.Angles(math.rad(180), 0, 0),
}
local PIPS = {
	[1] = { { 0, 0 } },
	[2] = { { -1, -1 }, { 1, 1 } },
	[3] = { { -1, -1 }, { 0, 0 }, { 1, 1 } },
	[4] = { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } },
	[5] = { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 }, { 0, 0 } },
	[6] = { { -1, -1 }, { -1, 0 }, { -1, 1 }, { 1, -1 }, { 1, 0 }, { 1, 1 } },
}

local function buildDie(dieId: string): Model
	local die = Config.Dice.ById[dieId] or Config.Dice.ById[Config.Game.StartingDie]
	local model = Instance.new("Model")
	model.Name = die.Id
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.Size = Vector3.one * DIE_SIZE
	body.Color = Format.Color(die.Color)
	body.Material = (Enum.Material :: any)[die.Material] or Enum.Material.SmoothPlastic
	body.Parent = model
	model.PrimaryPart = body
	local pipColor = Format.Color(die.PipColor)
	for side, axes in SIDES do
		local value = die.Faces[side]
		for _, uv in PIPS[value] do
			local pip = Instance.new("Part")
			pip.Name = "Pip"
			pip.Shape = Enum.PartType.Ball
			pip.Anchored = true
			pip.Size = Vector3.one * 0.36
			pip.Color = pipColor
			pip.Material = Enum.Material.SmoothPlastic
			local offset = axes[1] * (DIE_SIZE / 2 - 0.1) + axes[2] * uv[1] * 0.5 + axes[3] * uv[2] * 0.5
			pip.CFrame = CFrame.new(offset)
			pip.Parent = model
		end
	end
	-- Store each part's offset from the body so the die can be moved as one rigid object.
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part:SetAttribute("Offset", part.CFrame)
		end
	end
	return model
end

local function placeDie(model: Model, cf: CFrame)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.CFrame = cf * (part:GetAttribute("Offset") :: CFrame)
		end
	end
end

-- Chooses which physical side shows `value` (random among duplicates, e.g. Clover's two 6s).
local function sideFor(dieId: string, value: number): number
	local die = Config.Dice.ById[dieId] or Config.Dice.ById[Config.Game.StartingDie]
	local matches = {}
	for side, face in die.Faces do
		if face == value then
			table.insert(matches, side)
		end
	end
	if #matches == 0 then
		return 1
	end
	return matches[math.random(1, #matches)]
end

function DiceTray.new(parent: Instance)
	local self = setmetatable({}, DiceTray)
	local frame = Kit.new("Frame", {
		Name = "DiceTray",
		Size = UDim2.fromOffset(330, 140),
		BackgroundColor3 = Theme.Colors.PanelAlt,
		BackgroundTransparency = 0.15,
		Parent = parent,
	})
	Kit.Corner(frame, 18)
	Kit.Stroke(frame, Theme.Colors.Stroke, 2, 0.2)
	local viewport = Kit.new("ViewportFrame", {
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 160, 150),
		LightColor = Color3.fromRGB(255, 245, 230),
		LightDirection = Vector3.new(-0.4, -1, -0.3),
		Parent = frame,
	})
	Kit.Corner(viewport, 16)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 10.5, 3.6), Vector3.new(0, 0.4, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local felt = Instance.new("Part")
	felt.Anchored = true
	felt.Size = Vector3.new(16, 0.4, 7)
	felt.Position = Vector3.new(0, -0.2, 0)
	felt.Color = Color3.fromRGB(70, 130, 80)
	felt.Material = Enum.Material.Fabric
	felt.Parent = world

	-- Face value badges under each die, so results never depend on reading pips.
	local badges = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 1, -30),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local comboLabel = Kit.Label({
		Parent = frame,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0, -34),
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 26,
		TextColor3 = Theme.Colors.Gold,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	})

	self.Frame = frame
	self.World = world
	self.Badges = badges
	self.ComboLabel = comboLabel
	self.Dice = {} :: { { Id: string, Model: Model, Rest: CFrame } }
	self.Animating = nil :: RBXScriptConnection?
	return self
end

function DiceTray:SetDice(diceIds: { string })
	local key = table.concat(diceIds, ",")
	if key == self.DiceKey then
		return
	end
	self.DiceKey = key
	for _, d in self.Dice do
		d.Model:Destroy()
	end
	self.Dice = {}
	local n = #diceIds
	for i, dieId in diceIds do
		local model = buildDie(dieId)
		local x = (i - (n + 1) / 2) * SPACING
		local rest = CFrame.new(x, DIE_SIZE / 2, 0) * CFrame.Angles(0, math.rad(-15 + i * 12), 0)
		placeDie(model, rest)
		model.Parent = self.World
		table.insert(self.Dice, { Id = dieId, Model = model, Rest = rest })
	end
	self:ClearBadges()
end

function DiceTray:ClearBadges()
	for _, child in self.Badges:GetChildren() do
		child:Destroy()
	end
	self.ComboLabel.Visible = false
end

function DiceTray:ShowBadges(faces: { number })
	self:ClearBadges()
	local n = #faces
	for i, face in faces do
		-- Horizontal screen position roughly under each die.
		local x = 0.5 + (i - (n + 1) / 2) * 0.205
		local badge = Kit.Label({
			Parent = self.Badges,
			Size = UDim2.fromOffset(34, 24),
			Position = UDim2.fromScale(x, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Colors.Ink,
			Text = tostring(face),
			TextColor3 = Theme.Colors.White,
			Font = Theme.Fonts.Title,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Kit.Corner(badge, 8)
	end
end

function DiceTray:StopAnimation()
	if self.Animating then
		self.Animating:Disconnect()
		self.Animating = nil
	end
end

-- Anticipation: dice lift and jiggle while the server resolves the roll.
function DiceTray:Windup()
	self:StopAnimation()
	self:ClearBadges()
	if Kit.ReducedMotion then
		return
	end
	local started = os.clock()
	self.Animating = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		local lift = math.min(t / 0.15, 1)
		for i, d in self.Dice do
			local wobble = CFrame.Angles(math.sin(t * 22 + i) * 0.25, t * 4, math.cos(t * 19 + i) * 0.25)
			placeDie(d.Model, d.Rest * CFrame.new(0, lift * 1.4, 0) * wobble)
		end
	end)
end

-- Put the dice back at rest (e.g. when a roll request is refused).
function DiceTray:Settle()
	self:StopAnimation()
	for _, d in self.Dice do
		placeDie(d.Model, d.Rest)
	end
end

-- Throws the dice and lands them on `faces`. Yields until they land. onLand fires at impact.
function DiceTray:Throw(faces: { number }, onLand: (() -> ())?)
	self:StopAnimation()
	local n = #self.Dice
	local targets = {}
	for i, d in self.Dice do
		local value = faces[i] or 1
		local side = sideFor(d.Id, value)
		local x = (i - (n + 1) / 2) * SPACING + (math.random() - 0.5) * 0.5
		local yaw = math.rad(math.random(-25, 25))
		local final = CFrame.new(x, DIE_SIZE / 2, (math.random() - 0.5) * 0.8) * CFrame.Angles(0, yaw, 0) * SIDE_UP[side]
		local axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		if axis.Magnitude < 0.1 then
			axis = Vector3.xAxis
		end
		targets[i] = {
			Final = final,
			Start = Vector3.new(x * 0.4, 6, 2.4),
			Axis = axis.Unit,
			Spin = math.rad(math.random(540, 900)),
			Delay = (i - 1) * 0.06,
		}
		d.Rest = final
	end

	if Kit.ReducedMotion then
		for i, d in self.Dice do
			placeDie(d.Model, targets[i].Final)
		end
		if onLand then
			onLand()
		end
		self:ShowBadges(faces)
		return
	end

	local started = os.clock()
	local landed = false
	local done = false
	self.Animating = RunService.RenderStepped:Connect(function()
		local now = os.clock() - started
		local allDone = true
		for i, d in self.Dice do
			local target = targets[i]
			local t = math.clamp((now - target.Delay) / THROW_TIME, 0, 1)
			if t < 1 then
				allDone = false
			end
			local flight = math.clamp(t / 0.7, 0, 1)
			local horizontal = 1 - (1 - flight) ^ 2
			local endPos = target.Final.Position
			local pos = target.Start:Lerp(endPos, horizontal)
			local y
			if flight < 1 then
				y = target.Start.Y + (endPos.Y - target.Start.Y) * flight ^ 2
			else
				local b = (t - 0.7) / 0.3
				y = endPos.Y + math.sin(b * math.pi) * 0.45 * (1 - b)
			end
			local spinLeft = target.Spin * (1 - math.min(t / 0.85, 1)) ^ 3
			local cf = CFrame.new(pos.X, y, pos.Z) * CFrame.fromAxisAngle(target.Axis, spinLeft) * target.Final.Rotation
			placeDie(d.Model, cf)
			if flight >= 1 and not landed and i == 1 then
				landed = true
				if onLand then
					task.spawn(onLand)
				end
			end
		end
		if allDone then
			done = true
		end
	end)
	local deadline = os.clock() + THROW_TIME + 0.4
	while not done and os.clock() < deadline do
		task.wait()
	end
	self:StopAnimation()
	for i, d in self.Dice do
		placeDie(d.Model, targets[i].Final)
	end
	self:ShowBadges(faces)
end

-- Flash a combo banner above the tray.
function DiceTray:ShowCombo(text: string)
	local label = self.ComboLabel
	label.Text = text
	label.Visible = true
	label.TextTransparency = 0
	if not Kit.ReducedMotion then
		label.TextSize = 12
		Kit.Tween(label, 0.25, { TextSize = 28 }, Enum.EasingStyle.Back)
	end
end

return DiceTray
