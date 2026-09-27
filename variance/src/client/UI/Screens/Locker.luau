-- THE LOCKER: every cosmetic, by category. Owned items can be equipped; locked
-- ones say exactly how to earn them; shop items cost Marks (earned by playing).
-- Arbiter finishes preview on a turning device. Nothing here changes how a
-- Trial plays. The SUPPORT tab lists optional cosmetic purchases, if the
-- experience has any configured.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Variance.Config)
local Cosmetics = require(ReplicatedStorage.Variance.Data.Cosmetics)
local Achievements = require(ReplicatedStorage.Variance.Data.Achievements)
local ArbiterModel = require(ReplicatedStorage.Variance.Visual.ArbiterModel)
local Format = require(ReplicatedStorage.Variance.Util.Format)
local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Window = require(script.Parent.Parent.Window)

local Locker = {}
Locker.__index = Locker

local function tabs()
	local out = {}
	for _, category in Cosmetics.Categories do
		if #out < 7 then
			table.insert(out, { Id = category.Id, Label = category.Name })
		end
	end
	table.insert(out, { Id = "More", Label = "MORE" })
	return out
end

function Locker.new(ui, controllers)
	local self = setmetatable({}, Locker)
	self.UI = ui
	self.C = controllers
	self.Main = true
	self.Category = "DeviceSkin"
	self.Selected = nil
	self.Window = Window.new(ui, {
		Name = "Locker",
		Title = "THE LOCKER",
		Subtitle = "COSMETIC ONLY  ·  NOTHING HERE CHANGES A TRIAL",
		Width = 1020,
		Height = 640,
		Tabs = tabs(),
		OnTab = function(id)
			if id == "More" then
				self.Category = self.Category == "CardFrame" and "Banner" or "CardFrame"
				self:showMore()
			else
				self.Category = id
				self.Selected = nil
				self:render()
			end
		end,
	})
	self.Frame = self.Window.Frame
	controllers.ProfileController.Changed:Connect(function()
		if self.Window.Visible then
			self:render()
		end
	end)
	return self
end

-- The remaining categories (and Support) behind MORE.
function Locker:showMore()
	local body = self.Window.Body
	Window.clear(body)
	local row =
		Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = body }) :: Frame
	Kit.list(row, "X", 6)
	local extra = {}
	for i, category in Cosmetics.Categories do
		if i > 7 then
			table.insert(extra, { Id = category.Id, Label = category.Name })
		end
	end
	table.insert(extra, { Id = "Support", Label = "SUPPORT" })
	for i, entry in extra do
		local b = Kit.button(row, {
			Text = entry.Label,
			Size = UDim2.new(1 / #extra, -6, 1, 0),
			Style = "Ghost",
			TextSize = "Tiny",
			LayoutOrder = i,
			Sound = "Tab",
			OnClick = function()
				self.Category = entry.Id
				self.Selected = nil
				self:render(true)
			end,
		})
		b:SetAttribute("Active", self.Category == entry.Id)
	end
	local holder = Kit.create("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -48),
		Position = UDim2.fromOffset(0, 48),
		Parent = body,
	}) :: Frame
	self.MoreHolder = holder
	self:render(true)
end

local function rarityColor(item): Color3
	local r = Cosmetics.Rarities[item.Rarity]
	return r and Color3.fromRGB(r.Color[1], r.Color[2], r.Color[3]) or Theme.Colors.Dim
end

local function achievementName(id: string): string?
	local a = Achievements.get(id)
	if a == nil then
		return nil
	end
	return if a.Hidden then "???" else a.Name
end

