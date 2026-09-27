-- Networking layer.
--
-- Clients never get their own RemoteEvent per feature. Instead there are two
-- client → server channels:
--
--   Request  (RemoteFunction)  Net.Request("ShopBuy", shopId, itemId, qty) → ok, result
--   Signal   (RemoteEvent)     Net.Send("ToolUse", toolId, position, opts)   fire-and-forget
--
-- and a handful of server → client event channels (Sync, Notify, FX, ...).
--
-- Every client action is declared in ACTIONS below with a rate limit and an
-- argument schema. The server router rejects unknown actions, wrong argument
-- types, NaN/inf numbers, oversize strings or tables, and anything over the
-- rate limit *before* a service handler ever sees it, and reports each
-- rejection to SecurityService. Handlers still validate game rules (ownership,
-- distance, permissions, costs) themselves.
--
-- Schema types: "string" (≤120 chars), "string:N" (≤N chars), "number", "int",
-- "bool", "Vector3", "table" (≤64 entries, depth ≤3), "any". Suffix "?" = optional.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type ActionDef = {
	Channel: "Request" | "Signal",
	Rate: number, -- tokens refilled per second
	Burst: number, -- bucket size
	Args: { string },
}

local function req(rate: number, burst: number, args: { string }): ActionDef
	return { Channel = "Request", Rate = rate, Burst = burst, Args = args }
end

local function sig(rate: number, burst: number, args: { string }): ActionDef
	return { Channel = "Signal", Rate = rate, Burst = burst, Args = args }
end

