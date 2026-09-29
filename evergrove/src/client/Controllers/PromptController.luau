-- Interaction prompts. Every ProximityPrompt in Evergrove uses the Custom
-- style and carries a Kind + Target attribute; this controller draws the
-- prompt card (key / button glyph, action, object, hold ring) and routes a
-- triggered prompt to the right window or network action.

local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)

local C = require(script.Parent)
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UIFolder.Kit)
local Theme = require(UIFolder.Theme)

local PromptController = {}

local player = Players.LocalPlayer
local cards: { [ProximityPrompt]: BillboardGui } = {}

local GAMEPAD_GLYPHS = {
	[Enum.KeyCode.ButtonX] = "Ⓧ",
	[Enum.KeyCode.ButtonA] = "Ⓐ",
	[Enum.KeyCode.ButtonY] = "Ⓨ",
	[Enum.KeyCode.ButtonB] = "Ⓑ",
}

local function held(): string?
	local character = player.Character
	return character and character:GetAttribute("Held")
end

local function request(action: string, ...: any)
	local ok, result = Net.Request(action, ...)
	if not ok and type(result) == "string" then
		C.Notify.Toast(result, "Warning")
	end
	return ok, result
end

-- Routing ------------------------------------------------------------------------------------------------------------

local routes: { [string]: (ProximityPrompt, string?) -> () } = {}

routes.Npc = function(_, target)
	C.NPC.Talk(target :: string)
end
routes.Machine = function(_, target)
	C.Windows.Open("Machine", { Uid = target })
end
routes.Chest = function(_, target)
	C.Windows.Open("Inventory", { Container = "chest:" .. tostring(target) })
	C.Tutorial.Hint("Chest")
end
routes.Silo = function()
	C.Windows.Open("Inventory", { Container = "silo" })
end
routes.AnimalHome = function(_, target)
	C.Windows.Open("Animals", { Home = target })
end
routes.Animal = function(_, target)
	C.Windows.Open("AnimalCare", { Aid = target })
end
routes.Station = function(prompt)
	C.Windows.Open("Crafting", { Station = prompt:GetAttribute("Station") })
end
routes.Water = function(prompt)
	local item = held()
	local def = item and Registry.Items[item]
	local position = (prompt.Parent :: BasePart).Position
	if def and def.Tool == "can" then
		Net.Send("ToolUse", item, position, nil)
		C.Animation.Play("Water")
	elseif def and def.Tool == "rod" then
		C.Fishing.Cast(position)
	else
		C.Notify.Toast(
			"Hold your watering can to refill it"
				.. (if prompt:GetAttribute("Water") == "Pond" then ", or your rod to fish" else ""),
			"Info"
		)
	end
end
routes.Display = function()
	C.Windows.Open("Collection", { Tab = "Showcase" })
end
routes.Stall = function(prompt)
	C.Windows.Open("Stall", { Owner = prompt:GetAttribute("Owner") })
end
routes.Sign = function(prompt, target)
	if prompt:GetAttribute("Owner") == player.UserId then
		C.Windows.Open("SignEdit", { Uid = target })
	else
		local model = prompt:FindFirstAncestorOfClass("Model")
		local text = model and model:GetAttribute("Text")
		C.Notify.Toast("🪧 " .. (text or "(an empty sign)"), "Info")
	end
end
for _, kind in { "Controller", "Dock", "Farmbot", "Drones", "Logistics", "Feeder", "Collector", "Power" } do
	routes[kind] = function(_, target)
		C.Windows.Open("FarmControl", { Tab = kind, Uid = target })
	end
end
routes.House = function()
	C.Windows.Open("House")
end
routes.Bin = function()
	C.Windows.Open("Sell", { Venue = "Bin" })
end
routes.Mail = function()
	C.Windows.Open("Mail")
end
routes.FarmSign = function()
	C.Windows.Open("Land")
end
routes.Parcel = function(_, target)
	C.Windows.Open("Land", { Parcel = target })
end
routes.Travel = function()
	C.Windows.Open("Map", { Travel = true })
end
routes.Lift = function(_, target)
	request("Travel", target)
end
routes.Board = function()
	C.Windows.Open("Quests", { Tab = "Board" })
end
routes.Projects = function()
	C.Windows.Open("Projects")
end
routes.Museum = function()
	C.Windows.Open("Collection", { Tab = "Museum" })