function Locker:render(inMore: boolean?)
	local container = if inMore
			and self.MoreHolder
			and self.MoreHolder.Parent
		then self.MoreHolder
		else self.Window.Body
	if not inMore then
		Window.clear(self.Window.Body)
		self.MoreHolder = nil
	else
		Window.clear(container)
	end
	if self.Category == "Support" then
		self:renderSupport(container)
		return
	end
	local profile = self.C.ProfileController:get()
	local owned = profile and profile.Cosmetics.Owned or {}
	local equipped = profile and profile.Cosmetics.Equipped or {}
	local items = table.clone(Cosmetics.ByCategory[self.Category] or {})
	table.sort(items, function(a, b)
		local ao, bo = owned[a.Id] == true, owned[b.Id] == true
		if ao ~= bo then
			return ao
		end
		local ar, br = Cosmetics.Rarities[a.Rarity].Order, Cosmetics.Rarities[b.Rarity].Order
		if ar ~= br then
			return ar < br
		end
		return a.Name < b.Name
	end)
	self.Window:setSubtitle(
		string.format("%s MARKS  ·  COSMETIC ONLY", Format.thousands(profile and profile.Marks or 0))
	)

	local gridHolder = Kit.create(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(0.6, -8, 1, 0), Parent = container }
	) :: Frame
	local scroll = Kit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = gridHolder,
	}) :: ScrollingFrame
	Kit.grid(scroll, UDim2.fromOffset(170, 74), 8)
	for i, item in items do
		local isOwned = owned[item.Id] == true
		local isEquipped = equipped[item.Category] == item.Id
		local b = Kit.button(scroll, {
			Text = "",
			Size = UDim2.fromOffset(170, 74),
			LayoutOrder = i,
			Style = if isEquipped then "Primary" else "Default",
			OnClick = function()
				self.Selected = item.Id
				self:detail(item)
			end,
		})
		Kit.label(b, {
			Text = item.Name,
			Font = "Bold",
			TextSize = "Tiny",
			Wrap = true,
			Size = UDim2.new(1, -12, 0, 32),
			Position = UDim2.fromOffset(6, 6),
			YAlign = "Top",
			ZIndex = 3,
			Color = if isEquipped then "Bg" else "Text",
		})
		local sub = if isEquipped
			then "EQUIPPED"
			elseif isOwned then "OWNED"
			else Cosmetics.unlockText(item, achievementName)
		Kit.label(b, {
			Text = string.upper(sub),
			Font = "Mono",
			TextSize = "Tiny",
			Wrap = true,
			Size = UDim2.new(1, -12, 0, 26),
			Position = UDim2.new(0, 6, 1, -30),
			YAlign = "Bottom",
			ZIndex = 3,
			Color = if isEquipped then "Bg" elseif isOwned then "Good" else "Dim",
		})
		local stripe = Kit.create("Frame", {
			BorderSizePixel = 0,
			Size = UDim2.new(0, 3, 1, -8),
			Position = UDim2.fromOffset(0, 4),
			ZIndex = 3,
			Parent = b,
		}) :: Frame
		stripe.BackgroundColor3 = rarityColor(item)
		if not isOwned then
			b.BackgroundTransparency = 0.4
		end
	end
	local detail = Kit.panel(
		container,
		{ Name = "Detail", Size = UDim2.new(0.4, -8, 1, 0), Position = UDim2.new(0.6, 8, 0, 0), Color = "PanelAlt" }
	)
	Kit.padding(detail, 14, 16)
	self.DetailFrame = detail
	local selected = self.Selected and Cosmetics.get(self.Selected)
	if selected == nil then
		local id = equipped[self.Category]
		selected = id and Cosmetics.get(id) or items[1]
	end
	if selected then
		self:detail(selected)
	end
end

