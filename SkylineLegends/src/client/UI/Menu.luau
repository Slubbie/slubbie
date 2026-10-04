-- The full-screen menu: a navigation rail and one page at a time. Pages are
-- modules in UI/Pages; each builds its content into a container and is
-- rebuilt when the profile data it shows changes.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Bus = require(script.Parent.Parent.Core.Bus)
local Input = require(script.Parent.Parent.Core.Input)
local State = require(script.Parent.Parent.Core.State)
local Controller = require(script.Parent.Parent.Movement.Controller)
local CameraController = require(script.Parent.Parent.Camera.CameraController)
local Sfx = require(script.Parent.Parent.Audio.Sfx)
local Kit = require(script.Parent.Kit)
local Root = require(script.Parent.Root)

local C = Kit.Colors
local Menu = {}

export type Page = {
	Id: string,
	Title: string,
	Icon: string,
	Order: number,
	Hidden: boolean?,
	Sections: { string }?, -- profile sections that trigger a rebuild
	Build: (container: Frame, args: any) -> (),
}

local pages: { [string]: Page } = {}
local ordered: { Page } = {}
local current: string? = nil
local currentArgs: any = nil
local lastPage = "Map"

local gui: ScreenGui
local shade: Frame
local rail: ScrollingFrame
local content: Frame
local title: TextLabel
local navButtons: { [string]: TextButton } = {}
local rebuildQueued = false

local function build()
	local page = current and pages[current]
	if not page then
		return
	end
	Kit.Clear(content)
	title.Text = page.Icon .. "  " .. page.Title
	for id, button in navButtons do
		button.BackgroundColor3 = if id == current then C.Accent:Lerp(C.PanelLight, 0.55) else C.PanelLight
	end
	local ok, err = pcall(page.Build, content, currentArgs)
	if not ok then
		Kit.Paragraph(content, "Something went wrong drawing this page: " .. tostring(err), 14, C.Bad)
		warn("[Menu] " .. page.Id .. ": " .. tostring(err))
	end
end

function Menu.Open(id: string, args: any?)
	local page = pages[id]
	if not page then
		return
	end
	local wasOpen = current ~= nil
	current = id
	currentArgs = args
	if not page.Hidden then
		lastPage = id
	end
	shade.Visible = true
	CameraController.MenuOpen = true
	Controller.SetLock("Menu", true)
	build()
	if not wasOpen then
		Sfx.Stinger("Open")
	end
	Bus.PageChanged:Fire(id)
	if Input.Device == "Gamepad" then
		task.defer(function()
			GuiService.SelectedObject = navButtons[id]
		end)
	end
end

function Menu.Close()
	if not current then
		return
	end
	current = nil
	shade.Visible = false
	Kit.Clear(content)
	CameraController.MenuOpen = false
	Controller.SetLock("Menu", false)
	GuiService.SelectedObject = nil
	Sfx.Stinger("Close")
	Bus.PageChanged:Fire(nil)
end

function Menu.Refresh()
	if current and not rebuildQueued then
		rebuildQueued = true
		task.defer(function()
			rebuildQueued = false
			build()
		end)
	end
end

function Menu.Current(): string?
	return current
end

function Menu.Register(page: Page)
	pages[page.Id] = page
	if not page.Hidden then
		table.insert(ordered, page)
		table.sort(ordered, function(a, b)
			return a.Order < b.Order
		end)
	end
end

function Menu.Start()
	gui = Root.Get("Menu")
	shade = Kit.new("Frame", {
		Name = "Menu",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.12,
		Visible = false,
		Parent = gui,
	})
	-- Register every page module.
	for _, module in script.Parent.Pages:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, page = pcall(require, module)
			if ok and type(page) == "table" and page.Id then
				Menu.Register(page :: any)
			elseif ok and type(page) == "table" and type(page.Pages) == "table" then
				-- A module can define several related pages.
				for _, entry in page.Pages do
					Menu.Register(entry)
				end
			else
				warn("[Menu] Couldn't load page " .. module.Name .. ": " .. tostring(page))
			end
		end
	end

	local inset = GuiService:GetGuiInset().Y
	rail = Kit.Scroll(shade, {
		Position = UDim2.fromOffset(16, inset + 16),
		Size = UDim2.new(0, 190, 1, -(inset + 32)),
	})
	Kit.List(rail, false, 6)
	for index, page in ordered do
		local button = Kit.Button(
			rail,
			page.Icon .. "  " .. page.Title,
			function()
				Menu.Open(page.Id, nil)
			end,
			"Secondary",
			{ Size = UDim2.new(1, -10, 0, 40), LayoutOrder = index, TextXAlignment = Enum.TextXAlignment.Left }
		)
		Kit.Padding(button, 0, 12)
		navButtons[page.Id] = button
	end
	local panel = Kit.Panel(shade, {
		Position = UDim2.fromOffset(222, inset + 16),
		Size = UDim2.new(1, -238, 1, -(inset + 32)),
		BackgroundTransparency = 0.1,
	})
	Kit.Padding(panel, 18)
	title = Kit.Label(panel, "", 26, { Font = Kit.Fonts.Black, Size = UDim2.new(1, -50, 0, 34), TextColor3 = C.Accent })
	Kit.Button(
		panel,
		"✕",
		Menu.Close,
		"Ghost",
		{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(38, 38) }
	)
	content = Kit.new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		BackgroundTransparency = 1,
		Parent = panel,
	})

	-- Narrow screens: the rail becomes a top strip.
	local function adapt()
		local camera = workspace.CurrentCamera
		local width = if camera then camera.ViewportSize.X else 1200
		if width < 760 then
			rail.Size = UDim2.new(1, -32, 0, 48)
			rail.ScrollingDirection = Enum.ScrollingDirection.X
			rail.AutomaticCanvasSize = Enum.AutomaticSize.X
			local layout = rail:FindFirstChildOfClass("UIListLayout")
			if layout then
				layout.FillDirection = Enum.FillDirection.Horizontal
			end
			for _, button in navButtons do
				button.Size = UDim2.fromOffset(150, 40)
			end
			panel.Position = UDim2.fromOffset(16, inset + 72)
			panel.Size = UDim2.new(1, -32, 1, -(inset + 88))
		end
	end
	adapt()

	Bus.OpenPage:Connect(function(id: string, args: any)
		Menu.Open(id, args)
	end)
	Bus.ClosePages:Connect(Menu.Close)
	Input.Pressed:Connect(function(action: string)
		if action == "Menu" then
			if current then
				Menu.Close()
			else
				Menu.Open(lastPage, nil)
			end
		elseif action == "Map" then
			if current == "Map" then
				Menu.Close()
			else
				Menu.Open("Map", nil)
			end
		elseif action == "Journal" then
			if current == "Journal" then
				Menu.Close()
			else
				Menu.Open("Journal", nil)
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if current and input.KeyCode == Enum.KeyCode.ButtonB then
			Menu.Close()
		end
	end)
	-- Lobby changes redraw the race board while it's open.
	Bus.Mode:Connect(function(kind: string)
		if current == "Races" and (kind == "Race" or kind == "Relay") then
			Menu.Refresh()
		end
	end)
	State.Changed:Connect(function(section: string)
		local page = current and pages[current]
		if page and page.Sections and table.find(page.Sections, section) then
			Menu.Refresh()
		end
	end)
end

return Menu
