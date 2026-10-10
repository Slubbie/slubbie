-- One modal panel at a time. Opening a panel closes the current one, a dim
-- backdrop sits behind it (tap/click to close), gamepad B closes it, and
-- gamepad selection moves into the panel when a controller is in use.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)
local UITheme = require(Shared.UITheme)

local PanelManager = {}

-- (name | nil)
PanelManager.Changed = Signal.new()

type Entry = {
	Panel: any,
	OnOpen: ((...any) -> ())?,
	OnClose: (() -> ())?,
}

local controllers: { [string]: any } = {}
local entries: { [string]: Entry } = {}
local current: string? = nil
local gui: ScreenGui
local backdrop: TextButton

function PanelManager.Gui(): ScreenGui
	return gui
end

function PanelManager.Register(name: string, panel: any, onOpen: ((...any) -> ())?, onClose: (() -> ())?)
	entries[name] = { Panel = panel, OnOpen = onOpen, OnClose = onClose }
	panel.Close.Activated:Connect(function()
		if current == name then
			PanelManager.Close()
		end
	end)
end

function PanelManager.Current(): string?
	return current
end

function PanelManager.IsOpen(name: string?): boolean
	if name then
		return current == name
	end
	return current ~= nil
end

function PanelManager.Close()
	local name = current
	if not name then
		return
	end
	current = nil
	local entry = entries[name]
	controllers.Components.ShowPanel(entry.Panel.Root, false)
	backdrop.Visible = false
	ContextActionService:UnbindAction("ClosePanel")
	GuiService.SelectedObject = nil
	controllers.AudioController.Play("UIClose")
	if entry.OnClose then
		entry.OnClose()
	end
	PanelManager.Changed:Fire(nil)
end

function PanelManager.Open(name: string, ...: any)
	local entry = entries[name]
	if not entry then
		warn(`[Panels] Unknown panel {name}`)
		return
	end
	if current == name then
		if entry.OnOpen then
			entry.OnOpen(...)
		end
		return
	end
	if current then
		PanelManager.Close()
	end
	current = name
	backdrop.Visible = true
	controllers.Components.ShowPanel(entry.Panel.Root, true)
	controllers.AudioController.Play("UIOpen")
	ContextActionService:BindAction("ClosePanel", function(_, state)
		if state == Enum.UserInputState.Begin then
			PanelManager.Close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonB)
	if entry.OnOpen then
		entry.OnOpen(...)
	end
	controllers.Components.FocusFirst(entry.Panel.FirstSelectable or entry.Panel.Close)
	PanelManager.Changed:Fire(name)
end

function PanelManager.Toggle(name: string, ...: any)
	if current == name then
		PanelManager.Close()
	else
		PanelManager.Open(name, ...)
	end
end

function PanelManager.Init(registry: { [string]: any })
	controllers = registry
end

function PanelManager.Start()
	local Components = controllers.Components
	gui = Components.Screen("Panels", 10)
	backdrop = Components.Make("TextButton", {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(2, 0, 2, 0),
		Position = UDim2.fromScale(-0.5, -0.5),
		BackgroundColor3 = UITheme.Colors.Background,
		BackgroundTransparency = 0.45,
		Visible = false,
		Selectable = false,
		Parent = gui,
	})
	backdrop.Activated:Connect(PanelManager.Close)
end

return PanelManager
