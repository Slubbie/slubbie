-- Creature portraits in ViewportFrames: inventory cards, detail views,
-- reveals and the collection book. The camera does the turning, so
-- procedural models never need joints solved inside the viewport.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureRig = require(Shared.CreatureRig)

local Viewport = {}

export type Options = {
	Mutation: string?,
	Silhouette: boolean?,
	Yaw: number?, -- degrees around the creature (0 = straight on)
	Pitch: number?,
	Zoom: number?,
}

export type Portrait = {
	Frame: ViewportFrame,
	Model: Model,
	Camera: Camera,
	SetYaw: (number) -> (),
	Destroy: () -> (),
}

function Viewport.Creature(parent: Instance, speciesId: string, options: Options?): Portrait
	local o = options or {}
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Portrait"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Ambient = Color3.fromRGB(170, 160, 210)
	frame.LightColor = Color3.fromRGB(255, 248, 240)
	frame.LightDirection = Vector3.new(-0.6, -1, 0.8)

	local model = CreatureRig.Build(speciesId, {
		Mutation = o.Mutation,
		ForViewport = true,
		Silhouette = o.Silhouette,
	})
	model.Parent = frame

	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = frame
	frame.CurrentCamera = camera

	local height = (model:GetAttribute("Height") :: number?) or 3
	local radius = (model:GetAttribute("Radius") :: number?) or 2
	local target = Vector3.new(0, height * 0.5, 0)
	local extent = math.max(height * 0.62, radius * 1.15)
	local distance = extent / math.tan(math.rad(15)) * (o.Zoom or 1)
	local pitch = math.rad(o.Pitch or 12)

	local function setYaw(degrees: number)
		local yaw = math.rad(degrees)
		local offset = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
			* distance
		camera.CFrame = CFrame.lookAt(target + offset, target)
	end
	setYaw(o.Yaw or 28)
	frame.Parent = parent

	return {
		Frame = frame,
		Model = model,
		Camera = camera,
		SetYaw = setYaw,
		Destroy = function()
			frame:Destroy()
		end,
	}
end

-- Slowly turns a portrait until the returned function is called.
function Viewport.Spin(portrait: Portrait, degreesPerSecond: number?): () -> ()
	local yaw = 28
	local connection = RunService.RenderStepped:Connect(function(dt)
		yaw += dt * (degreesPerSecond or 30)
		portrait.SetYaw(yaw)
	end)
	return function()
		connection:Disconnect()
	end
end

return Viewport
