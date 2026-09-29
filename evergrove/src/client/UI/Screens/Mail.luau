-- The mailbox: letters from villagers, shipping receipts, rewards, gifts
-- from friends and store purchases. Attachments are claimed into your bag;
-- nothing with an attachment is ever thrown away.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local GameTime = require(Shared.Lib.GameTime)
local Format = require(Shared.Lib.Format)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local C = require(UI.Parent.Controllers)

local function hasAttachments(mail: any): boolean
	return not mail.Claimed and ((mail.Coins or 0) > 0 or (mail.Tokens or 0) > 0 or (mail.Items ~= nil and #mail.Items > 0) or mail.Title ~= nil)
end

local function request(action: string, ...: any): (boolean, any)
	local ok, result = Net.Request(action, ...)
	if not ok and result then
		C.Notify.Toast(tostring(result), "Warning")
	end
	return ok, result
end

return {
	Id = "Mail",
	Title = "Mailbox",
	Icon = "✉️",
	Size = Vector2.new(900, 580),
	Watch = { "Mail" },
	Build = function(win)
		local content = win.Content :: Frame
		local selected: string? = nil

		local function render()
			Kit.Clear(content)
			local box = C.State.Get("Mail") or { List = {}, Overflow = {} }
			local list = {}
			for _, mail in box.List do
				table.insert(list, mail)
			end
			table.sort(list, function(a, b)
				return (a.At or 0) > (b.At or 0)
			end)
			local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = content })
			local count = Kit.Label(#list .. " letters" .. (if #box.Overflow > 0 then " · " .. #box.Overflow .. " waiting at the post office (make room)" else ""), { Size = Theme.Sizes.Small, Color = "SubText" })
			count.Size = UDim2.new(1, -170, 1, 0)
			count.Parent = top
			local claimAll = Kit.Button("📥 Claim all", { Style = "Good", Size = UDim2.fromOffset(160, 34), TextSize = Theme.Sizes.Small, OnClick = function()
				local ok, result = request("MailClaimAll")
				if ok then
					C.Audio.PlayUI("ItemPickup")
					if result and (result.Skipped or 0) > 0 then
						C.Notify.Toast(result.Skipped .. " letters didn't fit in your bag", "Warning")
					end
				end
			end })
			claimAll.Position = UDim2.new(1, -160, 0, 0)
			claimAll.Parent = top
			local left = Kit.Scroll({ Size = UDim2.new(0.42, -6, 1, -44), Position = UDim2.fromOffset(0, 44) })
			left.Parent = content
			Kit.List(left, "Y", 4)
			if #list == 0 then
				Kit.Empty("No mail. Villagers write when they have something to say — and friends can send gifts.").Parent = left
			end
			if not selected and list[1] then
				selected = list[1].Id
			end
			for i, mail in list do
				local row = Kit.new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.new(1, -8, 0, 52), LayoutOrder = i, Selectable = true, Parent = left })
				Kit.Paint(row, "BackgroundColor3", if mail.Id == selected then "SlotHover" else "PanelAlt")
				Kit.Corner(row, 8)
				local icon = if hasAttachments(mail) then "🎁" elseif mail.Read then "📭" else "📩"
				local subject = Kit.Label(icon .. " " .. (if mail.Subject ~= "" then mail.Subject else "(no subject)"), { Size = Theme.Sizes.Small, Font = if mail.Read then Theme.Fonts.Body else Theme.Fonts.Bold })
				subject.Position = UDim2.fromOffset(10, 4)
				subject.Size = UDim2.new(1, -20, 0, 20)
				subject.Parent = row
				local from = Kit.Label(tostring(mail.From) .. " · " .. Format.Duration(math.max(0, GameTime.Now() - (mail.At or 0))) .. " ago", { Size = Theme.Sizes.Tiny, Color = "SubText" })
				from.Position = UDim2.fromOffset(10, 26)
				from.Size = UDim2.new(1, -20, 0, 16)
				from.Parent = row
				row.Activated:Connect(function()
					selected = mail.Id
					if not mail.Read then
						task.spawn(Net.Request, "MailRead", mail.Id)
					end
					Kit.PlaySound("UIClick")
					render()
				end)
			end
			local mail
			for _, m in list do
				if m.Id == selected then
					mail = m
				end
			end
			local paper = Kit.Panel({ Size = UDim2.new(0.58, -6, 1, -44), Position = UDim2.new(0.42, 6, 0, 44), Color = "Inset" })
			paper.Parent = content
			Kit.Padding(paper, 16, 18)
			if not mail then
				return
			end
			if not mail.Read then
				task.spawn(Net.Request, "MailRead", mail.Id)
			end
			local scroll = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -46) })
			scroll.Parent = paper
			Kit.List(scroll, "Y", 8)
			Kit.Heading(if mail.Subject ~= "" then mail.Subject else "(no subject)", 20).Parent = scroll
			local from = Kit.Label("From " .. tostring(mail.From), { Size = Theme.Sizes.Small, Color = "SubText" })
			from.LayoutOrder = 1
			from.Parent = scroll
			local body = Kit.Label(mail.Body or "", { Size = Theme.Sizes.Body, Wrap = true })
			body.LayoutOrder = 2
			body.Parent = scroll
			local attachments = {}
			if (mail.Coins or 0) > 0 then
				table.insert(attachments, Kit.Money(mail.Coins))
			end
			if (mail.Tokens or 0) > 0 then
				table.insert(attachments, Kit.Money(mail.Tokens, "Tokens"))
			end
			if mail.Title then
				table.insert(attachments, "🏷️ Title: " .. mail.Title)
			end
			local grid = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4, Parent = scroll })
			Kit.Grid(grid, 52, 6)
			for i, stack in mail.Items or {} do
				local slot = Kit.ItemSlot(52)
				slot.Button.LayoutOrder = i
				slot.Set(if type(stack) == "table" and stack.Id then stack else { Id = stack[1], N = stack[2] or 1 })
				slot.Button.Parent = grid
				if mail.Claimed then
					slot.Button.BackgroundTransparency = 0.6
				end
			end
			if #attachments > 0 then
				local a = Kit.Label((if mail.Claimed then "✔ Claimed: " else "Attached: ") .. table.concat(attachments, "  ·  "), { Size = Theme.Sizes.Small, Color = "Accent", Wrap = true })
				a.LayoutOrder = 3
				a.Parent = scroll
			end
			local buttons = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 1, -40), Parent = paper })
			Kit.List(buttons, "X", 8)
			if hasAttachments(mail) then
				Kit.Button("📥 Claim", { Style = "Good", Size = UDim2.fromOffset(120, 38), OnClick = function()
					if request("MailClaim", mail.Id) then
						C.Audio.PlayUI("ItemPickup")
					end
				end }).Parent = buttons
			end
			local delete = Kit.Button("🗑️ Delete", { Style = "Danger", Size = UDim2.fromOffset(110, 38), LayoutOrder = 1, OnClick = function()
				if request("MailDelete", mail.Id) then
					selected = nil
				end
			end })
			delete.Parent = buttons
			Kit.SetEnabled(delete, not hasAttachments(mail))
			Kit.RepaintGradients(content)
		end
		render()
		return { Refresh = render }
	end,
}
