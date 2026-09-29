-- Build & decoration mode.
--
-- Press H (or use a placeable from your bag) to enter. The camera lifts to a
-- top-down view of the farm you're standing on; the catalog lists every
-- placeable you own (categories, search, favourites).
--
--   Click            place the selected item / pick up an existing object
--   R / Shift+R      rotate (90° on the grid, 15° free)
--   T                grid ↔ free placement (decorations only)
--   G                cycle free-placement snap (0.5 / 1 / 2 / 4 studs)
--   [ and ]          smaller / bigger (items with a size range)
--   PageUp/PageDown  lift / lower (free decorations)
--   Ctrl+Z / Ctrl+Y  undo / redo        Delete   pick up the selected object
--   Ctrl+D           duplicate the selected object   I   copy its style
--   WASD / right stick pan · scroll zoom · Z/X turn · H or Esc to exit
-- Paths paint while you hold the button. The ghost turns red where the
-- server would refuse (outside your land, overlapping, on soil...); the
-- server always has the final word.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Placeables = require(Shared.Config.Placeables)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Models = require(Shared.Models)

local C = require(script.Parent)
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UIFolder.Kit)
local Theme = require(UIFolder.Theme)

local BuildController = {}

local TILE = 4
local player = Players.LocalPlayer

local active = false
local origin: Vector3? = nil
local selectedId: string? = nil -- placeable id to place
local picked: Model? = nil -- existing object being moved
local ghost: Model? = nil
local ghostKey = ""
local highlight: Highlight? = nil
local rotation = 0
local free = false
local snapIndex = 1
local scale = 1
local lift = 0
local brush: { C: string?, Mt: string? } = {}
local favorites: { [string]: boolean } = {}
local category = "All"
local search = ""
local undoStack: { any } = {}
local redoStack: { any } = {}
local uidAlias: { [string]: string } = {} -- old uid → new uid after undo re-placement
local releaseCamera: (() -> ())? = nil
local camFocus = Vector3.zero
local camZoom = 90
local camYaw = 0
local painting = false
local lastPaintKey = ""
local panel: Frame? = nil
local catalogList: ScrollingFrame? = nil
local inspector: Frame? = nil
local statusLabel: TextLabel? = nil
local busy = false
local touchPoint: Vector2? = nil -- last tap on touch screens

function BuildController.Active(): boolean
	return active
end

-- Helpers ------------------------------------------------------------------------------------------------------------

local function def(id: string?): any
	return id and Registry.Placeables[id]
end

local function isDecor(d: any): boolean
	return d ~= nil and Registry.HasTag(d.Id, "Decor")
end

local function owned(): { [string]: number }
	local counts = {}
	for _, stack in C.State.Get("Inventory", "Slots") or {} do
		local item = Registry.Items[stack.Id]
		if item and item.Placeable then
			counts[stack.Id] = (counts[stack.Id] or 0) + stack.N
		end
	end
	return counts
end

local function resolve(uid: string): string
	while uidAlias[uid] do
		uid = uidAlias[uid]
	end
	return uid
end

local function status(text: string, key: string?)
	if statusLabel then
		statusLabel.Text = text
		Kit.Paint(statusLabel, "TextColor3", key or "SubText")
	end
end

local function specFromModel(m: Model): any
	return {
		X = m:GetAttribute("Px"),
		Z = m:GetAttribute("Pz"),
		R = m:GetAttribute("Ry") or 0,
		Y = m:GetAttribute("Py"),
		Free = m:GetAttribute("Free") == true,
		Sc = m:GetAttribute("Sc"),
		C = m:GetAttribute("C"),
		Mt = m:GetAttribute("Mt"),
	}
end

-- Placement spec under the pointer --------------------------------------------------------------------------------

