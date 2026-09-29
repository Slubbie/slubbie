-- The guided tutorial on the client: a coach card with the current step,
-- its progress and Skip / Got it buttons, a bouncing marker and a guide
-- trail to the step's target (your field, the bin, the chest, the well, a
-- villager), and a pulse on the hotbar slot or menu button it mentions.
--
-- The server decides when a step is done (TutorialService); this only shows
-- where to go. Hint(name) shows one-off contextual tips (first chest, first
-- time in build mode, ...), once per session.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tutorial = require(Shared.Config.Tutorial)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)

local C = require(script.Parent)
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UIFolder.Kit)
local Theme = require(UIFolder.Theme)

local TutorialController = {}

local player = Players.LocalPlayer

local card: Frame? = nil
local marker: BillboardGui? = nil
local markerPart: Part? = nil
local beam: Beam? = nil
local attachFrom: Attachment? = nil
local shownStep = 0
local pulseTarget: GuiObject? = nil
local seenHints: { [string]: boolean } = {}

local HINTS = {
	Chest = {
		Title = "Storage",
		Text = "Drag items between your backpack and the chest. Shift-click (or the ⇄ button) moves a whole stack; right-click splits one.",
	},
	Build = {
		Title = "Build mode",
		Text = "Pick something from the catalog, then click to place it. R rotates, T toggles free placement for decorations, Ctrl+Z undoes. Click an existing object to move it.",
	},
	Machine = {
		Title = "Artisan machines",
		Text = "Load ingredients into the queue and collect the goods when they're done. Machines keep working while you're away.",
	},
	Animals = {
		Title = "Animals",
		Text = "Pet, feed and brush your animals every day. Happy animals give better products — and they remember who cares for them.",
	},
	Fishing = {
		Title = "Fishing",
		Text = "Keep the fish inside the green bar: hold to raise it, release to let it fall. Better rods make the bar bigger.",
	},
	Visit = {
		Title = "Visiting",
		Text = "You're on someone else's farm. What you can do here depends on the permissions the owner gave you.",
	},
}

-- Helpers ---------------------------------------------------------------------------------------------------------------

local function currentStep(): (number?, any?)
	local t = C.State.Get("Tutorial")
	if not t or t.Done then
		return nil, nil
	end
	return t.Step, Tutorial.Steps[t.Step]
end

local function myLot(): Instance?
	local lotId = player:GetAttribute("Lot")
	local farms = workspace:FindFirstChild("Farms")
	if not lotId or not farms then
		return nil
	end
	for _, lot in farms:GetChildren() do
		if lot:GetAttribute("Lot") == lotId then
			return lot
		end
	end
	return nil
end

local function findPrompt(lot: Instance, kind: string, extra: ((ProximityPrompt) -> boolean)?): Vector3?
	for _, d in lot:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute("Kind") == kind and (not extra or extra(d)) then
			local parent = d.Parent
			if parent and parent:IsA("BasePart") then
				return parent.Position
			elseif parent and parent:IsA("Attachment") then
				return parent.WorldPosition
			end
		end
	end
	return nil
end

-- World position for a step target, or nil.
local function targetPosition(target: string?): Vector3?
	if not target then
		return nil
	end
	local npcId = string.match(target, "^Npc:(.+)$")
	if npcId then
		local model = C.NPC.Model(npcId)
		local head = model and model:FindFirstChild("Head") :: BasePart?
		return head and head.Position
	end
	local lot = myLot()
	if not lot then
		return nil
	end
	local origin = lot:GetAttribute("Origin")
	if target == "Tile" and typeof(origin) == "Vector3" then
		-- The tilled tile nearest the house corner (or the field corner before any are tilled).
		local tiles = lot:FindFirstChild("Tiles")
		local best: Vector3? = nil
		if tiles then
			for _, tile in tiles:GetChildren() do
				if tile:IsA("BasePart") then
					if not best or (tile.Position - origin).Magnitude < ((best :: Vector3) - origin).Magnitude then
						best = tile.Position
					end
				end
			end
		end
		return best or (origin + Vector3.new(10, 0, 10))
	elseif target == "Bin" then
		return findPrompt(lot, "Bin")
	elseif target == "Chest" then
		return findPrompt(lot, "Chest")
	elseif target == "Well" then
		return findPrompt(lot, "Water", function(p)
			return p:GetAttribute("Water") == "Well"
		end)
	end
	return nil
