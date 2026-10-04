-- The emote wheel: press Emote to show your equipped emotes, then click one
-- (or press its number). Emotes play while you stand still and stop the
-- moment you move.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Net = require(ReplicatedStorage.Shared.Net)

local Input = require(script.Parent.Parent.Core.Input)
local State = require(script.Parent.Parent.Core.State)
local Controller = require(script.Parent.Parent.Movement.Controller)
local Animator = require(script.Parent.Parent.Animation.Animator)
local Kit = require(script.Parent.Kit)
local Root = require(script.Parent.Root)

local C = Kit.Colors
local Emotes = {}

local wheel: Frame
local styles: { string } = {}

local function play(style: string)
	wheel.Visible = false
	if Controller.Info.State ~= "Ground" or Controller.Info.Speed > 2 then
		return
	end
	Animator.PlayEmote(style)
	Net.Send("Emote.Play", style)
end

local function open()
	Kit.Clear(wheel)
	table.clear(styles)
	local profile = State.Profile
	local equipped = profile and profile.Equipped and profile.Equipped.Emotes or {}
	for index, id in equipped do
		local item = Cosmetics.ById[id]
		if item and item.Style and Animator.HasEmote(item.Style) then
			table.insert(styles, item.Style)
			Kit.Button(wheel, ("%d  %s"):format(index, item.Name), function()
				play(item.Style :: string)
			end, "Secondary", { Size = UDim2.fromOffset(130, 40), LayoutOrder = index })
		end
	end
	if #styles == 0 then
		Kit.Label(
			wheel,
			"No emotes equipped. Visit your Locker.",
			14,
			{ Size = UDim2.fromOffset(300, 40), TextColor3 = C.Muted }
		)
	end
	wheel.Visible = true
end

function Emotes.Start()
	local gui = Root.Get("Hud")
	wheel = Kit.Panel(gui, {
		Name = "EmoteWheel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -170),
		Size = UDim2.fromOffset(0, 56),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
	})
	Kit.Padding(wheel, 8)
	Kit.List(wheel, true, 6)
	Input.Pressed:Connect(function(action: string)
		if action == "Emote" then
			if wheel.Visible then
				wheel.Visible = false
			else
				open()
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not wheel.Visible then
			return
		end
		local digit = tonumber(string.match(input.KeyCode.Name, "^(%d)$") or ({
			One = "1",
			Two = "2",
			Three = "3",
			Four = "4",
			Five = "5",
			Six = "6",
			Seven = "7",
			Eight = "8",
		})[input.KeyCode.Name] or "")
		if digit and styles[digit] then
			play(styles[digit])
		end
	end)
	Controller.StateChanged:Connect(function(state: string)
		if state ~= "Ground" then
			wheel.Visible = false
		end
	end)
end

return Emotes