local function pointerHit(): RaycastResult?
	local location = UserInputService:GetMouseLocation()
	local primary = C.Settings.PrimaryInput()
	if primary == "Touch" and touchPoint then
		location = touchPoint :: Vector2
	elseif primary ~= "Keyboard" then
		-- Gamepad (and touch before the first tap): aim with the screen centre.
		location = workspace.CurrentCamera.ViewportSize / 2
	end
	local ray = workspace.CurrentCamera:ViewportPointToRay(location.X, location.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { workspace.CurrentCamera }
	for _, name in { "ClientCrops", "ClientAnimals", "ClientFX", "ClientBuild", "ClientGather" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(exclude, f)
		end
	end
	if player.Character then
		table.insert(exclude, player.Character)
	end
	if ghost then
		table.insert(exclude, ghost)
	end
	params.FilterDescendantsInstances = exclude
	return workspace:Raycast(ray.Origin, ray.Direction * 600, params)
end

local function currentDef(): any
	if picked then
		return def(picked:GetAttribute("Placeable") :: string?)
	end
	return def(selectedId)
end

local function buildSpec(hit: RaycastResult): any?
	local d = currentDef()
	if not d or not origin then
		return nil
	end
	local rel = hit.Position - (origin :: Vector3)
	local spec: any = { R = rotation, Sc = scale, C = brush.C, Mt = brush.Mt }
	if free and isDecor(d) then
		local snap = Placeables.GridSnap[snapIndex]
		spec.Free = true
		spec.Snap = snap
		spec.X = math.round(rel.X / snap) * snap
		spec.Z = math.round(rel.Z / snap) * snap
		spec.Y = if lift > 0 then lift else nil
	else
		local quarter = math.round(rotation / 90) % 4
		local w, dd = d.Size[1], d.Size[2]
		if quarter % 2 == 1 then
			w, dd = dd, w
		end
		local gx0 = math.round(rel.X / TILE - w / 2)
		local gz0 = math.round(rel.Z / TILE - dd / 2)
		spec.X = (gx0 + w / 2) * TILE
		spec.Z = (gz0 + dd / 2) * TILE
		spec.R = quarter * 90
		spec.Free = false
	end
	return spec
end

-- Client-side validity (a preview; the server decides).
local function looksValid(d: any, spec: any): (boolean, string?)
	local sc = if d.Scale then math.clamp(spec.Sc or 1, d.Scale[1], d.Scale[2]) else 1
	local halfW, halfD = d.Size[1] * TILE * sc / 2, d.Size[2] * TILE * sc / 2
	if spec.R % 180 == 90 then
		halfW, halfD = halfD, halfW
	end
	if spec.X - halfW < -0.1 or spec.X + halfW > 240.1 or spec.Z - halfD < -44.1 or spec.Z + halfD > 240.1 then
		return false, "Outside the farm"
	end
	-- Overlap with other placed objects (axis-aligned approximation).
	local lotFolder
	for _, lot in (workspace:FindFirstChild("Farms") :: Instance):GetChildren() do
		if lot:GetAttribute("Origin") == origin then
			lotFolder = lot:FindFirstChild("Placed")
		end
	end
	if lotFolder then
		local isPath = d.Category == "Path"
		for _, m in lotFolder:GetChildren() do
			if m ~= picked and m:IsA("Model") then
				local other = def(m:GetAttribute("Placeable"))
				if
					other
					and (other.Category == "Path") == isPath
					and not (other.Function and other.Function.Kind == "Interior" and d.OnSoil)
				then
					local osc = if other.Scale then (m:GetAttribute("Sc") or 1) else 1
					local ow, od = other.Size[1] * TILE * osc / 2, other.Size[2] * TILE * osc / 2
					if (m:GetAttribute("Ry") or 0) % 180 == 90 then
						ow, od = od, ow
					end
					local ox, oz = m:GetAttribute("Px") or 0, m:GetAttribute("Pz") or 0
					if math.abs(ox - spec.X) < ow + halfW - 0.2 and math.abs(oz - spec.Z) < od + halfD - 0.2 then
						return false, "Overlaps " .. other.Name
					end
				end
			end
		end
	end
	return true, nil
end

-- Ghost ---------------------------------------------------------------------------------------------------------------

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	ghostKey = ""
end

local function updateGhost()
	local d = currentDef()
	if not d then
		clearGhost()
		return
	end
	local key = d.Id .. "|" .. tostring(scale) .. "|" .. tostring(brush.C) .. "|" .. tostring(brush.Mt)
	if key ~= ghostKey then
		clearGhost()
		local g = Models.Ghost(d, { C = brush.C, Mt = brush.Mt, Sc = scale })
		ghostKey = key
		local h = Instance.new("Highlight")
		h.FillTransparency = 0.7
		h.OutlineTransparency = 0.2
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = g
		highlight = h
		g.Parent = workspace:FindFirstChild("ClientBuild")
		ghost = g
	end
	local hit = pointerHit()
	local spec = hit and buildSpec(hit)
	if not spec or not origin then
		(ghost :: Model):PivotTo(CFrame.new(0, -1000, 0))
		return
	end
	local o = origin :: Vector3
	local pos = o + Vector3.new(spec.X, spec.Y or 0, spec.Z);
	(ghost :: Model):PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(spec.R), 0))
	local ok, why = looksValid(d, spec)
	if highlight then
		highlight.FillColor = if ok then Color3.fromRGB(120, 230, 120) else Color3.fromRGB(240, 90, 80)
		highlight.OutlineColor = highlight.FillColor
	end
	if why then
		status("✋ " .. why, "Bad")
	else
		local counts = owned()
		local n = if picked then 1 else (counts[d.Id] or 0)
		status(
			(if picked then "Moving " else "Placing ")
				.. d.Name
				.. (if picked then "" else "  ·  " .. n .. " in your bag")
				.. (if free then "  ·  free (" .. Placeables.GridSnap[snapIndex] .. " studs)" else "  ·  grid"),
			"SubText"
		)
	end