local ACTIONS: { [string]: ActionDef } = {
	-- Core loop -------------------------------------------------------------
	ToolUse = sig(14, 24, { "string:40", "Vector3", "table?" }), -- (itemOrToolId, target, {Size=n, Dir=Vector3})
	Hotbar = sig(20, 30, { "int" }), -- equip hotbar slot (0 = empty hand)
	MenuState = sig(4, 8, { "bool" }), -- a blocking menu is open (lets solo private servers slow time)
	SaveSettings = sig(1, 3, { "table" }),
	Pose = sig(2, 4, { "string:24?" }),

	-- Inventory / storage -------------------------------------------------------
	InvMove = req(12, 20, { "string:48", "string:48", "int?" }),
	InvSort = req(2, 4, { "string:48" }),
	InvLock = req(6, 10, { "string:48" }),
	InvTrash = req(4, 8, { "string:48", "int?" }),
	InvUse = req(4, 8, { "string:48" }),
	InvQuick = req(10, 20, { "string:48", "string:48" }),
	InvStackAll = req(2, 4, { "string:48", "string:48" }),

	-- Shops, selling and the market ---------------------------------------------
	ShopGet = req(4, 8, { "string:40" }),
	ShopBuy = req(6, 10, { "string:40", "string:48", "int" }),
	Sell = req(8, 16, { "string:48", "int", "string:48" }),
	SellMany = req(2, 4, { "table", "string:48" }),
	MarketGet = req(1, 3, {}),
	MarketTrack = req(3, 6, { "string:48", "bool" }),
	ContractList = req(1, 3, {}),
	ContractAccept = req(2, 4, { "string:40" }),
	ContractDeliver = req(3, 6, { "string:40" }),
	ExportShip = req(1, 3, { "table" }),
	StallSet = req(3, 6, { "int", "string:48", "int", "int" }), -- (stallSlot, slotRef, count, pricePerItem)
	StallClear = req(3, 6, { "int" }),
	StallGet = req(2, 4, { "int" }),
	StallBuy = req(3, 6, { "int", "int", "int" }), -- (ownerUserId, stallSlot, qty)

	-- Crafting and machines -----------------------------------------------------------
	Craft = req(5, 10, { "string:48", "int" }),
	Experiment = req(1, 3, { "table" }),
	MachineGet = req(4, 8, { "string:40" }),
	MachineQueue = req(6, 12, { "string:40", "string:48", "int" }), -- (uid, inputItemId or recipe key, times)
	MachineCollect = req(6, 12, { "string:40" }),
	MachineCancel = req(3, 6, { "string:40", "int" }),
	MachineUpgrade = req(2, 4, { "string:40" }),
	MachineConfig = req(3, 6, { "string:40", "table" }),
	AutomationRules = req(2, 4, { "table" }),

	-- Building & land ----------------------------------------------------------------
	BuildPlace = req(8, 16, { "string:48", "table" }),
	BuildMove = req(8, 16, { "string:40", "table" }),
	BuildRemove = req(8, 16, { "string:40" }),
	BuildStyle = req(8, 16, { "string:40", "table" }),
	LayoutSave = req(1, 2, { "int", "string:40" }),
	LayoutLoad = req(1, 2, { "int" }),
	LayoutList = req(1, 3, {}),
	LandBuy = req(1, 3, { "string:16" }),
	HouseUpgrade = req(1, 2, {}),
	FarmRename = req(1, 2, { "string:40" }),

	-- Animals ---------------------------------------------------------------------------
	AnimalBuy = req(2, 4, { "string:40", "string:40" }),
	AnimalAct = req(8, 16, { "string:40", "string:16" }),
	AnimalName = req(1, 3, { "string:40", "string:24" }),
	AnimalBreed = req(1, 3, { "string:40", "string:40" }),
	AnimalSell = req(1, 3, { "string:40" }),
	AnimalMove = req(2, 4, { "string:40", "string:40" }),
	SeedBreed = req(2, 4, { "string:48", "string:48" }),

	-- NPCs and quests -------------------------------------------------------------------
	NpcTalk = req(3, 6, { "string:32" }),
	NpcGift = req(2, 4, { "string:32", "string:48" }),
	NpcChoice = req(4, 8, { "string:32", "int" }),
	QuestAccept = req(3, 6, { "string:48" }),
	QuestAbandon = req(2, 4, { "string:48" }),
	QuestTurnIn = req(3, 6, { "string:48" }),
	QuestTrack = req(4, 8, { "string:48" }),
	BoardGet = req(1, 3, {}),
	TownContribute = req(2, 4, { "string:40", "string:48", "int" }),

	-- Progression --------------------------------------------------------------------------
	SkillUnlock = req(3, 6, { "string:24", "string:40" }),
	SkillRespec = req(1, 2, { "string:24" }),
	ToolUpgrade = req(1, 3, { "string:24" }),
	CollectionClaim = req(3, 6, { "string:24", "int" }),
	MuseumDonate = req(3, 6, { "string:48" }),
	ShowcaseSet = req(3, 6, { "int", "string:48?" }),
	AchievementsGet = req(1, 3, {}),

	-- Gathering ----------------------------------------------------------------------------
	NodeHit = req(6, 10, { "string:40" }),
	ForageCollect = req(6, 10, { "string:40" }),
	BugCatch = req(4, 8, { "string:40" }),
	DigSpot = req(4, 8, { "string:40" }),
	FishCast = req(1, 3, { "Vector3", "string:48?" }),
	FishResolve = req(1, 3, { "string:40", "table" }),
	Travel = req(1, 2, { "string:40" }),
	SecretTrigger = req(2, 4, { "string:40" }),

	-- Festivals ----------------------------------------------------------------------------
	FestivalGet = req(1, 3, {}),
	FestivalAction = req(6, 12, { "string:24", "any?" }),

	-- Multiplayer ----------------------------------------------------------------------------
	PermSet = req(2, 4, { "string:24", "string:24" }), -- (userId or "Default", level)
	PermGet = req(1, 3, {}),
	VisitFarm = req(1, 2, { "int" }),
	GoHome = req(1, 2, {}),
	TradeRequest = req(1, 3, { "int" }),
	TradeRespond = req(2, 4, { "int", "bool" }),
	TradeOffer = req(6, 12, { "string:48", "int" }),
	TradeRemove = req(6, 12, { "int" }),
	TradeCoins = req(3, 6, { "int" }),
	TradeConfirm = req(2, 4, {}),
	TradeCancel = req(2, 4, {}),
	GuildCreate = req(1, 2, { "string:24" }),
	GuildJoin = req(1, 2, { "string:40" }),
	GuildLeave = req(1, 2, {}),
	GuildInfo = req(1, 3, {}),
	GuildContribute = req(2, 4, { "string:48", "int" }),
	GuildSearch = req(1, 2, { "string:24?" }),

	-- Mail, daily, profile, store -------------------------------------------------------------
	MailClaim = req(4, 8, { "string:40" }),
	MailClaimAll = req(1, 2, {}),
	MailDelete = req(4, 8, { "string:40" }),
	MailRead = req(6, 12, { "string:40" }),
	DailyClaim = req(1, 2, {}),
	ProfileGet = req(2, 4, { "int" }),
	ProfileSet = req(2, 4, { "string:24", "any?" }),
	StoreGet = req(1, 2, {}),
	CosmeticEquip = req(3, 6, { "string:24", "string:40?" }),
	TutorialSkip = req(1, 2, {}),
	TutorialAck = req(2, 4, { "string:32" }),

	-- Developer tools (AdminDebugService checks the caller is an admin) ----------------------
	Admin = req(5, 10, { "string:32", "table?" }),
}