end

local function clearWorldGuide()
	if marker then
		marker:Destroy()
		marker = nil
	end
	if markerPart then
		markerPart:Destroy()
		markerPart = nil
	end
	if beam then
		beam:Destroy()
		beam = nil
	end
	if attachFrom then
		attachFrom:Destroy()
		attachFrom = nil
	end
end

local function ensureWorldGuide(label: string)
	if markerPart then
		return
	end
	local part = Instance.new("Part")
	part.Name = "TutorialTarget"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = workspace:FindFirstChild("ClientFX") or workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 70)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.Adornee = part
	local arrow = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		Text = "⬇",
		TextScaled = true,
		Font = Theme.Fonts.Bold,
		TextColor3 = Color3.fromRGB(255, 225, 90),
		TextStrokeTransparency = 0.2,
		Name = "Arrow",
		Parent = gui,
	})
	arrow.TextStrokeColor3 = Color3.fromRGB(90, 60, 10)
	Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 46),
		Text = label,
		TextScaled = true,
		Font = Theme.Fonts.Bold,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.3,
		Parent = gui,
	})
	gui.Parent = C.UI.Root()
	local a1 = Instance.new("Attachment")
	a1.Parent = part
	local b = Instance.new("Beam")
	b.Attachment1 = a1
	b.Width0 = 0.6
	b.Width1 = 0.6
	b.FaceCamera = true
	b.LightEmission = 0.6
	b.LightInfluence = 0
	b.Segments = 20
	b.CurveSize0 = 4
	b.CurveSize1 = -4
	b.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
	b.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.3, 0.35),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	b.Parent = part
	markerPart = part
	marker = gui
	beam = b
end

-- Attach the beam's start to the character (re-done after respawns).
local function attachToCharacter()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart or not beam then
		return
	end
	if attachFrom and attachFrom.Parent == rootPart then
		return
	end
	if attachFrom then
		attachFrom:Destroy()
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TutorialFrom"
	a0.Position = Vector3.new(0, -1.5, 0)
	a0.Parent = rootPart
	attachFrom = a0
	beam.Attachment0 = a0
end

local function clearPulse()
	if pulseTarget then
		local stroke = pulseTarget:FindFirstChild("TutorialPulse")
		if stroke then
			stroke:Destroy()
		end
		pulseTarget = nil
	end
end

local function pulseGui(gui: GuiObject?)
	clearPulse()
	if not gui then
		return
	end
	local stroke = Instance.new("UIStroke")
	stroke.Name = "TutorialPulse"
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(255, 225, 90)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = gui
	pulseTarget = gui
end

local function findGui(name: string): GuiObject?
	local hud = C.UI.Layer("HUD")
	local found = hud and hud:FindFirstChild(name, true)
	return if found and found:IsA("GuiObject") then found else nil
end

-- Coach card ---------------------------------------------------------------------------------------------------------------

local function closeCard()
	if card then
		local c = card
		card = nil
		Kit.PopOut(c, function()
			c:Destroy()
		end)
		task.delay(0.3, function()
			if c.Parent then
				c:Destroy()
			end
		end)
	end
end