end

-- Undo / redo ------------------------------------------------------------------------------------------------------------

local function record(op: any)
	table.insert(undoStack, op)
	if #undoStack > 60 then
		table.remove(undoStack, 1)
	end
	table.clear(redoStack)
end

local function doPlace(id: string, spec: any): string?
	local ok, result = Net.Request("BuildPlace", id, spec)
	if not ok then
		status("✋ " .. tostring(result), "Bad")
		C.Audio.PlayUI("UIError")
		return nil
	end
	C.Audio.PlayUI("Place")
	return result
end

local function apply(op: any, inverse: boolean): boolean
	if op.Type == "Place" then
		if inverse then
			return (Net.Request("BuildRemove", resolve(op.Uid)))
		end
		local newUid = doPlace(op.Id, op.Spec)
		if newUid then
			uidAlias[op.Uid] = newUid
			return true
		end
		return false
	elseif op.Type == "Remove" then
		if inverse then
			local newUid = doPlace(op.Id, op.Spec)
			if newUid then
				uidAlias[op.Uid] = newUid
				return true
			end
			return false
		end
		return (Net.Request("BuildRemove", resolve(op.Uid)))
	elseif op.Type == "Move" then
		return (Net.Request("BuildMove", resolve(op.Uid), if inverse then op.From else op.To))
	elseif op.Type == "Style" then
		return (Net.Request("BuildStyle", resolve(op.Uid), if inverse then op.From else op.To))
	end
	return false
end

function BuildController.Undo()
	local op = table.remove(undoStack)
	if not op then
		status("Nothing to undo")
		return
	end
	if apply(op, true) then
		table.insert(redoStack, op)
		status("↶ Undone")
	else
		status("Couldn't undo that", "Bad")
	end
end

function BuildController.Redo()
	local op = table.remove(redoStack)
	if not op then
		status("Nothing to redo")
		return
	end
	if apply(op, false) then
		table.insert(undoStack, op)
		status("↷ Redone")
	else
		status("Couldn't redo that", "Bad")
	end
end

-- Actions ---------------------------------------------------------------------------------------------------------------

local function selectedModel(): Model?
	local hit = pointerHit()
	local inst: Instance? = hit and hit.Instance
	while inst and inst ~= workspace do
		if inst:IsA("Model") and inst:GetAttribute("Uid") and inst:GetAttribute("Placeable") then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

