-- A simulated client: every controller loaded from src/client, started
-- against mocked engine services, with real Lune instances for the UI (so
-- invalid property names, enums and value types fail) and scripted server
-- responses for remotes.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Loader = require("./Loader")
local Mock = require("./Mock")

local Instance = roblox.Instance
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local Client = {}
Client.__index = Client

-- Stable mock signals per instance, for engine events Lune doesn't model.
local signalStore: { [number]: { [string]: any } } = {}
local nextId = 0
local function signalFor(instance: any, name: string)
	local id = instance:GetAttribute("MockId")
	if not id then
		nextId += 1
		id = nextId
		instance:SetAttribute("MockId", id)
	end
	local store = signalStore[id]
	if not store then
		store = {}
		signalStore[id] = store
	end
	local signal = store[name]
	if not signal then
		signal = Mock.Signal()
		store[name] = signal
	end
	return signal
end

local installed = false
local currentServerTime = { Value = 1000 }
local function installEngineShims()
	if installed then
		return
	end
	installed = true
	local guiEvents = {
		"MouseEnter",
		"MouseLeave",
		"MouseButton1Down",
		"MouseButton1Up",
		"Activated",
		"SelectionGained",
		"SelectionLost",
		"InputBegan",
		"InputEnded",
	}
	for _, className in
		{
			"TextButton",
			"TextLabel",
			"Frame",
			"ScrollingFrame",
			"ViewportFrame",
			"ImageLabel",
			"ImageButton",
			"TextBox",
		}
	do
		for _, event in guiEvents do
			pcall(roblox.implementProperty, className, event, function(instance)
				return signalFor(instance, event)
			end)
		end
	end
	pcall(roblox.implementProperty, "ProximityPrompt", "Triggered", function(instance)
		return signalFor(instance, "Triggered")
	end)
	pcall(roblox.implementProperty, "BasePart", "Touched", function(instance)
		return signalFor(instance, "Touched")
	end)
	roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(instance, property)
		return signalFor(instance, "Changed:" .. property)
	end)
	pcall(roblox.implementProperty, "BindableEvent", "Event", function(instance)
		return signalFor(instance, "Event")
	end)
	roblox.implementMethod("BindableEvent", "Fire", function(instance, ...)
		signalFor(instance, "Event"):Fire(...)
	end)
	roblox.implementMethod("Sound", "Play", function() end)
	roblox.implementMethod("Sound", "Stop", function() end)
	roblox.implementMethod("ParticleEmitter", "Emit", function() end)
	roblox.implementMethod("Workspace", "GetServerTimeNow", function()
		return currentServerTime.Value
	end)
	roblox.implementMethod("Workspace", "Raycast", function()
		return nil
	end)
	roblox.implementMethod("Camera", "WorldToViewportPoint", function()
		return Vector3.new(640, 360, 10), true
	end)
end