local function buildCard(index: number, step: any)
	closeCard()
	local panel = Kit.Panel({ Size = UDim2.fromOffset(380, 0), Shadow = true, Name = "Tutorial", StrokeKey = "Accent" })
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 56)
	Kit.Padding(panel, 12, 14)
	Kit.List(panel, "Y", 6)
	local speaker = step.Speaker and Registry.Npcs[step.Speaker]
	local top = Kit.Label(
		(if speaker then speaker.Icon .. " " .. speaker.Name .. "  ·  " else "🌱 ")
			.. "Step "
			.. index
			.. " of "
			.. #Tutorial.Steps,
		{ Size = Theme.Sizes.Tiny, Color = "SubText" }
	)
	top.Parent = panel
	local title = Kit.Heading(step.Title, 20)
	title.LayoutOrder = 1
	title.Parent = panel
	local body = Kit.Label(step.Text, { Wrap = true, Size = Theme.Sizes.Small })
	body.LayoutOrder = 2
	body.Parent = panel
	local progress = nil
	if (step.Count or 1) > 1 then
		progress = Kit.Progress({ Size = UDim2.new(1, 0, 0, 14), Color = "Accent" })
		progress.Frame.LayoutOrder = 3
		progress.Frame.Parent = panel
	end
	local buttons =
		Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 4, Parent = panel })
	Kit.List(buttons, "X", 8, "Right")
	local skip = Kit.Button("Skip tutorial", {
		Style = "Ghost",
		Size = UDim2.fromOffset(120, 32),
		TextSize = Theme.Sizes.Tiny,
		OnClick = function()
			Kit.Confirm(
				"Skip the tutorial?",
				"You'll still get Mabel's starter gift. You can always ask villagers for help.",
				function(yes)
					if yes then
						Net.Request("TutorialSkip")
					end
				end,
				"Skip"
			)
		end,
	})
	skip.Parent = buttons
	if step.Wait == "Ack" then
		local ok = Kit.Button(if index == #Tutorial.Steps then "Let's go!" else "Got it", {
			Style = "Accent",
			Size = UDim2.fromOffset(110, 32),
			TextSize = Theme.Sizes.Small,
			OnClick = function()
				local done = Net.Request("TutorialAck", step.Id)
				if done then
					C.Audio.PlayUI("UIConfirm")
				end
			end,
		})
		ok.LayoutOrder = 1
		ok.Parent = buttons
	end
	panel.Parent = C.UI.Layer("HUD")
	Kit.Pop(panel)
	Kit.RepaintGradients(panel)
	card = panel
	return progress
end

local progressBar: any = nil

local function refresh()
	local index, step = currentStep()
	if not index or not step then
		closeCard()
		clearWorldGuide()
		clearPulse()
		shownStep = 0
		return
	end
	if index ~= shownStep or not card then
		shownStep = index
		progressBar = buildCard(index, step)
		clearWorldGuide()
		C.Audio.PlayUI("Notification")
	end
	if progressBar then
		local count = C.State.Get("Tutorial", "Count") or 0
		progressBar.Set(count / (step.Count or 1), count .. " / " .. (step.Count or 1))
	end
	-- UI target: hotbar slot or menu button.
	local menu = string.match(step.Target or "", "^Menu:(.+)$")
	if step.Hotbar and C.State.Get("Hotbar") ~= step.Hotbar then
		pulseGui(findGui("Slot" .. step.Hotbar))
	elseif menu then
		pulseGui(findGui(menu))
	else
		clearPulse()
	end
end

function TutorialController.Show(_step: number?)
	refresh()
end

-- One-off contextual tips.
function TutorialController.Hint(name: string)
	local hint = HINTS[name]
	if not hint or seenHints[name] then
		return
	end
	seenHints[name] = true
	C.Notify.Banner("💡 " .. hint.Title, hint.Text, nil, "Default", 6)
end

function TutorialController.Start()
	C.State.Watch("Tutorial", function()
		refresh()
	end)
	C.State.Watch("Hotbar", function()
		refresh()
	end)
	-- Keep the marker on its (possibly moving) target; bounce the arrow every frame.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		local arrow = marker and marker:FindFirstChild("Arrow") :: TextLabel?
		if arrow then
			arrow.Position =
				UDim2.fromOffset(0, if Kit.ReducedMotion then 0 else math.abs(math.sin(os.clock() * 3)) * -10)
		end
		elapsed += dt
		if elapsed < 0.2 then
			return
		end
		elapsed = 0
		local _, step = currentStep()
		local position = step and not C.Build.Active() and targetPosition(step.Target)
		if not position then
			clearWorldGuide()
			return
		end
		local label = if step.Target == "Tile"
			then "Your field"
			elseif step.Target == "Bin" then "Shipping bin"
			elseif step.Target == "Chest" then "Chest"
			elseif step.Target == "Well" then "Well"
			else (function()
				local npcId = string.match(step.Target or "", "^Npc:(.+)$")
				local npc = npcId and Registry.Npcs[npcId]
				return if npc then npc.Name else ""
			end)()
		ensureWorldGuide(label)
		attachToCharacter()
		local part = markerPart :: Part
		part.Position = position
		-- Hide the trail once you're there.
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if beam and rootPart then
			beam.Enabled = (rootPart.Position - position).Magnitude > 14
		end
	end)
	player.CharacterAdded:Connect(function()
		task.wait(1)
		attachToCharacter()
	end)
end

return TutorialController