local function refreshInspector()
	local frame = inspector
	if not frame then
		return
	end
	Kit.Clear(frame)
	local d = currentDef()
	if not d then
		local tip = Kit.Label(
			"Pick something from the catalog, or click an object on your farm to move it.",
			{ Wrap = true, Color = "SubText", Size = Theme.Sizes.Small }
		)
		tip.Parent = frame
		return
	end
	local title = Kit.Heading(d.Icon .. " " .. d.Name, 18)
	title.Parent = frame
	if d.Description then
		local desc = Kit.Label(d.Description, { Wrap = true, Size = Theme.Sizes.Small, Color = "SubText" })
		desc.LayoutOrder = 1
		desc.Parent = frame
	end
	local order = 2
	local function row(widget: GuiObject)
		widget.LayoutOrder = order
		order += 1
		widget.Parent = frame
	end
	if d.Paint then
		local swatches = Kit.new(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }
		)
		local grid = Kit.Grid(swatches, 24, 4)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		for i, color in Placeables.Palette do
			local sw = Kit.new(
				"TextButton",
				{ AutoButtonColor = true, Text = "", BackgroundColor3 = color, LayoutOrder = i, Parent = swatches }
			)
			Kit.Corner(sw, 6)
			sw.Activated:Connect(function()
				brush.C = color:ToHex()
				C.Audio.PlayUI("UIClick")
				if picked then
					local uid = picked:GetAttribute("Uid")
					local from = { C = picked:GetAttribute("C") or false }
					local to = { C = brush.C }
					if Net.Request("BuildStyle", uid, to) then
						record({ Type = "Style", Uid = uid, From = from, To = to })
					end
				end
			end)
		end
		local clear =
			Kit.new("TextButton", { Text = "✕", BackgroundTransparency = 0.5, LayoutOrder = 99, Parent = swatches })
		clear.Activated:Connect(function()
			brush.C = nil
		end)
		row(Kit.Label("Paint", { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold }))
		row(swatches)
	end
	if d.Materials then
		local options = { "Default" }
		for _, m in d.Materials do
			table.insert(options, m)
		end
		row(Kit.Row(
			"Material",
			Kit.Choice(options, brush.Mt or "Default", function(v)
				brush.Mt = if v == "Default" then nil else v
			end)
		))
	end
	if d.Scale then
		row(Kit.Label("Size", { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold }))
		row(Kit.Slider(scale, d.Scale[1], d.Scale[2], 0.05, function(v)
			scale = v
		end))
	end
	if isDecor(d) then
		row(Kit.Row("Free placement", (Kit.Toggle(free, function(v)
			free = v
		end))))
	end
	local buttons = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36) })
	Kit.List(buttons, "X", 6)
	Kit.Button("⟲", {
		Style = "Secondary",
		Size = UDim2.fromOffset(40, 34),
		OnClick = function()
			rotation = (rotation + (if free then 15 else 90)) % 360
		end,
	}).Parent =
		buttons
	if picked then
		Kit.Button("Pick up", {
			Style = "Danger",
			Size = UDim2.fromOffset(90, 34),
			OnClick = function()
				BuildController.RemovePicked()
			end,
		}).Parent =
			buttons
		Kit.Button("Copy", {
			Style = "Secondary",
			Size = UDim2.fromOffset(70, 34),
			OnClick = function()
				BuildController.Duplicate()
			end,
		}).Parent =
			buttons
	end
	row(buttons)
end

function BuildController.Select(id: string?)
	picked = nil
	selectedId = id
	if id then
		local d = def(id)
		if d and not isDecor(d) then
			free = false
		end
	end
	clearGhost()
	refreshInspector()
end

function BuildController.RemovePicked()
	local m = picked
	if not m then
		return
	end
	local uid = m:GetAttribute("Uid")
	local spec = specFromModel(m)
	local id = m:GetAttribute("Placeable")
	local ok, err = Net.Request("BuildRemove", uid)
	if ok then
		record({ Type = "Remove", Uid = uid, Id = id, Spec = spec })
		C.Audio.PlayUI("Remove")
		picked = nil
		clearGhost()
		refreshInspector()
		status("Picked up — it's back in your bag")
	else
		status("✋ " .. tostring(err), "Bad")
	end
end

