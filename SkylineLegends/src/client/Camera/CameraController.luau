-- The runner's camera: a third-person orbit built for parkour.
--
--   * mouse (hold right button, or locked to centre), gamepad right stick and
--     touch drag on the right of the screen, each with its own sensitivity,
--     plus invert-Y
--   * collision that pulls in quickly and eases back out
--   * an optional follow assist that swings in behind you while you run
--   * speed FOV, wall-run tilt, landing dip and shake (all respect Reduced
--     Motion and their individual toggles)
--   * overrides for course previews, dialogue framing and results screens

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Input = require(script.Parent.Parent.Core.Input)
local Settings = require(script.Parent.Parent.Core.Settings)
local Controller = require(script.Parent.Parent.Movement.Controller)

local player = Players.LocalPlayer

local CameraController = {}

-- When set, called every frame instead of the orbit: returns (cframe, fov?).
type Override = (dt: number) -> (CFrame, number?)
local override: Override? = nil
local overrideBlend = 0

-- Set by UI while a full-screen menu is open (frees the mouse).
CameraController.MenuOpen = false

local MIN_PITCH = math.rad(-72)
local MAX_PITCH = math.rad(68)
local MIN_ZOOM = 6
local MAX_ZOOM = 42

local yaw = 0
local pitch = math.rad(-14)
local zoom = 15
local zoomTarget = 15
local actualDistance = 15
local lastManual = 0
local focusY: number? = nil
local focusVelocity = 0
local fov = 72
local tilt = 0
local trauma = 0
local dip = 0
local dipVelocity = 0
local fovPunch = 0
local stick = Vector2.zero
local cameraTouches: { [InputObject]: boolean } = {}
local pinchDistance: number? = nil
local lastCFrame = CFrame.identity

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.CollisionGroup = Tags.Groups.Players
params.RespectCanCollide = true

-- Helpers ------------------------------------------------------------------------------------------

