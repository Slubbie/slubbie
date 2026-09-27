-- Developer panel (F8, only for players the server allows). Every button runs
-- a server command from DebugService, which re-checks permission:
--   sequence forcing, integrity, instrument grants, infinite instruments,
--   surrogate behaviour overrides, ending loads/trials, skipping trials,
--   speed, simulated latency, ambient events, reveal, the validation suite
--   and the anti-exploit flag log.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Instruments = require(ReplicatedStorage.Variance.Core.Instruments)
local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local DebugPanel = {}
DebugPanel.__index = DebugPanel

function DebugPanel.new(ui, controllers)
	local self = setmetatable({}, DebugPanel)
	self.UI = ui
	self.C = controllers
	self.Main = false
	self.Visible = false
	local panel = Kit.panel(ui.Overlay, { Name = "DebugPanel", Size = UDim2.fromOffset(420, 560), Position = UDim2.new(1, -16, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Color = "Bg", Visible = false, ZIndex = 150 })
	Kit.padding(panel, 10, 12)
	self.Frame = panel
	Kit.label(panel, { Text = "DEBUG  ·  F8", Font = "Mono", TextSize = "Label", Color = "Warn", Size = UDim2.new(1, 0, 0, 18), ZIndex = 151 })
	local input = Kit.create("TextBox", {
		Text = "",
		PlaceholderText = "Sequence e.g. CHHC  /  value",
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Mono,
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 22),
		BorderSizePixel = 0,
		ZIndex = 151,
		Parent = panel,
	}) :: TextBox
	Theme.bind(input, "BackgroundColor3", "Raised")
	Theme.bind(input, "TextColor3", "Text")
	self.Input = input
	local scroll = Kit.scroll(panel, { Size = UDim2.new(1, 0, 1, -150), Position = UDim2.fromOffset(0, 58), Padding = 4 })
	local output = Kit.label(panel, { Text = "", Font = "Mono", TextSize = "Tiny", Color = "Dim", Wrap = true, YAlign = "Top", Size = UDim2.new(1, 0, 0, 84), Position = UDim2.new(0, 0, 1, -84), ZIndex = 151 })
	self.Output = output

	local function run(name: string, args: { [string]: any }?)
		task.spawn(function()
			local ok, result = controllers.DebugController:run(name, args)
			if type(result) == "table" then
				local lines = {}
				for k, v in result do
					table.insert(lines, tostring(k) .. ": " .. (if type(v) == "table" then (v.Reason or v.Text or "table") else tostring(v)))
				end
				result = table.concat(lines, "\n")
			end
			output.Text = (if ok then "OK  " else "FAIL  ") .. tostring(result)
		end)
	end
	local function number(): number?
		return tonumber(input.Text)
	end
	local buttons = {
		{ "FORCE NEXT LOAD (sequence)", function()
			run("Sequence", { Pattern = input.Text })
		end },
		{ "SET MY INTEGRITY (value)", function()
			run("Integrity", { Subject = controllers.MatchClient:you(), Value = number() or 1 })
		end },
		{ "SET OPPONENT INTEGRITY (value)", function()
			local opponents = controllers.MatchClient:opponents()
			run("Integrity", { Subject = opponents[1], Value = number() or 1 })
		end },
		{ "INFINITE INSTRUMENTS ON", function()
			run("Infinite", { On = true })
		end },
		{ "INFINITE INSTRUMENTS OFF", function()
			run("Infinite", { On = false })
		end },
		{ "SURROGATE: ALWAYS SELF", function()
			run("AI", { Mode = "AlwaysSelf" })
		end },
		{ "SURROGATE: ALWAYS OTHER", function()
			run("AI", { Mode = "AlwaysOther" })
		end },
		{ "SURROGATE: RANDOM", function()
			run("AI", { Mode = "Random" })
		end },
		{ "SURROGATE: STALL (timer test)", function()
			run("AI", { Mode = "Stall" })
		end },
		{ "SURROGATE: EXPERT", function()
			run("AI", { Mode = "Expert" })
		end },
		{ "SURROGATE: NORMAL", function()
			run("AI", { Mode = "" })
		end },
		{ "END LOAD", function()
			run("EndLoad")
		end },
		{ "END TRIAL (my team wins)", function()
			local me = controllers.MatchClient:subject(controllers.MatchClient:you())
			run("EndTrial", { Team = me and me.TeamId or 1 })
		end },
		{ "SKIP TO TRIAL (value)", function()
			run("SkipToTrial", { Trial = number() or 3 })
		end },
		{ "SPEED (value, 0.1-3)", function()
			run("Speed", { Scale = number() or 1 })
		end },
		{ "SIMULATE LATENCY (ms)", function()
			run("Latency", { Ms = number() or 0 })
		end },
		{ "AMBIENT: POWER DIP", function()
			run("Ambient", { Kind = "PowerDip" })
		end },
		{ "AMBIENT: PROCTOR WATCHING", function()
			run("Ambient", { Kind = "ProctorWatching" })
		end },
		{ "REVEAL SEQUENCE", function()
			run("Reveal")
		end },
		{ "RUN VALIDATION SUITE", function()
			run("Validation")
		end },
		{ "RECENT EXPLOIT FLAGS", function()
			run("Flags")
		end },
		{ "GRANT 1000 XP + 500 MARKS", function()
			run("Grant", { XP = 1000, Marks = 500 })
		end },
		{ "QUICK SOLO (sequence)", function()
			run("SoloQuick", { Pattern = if input.Text ~= "" then input.Text else nil })
		end },
	}
	for i, spec in buttons do
		Kit.button(scroll, { Text = spec[1], Size = UDim2.new(1, -8, 0, 28), TextSize = "Tiny", LayoutOrder = i, ZIndex = 152, OnClick = spec[2] })
	end
	local give = Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 100, Parent = scroll }) :: Frame
	Kit.grid(give, UDim2.fromOffset(94, 26), 4)
	for i, id in Instruments.ids() do
		Kit.button(give, {
			Text = "+" .. id,
			Size = UDim2.fromOffset(94, 26),
			TextSize = "Tiny",
			LayoutOrder = i,
			ZIndex = 152,
			OnClick = function()
				run("Give", { Subject = controllers.MatchClient:you(), Id = id })
			end,
		})
	end
	return self
end

function DebugPanel:Open()
	self.Visible = true
	self.Frame.Visible = true
end

function DebugPanel:Close()
	self.Visible = false
	self.Frame.Visible = false
end

return DebugPanel