function Client.new(responses: { [string]: (...any) -> any }, snapshot: { [string]: any })
	installEngineShims()
	local self = setmetatable({}, Client)
	local loader = Loader.new(".", {})
	self.Loader = loader
	self.Responses = responses
	self.Invocations = {}
	self.Fired = {}

	-- Engine services.
	local playerGui = Instance.new("PlayerGui")
	local character = Mock.Character(Vector3.new(0, 43, 110))
	local localPlayer = {
		Name = "Tester",
		DisplayName = "Tester",
		UserId = 1,
		Character = character,
		CharacterAdded = Mock.Signal(),
		PlayerGui = playerGui,
	}
	function localPlayer:WaitForChild(name)
		if name == "PlayerGui" then
			return playerGui
		end
		return {
			WaitForChild = function()
				return nil
			end,
		}
	end
	self.LocalPlayer = localPlayer
	self.PlayerGui = playerGui

	local players = { LocalPlayer = localPlayer }
	function players:GetPlayers()
		return { localPlayer }
	end

	local renderStepped = Mock.Signal()
	local heartbeat = Mock.Signal()
	local renderSteps = {}
	local runService = { RenderStepped = renderStepped, Heartbeat = heartbeat }
	function runService:BindToRenderStep(name, _priority, fn)
		renderSteps[name] = fn
	end
	function runService:IsClient()
		return true
	end
	function runService:IsServer()
		return false
	end
	self.RenderStepped = renderStepped
	self.Heartbeat = heartbeat
	self.RenderSteps = renderSteps

	local tweenService = {}
	function tweenService:Create(target, _info, props)
		local tween = { Completed = Mock.Signal() }
		function tween:Play()
			for key, value in props do
				target[key] = value
			end
			task.defer(function()
				tween.Completed:Fire(Enum.PlaybackState.Completed)
			end)
		end
		function tween:Cancel() end
		return tween
	end

	local userInput = {
		TouchEnabled = false,
		KeyboardEnabled = true,
		LastInputTypeChanged = Mock.Signal(),
		InputBegan = Mock.Signal(),
	}
	function userInput:GetLastInputType()
		return Enum.UserInputType.Keyboard
	end
	function userInput:GetFocusedTextBox()
		return nil
	end

	local boundActions = {}
	local contextActions = {}
	function contextActions:BindAction(name, fn)
		boundActions[name] = fn
	end
	function contextActions:BindActionAtPriority(name, fn)
		boundActions[name] = fn
	end
	function contextActions:UnbindAction(name)
		boundActions[name] = nil
	end
	self.BoundActions = boundActions

	local collection = {}
	function collection:GetTagged()
		return {}
	end
	function collection:GetInstanceAddedSignal()
		return Mock.Signal()
	end
	function collection:GetInstanceRemovedSignal()
		return Mock.Signal()
	end

	local workspaceInstance = Instance.new("Workspace")
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 55, 140), Vector3.new(0, 43, 110))
	camera.FieldOfView = 70
	pcall(function()
		camera.ViewportSize = Vector2.new(1280, 720)
	end)
	camera.Parent = workspaceInstance
	workspaceInstance.CurrentCamera = camera
	local terrain = Instance.new("Terrain")
	terrain.Parent = workspaceInstance
	self.Workspace = workspaceInstance

	local services = loader.Services
	services.Players = players
	services.RunService = runService
	services.TweenService = tweenService
	services.UserInputService = userInput
	services.GuiService = { SelectedObject = nil }
	services.ContextActionService = contextActions
	services.ProximityPromptService = { PromptTriggered = Mock.Signal() }
	services.SoundService = Instance.new("SoundService")
	services.CollectionService = collection
	services.Debris = { AddItem = function() end }
	services.StarterGui = { SetCoreGuiEnabled = function() end }
	services.Workspace = workspaceInstance
	loader.Globals.workspace = workspaceInstance
	-- Engine-computed properties have no defaults in Lune's DOM; give new
	-- instances the values the engine would.
	loader.Globals.Instance = {
		new = function(className, parent)
			local instance = Instance.new(className)
			pcall(function()
				if instance:IsA("Sound") then
					instance.IsPlaying = false
				elseif instance:IsA("GuiObject") then
					instance.AbsolutePosition = Vector2.new(0, 0)
					instance.AbsoluteSize = Vector2.new(100, 100)
				end
			end)
			if parent then
				instance.Parent = parent
			end
			return instance
		end,
	}

	-- Mount src/client.
	local starter = Loader.NewNode("StarterPlayerScripts", "Folder", nil)
	local clientRoot = Loader.NewNode("Client", "Folder", starter)
	local function mount(dir: string, parent: any)
		for _, entry in fs.readDir(dir) do
			local path = `{dir}/{entry}`
			if fs.isDir(path) then
				mount(path, Loader.NewNode(entry, "Folder", parent))
			elseif entry:match("%.luau$") and not entry:match("%.client%.luau$") then
				Loader.NewNode((entry:gsub("%.luau$", "")), "ModuleScript", parent, path)
			end
		end
	end
	mount("src/client", clientRoot)
	self.ClientRoot = clientRoot

	-- Remotes answered by the test's scripted server.
	local RemoteDefinitions = loader:require("Shared.RemoteDefinitions")
	local events = {}
	RemoteDefinitions.GetFunction = function(name)
		return {
			InvokeServer = function(_, ...)
				table.insert(self.Invocations, { Name = name, Args = { ... } })
				local handler = responses[name]
				return if handler then handler(...) else { Ok = false, Reason = "Unscripted" }
			end,
		}
	end
	RemoteDefinitions.GetEvent = function(name)
		local event = events[name]
		if not event then
			event = {
				OnClientEvent = Mock.Signal(),
				FireServer = function(_, ...)
					table.insert(self.Fired, { Name = name, Args = { ... } })
				end,
			}
			events[name] = event
		end
		return event
	end
	self.Events = events
	responses.StateSnapshot = responses.StateSnapshot or function()
		return { Ok = true, Snapshot = snapshot }
	end

	-- Controllers.
	local registry = {}
	registry.Components = loader:require(clientRoot.UI.Components)
	registry.Viewport = loader:require(clientRoot.UI.Viewport)
	self.Registry = registry
	self.Order = {
		"ClientState",
		"InputController",
		"PanelManager",
		"AudioController",
		"SettingsController",
		"CameraController",
		"EffectsController",
		"NotificationController",
		"CometController",
		"CaptureController",
		"RevealController",
		"WispController",
		"CreatureAnimator",
		"AmbientController",
		"SanctuaryController",
		"InventoryController",
		"WorkshopController",
		"HUDController",
		"ObjectiveController",
	}
	for _, name in self.Order do
		registry[name] = loader:require(clientRoot.Controllers[name])
	end
	return self
end

function Client:Boot()
	local registry = self.Registry
	registry.Components.UpdateScale(Vector2.new(1280, 720))
	for _, name in self.Order do
		local controller = registry[name]
		if controller.Init then
			controller.Init(registry)
		end
	end
	assert(registry.ClientState.Load(), "snapshot failed to load")
	for _, name in self.Order do
		local controller = registry[name]
		if controller.Start and name ~= "ClientState" then
			controller.Start()
		end
	end
end

function Client:SetServerTime(value: number)
	currentServerTime.Value = value
end

-- Runs render and heartbeat callbacks for `frames` frames of `dt` seconds.
function Client:Step(frames: number, dt: number?)
	local step = dt or 1 / 60
	for _ = 1, frames do
		currentServerTime.Value += step
		self.RenderStepped:Fire(step)
		self.Heartbeat:Fire(step)
		for _, fn in self.RenderSteps do
			fn(step)
		end
	end
end

-- Delivers a server → client event.
function Client:Receive(eventName: string, ...: any)
	local event = self.Registry.ClientState and self.Loader:require("Shared.RemoteDefinitions").GetEvent(eventName)
	event.OnClientEvent:Fire(...)
end

function Client:Settle()
	for _ = 1, 4 do
		task.wait()
	end
end

return Client
