-- The goal card: the 3-step tutorial (first roll → first sale → first upgrade), then always a
-- clear next goal. Highlights the relevant button and draws a beam to the merchant when needed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local C = Theme.Colors

local Guide = {}

local hud
local highlight: Frame? = nil
local beamParts: { Instance } = {}

local function clearBeam()
	for _, inst in beamParts do
		inst:Destroy()
	end
	table.clear(beamParts)
end

-- A beam from the character to the region's merchant.
local function showBeam()
	if #beamParts > 0 then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local region = Config.Regions.List[1]
	local target = Instance.new("Part")
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.Transparency = 1
	target.Size = Vector3.one
	target.Position = ClientState.WorldPosition(region, region.Merchant.Position) + Vector3.new(0, 3, 0)
	target.Parent = Workspace
	local a0 = Instance.new("Attachment")
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Parent = target
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 1.2
	beam.Width1 = 1.2
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(C.Gold)
	beam.LightEmission = 0.6
	beam.Transparency = NumberSequence.new(0.3)
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 3
	beam.TextureSpeed = 1.5
	beam.Parent = target
	table.insert(beamParts, target)
	table.insert(beamParts, a0)
end

local function setHighlight(target: GuiObject?)
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
	if not target then
		return
	end
	local ring = Kit.new("Frame", {
		Name = "Highlight",
		Size = UDim2.new(1, 12, 1, 12),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = target,
	})
	Kit.Corner(ring, 14)
	local stroke = Kit.Stroke(ring, C.Gold, 4)
	highlight = ring
	if not Kit.ReducedMotion then
		task.spawn(function()
			while ring.Parent do
				Kit.Tween(stroke, 0.5, { Transparency = 0.7 }, Enum.EasingStyle.Sine)
				task.wait(0.5)
				Kit.Tween(stroke, 0.5, { Transparency = 0 }, Enum.EasingStyle.Sine)
				task.wait(0.5)
			end
		end)
	end
end

