-- Fishing on the client: cast → wait for a bite → hook it in time → reel.
--
-- The server already decided what's on the line (FishCast returns only what
-- the minigame needs: difficulty, behaviour, catch-zone size). The reeling
-- minigame (Config/Fish.Minigame): keep the fish inside your catch zone to
-- fill the progress bar. Hold the use button (mouse / Space / R2 / tap) to
-- lift the zone; let go and it sinks. A catch where the fish never left the
-- zone is "Perfect" and earns a quality bonus.
--
-- Bait: the bait you chose in your bag ("Use as bait"), otherwise the first
-- ordinary bait found (never the Legendary Lure unless chosen).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FishConfig = require(Shared.Config.Fish)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)

local C = require(script.Parent)
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UIFolder.Kit)
local Theme = require(UIFolder.Theme)

local FishingController = {}

local GAME = FishConfig.Minigame
local HOOK_WINDOW = 1.2
local AUTO_BAIT = { bait = true, glow_bait = true, deluxe_bait = true }

local player = Players.LocalPlayer
local state: string = "Idle" -- Idle | Waiting | Bite | Reeling
local cast: any = nil
local chosenBait: string? = nil
local ui: Frame? = nil
local conn: RBXScriptConnection? = nil
local random = Random.new()
local touches = 0 -- fingers currently on the screen

function FishingController.Busy(): boolean
	return state ~= "Idle"
end

function FishingController.SetBait(ref: string?)
	chosenBait = ref
	if ref then
		local stack = C.State.Get("Inventory", "Slots", string.match(ref, "%d+") or "")
		local def = stack and Registry.Items[stack.Id]
		C.Notify.Toast("🪱 Bait set: " .. (def and def.Name or "bait"), "Success")
	end
end

local function findBait(): string?
	local slots = C.State.Get("Inventory", "Slots") or {}
	if chosenBait then
		local slot = string.match(chosenBait, "^inv:(%d+)$")
		local stack = slot and slots[slot]
		local def = stack and Registry.Items[stack.Id]
		if def and def.Category == "Bait" then
			return chosenBait
		end
		chosenBait = nil
	end
	local tier = C.State.Get("Tools", "rod") or 1
	for slot, stack in slots do
		if AUTO_BAIT[stack.Id] and (tier >= 3 or stack.Id == "bait") then
			return "inv:" .. slot
		end
	end
	return nil
end

local function cleanup()
	state = "Idle"
	cast = nil
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if ui then
		ui:Destroy()
		ui = nil
	end
	local character = player.Character
	if character then
		character:SetAttribute("Bite", nil)
	end
end

local function banner(text: string, key: string?)
	if ui then
		ui:Destroy()
	end
	local frame = Kit.Panel({ Size = UDim2.fromOffset(260, 46), Shadow = true })
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -170)
	local label = Kit.Label(text, { Align = "Center", Font = Theme.Fonts.Heading, Size = 20, Color = key })
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = frame
	frame.Parent = C.UI.Layer("HUD")
	Kit.Pop(frame)
	ui = frame
	return frame
end

-- Minigame ---------------------------------------------------------------------------------------------------------

local function fishMotion(behavior: string, difficulty: number, t: number, current: number, dt: number, memory: any): number
	local speed = 0.25 + difficulty / 100 * 1.4
	if behavior == "Smooth" then
		return 0.5 + 0.38 * math.sin(t * speed * 1.6)
	elseif behavior == "Floater" then
		return 0.55 + 0.35 * math.sin(t * speed) + 0.08 * math.sin(t * speed * 3.1)
	elseif behavior == "Sinker" then
		return 0.35 + 0.3 * math.sin(t * speed * 1.2) - 0.1 * math.abs(math.sin(t * speed * 0.5))
	end
	-- Darting behaviours jump to new targets.
	memory.NextJump = memory.NextJump or 0
	if t >= memory.NextJump then
		local erratic = if behavior == "Legend" then 0.9 elseif behavior == "Mixed" then 0.6 else 0.45
		memory.Goal = math.clamp(current + random:NextNumber(-erratic, erratic), 0.05, 0.95)
		memory.NextJump = t + random:NextNumber(0.3, 1.4) / (0.6 + difficulty / 80)
	end
	local goal = memory.Goal or current
	return current + (goal - current) * math.min(1, dt * (2 + difficulty / 18))
end