function BuildController.Duplicate()
	local m = picked
	if not m then
		return
	end
	local id = m:GetAttribute("Placeable")
	local style = specFromModel(m)
	picked = nil
	selectedId = id
	brush.C = style.C
	brush.Mt = style.Mt
	scale = style.Sc or 1
	rotation = style.R or 0
	free = style.Free
	clearGhost()
	refreshInspector()
	status("Duplicating — click to place a copy")
end

local function copyStyle()
	local m = selectedModel()
	if m then
		brush.C = m:GetAttribute("C")
		brush.Mt = m:GetAttribute("Mt")
		scale = m:GetAttribute("Sc") or 1
		status("🎨 Style copied")
		clearGhost()
		refreshInspector()
	end
end

local function click()
	if busy then
		return
	end
	local hit = pointerHit()
	if not hit then
		return
	end
	-- Moving a picked object
	if picked then
		local spec = buildSpec(hit)
		if not spec then
			return
		end
		busy = true
		local uid = picked:GetAttribute("Uid")
		local from = specFromModel(picked)
		local ok, err = Net.Request("BuildMove", uid, spec)
		busy = false
		if ok then
			record({ Type = "Move", Uid = uid, From = from, To = spec })
			C.Audio.PlayUI("Place")
			picked = nil
			clearGhost()
			refreshInspector()
		else
			status("✋ " .. tostring(err), "Bad")
			C.Audio.PlayUI("UIError")
		end
		return
	end
	-- Placing a new object
	if selectedId then
		local spec = buildSpec(hit)
		if not spec then
			return
		end
		busy = true
		local uid = doPlace(selectedId, spec)
		busy = false
		if uid then
			record({ Type = "Place", Uid = uid, Id = selectedId, Spec = spec })
			if (owned()[selectedId] or 0) <= 1 then
				-- That was the last one.
				task.delay(0.3, function()
					if (owned()[selectedId or ""] or 0) <= 0 then
						BuildController.Select(nil)
					end
				end)
			end
		end
		return
	end
	-- Pick up an existing object to move it
	local m = selectedModel()
	if m then
		picked = m
		local style = specFromModel(m)
		rotation = style.R or 0
		free = style.Free
		scale = style.Sc or 1
		brush.C = style.C
		brush.Mt = style.Mt
		lift = style.Y or 0
		clearGhost()
		refreshInspector()
		status("Moving " .. (def(m:GetAttribute("Placeable")) or {}).Name .. " — click to set it down")
	end
end

-- Catalog -------------------------------------------------------------------------------------------------------------------