local lastKey = ""
function Guide.Update()
	local data = ClientState.Data
	if not data or not hud then
		return
	end
	local region = Config.Regions.List[1]
	local tutorial = data.Tutorial
	local key, target
	if not tutorial.Done then
		local step = tutorial.Step
		if step == 1 then
			key = "t1"
			target = hud.RollButton.Instance
			hud.SetGoal("TUTORIAL 1/3", "Press ROLL (or R) to throw your die and discover treasure!", nil, nil, true)
		elseif step == 2 then
			local near = ClientState.NearMerchant()
			key = if near then "t2near" else "t2"
			target = if near then hud.MenuButtons.Bag.Instance else nil
			hud.SetGoal(
				"TUTORIAL 2/3",
				if near
					then "You're at the stall! Press E at the counter (or open 🎒 Bag), select an item and sell it."
					else "Your find is in your bag. Follow the golden trail to " .. region.Merchant.Name .. "'s stall.",
				nil,
				"Tip: roll a few more times first. Each sale earns coins.",
				true
			)
		else
			local upgrade, cost = ClientState.CheapestUpgrade()
			key = "t3"
			local canAfford = cost ~= nil and data.Coins >= cost
			target = if canAfford then hud.MenuButtons.Upgrades.Instance else hud.RollButton.Instance
			hud.SetGoal(
				"TUTORIAL 3/3",
				if canAfford
					then "You can afford an upgrade! Open 🔧 Upgrades and buy one."
					else "Roll and sell until you can afford your first upgrade.",
				if cost then data.Coins / cost else nil,
				if upgrade and cost
					then string.format("%s: 🪙 %s / %s", upgrade.Name, Format.Coins(data.Coins), Format.Coins(cost))
					else nil,
				true
			)
		end
		if tutorial.Step == 2 and not ClientState.NearMerchant() then
			showBeam()
		else
			clearBeam()
		end
	else
		clearBeam()
		local here = ClientState.CurrentRegion() or region
		local found, total = ClientState.DiscoveredIn(here.Id)
		local detail = string.format("%s collection: %d / %d", here.Name, found, total)

		-- The next locked region and how close we are to it.
		local nextRegion = nil
		for _, r in Config.Regions.List do
			if Config.IsLive(r) and not data.Regions[r.Id] then
				nextRegion = r
				break
			end
		end
		local regionReady, regionFraction = false, 1
		if nextRegion then
			local previous = Config.Regions.Previous(nextRegion.Id)
			local need = nextRegion.Unlock
			local prevFound = if previous then ClientState.DiscoveredIn(previous.Id) else 0
			local discNeed = need.Discoveries or 0
			local discFraction = if discNeed > 0 then math.min(prevFound / discNeed, 1) else 1
			regionFraction = math.min(data.Coins / math.max(need.Coins, 1), 1) * 0.8 + discFraction * 0.2
			regionReady = data.Coins >= need.Coins and prevFound >= discNeed
			detail ..= string.format(
				"\nNext region: %s · 🪙 %s / %s · finds %d/%d",
				nextRegion.Name,
				Format.Coins(data.Coins),
				Format.Coins(need.Coins),
				math.min(prevFound, discNeed),
				discNeed
			)
		end

		local claimable = data.Claimable
		local rewards = claimable.Daily + claimable.Milestones
		local upgrade, cost = ClientState.CheapestUpgrade()
		if data.Used >= data.Capacity then
			key = "full"
			target = nil
			hud.SetGoal("BAG FULL", "Sell treasure at a merchant stall (or fill an order) to keep rolling.", 1, detail)
		elseif regionReady and nextRegion then
			key = "region"
			target = hud.MenuButtons.Map.Instance
			hud.SetGoal("NEW REGION!", "You can unlock " .. nextRegion.Name .. "! Open 🗺️ Map.", 1, detail)
		elseif claimable.Collection > 0 then
			key = "book"
			target = hud.MenuButtons.Book.Instance
			hud.SetGoal("REWARD READY", "A collection is complete! Claim it in 📖 Book.", 1, detail)
		elseif rewards > 0 then
			key = "quests"
			target = hud.MenuButtons.Quests.Instance
			hud.SetGoal("REWARD READY", "You have rewards to claim in 📜 Quests.", 1, detail)
		elseif upgrade and cost and data.Coins >= cost then
			key = "buy"
			target = hud.MenuButtons.Upgrades.Instance
			hud.SetGoal("NEXT GOAL", "You can afford " .. upgrade.Name .. "! Open 🔧 Upgrades.", 1, detail)
		elseif nextRegion then
			key = "save-region"
			target = nil
			hud.SetGoal(
				"NEXT GOAL",
				"Work toward " .. nextRegion.Name .. ". Fill orders for bonus coins!",
				regionFraction,
				detail
			)
		elseif upgrade and cost then
			key = "save"
			target = nil
			hud.SetGoal(
				"NEXT GOAL",
				string.format(
					"Save up for %s (🪙 %s / %s)",
					upgrade.Name,
					Format.Coins(data.Coins),
					Format.Coins(cost)
				),
				data.Coins / cost,
				detail
			)
		else
			key = "done"
			target = nil
			hud.SetGoal("NEXT GOAL", "Complete every collection and chase the Secret treasures!", found / total, detail)
		end
	end
	if key ~= lastKey then
		lastKey = key
		setHighlight(target)
	end
end

function Guide.Start(hudObject)
	hud = hudObject
	ClientState.Changed:Connect(Guide.Update)
	-- Re-check location-based hints twice a second (merchant proximity).
	task.spawn(function()
		while true do
			task.wait(0.5)
			local data = ClientState.Data
			if data and not data.Tutorial.Done then
				Guide.Update()
			end
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		clearBeam()
	end)
end

return Guide
