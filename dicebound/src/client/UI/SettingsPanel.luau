-- Audio, motion and reveal settings. Saved to your profile on the server.

local ClientState = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Panels = require(script.Parent.Panels)

local C = Theme.Colors

local SettingsPanel = {}

function SettingsPanel.new()
	local content = Panels.Create("Settings", "Settings", "⚙️")
	local scroll = Kit.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	})
	Kit.List(scroll, Enum.FillDirection.Vertical, 8)
	Kit.Padding(scroll, 4, 10)

	local built = false
	local function build()
		if built then
			return
		end
		built = true
		local s = ClientState.Settings
		Kit.Slider(scroll, "Music volume", s.Music, function(v)
			ClientState.SetSetting("Music", v)
		end, 1)
		Kit.Slider(scroll, "Sound effects", s.Sfx, function(v)
			ClientState.SetSetting("Sfx", v)
		end, 2)
		Kit.Toggle(scroll, "Reduced motion (no tumbling, shakes or bursts)", s.ReducedMotion, function(v)
			ClientState.SetSetting("ReducedMotion", v)
		end, 3)
		Kit.Toggle(scroll, "Skip long reveals (Legendary+ show as a card)", s.SkipReveals, function(v)
			ClientState.SetSetting("SkipReveals", v)
		end, 4)
		Kit.Label({
			Parent = scroll,
			Text = "Controls: R roll · B bag · U upgrades · G dice · M map · Q quests · C collection · E at a stall.\n"
				.. "Your progress saves automatically every 90 seconds and when you leave.",
			TextSize = 14,
			TextColor3 = C.InkSoft,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = 10,
		})
	end

	Panels.Opened:Connect(function(name)
		if name == "Settings" then
			build()
		end
	end)
end

return SettingsPanel