-- Server → client channels.
local CHANNELS = {
	"Sync", -- (patches) player data replication
	"Notify", -- (kind, payload) toasts, banners, level ups, discoveries
	"FX", -- (kind, payload) world feedback: harvest popups, mutation reveals, lightning
	"Dialogue", -- (npcId, payload)
	"Trade", -- (state)
	"Festival", -- (kind, payload)
	"Fishing", -- (kind, payload)
	"AdminLog", -- (text)
}

local Net = {}
Net.Actions = ACTIONS

local MAX_STRING = 120
local MAX_TABLE_ENTRIES = 64
local MAX_TABLE_DEPTH = 3

local folder: Folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Net"
	local request = Instance.new("RemoteFunction")
	request.Name = "Request"
	request.Parent = folder
	local signal = Instance.new("RemoteEvent")
	signal.Name = "Signal"
	signal.Parent = folder
	for _, name in CHANNELS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Net") :: Folder
end

local function remote(name: string): any
	return folder:WaitForChild(name)
end

-- Validation -----------------------------------------------------------------------------

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function checkTable(value: any, depth: number): (boolean, string?)
	if depth > MAX_TABLE_DEPTH then
		return false, "table too deep"
	end
	local count = 0
	for key, item in value do
		count += 1
		if count > MAX_TABLE_ENTRIES then
			return false, "table too large"
		end
		local keyType = type(key)
		if keyType == "string" then
			if #key > MAX_STRING then
				return false, "key too long"
			end
		elseif keyType == "number" then
			if not isFinite(key) then
				return false, "bad key"
			end
		else
			return false, "bad key type"
		end
		local itemType = typeof(item)
		if itemType == "number" then
			if not isFinite(item) then
				return false, "bad number"
			end
		elseif itemType == "string" then
			if #item > 400 then
				return false, "string too long"
			end
		elseif itemType == "table" then
			local ok, err = checkTable(item, depth + 1)
			if not ok then
				return false, err
			end
		elseif itemType == "Vector3" then
			if not (isFinite(item.X) and isFinite(item.Y) and isFinite(item.Z)) then
				return false, "bad vector"
			end
		elseif itemType ~= "boolean" then
			return false, "bad value type " .. itemType
		end
	end
	return true
end

local function checkArg(spec: string, value: any): (boolean, string?)
	local optional = string.sub(spec, -1) == "?"
	if optional then
		spec = string.sub(spec, 1, -2)
		if value == nil then
			return true
		end
	end
	local base, limit = string.match(spec, "^(%a+):(%d+)$")
	base = base or spec
	local kind = typeof(value)
	if base == "any" then
		if kind == "table" then
			return checkTable(value, 1)
		elseif kind == "number" then
			return isFinite(value), "bad number"
		elseif kind == "string" then
			return #value <= MAX_STRING, "string too long"
		end
		return kind == "boolean" or kind == "nil" or kind == "Vector3", "bad any"
	elseif base == "string" then
		if kind ~= "string" then
			return false, "expected string"
		end
		if #value > (tonumber(limit) or MAX_STRING) then
			return false, "string too long"
		end
		return true
	elseif base == "number" then
		return kind == "number" and isFinite(value), "expected number"
	elseif base == "int" then
		return kind == "number" and isFinite(value) and value == math.floor(value) and math.abs(value) < 2 ^ 52,
			"expected int"
	elseif base == "bool" then
		return kind == "boolean", "expected bool"
	elseif base == "Vector3" then
		return kind == "Vector3" and isFinite(value.X) and isFinite(value.Y) and isFinite(value.Z), "expected Vector3"
	elseif base == "table" then
		if kind ~= "table" then
			return false, "expected table"
		end
		return checkTable(value, 1)
	end
	return false, "unknown schema " .. spec
end

function Net.Validate(action: string, ...: any): (boolean, string?)
	local def = ACTIONS[action]
	if not def then
		return false, "unknown action"
	end
	local count = select("#", ...)
	if count > #def.Args then
		return false, "too many arguments"
	end
	for i, spec in def.Args do
		local ok, err = checkArg(spec, (select(i, ...)))
		if not ok then
			return false, string.format("arg %d: %s", i, err or "invalid")
		end
	end
	return true
