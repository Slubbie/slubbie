-- Surface icons: small shape markers on interactive surfaces (climbable walls,
-- beams, anchors, ropes, hazards, mechanisms) so nothing in a route relies on
-- colour alone. "Nearby" shows them within a short range, "Always" from much
-- further, and High Contrast makes them bolder.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Shared.Tags)

local Settings = require(script.Parent.Parent.Core.Settings)

local Icons = {}

local function apply(gui: Instance)
	if not gui:IsA("BillboardGui") then
		return
	end
	local mode = Settings.Get("SurfaceIcons") or "Nearby"
	local high = Settings.Get("HighContrast") == true
	gui.Enabled = mode ~= "Off"
	gui.MaxDistance = if mode == "Always" then 160 else 60
	local label = gui:FindFirstChildOfClass("TextLabel")
	if label then
		label.BackgroundTransparency = if high then 0 else 0.25
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = if high then 3.5 else 2
		end
	end
end

local function applyAll()
	for _, gui in CollectionService:GetTagged(Tags.SurfaceIcon) do
		apply(gui)
	end
end

function Icons.Start()
	applyAll()
	CollectionService:GetInstanceAddedSignal(Tags.SurfaceIcon):Connect(apply)
	Settings.Changed:Connect(function(id)
		if id == "SurfaceIcons" or id == "HighContrast" then
			applyAll()
		end
	end)
end

return Icons
