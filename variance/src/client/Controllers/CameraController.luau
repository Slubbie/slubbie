-- Camera direction.
--
-- Modes:
--   Lobby     Roblox's default follow camera.
--   Seat      first person from the subject's own head at the table. Look
--             input (right mouse drag, right stick, drag) turns the head within
--             a natural range; the head direction is replicated so opponents see
--             where you look. Your own head and hats are hidden; your arms and
--             hands stay visible, so you watch yourself pick up the Arbiter.
--   Shot      scripted cinematic moves (match intro, trial cards, results),
--             then back to the seat. The Cinematic Camera setting shortens or
--             skips them.
--   Spectate  a slow orbit over the table (drag to orbit) or a seat's view.
--   Orbit     a slow circle around the table behind the results screen.
--
-- Layered on top: recoil kicks, trauma-based shake, FOV punches, soft focus
-- pulls toward the action (never fighting the player's own look), and the
-- slump when your Integrity reaches zero. Camera Shake and Reduced Motion
-- scale every one of them.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TableLayout = require(ReplicatedStorage.Variance.Visual.TableLayout)

local CameraController = {}

local camera: Camera = workspace.CurrentCamera
local mode = "Lobby"
local seatInfo: { Origin: CFrame, Seat: number }? = nil
local yaw, pitch = 0, 0 -- player look (radians, relative to the seat's facing)
local lastLookInput = 0
local focus: { Point: Vector3, Strength: number, Until: number }? = nil
local focusYaw, focusPitch = 0, 0
local kickPitch, kickYaw = 0, 0
local kickVelPitch, kickVelYaw = 0, 0
local trauma = 0
local fovPunch = 0
local slump = 0
local slumpTarget = 0
local pullBack = 0
local pullBackTarget = 0
local shotQueue: { { [string]: any } } = {}
local shot: { [string]: any }? = nil
local orbit = { Centre = Vector3.zero, Angle = 0, Radius = 16, Height = 9, Speed = 0.08 }
local spectateSeat: number? = nil
local hidden: { [BasePart]: boolean } = {}
local blur: BlurEffect? = nil
local grade: ColorCorrectionEffect? = nil
local noiseSeed = math.random() * 100

local BASE_PITCH = -0.3
local YAW_LIMIT, PITCH_MIN, PITCH_MAX = 1.25, -0.95, 0.55

function CameraController:Init(controllers)
	self.Controllers = controllers
end

local function settings()
	return CameraController.Controllers.SettingsController
end

local function motionScale(): number
	local s = settings()
	local base = s:get("CameraShake") or 0.7
	if s:get("ReducedMotion") then
		base *= 0.3
	end
	return base
end

local function fov(): number
	return settings():get("FieldOfView") or 68
end

---------------------------------------------------------------------------
-- Own-head visibility in first person
---------------------------------------------------------------------------

local function setHeadHidden(hide: boolean)
	local character = Players.LocalPlayer.Character
	if hide and character then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				local accessory = d:FindFirstAncestorOfClass("Accessory")
				local isHead = d.Name == "Head" or d.Name == "VarianceHeadwear" or accessory ~= nil
				if isHead then
					d.LocalTransparencyModifier = 1
					hidden[d] = true
				end
			elseif d:IsA("Decal") and d.Parent and d.Parent.Name == "Head" then
				d.Transparency = 1
			end
		end
	else
		for part in hidden do
			if part.Parent then
				part.LocalTransparencyModifier = 0
			end
		end
		table.clear(hidden)
		if character then
			local head = character:FindFirstChild("Head")
			if head then
				for _, d in head:GetChildren() do
					if d:IsA("Decal") then
						d.Transparency = 0
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Mode switching
---------------------------------------------------------------------------

function CameraController:mode(): string
	return mode
end

function CameraController:toLobby()
	mode = "Lobby"
	shot = nil
	table.clear(shotQueue)
	seatInfo = nil
	spectateSeat = nil
	slumpTarget, slump = 0, 0
	pullBackTarget, pullBack = 0, 0
	setHeadHidden(false)
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	camera.FieldOfView = 70
end

-- Sits the camera at a seat. `origin` is the arena origin CFrame.
function CameraController:toSeat(origin: CFrame, seat: number)
	seatInfo = { Origin = origin, Seat = seat }
	yaw, pitch = 0, BASE_PITCH
	focusYaw, focusPitch = 0, 0
	slumpTarget, slump = 0, 0
	mode = "Seat"
	camera.CameraType = Enum.CameraType.Scriptable
	setHeadHidden(true)
end

function CameraController:toSpectate(origin: CFrame)
	seatInfo = { Origin = origin, Seat = 1 }
	orbit.Centre = (origin * CFrame.new(0, TableLayout.TableTop, 0)).Position
	orbit.Angle = math.random() * math.pi * 2
	orbit.Radius, orbit.Height, orbit.Speed = 15, 8.5, 0.07
	spectateSeat = nil
	mode = "Spectate"
	camera.CameraType = Enum.CameraType.Scriptable
	setHeadHidden(false)
end

-- Spectators can ride along in a seat's view (nil = orbit).
function CameraController:spectateSeat(seat: number?)
	spectateSeat = seat
	yaw, pitch = 0, BASE_PITCH
end

function CameraController:toOrbit(origin: CFrame)
	orbit.Centre = (origin * CFrame.new(0, TableLayout.TableTop, 0)).Position
	orbit.Radius, orbit.Height, orbit.Speed = 13, 6, 0.1
	mode = "Orbit"
	camera.CameraType = Enum.CameraType.Scriptable
	setHeadHidden(false)
end

-- Where the local player is looking (yaw, pitch relative to the seat).
function CameraController:look(): (number, number)
	return yaw, pitch
end

---------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------

-- Recoil-style impulse (radians).
function CameraController:kick(pitchAmount: number, yawAmount: number?)
	local s = motionScale()
	kickVelPitch += pitchAmount * 22 * s
	kickVelYaw += (yawAmount or 0) * 22 * s
end

-- Trauma 0..1; shake is trauma squared, decaying.
function CameraController:shake(amount: number)
	trauma = math.clamp(trauma + amount, 0, 1)
end

function CameraController:punch(degrees: number)
	fovPunch += degrees * (if settings():get("ReducedMotion") then 0.3 else 1)
end

-- Gently pulls the view toward a point for `duration` seconds. Strength 0..1.
function CameraController:focus(point: Vector3?, strength: number?, duration: number?)
	if point == nil then
		focus = nil
		return
	end
	local cinematics = settings():get("Cinematics") or "Full"
	local s = (strength or 0.5) * (if cinematics == "Minimal" then 0.35 elseif cinematics == "Reduced" then 0.7 else 1)
	focus = { Point = point, Strength = s, Until = os.clock() + (duration or 1.5) }
end

-- Eliminated: the view sags and greys out.
function CameraController:setSlump(on: boolean)
	slumpTarget = if on then 1 else 0
end

-- Pull back from the face (aiming at yourself, 0..1).
function CameraController:setPullBack(amount: number)
	pullBackTarget = math.clamp(amount, 0, 1)
end

-- Queues cinematic shots: { From = CFrame, To = CFrame, Duration, Fov?, Essential? }.
-- With Cinematic Camera "Minimal" only essential shots play (shortened).
function CameraController:shots(list: { { [string]: any } }, replace: boolean?)
	local cinematics = settings():get("Cinematics") or "Full"
	if replace then
		table.clear(shotQueue)
		shot = nil
	end
	for _, s in list do
		if cinematics ~= "Minimal" or s.Essential then
			local copy = table.clone(s)
			if cinematics == "Reduced" then
				copy.Duration = copy.Duration * 0.7
			elseif cinematics == "Minimal" then
				copy.Duration = math.min(copy.Duration, 1.2)
			end
			table.insert(shotQueue, copy)
		end
	end
end

function CameraController:cancelShots()
	table.clear(shotQueue)
	shot = nil
end

function CameraController:inShot(): boolean
	return shot ~= nil or #shotQueue > 0
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local function seatEye(): CFrame
	local info = seatInfo :: { Origin: CFrame, Seat: number }
	local anim = CameraController.Controllers.AnimationController
	local rig = anim:rigFor(Players.LocalPlayer.Character)
	local facing = info.Origin * TableLayout.seatCFrame(info.Seat)
	local eyePos
	if rig and rig.Head then
		eyePos = (rig.Head * CFrame.new(0, 0.12, -0.3)).Position
	else
		eyePos = (info.Origin * TableLayout.eyeCFrame(info.Seat)).Position
	end
	return CFrame.new(eyePos) * facing.Rotation
end

local function noise(t: number, s: number): number
	return math.sin(t * 13.1 + s) * 0.5 + math.sin(t * 23.7 + s * 1.7) * 0.3 + math.sin(t * 41.3 + s * 0.3) * 0.2
end

local function frame(dt: number)
	local self = CameraController
	if mode == "Lobby" then
		camera.FieldOfView += (70 + fovPunch - camera.FieldOfView) * math.min(1, dt * 8)
		fovPunch *= math.exp(-6 * dt)
		return
	end
	local now = os.clock()
	local input = self.Controllers.InputController
	local s = settings()
	local sensitivity = (s:get("Sensitivity") or 1) * 0.0055
	local delta = input:takeLook(dt)
	if delta.Magnitude > 0 then
		lastLookInput = now
	end
	local invert = if s:get("InvertY") then -1 else 1

	-- Spring the recoil back to zero.
	kickVelPitch += (-kickPitch * 160 - kickVelPitch * 18) * dt
	kickVelYaw += (-kickYaw * 160 - kickVelYaw * 18) * dt
	kickPitch += kickVelPitch * dt
	kickYaw += kickVelYaw * dt
	trauma = math.max(0, trauma - dt * 0.9)
	fovPunch *= math.exp(-5 * dt)
	slump += (slumpTarget - slump) * (1 - math.exp(-1.5 * dt))
	pullBack += (pullBackTarget - pullBack) * (1 - math.exp(-4 * dt))
	local shakeAmount = trauma * trauma * motionScale()
	local shakeRot = CFrame.Angles(
		noise(now, noiseSeed) * 0.05 * shakeAmount,
		noise(now, noiseSeed + 10) * 0.05 * shakeAmount,
		noise(now, noiseSeed + 20) * 0.07 * shakeAmount
	)

	if blur then
		blur.Size = slump * 10
	end
	if grade then
		grade.Saturation = -0.7 * slump
		grade.Brightness = -0.1 * slump
	end

	-- Cinematic shots take over completely.
	if shot == nil and #shotQueue > 0 then
		shot = table.remove(shotQueue, 1)
		shot.Start = now
	end
	if shot then
		local t = math.clamp((now - shot.Start) / shot.Duration, 0, 1)
		local a = t * t * (3 - 2 * t)
		local cf = shot.From:Lerp(shot.To or shot.From, a)
		camera.CFrame = cf * shakeRot
		camera.FieldOfView = (shot.Fov or 50) + fovPunch
		if t >= 1 then
			shot = nil
		end
		return
	end

	if mode == "Seat" or (mode == "Spectate" and spectateSeat) then
		yaw = math.clamp(yaw - delta.X * sensitivity, -YAW_LIMIT, YAW_LIMIT)
		pitch = math.clamp(pitch - delta.Y * sensitivity * invert, PITCH_MIN, PITCH_MAX)
		local eye
		if mode == "Spectate" and spectateSeat and seatInfo then
			eye = CFrame.new((seatInfo.Origin * TableLayout.eyeCFrame(spectateSeat)).Position)
				* (seatInfo.Origin * TableLayout.seatCFrame(spectateSeat)).Rotation
		else
			eye = seatEye()
		end
		-- Focus pulls only while the player isn't steering the view.
		local fy, fp = 0, 0
		if focus and now < focus.Until and now - lastLookInput > 0.8 then
			local local_ = eye:PointToObjectSpace(focus.Point)
			local wantYaw = math.atan2(-local_.X, -local_.Z)
			local wantPitch = math.atan2(local_.Y, Vector2.new(local_.X, local_.Z).Magnitude)
			fy = (wantYaw - yaw) * focus.Strength
			fp = (wantPitch - pitch) * focus.Strength
		end
		local k = 1 - math.exp(-3 * dt)
		focusYaw += (fy - focusYaw) * k
		focusPitch += (fp - focusPitch) * k
		local finalYaw = yaw + focusYaw + kickYaw
		local finalPitch = pitch + focusPitch + kickPitch - slump * 0.55
		local cf = eye
			* CFrame.Angles(0, finalYaw, 0)
			* CFrame.Angles(finalPitch, 0, slump * 0.25)
			* CFrame.new(0, -slump * 0.4, pullBack * 0.9)
		camera.CFrame = cf * shakeRot
		camera.FieldOfView = fov() + fovPunch - pullBack * 6
		if mode == "Seat" then
			self.Controllers.NetworkClient:look(yaw + focusYaw, pitch + focusPitch)
			local anim = self.Controllers.AnimationController
			local rig = anim:rigFor(Players.LocalPlayer.Character)
			if rig then
				anim:setLook(rig, yaw + focusYaw, pitch + focusPitch)
			end
		end
		return
	end

	-- Orbit / spectate orbit.
	orbit.Angle += dt * orbit.Speed - delta.X * sensitivity * 0.6
	orbit.Height = math.clamp(orbit.Height + delta.Y * 0.02, 3, 14)
	local pos = orbit.Centre
		+ Vector3.new(math.cos(orbit.Angle) * orbit.Radius, orbit.Height, math.sin(orbit.Angle) * orbit.Radius)
	local target = orbit.Centre
	if focus and now < focus.Until then
		target = orbit.Centre:Lerp(focus.Point, 0.5 * focus.Strength)
	end
	camera.CFrame = CFrame.lookAt(pos, target) * shakeRot
	camera.FieldOfView = 50 + fovPunch
end

function CameraController:Start()
	blur = Instance.new("BlurEffect")
	blur.Name = "VarianceSlumpBlur"
	blur.Size = 0
	blur.Parent = Lighting
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "VarianceSlumpGrade"
	grade.Parent = Lighting
	RunService:BindToRenderStep("VarianceCamera", Enum.RenderPriority.Camera.Value + 1, frame)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		if mode == "Lobby" then
			task.defer(function()
				self:toLobby()
			end)
		elseif mode == "Seat" then
			task.defer(setHeadHidden, true)
		end
	end)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		camera = workspace.CurrentCamera
	end)
end

return CameraController
