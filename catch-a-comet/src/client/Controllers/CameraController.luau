-- Camera feedback layered on top of the default camera: short shakes for
-- impacts and FOV punches for big moments. Both shrink to almost nothing with
-- Reduced Motion on.

local RunService = game:GetService("RunService")

local CameraController = {}

local controllers: { [string]: any } = {}
local shakeTime, shakeDuration, shakeStrength = 0, 0, 0
local fovOffset, fovTarget = 0, 0
local baseFov = 70

function CameraController.Shake(strength: number, duration: number)
	if controllers.SettingsController.ReducedMotion() then
		strength *= 0.15
	end
	if strength > shakeStrength * (1 - shakeTime / math.max(shakeDuration, 0.01)) then
		shakeStrength = strength
		shakeDuration = duration
		shakeTime = 0
	end
end

function CameraController.FovPunch(amount: number)
	if controllers.SettingsController.ReducedMotion() then
		return
	end
	fovTarget = amount
	task.delay(0.18, function()
		fovTarget = 0
	end)
end

function CameraController.Init(registry: { [string]: any })
	controllers = registry
end

function CameraController.Start()
	local camera = workspace.CurrentCamera
	baseFov = camera.FieldOfView
	RunService:BindToRenderStep("CometCameraFX", Enum.RenderPriority.Camera.Value + 1, function(dt)
		camera = workspace.CurrentCamera
		if shakeTime < shakeDuration then
			shakeTime += dt
			local fade = 1 - shakeTime / shakeDuration
			local t = os.clock() * 38
			local offset = Vector3.new(math.noise(t, 0.3), math.noise(0.7, t), 0) * shakeStrength * fade
			camera.CFrame *= CFrame.new(offset) * CFrame.Angles(0, 0, math.noise(t, 2.1) * 0.01 * shakeStrength * fade)
		end
		fovOffset += (fovTarget - fovOffset) * math.min(dt * 10, 1)
		if math.abs(fovOffset) > 0.01 then
			camera.FieldOfView = baseFov + fovOffset
		elseif camera.FieldOfView ~= baseFov and fovTarget == 0 then
			camera.FieldOfView = baseFov
		end
	end)
end

return CameraController
