-- Window manager. Screens live in UI/Screens as modules:
--
--   return {
--     Id = "Inventory", Title = "Backpack", Icon = "🎒", Size = Vector2.new(900, 560),
--     Build = function(win, ctx) return { Refresh = fn?, Destroy = fn? } end,
--   }
--
-- One main window is open at a time (opening another replaces it). Esc /
-- gamepad B closes it; the game world is blurred behind; the server is told a
-- blocking menu is open (it can slow time in solo private servers).

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Signal = require(Shared.Lib.Signal)

local C = require(script.Parent)
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UIFolder.Kit)

local Windows = {}
Windows.Opened = Signal.new() -- (id)
Windows.Closed = Signal.new() -- (id)

type Open = { Id: string, Window: any, Handle: any, Def: any }
local current: Open? = nil
local blur: BlurEffect
local cache: { [string]: any } = {}

local function screenDef(id: string): any?
	if cache[id] ~= nil then
		return cache[id] or nil
	end
	local module = UIFolder.Screens:FindFirstChild(id)
	if not module then
		warn("[Evergrove] No screen named", id)
		cache[id] = false
		return nil
	end
	local ok, def = pcall(require, module)
	if not ok then
		warn("[Evergrove] Screen", id, "failed to load:", def)
		cache[id] = false
		return nil
	end
	cache[id] = def
	return def
end

function Windows.Current(): string?
	return if current then current.Id else nil
end

function Windows.IsOpen(id: string?): boolean
	if id then
		return current ~= nil and current.Id == id
	end
	return current ~= nil
end

function Windows.Close(silent: boolean?)
	local open = current
	if not open then
		return
	end
	current = nil
	if open.Handle and open.Handle.Destroy then
		pcall(open.Handle.Destroy)
	end
	local root = open.Window.Root
	Kit.HideTooltip()
	Kit.PopOut(root, function()
		root:Destroy()
	end)
	if not Kit.ReducedMotion then
		task.delay(0.15, function()
			if root.Parent then
				root:Destroy()
			end
		end)
	end
	Kit.Tween(blur, { Size = 0 }, 0.2)
	GuiService.SelectedObject = nil
	if not silent then
		C.Audio.PlayUI("UIClose")
	end
	Net.Send("MenuState", false)
	Windows.Closed:Fire(open.Id)
end

function Windows.Open(id: string, args: any?)
	local def = screenDef(id)
	if not def then
		return
	end
	if current then
		Windows.Close(true)
	end
	local size = def.Size or Vector2.new(820, 540)
	-- Fit small screens.
	local layout = C.UI.LayoutSize()
	size = Vector2.new(math.min(size.X, layout.X - 24), math.min(size.Y, layout.Y - 90))
	local win = Kit.Window(def.Title or id, def.Icon, size)
	win.Root.Parent = C.UI.Layer("Windows")
	local open: Open = { Id = id, Window = win, Handle = nil, Def = def }
	current = open
	win.CloseButton.Activated:Connect(function()
		if current == open then
			Windows.Close()
		end
	end)
	local ctx = {
		Args = args,
		Close = function()
			if current == open then
				Windows.Close()
			end
		end,
	}
	local ok, handle = pcall(def.Build, win, ctx)
	if not ok then
		warn("[Evergrove] Screen", id, "build error:", handle)
		local msg = Kit.Label("Something went wrong opening this window.", { Wrap = true, Color = "Bad" })
		msg.Parent = win.Content
	else
		open.Handle = handle
	end
	Kit.RepaintGradients(win.Root)
	Kit.Pop(win.Root)
	Kit.Tween(blur, { Size = 10 }, 0.25)
	C.Audio.PlayUI("UIOpen")
	Net.Send("MenuState", true)
	-- Gamepad: select the first selectable thing in the content.
	if UserInputService.GamepadEnabled then
		task.defer(function()
			for _, d in win.Content:GetDescendants() do
				if d:IsA("GuiButton") and d.Selectable and d.Visible then
					GuiService.SelectedObject = d
					break
				end
			end
		end)
	end
	Windows.Opened:Fire(id)
end

function Windows.Toggle(id: string, args: any?)
	if current and current.Id == id then
		Windows.Close()
	else
		Windows.Open(id, args)
	end
end

-- Re-render the open window (after data changes).
function Windows.Refresh(id: string?)
	if current and (id == nil or current.Id == id) and current.Handle and current.Handle.Refresh then
		pcall(current.Handle.Refresh)
	end
end

function Windows.Init()
	blur = Instance.new("BlurEffect")
	blur.Name = "MenuBlur"
	blur.Size = 0
	blur.Parent = Lighting
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if current and (not processed or input.KeyCode == Enum.KeyCode.ButtonB) then
				Windows.Close()
			end
		end
	end)
	-- Windows that show live data re-render when that data changes.
	-- Coalesced: many patches in one frame cause a single refresh.
	local queued = false
	C.State.Changed:Connect(function(path)
		if current and current.Def.Watch and not queued then
			local key = path[1]
			if table.find(current.Def.Watch, key) then
				queued = true
				task.defer(function()
					queued = false
					Windows.Refresh()
				end)
			end
		end
	end)
end

return Windows