function Locker:detail(item)
	local detail = self.DetailFrame
	if detail == nil then
		return
	end
	for _, child in detail:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if self.PreviewConnection then
		self.PreviewConnection:Disconnect()
		self.PreviewConnection = nil
	end
	local profile = self.C.ProfileController:get()
	local owned = profile and profile.Cosmetics.Owned[item.Id] == true
	local equipped = profile and profile.Cosmetics.Equipped[item.Category] == item.Id
	-- Preview.
	local preview =
		Kit.create("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 190), Parent = detail }) :: Frame
	Theme.bind(preview, "BackgroundColor3", "Bg")
	Kit.corner(preview, 3)
	if item.Category == "DeviceSkin" then
		local viewport = Instance.new("ViewportFrame")
		viewport.BackgroundTransparency = 1
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.Ambient = Color3.fromRGB(150, 150, 150)
		viewport.LightColor = Color3.fromRGB(255, 240, 220)
		viewport.LightDirection = Vector3.new(-1, -1, -0.5)
		viewport.Parent = preview
		local model = ArbiterModel.build(CFrame.identity)
		ArbiterModel.applySkin(model, item.Data)
		model.Parent = viewport
		local cam = Instance.new("Camera")
		cam.FieldOfView = 32
		cam.CFrame = CFrame.lookAt(Vector3.new(6, 2.5, 0), Vector3.new(0, 0.1, -0.4))
		cam.Parent = viewport
		viewport.CurrentCamera = cam
		self.PreviewConnection = RunService.RenderStepped:Connect(function()
			if not viewport.Parent then
				return
			end
			local t = os.clock()
			ArbiterModel.place(
				model,
				CFrame.new(0, 0, -0.3) * CFrame.Angles(0, t * 0.6, 0) * CFrame.new(0, 0, 0.3),
				0,
				math.sin(t) * 0.6
			)
		end)
	else
		local swatch = Kit.create("Frame", {
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(90, 90),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = preview,
		}) :: Frame
		local data = item.Data or {}
		local color = data.Color or data.Top or data.Glow or data.Stroke or data.Fill or data.Accent
		swatch.BackgroundColor3 = if type(color) == "table"
			then Color3.fromRGB(color[1], color[2], color[3])
			else rarityColor(item)
		Kit.corner(swatch, 6)
		if data.Text then
			Kit.label(preview, {
				Text = '"' .. data.Text .. '"',
				Font = "Type",
				TextSize = "Title",
				XAlign = "Center",
				Size = UDim2.new(1, 0, 0, 30),
				Position = UDim2.new(0, 0, 1, -34),
			})
		end
	end
	local rarity = Cosmetics.Rarities[item.Rarity]
	Kit.label(detail, {
		Text = item.Name,
		Font = "Display",
		TextSize = "Title",
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.fromOffset(0, 200),
	})
	local rarityLabel = Kit.label(detail, {
		Text = (rarity and rarity.Label or "") .. "  ·  " .. string.upper(item.Category),
		Font = "Mono",
		TextSize = "Tiny",
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, 230),
	})
	rarityLabel.TextColor3 = rarityColor(item)
	Kit.label(detail, {
		Text = item.Description or "",
		Font = "Body",
		TextSize = "Small",
		Color = "Dim",
		Wrap = true,
		YAlign = "Top",
		Size = UDim2.new(1, 0, 0, 70),
		Position = UDim2.fromOffset(0, 252),
	})
	local action
	if equipped then
		action =
			Kit.button(detail, { Text = "EQUIPPED", Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -44) })
		Kit.setEnabled(action, false, "Already equipped.")
	elseif owned then
		action = Kit.button(detail, {
			Text = "EQUIP",
			Style = "Primary",
			Size = UDim2.new(1, 0, 0, 44),
			Position = UDim2.new(0, 0, 1, -44),
			OnClick = function()
				local ok, err = self.C.NetworkClient:request("Cosmetics.Equip", item.Category, item.Id)
				if not ok then
					self.UI:toast("LOCKER", tostring(err), "Warn")
				end
			end,
		})
	elseif item.Source.Kind == "Shop" then
		local marks = profile and profile.Marks or 0
		action = Kit.button(detail, {
			Text = string.format("BUY  ·  %s MARKS", Format.thousands(item.Price or 0)),
			Style = "Primary",
			Size = UDim2.new(1, 0, 0, 44),
			Position = UDim2.new(0, 0, 1, -44),
			OnClick = function()
				if
					Kit.confirm(
						"PURCHASE",
						string.format("Spend %s Marks on %s?", Format.thousands(item.Price or 0), item.Name),
						"BUY"
					)
				then
					local ok, err = self.C.NetworkClient:request("Cosmetics.Buy", item.Id)
					if not ok then
						self.UI:toast("LOCKER", tostring(err or "Purchase failed."), "Warn")
					end
				end
			end,
		})
		if marks < (item.Price or 0) then
			Kit.setEnabled(
				action,
				false,
				string.format("You need %s more Marks.", Format.thousands((item.Price or 0) - marks))
			)
		end
	else
		action =
			Kit.button(detail, { Text = "LOCKED", Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -44) })
		Kit.setEnabled(action, false, Cosmetics.unlockText(item, achievementName))
		Kit.label(detail, {
			Text = "HOW TO EARN: " .. string.upper(Cosmetics.unlockText(item, achievementName)),
			Font = "Mono",
			TextSize = "Tiny",
			Color = "Accent",
			Wrap = true,
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.new(0, 0, 1, -80),
		})
	end
end

function Locker:renderSupport(container: Instance)
	self.Window:setSubtitle("OPTIONAL  ·  COSMETIC ONLY  ·  NO GAMEPLAY ADVANTAGE")
	local scroll = Kit.scroll(container, { Padding = 8 })
	local any = false
	local order = 0
	for _, group in { Config.Monetization.Passes, Config.Monetization.Products } do
		for _, entry in group do
			if entry.Id and entry.Id ~= 0 then
				any = true
				order += 1
				local card =
					Kit.panel(scroll, { Size = UDim2.new(1, -8, 0, 70), LayoutOrder = order, Color = "PanelAlt" })
				Kit.padding(card, 10, 14)
				Kit.label(card, {
					Text = entry.Name,
					Font = "Display",
					TextSize = "Body",
					Color = "Accent",
					Size = UDim2.new(1, -170, 0, 22),
				})
				Kit.label(card, {
					Text = entry.Description or "",
					Font = "Body",
					TextSize = "Small",
					Color = "Dim",
					Size = UDim2.new(1, -170, 0, 20),
					Position = UDim2.fromOffset(0, 26),
				})
				Kit.button(card, {
					Text = "VIEW",
					Size = UDim2.fromOffset(150, 38),
					Position = UDim2.new(1, 0, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					OnClick = function()
						self.C.NetworkClient:request("Shop.Prompt", entry.Key)
					end,
				})
			end
		end
	end
	if not any then
		Kit.label(scroll, {
			Text = "Nothing is for sale. Everything in the Locker is earned by playing.",
			Font = "Mono",
			TextSize = "Small",
			Color = "Dim",
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = 1,
		})
	end
end

function Locker:Open(args)
	self.Window:open()
	if args and args.Category then
		self.Category = args.Category
	end
	if self.Window.select then
		self.Window.select(self.Category)
	end
end

function Locker:Close()
	if self.PreviewConnection then
		self.PreviewConnection:Disconnect()
		self.PreviewConnection = nil
	end
	self.Window:close()
end

return Locker
