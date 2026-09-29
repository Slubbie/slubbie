-- Lore pages: the valley's history, found through secrets and exploration.
-- Opened with { Id, Title, Text } when a page is found, or with nothing to
-- browse every page you've collected.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Secrets = require(Shared.Config.Secrets)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local C = require(UI.Parent.Controllers)

return {
	Id = "Lore",
	Title = "Lore",
	Icon = "📜",
	Size = Vector2.new(760, 520),
	Watch = { "Lore" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local content = win.Content :: Frame
		local selected: string? = args.Id

		local function render()
			Kit.Clear(content)
			local found = C.State.Get("Lore") or {}
			local list = Kit.Scroll({ Size = UDim2.new(0, 230, 1, 0) })
			list.Parent = content
			Kit.List(list, "Y", 4)
			local count = 0
			for i, page in Secrets.Lore do
				local have = found[page.Id] ~= nil or page.Id == args.Id
				if have then
					count += 1
				end
				local b = Kit.Button(if have then "📜 " .. page.Title else "❔ ???", { Style = if selected == page.Id then "Primary" else "Secondary", Size = UDim2.new(1, -8, 0, 34), TextSize = Theme.Sizes.Tiny, LayoutOrder = i, OnClick = function()
					if have then
						selected = page.Id
						render()
					end
				end })
				b.TextXAlignment = Enum.TextXAlignment.Left
				Kit.Padding(b, 0, 10)
				b.Parent = list
			end
			local header = Kit.Label(count .. " / " .. #Secrets.Lore .. " pages", { Size = Theme.Sizes.Tiny, Color = "SubText" })
			header.LayoutOrder = 0
			header.Parent = list
			local page = nil
			for _, p in Secrets.Lore do
				if p.Id == selected then
					page = p
				end
			end
			local paper = Kit.Panel({ Size = UDim2.new(1, -242, 1, 0), Position = UDim2.fromOffset(242, 0), Color = "Inset" })
			paper.Parent = content
			Kit.Padding(paper, 22, 26)
			Kit.List(paper, "Y", 14)
			if page then
				Kit.Heading(page.Title, 26).Parent = paper
				local text = Kit.Label(page.Text, { Size = 18, Wrap = true, Font = Theme.Fonts.Body })
				text.LayoutOrder = 1
				text.Parent = paper
			else
				Kit.Label("Lore pages are hidden around the valley: behind secrets, in old ruins, under full moons. Each tells a little of Evergrove's story.", { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }).Parent = paper
			end
			Kit.RepaintGradients(content)
		end
		render()
		if args.Id then
			C.Audio.PlayUI("Discovery")
		end
		return { Refresh = render }
	end,
}
