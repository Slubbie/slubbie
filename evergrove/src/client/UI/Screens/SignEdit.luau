-- Write on one of your signs. The text is filtered by Roblox before others see it.
-- Args: { Uid = signUid }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Social = require(Shared.Config.Social)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local C = require(UI.Parent.Controllers)

return {
	Id = "SignEdit",
	Title = "Sign",
	Icon = "🪧",
	Size = Vector2.new(520, 260),
	Build = function(win, ctx)
		local uid = ctx.Args and ctx.Args.Uid
		local content = win.Content :: Frame
		Kit.List(content, "Y", 10)
		local farms = workspace:FindFirstChild("Farms")
		local model = farms and farms:FindFirstChild(tostring(uid), true)
		local current = model and model:GetAttribute("Text") or ""
		Kit.Label("What should your sign say?", { Size = Theme.Sizes.Small, Color = "SubText" }).Parent = content
		local box = Kit.TextBox("Welcome to my farm!", { Text = tostring(current), MaxLength = Social.Names.SignMax })
		box.LayoutOrder = 1
		box.Parent = content
		local count = Kit.Label("", { Size = Theme.Sizes.Tiny, Color = "SubText", Align = "Right" })
		count.LayoutOrder = 2
		count.Parent = content
		local function update()
			count.Text = #box.Text .. " / " .. Social.Names.SignMax
		end
		box:GetPropertyChangedSignal("Text"):Connect(update)
		update()
		local row = Kit.new(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 3, Parent = content }
		)
		Kit.List(row, "X", 8, "Right")
		Kit.Button("Clear", {
			Style = "Secondary",
			Size = UDim2.fromOffset(100, 38),
			OnClick = function()
				box.Text = ""
			end,
		}).Parent =
			row
		local save = Kit.Button("Save", {
			Style = "Primary",
			Size = UDim2.fromOffset(110, 38),
			OnClick = function()
				local ok, err = Net.Request("BuildStyle", uid, { Tx = box.Text })
				if ok then
					ctx.Close()
				else
					C.Notify.Toast(tostring(err), "Warning")
				end
			end,
		})
		save.LayoutOrder = 1
		save.Parent = row
		task.defer(function()
			box:CaptureFocus()
		end)
		return nil
	end,
}