local function refreshCatalog()
	local list = catalogList
	if not list then
		return
	end
	Kit.Clear(list)
	local counts = owned()
	local entries = {}
	for id, n in counts do
		local d = def(id)
		if d then
			local matchCat = category == "All" or d.Category == category or (category == "Favorites" and favorites[id])
			local matchSearch = search == "" or string.find(string.lower(d.Name), string.lower(search), 1, true) ~= nil
			if matchCat and matchSearch then
				table.insert(entries, { Def = d, N = n })
			end
		end
	end
	table.sort(entries, function(a, b)
		local fa, fb = favorites[a.Def.Id] and 1 or 0, favorites[b.Def.Id] and 1 or 0
		if fa ~= fb then
			return fa > fb
		end
		return a.Def.Name < b.Def.Name
	end)
	if #entries == 0 then
		Kit.Empty(
			if category == "All" and search == ""
				then "Nothing to place yet. Buy decorations and buildings from Gus at Timberline Builders, or craft them."
				else "No matches."
		).Parent =
			list
		return
	end
	for i, entry in entries do
		local d = entry.Def
		local card = Kit.new(
			"TextButton",
			{ AutoButtonColor = false, Text = "", Size = UDim2.new(1, -6, 0, 46), LayoutOrder = i, Parent = list }
		)
		Kit.Paint(card, "BackgroundColor3", if selectedId == d.Id then "SlotHover" else "Slot")
		Kit.Corner(card, 8)
		local icon = Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			Text = d.Icon,
			TextScaled = true,
			Size = UDim2.fromOffset(34, 34),
			Position = UDim2.fromOffset(6, 6),
			Parent = card,
		})
		icon.Font = Theme.Fonts.Body
		local name = Kit.Label(d.Name, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
		name.Position = UDim2.fromOffset(46, 4)
		name.Size = UDim2.new(1, -90, 0, 20)
		name.Parent = card
		local sub = Kit.Label(
			"×" .. entry.N .. " · " .. d.Size[1] .. "×" .. d.Size[2],
			{ Size = Theme.Sizes.Tiny, Color = "SubText" }
		)
		sub.Position = UDim2.fromOffset(46, 24)
		sub.Size = UDim2.new(1, -90, 0, 16)
		sub.Parent = card
		local star = Kit.new("TextButton", {
			BackgroundTransparency = 1,
			Text = if favorites[d.Id] then "★" else "☆",
			TextSize = 20,
			Font = Theme.Fonts.Bold,
			Size = UDim2.fromOffset(32, 32),
			Position = UDim2.new(1, -36, 0, 7),
			Parent = card,
		})
		Kit.Paint(star, "TextColor3", "Accent")
		star.Activated:Connect(function()
			if favorites[d.Id] then
				favorites[d.Id] = nil
			else
				favorites[d.Id] = true
			end
			refreshCatalog()
		end)
		card.Activated:Connect(function()
			C.Audio.PlayUI("UIClick")
			BuildController.Select(d.Id)
			refreshCatalog()
		end)
		Kit.AttachTooltip(card, function()
			return {
				{ Text = d.Icon .. " " .. d.Name, Bold = true },
				{ Text = d.Description or d.Category, Color = "SubText", Size = Theme.Sizes.Small },
			}
		end)
	end
end

local function buildPanel()
	local layer = C.UI.Layer("HUD")
	local root = Kit.Panel({ Size = UDim2.new(0, 300, 1, -150), Shadow = true, Name = "BuildPanel" })
	root.AnchorPoint = Vector2.new(0, 0.5)
	root.Position = UDim2.new(0, 14, 0.5, -20)
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(300, 580), MinSize = Vector2.new(260, 300), Parent = root })
	root.Parent = layer
	Kit.Padding(root, 10, 10)
	local title = Kit.Heading("🛠️ Build Mode", 20)
	title.Parent = root
	local close = Kit.Button("Done", {
		Style = "Accent",
		Size = UDim2.fromOffset(70, 30),
		TextSize = 14,
		OnClick = function()
			BuildController.Exit()
		end,
	})
	close.Position = UDim2.new(1, -70, 0, -2)
	close.Parent = root
	local searchBox = Kit.TextBox("🔍 Search…", { Size = UDim2.new(1, 0, 0, 32) })
	searchBox.Position = UDim2.fromOffset(0, 36)
	searchBox.Parent = root
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		search = searchBox.Text
		refreshCatalog()
	end)
	local cats = Kit.Scroll({ Horizontal = true, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 74) })
	cats.Parent = root
	Kit.List(cats, "X", 4)
	local catIds =
		{ { Id = "All", Name = "All", Icon = "✨" }, { Id = "Favorites", Name = "Favourites", Icon = "★" } }
	for _, cat in Placeables.Categories do
		table.insert(catIds, cat)
	end
	for i, cat in catIds do
		local b = Kit.Button(cat.Icon, {
			Style = "Secondary",
			Size = UDim2.fromOffset(34, 30),
			TextSize = 16,
			LayoutOrder = i,
			OnClick = function()
				category = cat.Id
				refreshCatalog()
			end,
		})
		Kit.AttachTooltip(b, function()
			return { { Text = cat.Name } }
		end)
		b.Parent = cats
	end
	local list = Kit.Scroll({ Size = UDim2.new(1, 0, 0.5, -60), Position = UDim2.fromOffset(0, 114) })
	Kit.List(list, "Y", 4)
	list.Parent = root
	catalogList = list
	local insp = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0.5, -70),
		Position = UDim2.new(0, 0, 0.5, 60),
		Parent = root,
	})
	Kit.List(insp, "Y", 6)
	inspector = insp
	-- Status line along the bottom (right of the catalog), tool buttons above it.
	local bar = Kit.Panel({ Size = UDim2.new(1, -350, 0, 44), Shadow = true, Name = "BuildStatus" })
	bar.AnchorPoint = Vector2.new(1, 1)
	bar.Position = UDim2.new(1, -16, 1, -16)
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(640, 44), Parent = bar })
	bar.Parent = layer
	local label = Kit.Label("", { Align = "Center", Size = Theme.Sizes.Small })
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = bar
	statusLabel = label
	local toolbar = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 0, -8),
		Parent = bar,
	})
	Kit.List(toolbar, "X", 6)
	Kit.IconButton("↶", "Undo (Ctrl+Z)", BuildController.Undo).Parent = toolbar
	Kit.IconButton("↷", "Redo (Ctrl+Y)", BuildController.Redo).Parent = toolbar
	Kit.IconButton("🎨", "Copy style from an object (I)", copyStyle).Parent = toolbar
	Kit.IconButton("✋", "Stop placing (select objects to move)", function()
		BuildController.Select(nil)
	end).Parent =
		toolbar
	panel = root
	Kit.Pop(root)
	Kit.RepaintGradients(root)
	local pieces = { root, bar }
	root.Destroying:Connect(function()
		for _, p in pieces do
			if p ~= root then
				p:Destroy()
			end
		end
	end)
	refreshCatalog()
	refreshInspector()
