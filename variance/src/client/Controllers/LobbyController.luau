-- The Intake as a place: terminals, the locker showcase and the surrogates on
-- display.
--
-- Terminals are ProximityPrompts carrying a "Terminal" attribute (built by the
-- server's LobbyBuilder); triggering one opens the matching screen. Every
-- terminal is also reachable from the lobby HUD menu, so nothing depends on
-- walking somewhere. The locker's showcase Arbiter turns slowly wearing your
-- equipped finish; the surrogates in their cases breathe and follow whoever
-- walks past.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArbiterModel = require(ReplicatedStorage.Variance.Visual.ArbiterModel)
local Cosmetics = require(ReplicatedStorage.Variance.Data.Cosmetics)

local LobbyController = {}

-- Terminal attribute -> screen and its arguments.
local TERMINALS = {
	Play = { "Play", { Tab = "Queue" } },
	Solo = { "Play", { Tab = "Solo" } },
	Practice = { "Play", { Tab = "Practice" } },
	Tutorial = { "Play", { Tab = "Training" } },
	Spectate = { "Play", { Tab = "Watch" } },
	Private = { "Private", nil },
	Ranked = { "Ranked", nil },
	Locker = { "Locker", nil },
	Archive = { "Archive", nil },
	Challenges = { "Challenges", nil },
	Record = { "Record", nil },
}

local showcases: { { Model: Model, Pivot: CFrame } } = {}
local displays: { [Model]: boolean } = {}

function LobbyController:Init(controllers)
	self.Controllers = controllers
end

function LobbyController:openTerminal(terminal: string, extra: { [string]: any }?)
	local entry = TERMINALS[terminal]
	if entry == nil then
		return
	end
	local args = entry[2] and table.clone(entry[2]) or {}
	for k, v in extra or {} do
		args[k] = v
	end
	self.Controllers.UIController:open(entry[1], args)
end

local function equippedSkin(self)
	local profile = self.Controllers.ProfileController
	local id = profile:equipped("DeviceSkin")
	local item = id and Cosmetics.get(id)
	return item and item.Data or nil
end

local function watch(self, instance: Instance)
	if instance:IsA("Model") and instance:GetAttribute("Fx") == "Showcase" then
		local pivot = instance:GetAttribute("Pivot")
		if typeof(pivot) == "CFrame" then
			table.insert(showcases, { Model = instance, Pivot = pivot })
			ArbiterModel.applySkin(instance, equippedSkin(self))
		end
	elseif instance:IsA("Model") and instance:GetAttribute("Display") then
		if displays[instance] == nil then
			displays[instance] = true
			task.defer(function()
				self.Controllers.AnimationController:register(instance, {
					Kind = "Display",
					Personality = instance:GetAttribute("Surrogate"),
				})
			end)
		end
	end
end

function LobbyController:Start()
	local ui = self.Controllers.UIController
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player ~= Players.LocalPlayer then
			return
		end
		local terminal = prompt:GetAttribute("Terminal")
		if type(terminal) ~= "string" or self.Controllers.MatchClient:active() then
			return
		end
		self.Controllers.AudioController:play("Confirm")
		self:openTerminal(terminal, { Surrogate = prompt:GetAttribute("Surrogate") })
	end)
	-- Prompts stay quiet while a full screen is open.
	RunService.Heartbeat:Connect(function()
		local enabled = ui:currentScreen() == nil and not self.Controllers.MatchClient:active()
		if ProximityPromptService.Enabled ~= enabled then
			ProximityPromptService.Enabled = enabled
		end
	end)

	-- Showcase and display rigs (they stream in and out).
	for _, d in workspace:GetDescendants() do
		watch(self, d)
	end
	workspace.DescendantAdded:Connect(function(d)
		watch(self, d)
	end)
	workspace.DescendantRemoving:Connect(function(d)
		if displays[d] then
			displays[d] = nil
			self.Controllers.AnimationController:unregister(d :: Model)
		end
	end)
	self.Controllers.ProfileController.Changed:Connect(function()
		local skin = equippedSkin(self)
		for _, s in showcases do
			if s.Model.Parent then
				ArbiterModel.applySkin(s.Model, skin)
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for i = #showcases, 1, -1 do
			local s = showcases[i]
			if s.Model.Parent == nil then
				table.remove(showcases, i)
			else
				local cf = s.Pivot * CFrame.new(0, math.sin(now * 0.9) * 0.12, 0) * CFrame.Angles(0, now * 0.45, 0) * CFrame.Angles(0.12, 0, 0)
				ArbiterModel.place(s.Model, cf, 0, math.sin(now * 0.6) * 0.6)
			end
		end
		-- Displayed surrogates follow the nearest subject walking by.
		local anim = self.Controllers.AnimationController
		for model in displays do
			local rig = anim:rigFor(model)
			if rig then
				local nearest, best = nil, 16
				for _, player in Players:GetPlayers() do
					local character = player.Character
					local head = character and character:FindFirstChild("Head") :: BasePart?
					if head then
						local d = (head.Position - rig.Root.Position).Magnitude
						if d < best then
							nearest, best = head.Position, d
						end
					end
				end
				anim:lookAt(rig, nearest)
			end
		end
	end)
end

return LobbyController