local function runMinigame()
	state = "Reeling"
	if ui then
		ui:Destroy()
	end
	local root = Kit.Panel({ Size = UDim2.fromOffset(150, 380), Shadow = true, Name = "Fishing" })
	root.AnchorPoint = Vector2.new(1, 0.5)
	root.Position = UDim2.new(0.5, -60, 0.5, 0)
	root.Parent = C.UI.Layer("HUD")
	ui = root
	Kit.Pop(root)
	local well = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.new(0, 60, 1, -60), Position = UDim2.fromOffset(20, 40), Parent = root })
	Kit.Paint(well, "BackgroundColor3", "Info")
	well.BackgroundTransparency = 0.4
	Kit.Corner(well, 10)
	local zone = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, -8, cast.Zone, 0), Position = UDim2.new(0, 4, 1 - cast.Zone, 0), Parent = well })
	Kit.Paint(zone, "BackgroundColor3", "Good")
	zone.BackgroundTransparency = 0.25
	Kit.Corner(zone, 8)
	local fish = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Text = if cast.Legend then "🐉" else "🐟", TextScaled = true, Font = Theme.Fonts.Body, ZIndex = 5, Parent = well })
	local progress = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.new(0, 16, 1, -60), Position = UDim2.fromOffset(100, 40), Parent = root })
	Kit.Paint(progress, "BackgroundColor3", "Inset")
	Kit.Corner(progress, 8)
	local fill = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(1, GAME.StartProgress), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Parent = progress })
	Kit.Paint(fill, "BackgroundColor3", "Accent")
	Kit.Corner(fill, 8)
	local title = Kit.Label("Reel it in!", { Align = "Center", Font = Theme.Fonts.Heading, Size = 16 })
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Position = UDim2.fromOffset(0, 6)
	title.Parent = root
	local hint = Kit.Label(if C.Settings.PrimaryInput() == "Touch" then "Hold the screen" else "Hold click / Space", { Align = "Center", Size = 11, Color = "SubText" })
	hint.Size = UDim2.new(1, 0, 0, 18)
	hint.Position = UDim2.new(0, 0, 1, -20)
	hint.Parent = root

	local zonePos = 0 -- bottom of zone, 0..1-zone
	local zoneVel = 0
	local fishPos = 0.5
	local value = GAME.StartProgress
	local perfect = true
	local memory = {}
	local t0 = os.clock()
	local lastReel = 0
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		local pressing = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
			or UserInputService:IsKeyDown(Enum.KeyCode.Space)
			or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR2)
			or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
			or touches > 0
		zoneVel += (if pressing then 2.6 else -2.2) * dt
		zoneVel = math.clamp(zoneVel, -1.4, 1.4)
		zonePos += zoneVel * dt
		if zonePos <= 0 then
			zonePos = 0
			zoneVel = math.max(0, zoneVel) * 0.3
		elseif zonePos >= 1 - cast.Zone then
			zonePos = 1 - cast.Zone
			zoneVel = math.min(0, zoneVel) * 0.3
		end
		fishPos = math.clamp(fishMotion(cast.Behavior, cast.Difficulty, t, fishPos, dt, memory), 0.03, 0.97)
		local inside = fishPos >= zonePos and fishPos <= zonePos + cast.Zone
		if inside then
			value += (cast.Fill or GAME.FillRate) * dt
			if t - lastReel > 0.15 then
				lastReel = t
				C.Audio.PlayUI("Reel")
			end
		else
			value -= GAME.DrainRate * dt
			perfect = false
		end
		zone.Position = UDim2.new(0, 4, 1 - zonePos - cast.Zone, 0)
		fish.Position = UDim2.fromScale(0, 1 - fishPos)
		fill.Size = UDim2.fromScale(1, math.clamp(value, 0, 1))
		Kit.Paint(zone, "BackgroundColor3", if inside then "Good" else "Warn")
		if value >= 1 or value <= 0 or t > GAME.MaxSeconds then
			local caught = value >= 1
			local id = cast.Id
			cleanup()
			task.spawn(function()
				local ok, result = Net.Request("FishResolve", id, { Caught = caught, Perfect = caught and perfect })
				if not ok then
					C.Notify.Toast(tostring(result), "Warning")
				elseif caught and result and result.Caught then
					if perfect then
						C.Notify.Toast("🎯 Perfect catch!", "Success")
					end
					C.Animation.Play("Catch")
				else
					C.Notify.Toast("The fish got away…", "Info")
				end
			end)
		end
	end)
end

-- Cast -------------------------------------------------------------------------------------------------------------

function FishingController.Cast(position: Vector3)
	if state ~= "Idle" then
		-- Pressing again while waiting reels in early (no catch).
		if state == "Waiting" and cast then
			local id = cast.Id
			cleanup()
			task.spawn(Net.Request, "FishResolve", id, { Caught = false })
		end
		return
	end
	state = "Waiting"
	C.Animation.Play("Cast")
	C.Audio.PlayUI("Cast")
	local ok, result = Net.Request("FishCast", position, findBait())
	if not ok then
		state = "Idle"
		C.Notify.Toast(tostring(result), "Warning")
		return
	end
	cast = result
	C.Audio.PlayAt("Bobber", position)
	banner("🎣 Waiting for a bite…", "SubText")
	local myCast = cast
	task.delay(cast.BiteIn, function()
		if cast ~= myCast or (state :: string) ~= "Waiting" then
			return
		end
		state = "Bite"
		local character = player.Character
		if character then
			character:SetAttribute("Bite", true)
		end
		C.Audio.PlayUI("Bite")
		C.Camera.Shake(0.1, 0.25)
		banner("❗ BITE! Click / tap now!", "Bad")
		local hooked = false
		local hookConn
		hookConn = UserInputService.InputBegan:Connect(function(input, processed)
			if processed and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonA then
				hooked = true
			end
		end)
		local deadline = os.clock() + HOOK_WINDOW
		while os.clock() < deadline and not hooked and cast == myCast do
			task.wait()
		end
		hookConn:Disconnect()
		if cast ~= myCast then
			return
		end
		if hooked then
			if character then
				character:SetAttribute("Bite", nil)
			end
			runMinigame()
		else
			local id = myCast.Id
			cleanup()
			C.Notify.Toast("Too slow — it got away.", "Info")
			task.spawn(Net.Request, "FishResolve", id, { Caught = false })
		end
	end)
end

function FishingController.Start()
	UserInputService.TouchStarted:Connect(function()
		touches += 1
	end)
	UserInputService.TouchEnded:Connect(function()
		touches = math.max(0, touches - 1)
	end)
	-- Swapping tools or dying cancels fishing.
	local function watch(character: Model)
		character:GetAttributeChangedSignal("Held"):Connect(function()
			if state ~= "Idle" and character:GetAttribute("Held") ~= "tool_rod" then
				local id = cast and cast.Id
				cleanup()
				if id then
					task.spawn(Net.Request, "FishResolve", id, { Caught = false })
				end
			end
		end)
	end
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		cleanup()
		watch(character)
	end)
end

return FishingController