local function yawFor(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

local function rotate(dx: number, dy: number)
	local invert = if Settings.Get("InvertY") then -1 else 1
	yaw -= dx
	pitch = math.clamp(pitch - dy * invert, MIN_PITCH, MAX_PITCH)
	lastManual = os.clock()
end

local function angleDelta(from: number, to: number): number
	return (to - from + math.pi) % (math.pi * 2) - math.pi
end

-- Public ---------------------------------------------------------------------------------------------

function CameraController.SetOverride(fn: Override?)
	override = fn
	if not fn then
		overrideBlend = 0
	end
end

function CameraController.HasOverride(): boolean
	return override ~= nil
end

-- Add trauma (0..1). Shake strength grows with its square.
function CameraController.Shake(amount: number)
	if Settings.Motion("CameraShake") then
		trauma = math.min(trauma + amount, 1)
	end
end

-- A brief FOV punch (dashes, launches).
function CameraController.Punch(degrees: number)
	if Settings.Motion("FovKick") then
		fovPunch = math.max(fovPunch, degrees)
	end
end

-- Swing the camera behind a direction (after a teleport or course start).
function CameraController.FaceDirection(direction: Vector3, instant: boolean?)
	local flat = MathUtil.Flat(direction)
	if flat.Magnitude < 0.01 then
		return
	end
	yaw = yawFor(flat.Unit)
	if instant then
		pitch = math.rad(-14)
		focusY = nil
	end
end

function CameraController.Yaw(): number
	return yaw
end

-- Frame ------------------------------------------------------------------------------------------

local function updateMouseBehaviour()
	if CameraController.MenuOpen or override then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		return
	end
	if Input.Device == "Keyboard" and Settings.Get("MouseLock") then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	elseif UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

local function readDevices(dt: number)
	if CameraController.MenuOpen then
		return
	end
	-- Mouse.
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
		local delta = UserInputService:GetMouseDelta()
		if delta.Magnitude > 0 then
			local k = 0.0042 * (Settings.Get("MouseSensitivity") or 1)
			rotate(delta.X * k, delta.Y * k)
		end
	end
	-- Gamepad right stick with a dead zone and a response curve.
	local magnitude = stick.Magnitude
	if magnitude > 0.14 then
		local scaled = math.clamp((magnitude - 0.14) / 0.86, 0, 1) ^ 1.6
		local direction = stick / magnitude
		local rate = 4.2 * (Settings.Get("PadSensitivity") or 1) * scaled * dt
		rotate(direction.X * rate, -direction.Y * rate * 0.7)
	end
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	updateMouseBehaviour()
	readDevices(dt)

	local info = Controller.Info
	local root = info.Root
	local baseFov = Settings.Get("FieldOfView") or 72

	-- Overrides (previews, dialogue, results) blend in.
	local active = override
	if active then
		local cframe, overrideFov = active(dt)
		overrideBlend = math.min(overrideBlend + dt * 3, 1)
		local alpha = MathUtil.Smooth(overrideBlend)
		camera.CFrame = lastCFrame:Lerp(cframe, alpha)
		camera.FieldOfView = MathUtil.Damp(camera.FieldOfView, overrideFov or baseFov, 6, dt)
		if alpha >= 1 then
			lastCFrame = cframe
		end
		return
	end
	if not root or not root.Parent then
		return
	end

	-- Zoom eases toward its target.
	zoomTarget = math.clamp(zoomTarget, MIN_ZOOM, MAX_ZOOM)
	zoom = MathUtil.Damp(zoom, zoomTarget, 10, dt)

	-- Focus: tight horizontally, sprung vertically so landings don't jolt the view.
	local position = root.Position + Vector3.new(0, 2.1, 0)
	local holding = info.State == "Ledge" or info.State == "Climb" or info.State == "Mantle" or info.State == "Vault"
	if not focusY or math.abs(position.Y - (focusY :: number)) > 30 then
		focusY = position.Y
		focusVelocity = 0
	else
		local current = focusY :: number
		local stiffness = if holding then 60 else 140
		focusVelocity += ((position.Y - current) * stiffness - focusVelocity * 2 * math.sqrt(stiffness)) * dt
		focusY = current + focusVelocity * dt
		focusY = math.clamp(focusY :: number, position.Y - 3, position.Y + 3)
	end
	local focus = Vector3.new(position.X, focusY :: number, position.Z)

	-- Follow assist: ease in behind the runner when nobody's steering the camera.
	local velocity = info.Velocity
	local flat = MathUtil.Flat(velocity)
	if Settings.Get("CameraAssist") and os.clock() - lastManual > 1.1 and flat.Magnitude > 12 then
		local look = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
		local alignment = look:Dot(flat.Unit)
		if alignment > -0.25 and (info.State == "Ground" or info.State == "WallRun" or info.State == "Slide" or info.State == "Zipline") then
			local rate = math.clamp((flat.Magnitude - 12) / 30, 0, 1) * 1.6
			local delta = angleDelta(yaw, yawFor(flat.Unit))
			yaw += delta * math.min(rate * dt, 1)
			-- Level the pitch slightly while running.
			pitch = MathUtil.Damp(pitch, math.rad(-12), 0.6, dt)
		end
	end

	-- Orbit and collision.
	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local backward = rotation.LookVector * -1
	local character = info.Character
	params.FilterDescendantsInstances = if character then { character, camera } else { camera }
	local wanted = zoom
	local hit = workspace:Spherecast(focus, 0.45, backward * wanted, params)
	local allowed = if hit then math.max(hit.Distance - 0.2, 1.2) else wanted
	if allowed < actualDistance then
		actualDistance = allowed
	else
		actualDistance = MathUtil.Damp(actualDistance, allowed, 4, dt)
	end

	-- Motion effects.
	local motion = not Settings.Get("ReducedMotion")
	local targetTilt = 0
	if motion and Settings.Get("CameraTilt") and info.State == "WallRun" and info.WallNormal then
		local right = rotation.RightVector
		targetTilt = math.rad(7) * math.sign(right:Dot(-(info.WallNormal :: Vector3)))
	end
	tilt = MathUtil.Damp(tilt, targetTilt, 6, dt)

	dipVelocity += (-dip * 120 - dipVelocity * 16) * dt
	dip += dipVelocity * dt

	local shakeOffset = CFrame.identity
	if trauma > 0 then
		trauma = math.max(trauma - dt * 1.6, 0)
		local amount = trauma * trauma
		local t = os.clock()
		shakeOffset = CFrame.Angles(
			math.rad(2.2) * amount * math.noise(t * 22, 1),
			math.rad(2.2) * amount * math.noise(t * 22, 2),
			math.rad(1.4) * amount * math.noise(t * 22, 3)
		)
	end

	local cframe = CFrame.new(focus + Vector3.new(0, dip, 0)) * rotation * CFrame.new(0, 0, actualDistance) * CFrame.Angles(0, 0, tilt) * shakeOffset
	camera.CFrame = cframe
	camera.Focus = CFrame.new(focus)
	lastCFrame = cframe

	-- Speed FOV.
	local targetFov = baseFov
	if motion and Settings.Get("FovKick") then
		local speed = velocity.Magnitude
		targetFov += math.clamp((speed - 22) / 50, 0, 1) * 14
	end
	fovPunch = MathUtil.Damp(fovPunch, 0, 5, dt)
	fov = MathUtil.Damp(fov, targetFov + fovPunch, 5, dt)
	camera.FieldOfView = fov
end

-- Input ------------------------------------------------------------------------------------------

local function onInputChanged(input: InputObject, processed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if not processed and not CameraController.MenuOpen then
			zoomTarget -= input.Position.Z * 2.5
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		stick = Vector2.new(input.Position.X, input.Position.Y)
	elseif input.UserInputType == Enum.UserInputType.Touch and cameraTouches[input] then
		local count = 0
		for _ in cameraTouches do
			count += 1
		end
		if count >= 2 then
			-- Pinch to zoom.
			local points = {}
			for touch in cameraTouches do
				table.insert(points, Vector2.new(touch.Position.X, touch.Position.Y))
			end
			local distance = (points[1] - points[2]).Magnitude
			if pinchDistance then
				zoomTarget -= (distance - pinchDistance) * 0.06
			end
			pinchDistance = distance
		else
			local k = 0.0075 * (Settings.Get("TouchSensitivity") or 1)
			rotate(input.Delta.X * k, input.Delta.Y * k)
		end
	end
end

function CameraController.Start()
	local camera = workspace.CurrentCamera
	if camera then
		local look = camera.CFrame.LookVector
		yaw = yawFor(MathUtil.FlatUnit(look))
	end
	fov = Settings.Get("FieldOfView") or 72

	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.Touch and not processed then
			local viewport = if workspace.CurrentCamera then workspace.CurrentCamera.ViewportSize else Vector2.new(1000, 600)
			-- The left of the screen belongs to the movement stick.
			if input.Position.X > viewport.X * 0.35 then
				cameraTouches[input] = true
				pinchDistance = nil
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.zero
		end
		if cameraTouches[input] then
			cameraTouches[input] = nil
			pinchDistance = nil
		end
	end)

	Controller.Landed:Connect(function(impact: number, kind: string)
		if not Settings.Get("ReducedMotion") then
			dipVelocity -= math.clamp(impact / 30, 0, 5) * (if kind == "Roll" then 0.4 else 1)
		end
		if kind == "Heavy" then
			CameraController.Shake(0.55)
		elseif kind == "Hard" then
			CameraController.Shake(0.3)
		end
	end)
	Controller.Action:Connect(function(action: string)
		if action == "Dash" then
			CameraController.Punch(8)
		elseif action == "Launch" or action == "Bounce" then
			CameraController.Punch(6)
			CameraController.Shake(0.15)
		elseif action == "Knocked" then
			CameraController.Shake(0.45)
		elseif action == "GrappleRelease" then
			CameraController.Punch(5)
		end
	end)
	Controller.Teleported:Connect(function(cframe: CFrame)
		CameraController.FaceDirection(cframe.LookVector, true)
		actualDistance = zoom
	end)
	player.CharacterAdded:Connect(function(character)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and root:IsA("BasePart") then
			CameraController.FaceDirection(root.CFrame.LookVector, true)
		end
	end)

	RunService:BindToRenderStep("SkylineCamera", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