end

-- Enter / exit ---------------------------------------------------------------------------------------------------------------

function BuildController.Enter(itemId: string?)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local o = C.Input.LotOrigin(root.Position)
	if not o then
		C.Notify.Toast("Stand on a farm to build", "Info")
		return
	end
	if C.Windows.IsOpen() then
		C.Windows.Close(true)
	end
	if active then
		if itemId then
			BuildController.Select(itemId)
			refreshCatalog()
		end
		return
	end
	active = true
	origin = o
	camFocus = root.Position
	camZoom = 90
	releaseCamera = C.Camera.Take("Build")
	game:GetService("ProximityPromptService").Enabled = false
	buildPanel()
	BuildController.Select(itemId)
	Net.Send("MenuState", false)
	C.Tutorial.Hint("Build")
	ContextActionService:BindAction(
		"EvergroveBuildMovement",
		function()
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.PlayerActions.CharacterForward,
		Enum.PlayerActions.CharacterBackward,
		Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight
	)
end

function BuildController.Exit()
	if not active then
		return
	end
	active = false
	picked = nil
	selectedId = nil
	clearGhost()
	if panel then
		panel:Destroy()
		panel = nil
	end
	local bar = C.UI.Layer("HUD"):FindFirstChild("BuildStatus")
	if bar then
		bar:Destroy()
	end
	if releaseCamera then
		releaseCamera()
		releaseCamera = nil
	end
	ContextActionService:UnbindAction("EvergroveBuildMovement")
	game:GetService("ProximityPromptService").Enabled = true
end

function BuildController.Toggle()
	if active then
		BuildController.Exit()
	else
		BuildController.Enter(nil)
	end
end

-- Loop & input ----------------------------------------------------------------------------------------------------------------

