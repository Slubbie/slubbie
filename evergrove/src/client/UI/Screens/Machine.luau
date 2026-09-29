-- An artisan machine: its job queue (with live progress), what you can load
-- from your bag, finished goods waiting to be collected, upgrades and auto
-- mode (with a Logistics Hub). Args: { Uid = placedUid }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Format = require(Shared.Lib.Format)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local C = require(UI.Parent.Controllers)

return {
	Id = "Machine",
	Title = "Machine",
	Icon = "⚙️",
	Size = Vector2.new(940, 600),
	Watch = { "Inventory", "Coins" },
	Build = function(win, ctx)
		local uid = ctx.Args and ctx.Args.Uid
		local content = win.Content :: Frame
		local data: any = nil
		local offset = 0 -- server unix time − local unix time
		local alive = true
		local progressBars: { [number]: any } = {}
		local render: () -> ()

		local function serverNow(): number
			return os.time() + offset
		end

		local function apply(result: any)
			if type(result) ~= "table" then
				return
			end
			data = result
			offset = (result.Now or os.time()) - os.time()
			render()
		end

		local function fetch()
			local ok, result = Net.Request("MachineGet", uid)
			if not ok then
				C.Notify.Toast(tostring(result), "Warning")
				ctx.Close()
				return
			end
			apply(result)
		end

		local function act(action: string, ...: any)
			local ok, result = Net.Request(action, uid, ...)
			if ok then
				apply(result)
			elseif result then
				C.Notify.Toast(tostring(result), "Warning")
			end
			return ok
		end

		local header = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), Parent = content })
		local columns = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -110), Position = UDim2.fromOffset(0, 60), Parent = content })
		local footer = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -44), Parent = content })

		render = function()
			Kit.Clear(header)
			Kit.Clear(columns)
			Kit.Clear(footer)
			table.clear(progressBars)
			if not data then
				Kit.Empty("Checking the machine…").Parent = columns
				return
			end
			local machine = Registry.Machines[data.Machine]
			win.Title.Text = machine.Icon .. "  " .. machine.Name
			local stars = string.rep("★", data.Level) .. string.rep("☆", data.MaxLevel - data.Level)
			local title = Kit.Label(stars .. "   ·   speed ×" .. string.format("%.2f", data.Speed) .. "   ·   " .. #data.Queue .. " / " .. data.QueueSize .. " queued" .. (if data.Blocked then "   ·   ⚠️ output full" else ""), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Color = if data.Blocked then "Warn" else "Text" })
			title.Parent = header
			local desc = Kit.Label(machine.Description, { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
			desc.Position = UDim2.fromOffset(0, 22)
			desc.Parent = header

			-- Queue ------------------------------------------------------------------------------------------------
			local left = Kit.Panel({ Size = UDim2.new(0.34, -6, 1, 0), Color = "PanelAlt" })
			left.Parent = columns
			Kit.Padding(left, 8, 10)
			Kit.Heading("⏳ Queue", 16).Parent = left
			local queueList = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -28), Position = UDim2.fromOffset(0, 28) })
			queueList.Parent = left
			Kit.List(queueList, "Y", 6)
			for i = 1, data.QueueSize do
				local job = data.Queue[i]
				local card = Kit.Card(if job then 64 else 36)
				card.LayoutOrder = i
				card.Parent = queueList
				if job then
					local input = Registry.Items[job.I]
					local output = Registry.Items[job.O]
					local line = Kit.Label((if input then input.Icon else "?") .. " → " .. (if output then output.Icon .. " " .. output.Name else job.O) .. (if job.N > 1 then " ×" .. job.N else ""), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
					line.Size = UDim2.new(1, -34, 0, 20)
					line.Parent = card
					local bar = Kit.Progress({ Size = UDim2.new(1, -34, 0, 14), Color = "Accent" })
					bar.Frame.Position = UDim2.fromOffset(0, 26)
					bar.Frame.Parent = card
					progressBars[i] = bar
					local cancel = Kit.Button("✕", { Style = "Ghost", Size = UDim2.fromOffset(28, 28), TextSize = 13, OnClick = function()
						Kit.Confirm("Cancel this job?", "The ingredients go back to your bag.", function(yes)
							if yes then
								act("MachineCancel", i)
							end
						end, "Cancel job")
					end })
					cancel.Position = UDim2.new(1, -28, 0, 0)
					cancel.Parent = card
				else
					local empty = Kit.Label("Empty slot", { Size = Theme.Sizes.Tiny, Color = "SubText" })
					empty.Parent = card
				end
			end

			-- Options ---------------------------------------------------------------------------------------------
			local middle = Kit.Panel({ Size = UDim2.new(0.38, -6, 1, 0), Position = UDim2.new(0.34, 6, 0, 0), Color = "PanelAlt" })
			middle.Parent = columns
			Kit.Padding(middle, 8, 10)
			Kit.Heading("📥 Load from your bag", 16).Parent = middle
			local options = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -28), Position = UDim2.fromOffset(0, 28) })
			options.Parent = middle
			Kit.List(options, "Y", 6)
			local free = data.QueueSize - #data.Queue
			if #data.Options == 0 then
				local names = {}
				for _, recipe in machine.Recipes do
					local name = if recipe.In.Id then (Registry.Items[recipe.In.Id] and Registry.Items[recipe.In.Id].Name or recipe.In.Id) else ("any " .. tostring(recipe.In.Tag))
					if not table.find(names, name) then
						table.insert(names, name)
					end
					if #names >= 8 then
						break
					end
				end
				Kit.Empty("Nothing in your bag fits. The " .. machine.Name .. " takes: " .. table.concat(names, ", ") .. ".").Parent = options
			end
			for i, option in data.Options do
				local input = Registry.Items[option.Id]
				local output = Registry.Items[option.Out]
				local card = Kit.Card(74)
				card.LayoutOrder = i
				card.Parent = options
				local slot = Kit.ItemSlot(44)
				slot.Button.Active = false
				slot.Set({ Id = option.Id, N = option.Have, Q = option.Q, M = option.M })
				slot.Button.Parent = card
				local text = option.Need .. "× " .. (if input then input.Name else option.Id) .. "  →  " .. option.N .. "× " .. (if output then output.Name else option.Out)
				local line = Kit.Label(text, { Size = Theme.Sizes.Tiny, Font = Theme.Fonts.Bold, Wrap = true })
				line.Position = UDim2.fromOffset(52, 0)
				line.Size = UDim2.new(1, -130, 0, 0)
				line.Parent = card
				local extras = {}
				for _, extra in option.Extra or {} do
					local e = Registry.Items[extra.Id]
					table.insert(extras, (if e then e.Icon else "") .. extra.N)
				end
				local sub = Kit.Label("⏱️ " .. Format.Duration(option.Time) .. (if #extras > 0 then "  ·  + " .. table.concat(extras, " ") else "") .. (if output then "  ·  " .. Kit.Money(ItemUtil.UnitValue({ Id = option.Out, N = 1, Q = option.Q, M = option.M })) else ""), { Size = Theme.Sizes.Tiny, Color = "SubText" })
				sub.Position = UDim2.fromOffset(52, 34)
				sub.Size = UDim2.new(1, -130, 0, 16)
				sub.Parent = card
				local maxTimes = math.min(free, math.floor(option.Have / math.max(option.Need, 1)))
				local add = Kit.Button("Add", { Style = "Primary", Size = UDim2.fromOffset(70, 32), TextSize = Theme.Sizes.Small, OnClick = function()
					if maxTimes < 1 then
						C.Notify.Toast(if free < 1 then "The queue is full" else "You need " .. option.Need .. " for one batch", "Info")
						return
					end
					if maxTimes == 1 then
						if act("MachineQueue", option.Ref, 1) then
							C.Audio.PlayUI("MachineStart")
						end
					else
						Kit.AskNumber("How many batches?", maxTimes, maxTimes, function(n)
							if n and act("MachineQueue", option.Ref, n) then
								C.Audio.PlayUI("MachineStart")
							end
						end)
					end
				end })
				add.Position = UDim2.new(1, -72, 0, 18)
				add.Parent = card
				Kit.SetEnabled(add, maxTimes >= 1)
				if output then
					Kit.AttachTooltip(card, function()
						return Kit.ItemTooltip({ Id = option.Out, N = option.N, Q = option.Q, M = option.M })
					end)
				end
			end

			-- Output -----------------------------------------------------------------------------------------------
			local right = Kit.Panel({ Size = UDim2.new(0.28, -6, 1, 0), Position = UDim2.new(0.72, 6, 0, 0), Color = "PanelAlt" })
			right.Parent = columns
			Kit.Padding(right, 8, 10)
			local outCount = 0
			for _, stack in data.Output do
				outCount += stack.N
			end
			Kit.Heading("📦 Ready (" .. outCount .. " / " .. data.OutputSize .. ")", 16).Parent = right
			local grid = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -76), Position = UDim2.fromOffset(0, 28), Parent = right })
			Kit.Grid(grid, 52, 6)
			for i, stack in data.Output do
				local slot = Kit.ItemSlot(52)
				slot.Button.LayoutOrder = i
				slot.Set(stack)
				slot.Button.Parent = grid
			end
			local collect = Kit.Button("Collect all", { Style = "Good", Size = UDim2.new(1, 0, 0, 40), OnClick = function()
				if act("MachineCollect") then
					C.Audio.PlayUI("ItemPickup")
				end
			end })
			collect.Position = UDim2.new(0, 0, 1, -42)
			collect.Parent = right
			Kit.SetEnabled(collect, #data.Output > 0)

			-- Footer: upgrade & auto -------------------------------------------------------------------------------------
			Kit.List(footer, "X", 10)
			local isOwner = data.Owner == game:GetService("Players").LocalPlayer.UserId
			if data.UpgradeCost and isOwner then
				local mats = {}
				for _, mat in data.UpgradeMats or {} do
					local m = Registry.Items[mat.Id]
					table.insert(mats, mat.N .. " " .. (if m then m.Icon else mat.Id))
				end
				local up = Kit.Button("⬆️ Upgrade to ★" .. (data.Level + 1) .. " · " .. Kit.Money(data.UpgradeCost) .. (if #mats > 0 then " + " .. table.concat(mats, ", ") else ""), { Style = "Accent", Size = UDim2.fromOffset(0, 40), TextSize = Theme.Sizes.Small, OnClick = function()
					Kit.Confirm("Upgrade the " .. machine.Name .. "?", "Faster jobs, more queue slots and more output storage.", function(yes)
						if yes and act("MachineUpgrade") then
							C.Audio.PlayUI("LevelUp")
						end
					end, "Upgrade")
				end })
				up.AutomaticSize = Enum.AutomaticSize.X
				Kit.Padding(up, 0, 14)
				up.Parent = footer
			elseif isOwner then
				local maxed = Kit.Label("★ Fully upgraded", { Size = Theme.Sizes.Small, Color = "Accent" })
				maxed.Size = UDim2.fromOffset(160, 40)
				maxed.Parent = footer
			end
			if data.Logistics and isOwner then
				local autoWrap = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(190, 40), LayoutOrder = 2, Parent = footer })
				local label = Kit.Label("🤖 Auto (silo)", { Size = Theme.Sizes.Small })
				label.Size = UDim2.fromOffset(120, 40)
				label.Parent = autoWrap
				local toggle = Kit.Toggle(data.Auto, function(on)
					act("MachineConfig", { Auto = on })
				end)
				toggle.Position = UDim2.fromOffset(124, 6)
				toggle.Parent = autoWrap
				local specs = { "(any)" }
				for _, recipe in machine.Recipes do
					local spec = if recipe.In.Id then recipe.In.Id else "#" .. tostring(recipe.In.Tag)
					if not table.find(specs, spec) then
						table.insert(specs, spec)
					end
				end
				local names = {}
				local byName = {}
				for _, spec in specs do
					local name = if spec == "(any)" then "Any input" else Registry.SpecName(spec)
					table.insert(names, name)
					byName[name] = spec
				end
				local currentName = if data.Input then Registry.SpecName(data.Input) else "Any input"
				local choice = Kit.Choice(names, currentName, function(name)
					local spec = byName[name]
					act("MachineConfig", { Input = if spec == "(any)" then false else spec })
				end)
				choice.LayoutOrder = 3
				choice.Parent = footer
			elseif isOwner then
				local hint = Kit.Label("Build a Logistics Hub to let machines pull from and push to your silo automatically.", { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
				hint.Size = UDim2.fromOffset(360, 40)
				hint.LayoutOrder = 2
				hint.Parent = footer
			end
			Kit.RepaintGradients(content)
		end

		-- Live progress
		task.spawn(function()
			local refetchAt = 0
			while alive do
				if data and data.Start and #data.Queue > 0 then
					local t = serverNow()
					local jobStart = data.Start
					for i, job in data.Queue do
						local bar = progressBars[i]
						local elapsed = t - jobStart
						local fraction = math.clamp(elapsed / math.max(job.D, 1), 0, 1)
						if bar then
							if i == 1 or elapsed > 0 then
								bar.Set(fraction, if fraction >= 1 then (if data.Blocked then "waiting for space" else "done!") else Format.Duration(math.max(0, job.D - elapsed)), false)
							else
								bar.Set(0, "starts in " .. Format.Duration(-elapsed), false)
							end
						end
						if i == 1 and fraction >= 1 and os.clock() > refetchAt and not data.Blocked then
							refetchAt = os.clock() + 3
							task.spawn(fetch)
						end
						jobStart += job.D
					end
				end
				task.wait(0.5)
			end
		end)

		render()
		task.spawn(fetch)
		C.Tutorial.Hint("Machine")
		return {
			Refresh = function()
				task.spawn(fetch)
			end,
			Destroy = function()
				alive = false
			end,
		}
	end,
}
