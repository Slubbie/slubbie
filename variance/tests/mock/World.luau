--# selene: allow(global_usage, unused_variable, shadowing)
-- A Roblox place for the runtime mock: the DataModel and services, players and
-- R6 characters, remotes that route between the server and client contexts
-- (with Roblox's argument-serialization rules checked), in-memory DataStores
-- and MemoryStores, and the Rojo tree loaded from the source folders.
--
--   local world = World.new()
--   world:start()                        -- runs VarianceServer
--   local p = world:addPlayer(1001, "Ada") -- joins, runs VarianceClient for it
--   Scheduler.run(30)
--
-- The server and every client share one instance tree (the mock doesn't
-- replicate), but each has its own module cache, globals, camera and
-- LocalPlayer, and runs on threads tagged with its context.

local Types = require(script.Parent.Types)
local Scheduler = require(script.Parent.Scheduler)
local Instances = require(script.Parent.Instances)
local Dump = require(script.Parent.ApiDump)

local World = {}
World.__index = World

local new = Instances.new
local D = Instances.data
local special = Instances.special
local Enum = Types.makeEnum(Dump)
Instances.Enum = Enum

local EPOCH = 1790000000 -- virtual os.time() at t = 0 (inside Season One)

World.warnings = {}
World.serializationIssues = {}
World.prints = {}

---------------------------------------------------------------------------
-- Remote argument rules (what Roblox's serializer does to tables)
---------------------------------------------------------------------------

local function copyArg(value, path: string, depth: number)
	local t = type(value)
	if t == "function" or t == "thread" then
		table.insert(World.serializationIssues, path .. ": " .. t .. " can't cross a remote (becomes nil)")
		return nil
	end
	if t ~= "table" then
		return value
	end
	if Instances.isInstance(value) then
		return value
	end
	local tn = Types.typeof(value)
	if tn ~= "table" then
		return value -- immutable datatype
	end
	if depth > 30 then
		table.insert(World.serializationIssues, path .. ": nested too deeply")
		return nil
	end
	local stringKeys, numberKeys, otherKeys, maxN = 0, 0, 0, 0
	for k in value do
		local kt = type(k)
		if kt == "string" then
			stringKeys += 1
		elseif kt == "number" then
			numberKeys += 1
			maxN = math.max(maxN, k)
		else
			otherKeys += 1
		end
	end
	if stringKeys > 0 and numberKeys > 0 then
		table.insert(
			World.serializationIssues,
			path .. ": mixed string and number keys (number keys are dropped by Roblox)"
		)
	end
	if otherKeys > 0 then
		table.insert(World.serializationIssues, path .. ": non-string/number keys")
	end
	if numberKeys > 0 and stringKeys == 0 and maxN ~= numberKeys then
		table.insert(
			World.serializationIssues,
			path .. ": sparse/non-sequential array (" .. numberKeys .. " keys, max " .. maxN .. ")"
		)
	end
	local out = {}
	for k, v in value do
		out[k] = copyArg(v, path .. "." .. tostring(k), depth + 1)
	end
	return out
end

local function copyArgs(label: string, ...)
	local n = select("#", ...)
	local args = { ... }
	local out = {}
	for i = 1, n do
		out[i] = copyArg(args[i], label .. "[" .. i .. "]", 0)
	end
	return out, n
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function context(name: string, isServer: boolean, player)
	return {
		Name = name,
		IsServer = isServer,
		Player = player,
		Modules = {},
		Globals = nil,
		Camera = nil,
		RenderSteps = {},
	}
end

function World.new(options)
	local self = setmetatable({}, World)
	self.Options = options or {}
	self.Server = context("Server", true, nil)
	self.Clients = {}
	self.Players = {}
	self.DataStores = {}
	self.OrderedStores = {}
	self.MemoryMaps = {}
	self.Teleports = {}
	self.Purchases = {}
	self.CloseCallbacks = {}
	self.FailNextStoreCalls = 0
	Scheduler.setDefaultContext(self.Server)

	local game = new("DataModel")
	D[game].Name = "Game"
	self.Game = game
	local services = {}
	self.Services = services
	local function service(className: string, name: string?)
		local s = new(className)
		D[s].Name = name or className
		s.Parent = game
		services[className] = s
		return s
	end
	local workspace = service("Workspace", "Workspace")
	self.Workspace = workspace
	local terrain = new("Terrain")
	D[terrain].Name = "Terrain"
	terrain.Parent = workspace
	for _, className in
		{
			"Players",
			"ReplicatedStorage",
			"ServerScriptService",
			"ServerStorage",
			"StarterPlayer",
			"StarterGui",
			"StarterPack",
			"Lighting",
			"SoundService",
			"RunService",
			"TweenService",
			"UserInputService",
			"GuiService",
			"ContentProvider",
			"HttpService",
			"DataStoreService",
			"MemoryStoreService",
			"TeleportService",
			"MarketplaceService",
			"SocialService",
			"TextChatService",
			"HapticService",
			"ProximityPromptService",
			"CollectionService",
			"MessagingService",
			"BadgeService",
			"LocalizationService",
			"Chat",
		}
	do
		service(className)
	end
	local starterScripts = new("StarterPlayerScripts")
	starterScripts.Parent = services.StarterPlayer
	local channels = new("Folder")
	channels.Name = "TextChannels"
	channels.Parent = services.TextChatService
	local general = new("TextChannel")
	general.Name = "RBXGeneral"
	general.Parent = channels
	D[services.UserInputService].Props.KeyboardEnabled = true
	D[services.UserInputService].Props.MouseEnabled = true
	D[services.ProximityPromptService].Props.Enabled = true
	D[services.Players].Props.CharacterAutoLoads = true
	self:installBehaviour()
	self:loadTree()
	return self
end

---------------------------------------------------------------------------
-- Service behaviour
---------------------------------------------------------------------------

function World:installBehaviour()
	local world = self
	local services = self.Services

	special.DataModel = {
		get = {
			JobId = function()
				return "mock-job-0001"
			end,
			PlaceId = function()
				return 1818
			end,
			GameId = function()
				return 1919
			end,
			PrivateServerId = function()
				return ""
			end,
			PrivateServerOwnerId = function()
				return 0
			end,
			Workspace = function()
				return world.Workspace
			end,
		},
		methods = {
			GetService = function(_, name)
				local s = services[name]
				if s == nil then
					error("'" .. tostring(name) .. "' is not a valid Service name", 2)
				end
				return s
			end,
			FindService = function(_, name)
				return services[name]
			end,
			BindToClose = function(_, fn)
				table.insert(world.CloseCallbacks, fn)
			end,
			IsLoaded = function()
				return true
			end,
		},
	}

	special.Workspace = {
		get = {
			CurrentCamera = function()
				local ctx = Scheduler.context()
				if ctx.Camera == nil then
					local cam = new("Camera")
					D[cam].Name = "Camera"
					ctx.Camera = cam
					D[cam].Props.CFrame = Types.CFrame.new(0, 10, 20)
				end
				return ctx.Camera
			end,
			Terrain = function()
				return world.Workspace:FindFirstChild("Terrain")
			end,
			DistributedGameTime = function()
				return Scheduler.now
			end,
		},
		set = {
			CurrentCamera = function(_, _d, cam)
				Scheduler.context().Camera = cam
			end,
		},
		methods = {
			GetServerTimeNow = function()
				return EPOCH + Scheduler.now
			end,
			Raycast = function()
				return nil
			end,
			GetPartBoundsInBox = function()
				return {}
			end,
			GetPartBoundsInRadius = function()
				return {}
			end,
		},
	}

	special.RunService = {
		methods = {
			IsServer = function()
				return Scheduler.context().IsServer
			end,
			IsClient = function()
				return not Scheduler.context().IsServer
			end,
			IsStudio = function()
				return world.Options.Studio ~= false
			end,
			IsRunning = function()
				return true
			end,
			IsRunMode = function()
				return true
			end,
			BindToRenderStep = function(_, name, priority, fn)
				local ctx = Scheduler.context()
				ctx.RenderSteps[name] = { Priority = priority, Fn = fn }
			end,
			UnbindFromRenderStep = function(_, name)
				Scheduler.context().RenderSteps[name] = nil
			end,
		},
	}

	special.Players = {
		get = {
			LocalPlayer = function()
				return Scheduler.context().Player
			end,
		},
		methods = {
			GetPlayers = function()
				local out = {}
				for _, p in world.Players do
					if p.Parent then
						table.insert(out, p)
					end
				end
				return out
			end,
			GetPlayerByUserId = function(_, id)
				for _, p in world.Players do
					if p.Parent and p.UserId == id then
						return p
					end
				end
				return nil
			end,
			GetPlayerFromCharacter = function(_, character)
				for _, p in world.Players do
					if p.Character == character then
						return p
					end
				end
				return nil
			end,
			GetHumanoidDescriptionFromUserId = function()
				return new("HumanoidDescription")
			end,
			CreateHumanoidModelFromDescription = function(_, _desc, rigType)
				return world:buildR6()
			end,
			GetNameFromUserIdAsync = function(_, id)
				return "User" .. tostring(id)
			end,
			GetUserIdFromNameAsync = function()
				return 1
			end,
		},
	}

	special.Player = {
		methods = {
			Kick = function(self, message)
				world:removePlayer(self, message)
			end,
			IsFriendsWith = function()
				return world.Options.Friends == true
			end,
			GetJoinData = function(self)
				return D[self].Hidden.JoinData or {}
			end,
			RequestStreamAroundAsync = function() end,
			LoadCharacter = function(self)
				local character = world:buildR6()
				character.Name = self.Name
				character:PivotTo(Types.CFrame.new(0, 5, 40))
				self.Character = character
				character.Parent = world.Workspace
			end,
			GetRankInGroup = function()
				return 0
			end,
			GetNetworkPing = function()
				return 0.05
			end,
			IsInGroup = function()
				return false
			end,
		},
		set = {
			Character = function(self, d, character)
				local old = d.Props.Character
				if old and old ~= character then
					Instances.fire(self, "CharacterRemoving", old)
				end
				d.Props.Character = character
				if character then
					Instances.fire(self, "CharacterAdded", character)
				end
			end,
		},
		get = {
			Character = function(_, d)
				return d.Props.Character
			end,
		},
	}

	special.TweenService = {
		methods = {
			Create = function(_, instance, info, goals)
				if not Instances.isInstance(instance) then
					error("TweenService:Create expects an Instance", 2)
				end
				if Types.typeof(info) ~= "TweenInfo" then
					error("TweenService:Create expects a TweenInfo", 2)
				end
				-- Validate goal properties now (as the engine does).
				for k, v in goals do
					local _ = instance[k]
					local vt = Types.typeof(v)
					local cur = Types.typeof(instance[k])
					if cur ~= "nil" and cur ~= vt and not (cur == "number" and vt == "number") then
						error(string.format("TweenService:Create property %s: %s expected, got %s", k, cur, vt), 2)
					end
				end
				local tween = new("Tween")
				D[tween].Hidden.Target = instance
				D[tween].Hidden.Goals = goals
				D[tween].Hidden.Duration = info.Time + info.DelayTime
				return tween
			end,
			GetValue = function(_, alpha)
				return alpha
			end,
		},
	}

	special.UserInputService = {
		methods = {
			GetLastInputType = function()
				return Enum.UserInputType.MouseMovement
			end,
			GetMouseLocation = function()
				return Types.Vector2.new(640, 360)
			end,
			IsKeyDown = function()
				return false
			end,
			GetConnectedGamepads = function()
				return {}
			end,
			GetNavigationGamepads = function()
				return {}
			end,
			GetStringForKeyCode = function(_, key)
				return key.Name
			end,
			GetFocusedTextBox = function()
				return nil
			end,
			GetKeysPressed = function()
				return {}
			end,
		},
	}

	special.GuiService = {
		methods = {
			GetGuiInset = function()
				return Types.Vector2.new(0, 36), Types.Vector2.zero
			end,
		},
	}

	special.StarterGui = {
		methods = {
			SetCoreGuiEnabled = function() end,
			GetCoreGuiEnabled = function()
				return true
			end,
			SetCore = function() end,
			GetCore = function()
				return nil
			end,
		},
	}

	special.ContentProvider = {
		methods = {
			PreloadAsync = function(_, list, callback)
				for _, item in list do
					if callback then
						local id = if Instances.isInstance(item) and item:IsA("Sound")
							then item.SoundId
							else tostring(item)
						callback(id, Enum.AssetFetchStatus.Success)
					end
				end
			end,
		},
	}

	special.HttpService = {
		methods = {
			GenerateGUID = function(_, wrap)
				local s = string.format(
					"%08x-%04x-%04x-%04x-%012x",
					math.random(0, 0x7fffffff),
					math.random(0, 0xffff),
					math.random(0, 0xffff),
					math.random(0, 0xffff),
					math.random(0, 0x7fffffff)
				)
				return if wrap == false then s else "{" .. s .. "}"
			end,
			JSONEncode = function(_, v)
				return World.json(v)
			end,
		},
	}

	special.HapticService = {
		methods = {
			SetMotor = function() end,
			IsVibrationSupported = function()
				return false
			end,
			IsMotorSupported = function()
				return false
			end,
		},
	}

	special.SocialService = {
		methods = {
			CanSendGameInviteAsync = function()
				return true
			end,
			PromptGameInvite = function(_, player, options)
				world.Invites = (world.Invites or 0) + 1
			end,
		},
	}

	special.MarketplaceService = {
		methods = {
			UserOwnsGamePassAsync = function()
				return false
			end,
			PromptProductPurchase = function(_, player, id)
				table.insert(world.Purchases, { Player = player, Product = id })
			end,
			PromptGamePassPurchase = function(_, player, id)
				table.insert(world.Purchases, { Player = player, Pass = id })
			end,
			GetProductInfo = function()
				return { Name = "Mock", PriceInRobux = 0 }
			end,
		},
	}

	special.TeleportService = {
		methods = {
			TeleportAsync = function(_, placeId, players, options)
				table.insert(world.Teleports, { PlaceId = placeId, Players = players, Options = options })
				return nil
			end,
		},
	}

	special.TeleportOptions = {
		methods = {
			SetTeleportData = function(self, data)
				D[self].Hidden.TeleportData = data
			end,
			GetTeleportData = function(self)
				return D[self].Hidden.TeleportData
			end,
		},
	}

	-- DataStores -----------------------------------------------------------
	local function storeFailure()
		if world.FailNextStoreCalls > 0 then
			world.FailNextStoreCalls -= 1
			error("502: API Services rejected request (mock failure)", 3)
		end
		Scheduler.task.wait(0.05)
	end

	special.DataStoreService = {
		methods = {
			GetDataStore = function(_, name, scope)
				local key = name .. "/" .. tostring(scope or "global")
				local store = world.DataStores[key]
				if store == nil then
					store = new("DataStore")
					D[store].Name = name
					D[store].Hidden.Data = {}
					world.DataStores[key] = store
				end
				return store
			end,
			GetOrderedDataStore = function(_, name, scope)
				local key = name .. "/" .. tostring(scope or "global")
				local store = world.OrderedStores[key]
				if store == nil then
					store = new("OrderedDataStore")
					D[store].Name = name
					D[store].Hidden.Data = {}
					world.OrderedStores[key] = store
				end
				return store
			end,
			GetRequestBudgetForRequestType = function()
				return 100
			end,
		},
	}

	local function deep(v)
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deep(x)
		end
		return out
	end

	special.GlobalDataStore = {
		methods = {
			GetAsync = function(self, key)
				storeFailure()
				return deep(D[self].Hidden.Data[key])
			end,
			SetAsync = function(self, key, value)
				storeFailure()
				copyArg(value, "DataStore:" .. key, 0)
				D[self].Hidden.Data[key] = deep(value)
			end,
			UpdateAsync = function(self, key, fn)
				storeFailure()
				local current = deep(D[self].Hidden.Data[key])
				local result = fn(current, nil)
				if result ~= nil then
					copyArg(result, "DataStore:" .. key, 0)
					D[self].Hidden.Data[key] = deep(result)
				end
				return deep(result)
			end,
			RemoveAsync = function(self, key)
				storeFailure()
				local old = D[self].Hidden.Data[key]
				D[self].Hidden.Data[key] = nil
				return old
			end,
			IncrementAsync = function(self, key, delta)
				storeFailure()
				local v = (D[self].Hidden.Data[key] or 0) + (delta or 1)
				D[self].Hidden.Data[key] = v
				return v
			end,
		},
	}

	special.OrderedDataStore = {
		methods = {
			GetSortedAsync = function(self, ascending, pageSize)
				storeFailure()
				local entries = {}
				for k, v in D[self].Hidden.Data do
					table.insert(entries, { key = k, value = v })
				end
				table.sort(entries, function(a, b)
					if ascending then
						return a.value < b.value
					end
					return a.value > b.value
				end)
				local page = {}
				for i = 1, math.min(pageSize or 50, #entries) do
					page[i] = entries[i]
				end
				local pages = new("DataStorePages")
				D[pages].Hidden.Page = page
				return pages
			end,
		},
	}

	special.Pages = {
		get = {
			IsFinished = function()
				return true
			end,
		},
		methods = {
			GetCurrentPage = function(self)
				return D[self].Hidden.Page or {}
			end,
			AdvanceToNextPageAsync = function() end,
		},
	}

	special.MemoryStoreService = {
		methods = {
			GetHashMap = function(_, name)
				local map = world.MemoryMaps[name]
				if map == nil then
					map = new("MemoryStoreHashMap")
					D[map].Name = name
					D[map].Hidden.Data = {}
					world.MemoryMaps[name] = map
				end
				return map
			end,
		},
	}

	special.MemoryStoreHashMap = {
		methods = {
			GetAsync = function(self, key)
				return deep(D[self].Hidden.Data[key])
			end,
			SetAsync = function(self, key, value, ttl)
				copyArg(value, "MemoryStore:" .. key, 0)
				D[self].Hidden.Data[key] = deep(value)
				return true
			end,
			RemoveAsync = function(self, key)
				D[self].Hidden.Data[key] = nil
			end,
			UpdateAsync = function(self, key, fn, ttl)
				local result = fn(deep(D[self].Hidden.Data[key]))
				if result ~= nil then
					D[self].Hidden.Data[key] = deep(result)
				end
				return result
			end,
		},
	}

	-- Remotes ------------------------------------------------------------
	local function clientOf(ctx)
		return ctx and not ctx.IsServer and ctx.Player or nil
	end

	special.BaseRemoteEvent = {
		methods = {
			FireServer = function(self, ...)
				local ctx = Scheduler.context()
				local player = clientOf(ctx)
				if player == nil then
					error("FireServer can only be called from the client", 2)
				end
				local args, n = copyArgs(D[self].Name .. ":FireServer", ...)
				local remote = self
				Scheduler.deliver(function()
					local s = D[remote].Signals.OnServerEvent
					if s and player.Parent then
						Scheduler.fire(s, nil, player, table.unpack(args, 1, n))
					end
				end)
			end,
			FireClient = function(self, player, ...)
				if not Scheduler.context().IsServer then
					error("FireClient can only be called from the server", 2)
				end
				if not Instances.isInstance(player) or not player:IsA("Player") then
					error("FireClient: player argument must be a Player", 2)
				end
				local args, n = copyArgs(D[self].Name .. ":FireClient", ...)
				world:log(player, D[self].Name, args, n)
				local remote = self
				Scheduler.deliver(function()
					local s = D[remote].Signals.OnClientEvent
					if s and player.Parent then
						Scheduler.fire(s, function(c)
							return c and c.Player == player
						end, table.unpack(args, 1, n))
					end
				end)
			end,
			FireAllClients = function(self, ...)
				local args, n = copyArgs(D[self].Name .. ":FireAllClients", ...)
				local remote = self
				Scheduler.deliver(function()
					local s = D[remote].Signals.OnClientEvent
					if s then
						Scheduler.fire(s, function(c)
							return c and not c.IsServer
						end, table.unpack(args, 1, n))
					end
				end)
			end,
		},
	}

	special.RemoteFunction = {
		methods = {
			InvokeServer = function(self, ...)
				local ctx = Scheduler.context()
				local player = clientOf(ctx)
				if player == nil then
					error("InvokeServer can only be called from the client", 2)
				end
				local callback = D[self].Props.OnServerInvoke
				local args, n = copyArgs(D[self].Name .. ":InvokeServer", ...)
				local waited = 0
				while callback == nil and waited < 10 do
					Scheduler.task.wait(0.1)
					waited += 0.1
					callback = D[self].Props.OnServerInvoke
				end
				if callback == nil then
					error("InvokeServer: no OnServerInvoke", 2)
				end
				local handle, await = Scheduler.suspend()
				Scheduler.spawnIn(world.Server, function()
					local results = table.pack(pcall(callback, player, table.unpack(args, 1, n)))
					handle.resume(results)
				end)
				local results = await()
				if not results[1] then
					error("Server error: " .. tostring(results[2]), 2)
				end
				local out, m = copyArgs(D[self].Name .. ":return", table.unpack(results, 2, results.n))
				return table.unpack(out, 1, m)
			end,
		},
	}

	special.TextChannel = {
		methods = {
			DisplaySystemMessage = function() end,
			SendAsync = function() end,
		},
	}
end

---------------------------------------------------------------------------
-- R6 characters
---------------------------------------------------------------------------

local R = Types.CFrame.new
local JOINT_FRAMES = {
	{
		"RootJoint",
		"HumanoidRootPart",
		"HumanoidRootPart",
		"Torso",
		R(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0),
		R(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0),
	},
	{
		"Neck",
		"Torso",
		"Torso",
		"Head",
		R(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0),
		R(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0),
	},
	{
		"Left Shoulder",
		"Torso",
		"Torso",
		"Left Arm",
		R(-1, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0),
		R(0.5, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0),
	},
	{
		"Right Shoulder",
		"Torso",
		"Torso",
		"Right Arm",
		R(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0),
		R(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0),
	},
	{
		"Left Hip",
		"Torso",
		"Torso",
		"Left Leg",
		R(-1, -1, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0),
		R(-0.5, 1, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0),
	},
	{
		"Right Hip",
		"Torso",
		"Torso",
		"Right Leg",
		R(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0),
		R(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0),
	},
}

function World:buildR6()
	local model = new("Model")
	model.Name = "Character"
	local parts = {}
	for _, spec in
		{
			{ "HumanoidRootPart", Types.Vector3.new(2, 2, 1), Types.Vector3.new(0, 0, 0) },
			{ "Torso", Types.Vector3.new(2, 2, 1), Types.Vector3.new(0, 0, 0) },
			{ "Head", Types.Vector3.new(2, 1, 1), Types.Vector3.new(0, 1.5, 0) },
			{ "Left Arm", Types.Vector3.new(1, 2, 1), Types.Vector3.new(-1.5, 0, 0) },
			{ "Right Arm", Types.Vector3.new(1, 2, 1), Types.Vector3.new(1.5, 0, 0) },
			{ "Left Leg", Types.Vector3.new(1, 2, 1), Types.Vector3.new(-0.5, -2, 0) },
			{ "Right Leg", Types.Vector3.new(1, 2, 1), Types.Vector3.new(0.5, -2, 0) },
		}
	do
		local p = new("Part")
		p.Name = spec[1]
		p.Size = spec[2]
		p.CFrame = Types.CFrame.new(spec[3] + Types.Vector3.new(0, 3, 0))
		p.Parent = model
		parts[spec[1]] = p
	end
	parts.HumanoidRootPart.Transparency = 1
	-- Roblox's default avatar colours and the rounded head mesh.
	local skin = Types.Color3.fromRGB(245, 205, 48)
	parts.Head.Color = skin
	parts["Left Arm"].Color = skin
	parts["Right Arm"].Color = skin
	parts.Torso.Color = Types.Color3.fromRGB(13, 105, 172)
	parts["Left Leg"].Color = Types.Color3.fromRGB(164, 189, 71)
	parts["Right Leg"].Color = Types.Color3.fromRGB(164, 189, 71)
	local headMesh = new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Types.Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = parts.Head
	local face = new("Decal")
	face.Name = "face"
	face.Parent = parts.Head
	for _, j in JOINT_FRAMES do
		local m = new("Motor6D")
		m.Name = j[1]
		m.Part0 = parts[j[3]]
		m.Part1 = parts[j[4]]
		m.C0 = j[5]
		m.C1 = j[6]
		m.Parent = parts[j[2]]
	end
	local humanoid = new("Humanoid")
	humanoid.Parent = model
	D[humanoid].Props.RigType = Enum.HumanoidRigType.R6
	local animator = new("Animator")
	animator.Parent = humanoid
	local animate = new("LocalScript")
	animate.Name = "Animate"
	animate.Parent = model
	local hat = new("Accessory")
	hat.Name = "Hat"
	local handle = new("Part")
	handle.Name = "Handle"
	handle.Parent = hat
	hat.Parent = model
	model.PrimaryPart = parts.HumanoidRootPart
	return model
end

---------------------------------------------------------------------------
-- The Rojo tree
---------------------------------------------------------------------------

local function isFile(path: string): boolean
	return __readfile(path) ~= nil
end

-- Builds instances for a source directory (Rojo semantics: X.luau -> ModuleScript,
-- X.server.luau -> Script, X.client.luau -> LocalScript, dir/init*.luau -> the
-- directory is that script).
local function buildDir(path: string, name: string)
	local entries = __listdir(path) or {}
	local root
	for _, e in entries do
		if not e.Dir then
			if e.Name == "init.luau" then
				root = new("ModuleScript")
			elseif e.Name == "init.server.luau" then
				root = new("Script")
			elseif e.Name == "init.client.luau" then
				root = new("LocalScript")
			end
			if root then
				D[root].SourcePath = path .. "/" .. e.Name
				break
			end
		end
	end
	root = root or new("Folder")
	root.Name = name
	for _, e in entries do
		local child = nil
		if e.Dir then
			child = buildDir(path .. "/" .. e.Name, e.Name)
		elseif not string.match(e.Name, "^init%.") then
			local base, kind = string.match(e.Name, "^(.-)%.(%a+)%.luau$")
			if base and kind == "server" then
				child = new("Script")
			elseif base and kind == "client" then
				child = new("LocalScript")
			else
				base = string.match(e.Name, "^(.-)%.luau$")
				if base then
					child = new("ModuleScript")
				end
			end
			if child then
				child.Name = base
				D[child].SourcePath = path .. "/" .. e.Name
			end
		end
		if child then
			child.Parent = root
		end
	end
	return root
end

function World:loadTree()
	local shared = buildDir("src/shared", "Variance")
	shared.Parent = self.Services.ReplicatedStorage
	local server = buildDir("src/server", "VarianceServer")
	server.Parent = self.Services.ServerScriptService
	local client = buildDir("src/client", "VarianceClient")
	client.Parent = self.Services.StarterPlayer:FindFirstChild("StarterPlayerScripts")
	-- default.project.json settings the code depends on.
	D[self.Workspace].Props.StreamingEnabled = true
	D[self.Services.Players].Props.CharacterAutoLoads = false
end

---------------------------------------------------------------------------
-- Globals and require (per context)
---------------------------------------------------------------------------

function World:log(player, remote: string, args, n)
	self.Traffic = self.Traffic or {}
	local list = self.Traffic[player]
	if list == nil then
		list = {}
		self.Traffic[player] = list
	end
	local message = { Remote = remote, Kind = args[1], Payload = args[2], Time = Scheduler.now }
	table.insert(list, message)
	if #list > 4000 then
		table.remove(list, 1)
	end
	-- Monotonic per-kind counters and the latest message of each kind (the
	-- rolling list above drops old entries).
	self.KindCounts = self.KindCounts or {}
	self.LastOfKind = self.LastOfKind or {}
	local counts = self.KindCounts[player] or {}
	self.KindCounts[player] = counts
	local last = self.LastOfKind[player] or {}
	self.LastOfKind[player] = last
	local kind = tostring(args[1])
	counts[kind] = (counts[kind] or 0) + 1
	last[kind] = message
end

function World:count(player, kind: string): number
	local counts = self.KindCounts and self.KindCounts[player]
	return counts and counts[kind] or 0
end

function World:last(player, kind: string)
	local last = self.LastOfKind and self.LastOfKind[player]
	return last and last[kind] or nil
end

function World:globals(ctx)
	if ctx.Globals then
		return ctx.Globals
	end
	local world = self
	local g = {}
	for k, v in _G do
		g[k] = v
	end
	for _, name in { "string", "table", "math", "coroutine", "utf8", "bit32", "buffer", "debug" } do
		g[name] = _G[name] or (getfenv and getfenv(0)[name])
	end
	g.game = self.Game
	g.Game = self.Game
	g.workspace = self.Workspace
	g.Workspace = self.Workspace
	g.script = nil
	g.Instance = {
		new = function(className, parent)
			return new(className, parent)
		end,
	}
	for _, name in
		{
			"Vector3",
			"Vector2",
			"CFrame",
			"Color3",
			"UDim",
			"UDim2",
			"NumberSequence",
			"NumberSequenceKeypoint",
			"ColorSequence",
			"ColorSequenceKeypoint",
			"NumberRange",
			"TweenInfo",
			"Random",
			"Rect",
		}
	do
		g[name] = Types[name]
	end
	g.Enum = Enum
	g.typeof = Types.typeof
	g.task = Scheduler.task
	g.wait = Scheduler.task.wait
	g.spawn = Scheduler.task.defer
	g.delay = Scheduler.task.delay
	g.tick = function()
		return EPOCH + Scheduler.now
	end
	g.time = function()
		return Scheduler.now
	end
	g.os = {
		clock = function()
			return Scheduler.now
		end,
		time = function(t)
			if t then
				return os.time(t)
			end
			return math.floor(EPOCH + Scheduler.now)
		end,
		date = os.date,
		difftime = os.difftime,
	}
	g.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		table.insert(World.prints, ctx.Name .. ": " .. table.concat(parts, " "))
		if world.Options.Verbose then
			print("[" .. ctx.Name .. "] " .. table.concat(parts, " "))
		end
	end
	g.warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		local line = ctx.Name .. ": " .. table.concat(parts, " ")
		table.insert(World.warnings, line)
		print("WARN  " .. line)
	end
	g.shared = {}
	g._G = g
	g.settings = function()
		return setmetatable({}, {
			__index = function()
				return {}
			end,
		})
	end
	g.UserSettings = g.settings
	g.require = function(module)
		return world:require(ctx, module)
	end
	ctx.Globals = g
	return g
end

function World:require(ctx, module)
	if not Instances.isInstance(module) then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local d = D[module]
	if d.ClassName ~= "ModuleScript" then
		error("require: " .. d.ClassName .. " is not a ModuleScript", 2)
	end
	local cached = ctx.Modules[module]
	if cached then
		if cached.Loading then
			error("Requested module was required recursively: " .. module:GetFullName(), 2)
		end
		return cached.Value
	end
	local entry = { Loading = true }
	ctx.Modules[module] = entry
	local source = __readfile(d.SourcePath)
	if source == nil then
		error("module source missing: " .. tostring(d.SourcePath), 2)
	end
	local g = self:globals(ctx)
	local env = setmetatable({ script = module }, { __index = g })
	local fn = __compile(source, "@" .. d.SourcePath, env)
	local value = fn()
	if value == nil then
		error("Module code did not return exactly one value: " .. module:GetFullName(), 2)
	end
	entry.Value = value
	entry.Loading = false
	return value
end

-- Runs a Script / LocalScript in a context on its own thread.
function World:runScript(ctx, scriptInstance)
	local d = D[scriptInstance]
	local source = __readfile(d.SourcePath)
	local g = self:globals(ctx)
	local env = setmetatable({ script = scriptInstance }, { __index = g })
	local fn = __compile(source, "@" .. d.SourcePath, env)
	return Scheduler.spawnIn(ctx, fn)
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

function World:frame(dt: number)
	local run = self.Services.RunService
	local rs = D[run].Signals
	local function fire(name, ...)
		local s = rs[name]
		if s then
			Scheduler.fire(s, nil, ...)
		end
	end
	fire("PreRender", dt)
	fire("RenderStepped", dt)
	for _, ctx in self.Clients do
		local steps = {}
		for name, step in ctx.RenderSteps do
			table.insert(steps, step)
		end
		table.sort(steps, function(a, b)
			return a.Priority < b.Priority
		end)
		for _, step in steps do
			Scheduler.spawnIn(ctx, step.Fn, dt)
		end
	end
	fire("PreAnimation", dt)
	fire("Stepped", Scheduler.now, dt)
	fire("PreSimulation", dt)
	fire("PostSimulation", dt)
	fire("Heartbeat", dt)
end

function World:start()
	table.insert(Scheduler.frameHooks, function(dt)
		self:frame(dt)
	end)
	local server = self.Services.ServerScriptService:FindFirstChild("VarianceServer")
	self:runScript(self.Server, server)
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

function World:addPlayer(userId: number, name: string, joinData)
	local player = new("Player")
	player.Name = name
	D[player].Props.UserId = userId
	D[player].Props.DisplayName = name
	D[player].Hidden.JoinData = joinData or {}
	local gui = new("PlayerGui")
	gui.Parent = player
	local scripts = new("PlayerScripts")
	scripts.Parent = player
	local backpack = new("Backpack")
	backpack.Parent = player
	table.insert(self.Players, player)
	local ctx = context("Client:" .. name, false, player)
	table.insert(self.Clients, ctx)
	player.Parent = self.Services.Players
	Instances.fire(self.Services.Players, "PlayerAdded", player)
	-- The client starts once its PlayerScripts are populated.
	local starter = self.Services.StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("VarianceClient")
	local copy = starter:Clone()
	copy.Parent = scripts
	if not self.Options.NoClients then
		self:runScript(ctx, copy)
	end
	return player, ctx
end

function World:removePlayer(player, reason)
	if player.Parent == nil then
		return
	end
	Instances.fire(self.Services.Players, "PlayerRemoving", player)
	local character = player.Character
	player.Parent = nil
	if character then
		character:Destroy()
	end
	for i, ctx in self.Clients do
		if ctx.Player == player then
			table.remove(self.Clients, i)
			-- Stop the client's frame work: its connections won't fire again.
			ctx.Dead = true
			break
		end
	end
	self.Kicks = self.Kicks or {}
	if reason then
		table.insert(self.Kicks, { Player = player.Name, Reason = reason })
	end
end

function World:shutdown()
	for _, fn in self.CloseCallbacks do
		local done = false
		Scheduler.spawnIn(self.Server, function()
			fn()
			done = true
		end)
		Scheduler.runUntil(function()
			return done
		end, 60)
	end
end

---------------------------------------------------------------------------
-- Tiny JSON (HttpService:JSONEncode)
---------------------------------------------------------------------------

function World.json(v): string
	local t = type(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" or t == "number" then
		return tostring(v)
	elseif t == "string" then
		return '"'
			.. string.gsub(v, '[%c"\\]', function(c)
				return string.format("\\u%04x", string.byte(c))
			end)
			.. '"'
	elseif t == "table" then
		if #v > 0 then
			local parts = {}
			for _, x in v do
				table.insert(parts, World.json(x))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, x in v do
			table.insert(parts, World.json(tostring(k)) .. ":" .. World.json(x))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return '"' .. tostring(v) .. '"'
end

World.Scheduler = Scheduler
World.Instances = Instances
World.Types = Types
World.Enum = Enum
World.EPOCH = EPOCH

return World