function BuildController.Start()
	C.State.Watch("Inventory", function()
		if active then
			refreshCatalog()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not active or UserInputService:GetFocusedTextBox() then
			return
		end
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		local key = input.KeyCode
		if
			(
				input.UserInputType == Enum.UserInputType.MouseButton1
				or key == Enum.KeyCode.ButtonR2
				or input.UserInputType == Enum.UserInputType.Touch
			) and not processed
		then
			if input.UserInputType == Enum.UserInputType.Touch then
				touchPoint = Vector2.new(input.Position.X, input.Position.Y)
					+ game:GetService("GuiService"):GetGuiInset()
			end
			click()
			local d = currentDef()
			painting = d ~= nil and d.Category == "Path" and not picked
		elseif key == Enum.KeyCode.Escape or key == Enum.KeyCode.H or key == Enum.KeyCode.ButtonB then
			if picked or selectedId then
				BuildController.Select(nil)
			else
				BuildController.Exit()
			end
		elseif key == Enum.KeyCode.R or key == Enum.KeyCode.ButtonY then
			local stepDeg = if free then 15 else 90
			rotation = (rotation + (if shift then -stepDeg else stepDeg)) % 360
		elseif key == Enum.KeyCode.T then
			local d = currentDef()
			if isDecor(d) then
				free = not free
				refreshInspector()
			else
				status("Only decorations can be placed freely", "Warn")
			end
		elseif key == Enum.KeyCode.G then
			snapIndex = snapIndex % #Placeables.GridSnap + 1
		elseif key == Enum.KeyCode.LeftBracket or key == Enum.KeyCode.RightBracket then
			local d = currentDef()
			if d and d.Scale then
				scale =
					math.clamp(scale + (if key == Enum.KeyCode.RightBracket then 0.1 else -0.1), d.Scale[1], d.Scale[2])
			end
		elseif key == Enum.KeyCode.PageUp or key == Enum.KeyCode.PageDown then
			lift = math.clamp(lift + (if key == Enum.KeyCode.PageUp then 0.5 else -0.5), 0, 12)
		elseif key == Enum.KeyCode.Delete or key == Enum.KeyCode.Backspace or key == Enum.KeyCode.ButtonX then
			BuildController.RemovePicked()
		elseif ctrl and key == Enum.KeyCode.Z then
			BuildController.Undo()
		elseif ctrl and key == Enum.KeyCode.Y then
			BuildController.Redo()
		elseif ctrl and key == Enum.KeyCode.D then
			BuildController.Duplicate()
		elseif key == Enum.KeyCode.I then
			copyStyle()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonR2
		then
			painting = false
			lastPaintKey = ""
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if active and not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
			camZoom = math.clamp(camZoom - input.Position.Z * 8, 30, 180)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if not active then
			return
		end
		-- Camera pan
		local move = Vector3.zero
		if not UserInputService:GetFocusedTextBox() then
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then
				move += Vector3.new(0, 0, -1)
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then
				move += Vector3.new(0, 0, 1)
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then
				move += Vector3.new(-1, 0, 0)
			end
			if
				UserInputService:IsKeyDown(Enum.KeyCode.D) and not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			then
				move += Vector3.new(1, 0, 0)
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.Z) then
				camYaw += dt * 1.5
			elseif UserInputService:IsKeyDown(Enum.KeyCode.X) then
				camYaw -= dt * 1.5
			end
		end
		for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if state.KeyCode == Enum.KeyCode.Thumbstick1 and state.Position.Magnitude > 0.2 then
				move += Vector3.new(state.Position.X, 0, -state.Position.Y)
			elseif state.KeyCode == Enum.KeyCode.Thumbstick2 and state.Position.Magnitude > 0.2 then
				camYaw -= state.Position.X * dt * 2
				camZoom = math.clamp(camZoom - state.Position.Y * dt * 60, 30, 180)
			end
		end
		if move.Magnitude > 0 then
			local rotated = CFrame.Angles(0, camYaw, 0):VectorToWorldSpace(move.Unit)
			camFocus += rotated * dt * (30 + camZoom * 0.6)
			if origin then
				local o = origin :: Vector3
				camFocus = Vector3.new(
					math.clamp(camFocus.X, o.X - 20, o.X + 260),
					camFocus.Y,
					math.clamp(camFocus.Z, o.Z - 70, o.Z + 260)
				)
			end
		end
		local camera = workspace.CurrentCamera
		local eye = camFocus + CFrame.Angles(0, camYaw, 0):VectorToWorldSpace(Vector3.new(0, camZoom, camZoom * 0.45))
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eye, camFocus), 1 - math.exp(-12 * dt))
		updateGhost()
		-- Path painting while held
		if painting and selectedId then
			local hit = pointerHit()
			local spec = hit and buildSpec(hit)
			if spec then
				local key = spec.X .. "_" .. spec.Z
				if key ~= lastPaintKey and not busy then
					lastPaintKey = key
					task.spawn(click)
				end
			end
		end
	end)
end

return BuildController