end

-- Server ------------------------------------------------------------------------------------

if RunService:IsServer() then
	local handlers: { [string]: (Player, ...any) -> ...any } = {}
	local buckets: { [Player]: { [string]: { Tokens: number, At: number } } } = {}
	local violationHandlers: { (Player, string, string) -> () } = {}

	local function violation(player: Player, action: string, reason: string)
		for _, fn in violationHandlers do
			task.spawn(fn, player, action, reason)
		end
	end

	local function allow(player: Player, action: string, def: ActionDef): boolean
		local perPlayer = buckets[player]
		if not perPlayer then
			perPlayer = {}
			buckets[player] = perPlayer
		end
		local now = os.clock()
		local bucket = perPlayer[action]
		if not bucket then
			bucket = { Tokens = def.Burst, At = now }
			perPlayer[action] = bucket
		end
		bucket.Tokens = math.min(def.Burst, bucket.Tokens + (now - bucket.At) * def.Rate)
		bucket.At = now
		if bucket.Tokens < 1 then
			return false
		end
		bucket.Tokens -= 1
		return true
	end

	local function route(player: Player, channel: string, action: any, ...: any): (boolean, any)
		if type(action) ~= "string" then
			violation(player, "?", "non-string action")
			return false, "Bad request"
		end
		local def = ACTIONS[action]
		if not def or def.Channel ~= channel then
			violation(player, tostring(action):sub(1, 40), "unknown action")
			return false, "Bad request"
		end
		if not allow(player, action, def) then
			violation(player, action, "rate limit")
			return false, "Slow down!"
		end
		local ok, err = Net.Validate(action, ...)
		if not ok then
			violation(player, action, err or "invalid args")
			return false, "Bad request"
		end
		local handler = handlers[action]
		if not handler then
			return false, "Not available"
		end
		local results = table.pack(pcall(handler, player, ...))
		if not results[1] then
			warn(string.format("[Net] %s failed for %s: %s", action, player.Name, tostring(results[2])))
			return false, "Something went wrong. Please try again."
		end
		return results[2], results[3]
	end

	remote("Request").OnServerInvoke = function(player: Player, action: any, ...: any)
		return route(player, "Request", action, ...)
	end
	remote("Signal").OnServerEvent:Connect(function(player: Player, action: any, ...: any)
		route(player, "Signal", action, ...)
	end)

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)

	-- Register the handler for a client action. Request handlers return (ok, result).
	function Net.Handle(action: string, handler: (Player, ...any) -> ...any)
		assert(ACTIONS[action], "Net.Handle: undeclared action " .. action)
		assert(not handlers[action], "Net.Handle: duplicate handler for " .. action)
		handlers[action] = handler
	end

	function Net.OnViolation(fn: (Player, string, string) -> ())
		table.insert(violationHandlers, fn)
	end

	function Net.Fire(player: Player, channel: string, ...: any)
		remote(channel):FireClient(player, ...)
	end

	function Net.FireAll(channel: string, ...: any)
		remote(channel):FireAllClients(...)
	end

	function Net.FireOthers(except: Player?, channel: string, ...: any)
		local r = remote(channel)
		for _, player in Players:GetPlayers() do
			if player ~= except then
				r:FireClient(player, ...)
			end
		end
	end

	-- Fire to every player whose character is within `radius` of `position`.
	function Net.FireNearby(position: Vector3, radius: number, channel: string, ...: any)
		local r = remote(channel)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - position).Magnitude <= radius then
				r:FireClient(player, ...)
			end
		end
	end
else
	-- Client ---------------------------------------------------------------------------------

	-- Request(action, ...) → ok, result. Never errors; failures come back as (false, message).
	function Net.Request(action: string, ...: any): (boolean, any)
		local ok, a, b = pcall(function(...)
			return remote("Request"):InvokeServer(action, ...)
		end, ...)
		if not ok then
			return false, "Connection problem"
		end
		return a == true, b
	end

	function Net.Send(action: string, ...: any)
		remote("Signal"):FireServer(action, ...)
	end

	function Net.On(channel: string, fn: (...any) -> ()): RBXScriptConnection
		return remote(channel).OnClientEvent:Connect(fn)
	end
end

return Net