end
routes.Contracts = function()
	C.Windows.Open("Market", { Tab = "Contracts" })
end
routes.Forage = function(_, target)
	C.Animation.Play("Pick")
	request("ForageCollect", target)
end
routes.Bug = function(_, target)
	if held() ~= "tool_net" then
		C.Notify.Toast("Hold your bug net (select it in the hotbar)", "Info")
		return
	end
	C.Animation.Play("Net")
	C.Audio.PlayUI("NetSwing")
	request("BugCatch", target)
end
routes.Dig = function(_, target)
	C.Animation.Play("Dig")
	request("DigSpot", target)
end
routes.Festival = function(prompt)
	C.Animation.Play("Pick")
	request(
		"FestivalAction",
		"Find",
		{ Activity = prompt:GetAttribute("Activity"), Index = prompt:GetAttribute("Index") }
	)
end

-- Run a route without a prompt (e.g. swinging the net at a bug).
function PromptController.Run(kind: string, target: string?)
	local route = routes[kind]
	if route then
		route(nil :: any, target)
	end
end

function PromptController.Trigger(prompt: ProximityPrompt)
	local kind = prompt:GetAttribute("Kind")
	local route = kind and routes[kind]
	if route then
		local ok, err = pcall(route, prompt, prompt:GetAttribute("Target"))
		if not ok then
			warn("[Evergrove] Prompt", kind, "failed:", err)
		end
	end
end

-- Prompt cards ------------------------------------------------------------------------------------------------------

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		return GAMEPAD_GLYPHS[prompt.GamepadKeyCode] or "Ⓧ"
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		return "👆"
	end
	return prompt.KeyboardKeyCode.Name
end

local function showCard(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if cards[prompt] then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "PromptCard"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(230, 50)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.LightInfluence = 0
	gui.Active = true
	gui.Adornee = prompt.Parent :: any
	local card = Kit.new(
		"TextButton",
		{ AutoButtonColor = false, Text = "", BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = gui }
	)
	Kit.Paint(card, "BackgroundColor3", "Panel")
	card.BackgroundTransparency = 0.08
	Kit.Corner(card, 12)
	Kit.Stroke(card, "Stroke", 1.5)
	local key = Kit.new("TextLabel", {
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.fromOffset(7, 7),
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		Text = keyText(prompt, inputType),
		Parent = card,
	})
	Kit.Paint(key, "BackgroundColor3", "HeaderA")
	Kit.Paint(key, "TextColor3", "HeaderText")
	Kit.Corner(key, 8)
	local ring = Kit.new("UIStroke", { Thickness = 3, Transparency = 1, Parent = key })
	Kit.Paint(ring, "Color", "Accent")
	local action = Kit.Label(prompt.ActionText, { Size = 17, Font = Theme.Fonts.Bold })
	action.Position = UDim2.fromOffset(52, 4)
	action.Size = UDim2.new(1, -58, 0, 22)
	action.Parent = card
	local object = Kit.Label(prompt.ObjectText, { Size = 13, Color = "SubText" })
	object.Position = UDim2.fromOffset(52, 25)
	object.Size = UDim2.new(1, -58, 0, 18)
	object.Parent = card
	gui.Parent = C.UI.Root()
	cards[prompt] = gui
	Kit.Pop(card, 0.8)
	-- Touch: the card itself is the button.
	card.Activated:Connect(function()
		prompt:InputHoldBegin()
		task.wait()
		prompt:InputHoldEnd()
	end)
	prompt.PromptButtonHoldBegan:Connect(function()
		ring.Transparency = 0
	end)
	prompt.PromptButtonHoldEnded:Connect(function()
		ring.Transparency = 1
	end)
end

local function hideCard(prompt: ProximityPrompt)
	local gui = cards[prompt]
	if gui then
		cards[prompt] = nil
		gui:Destroy()
	end
end

function PromptController.Start()
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			showCard(prompt, inputType)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(hideCard)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if C.Windows.IsOpen() and prompt:GetAttribute("Kind") ~= "Lift" then
			return
		end
		PromptController.Trigger(prompt)
	end)
	-- While a window is open, prompts would steal the E key: disable them.
	C.Windows.Opened:Connect(function()
		ProximityPromptService.Enabled = false
	end)
	C.Windows.Closed:Connect(function()
		ProximityPromptService.Enabled = not C.Build.Active()
	end)
end

return PromptController
