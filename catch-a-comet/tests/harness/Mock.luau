-- Test doubles for the Roblox engine pieces the server code touches.
-- Real instances come from Lune's Roblox DOM (so invalid property names
-- fail loudly); engine services are small Lua mocks.

local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local CFrame = roblox.CFrame
local Enum = roblox.Enum
local Vector3 = roblox.Vector3

local Mock = {}

-- Make Lune's DOM behave a little more like the engine. -------------------------
do
	roblox.implementProperty("BasePart", "Position", function(part)
		return part.CFrame.Position
	end, function(part, value)
		part.CFrame = CFrame.new(value) * part.CFrame.Rotation
	end)
	roblox.implementMethod("Instance", "WaitForChild", function(instance, name)
		local child = instance:FindFirstChild(name)
		if not child then
			error(`WaitForChild: {name} not found under {instance.Name}`)
		end
		return child
	end)
	roblox.implementMethod("Model", "GetPivot", function(model)
		return if model.PrimaryPart then model.PrimaryPart.CFrame else CFrame.identity
	end)
	roblox.implementMethod("Model", "PivotTo", function(model, target)
		local pivot = if model.PrimaryPart then model.PrimaryPart.CFrame else CFrame.identity
		local delta = target * pivot:Inverse()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CFrame = delta * part.CFrame
			end
		end
	end)
	roblox.implementMethod("Model", "GetBoundingBox", function(model)
		return if model.PrimaryPart then model.PrimaryPart.CFrame else CFrame.identity, Vector3.new(4, 4, 4)
	end)
end

-- Signals ------------------------------------------------------------------------

function Mock.Signal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		local entry = { Fn = fn, Connected = true }
		table.insert(handlers, entry)
		return {
			Connected = true,
			Disconnect = function()
				entry.Connected = false
			end,
		}
	end
	function signal:Once(fn)
		local connection
		connection = signal:Connect(function(...)
			connection.Disconnect()
			fn(...)
		end)
		return connection
	end
	function signal:Fire(...)
		for _, entry in table.clone(handlers) do
			if entry.Connected then
				entry.Fn(...)
			end
		end
	end
	return signal
end

-- Random ------------------------------------------------------------------------

local MODULUS = 2147483647
local Random = {}
Random.__index = Random

function Random.new(seed: number?)
	local state = math.floor(seed or (os.clock() * 1e6)) % (MODULUS - 1) + 1
	return setmetatable({ State = state }, Random)
end

function Random:_next(): number
	self.State = (self.State * 48271) % MODULUS
	return self.State / MODULUS
end

function Random:NextNumber(min: number?, max: number?): number
	local r = self:_next()
	if min and max then
		return min + r * (max - min)
	end
	return r
end

function Random:NextInteger(min: number, max: number): number
	return min + math.floor(self:_next() * (max - min + 1))
end

Mock.Random = Random

-- A scripted RNG returning the given values in order (for deterministic rolls).
function Mock.ScriptedRandom(values: { number })
	local index = 0
	return {
		NextNumber = function()
			index += 1
			return values[(index - 1) % #values + 1]
		end,
		NextInteger = function(_, min, max)
			index += 1
			return min + math.floor(values[(index - 1) % #values + 1] * (max - min + 1))
		end,
	}
end

-- Clocks --------------------------------------------------------------------------

-- One controllable time source for a simulated server.
function Mock.Clock(start: number?)
	local clock = { Unix = start or 1_800_000_000, Server = 1000, Os = 50 }
	function clock:Advance(seconds: number)
		self.Unix += seconds
		self.Server += seconds
		self.Os += seconds
	end
	return clock
end

-- DataStore -----------------------------------------------------------------------

-- Copies a value the way a DataStore would (JSON): rejects userdata, functions,
-- mixed or non-string keys, NaN and infinity — anything a real save would lose.
local function jsonCopy(value: any, path: string): any
	local kind = typeof(value)
	if kind == "table" then
		local isArray = #value > 0
		local out = {}
		for key, item in value do
			if isArray then
				if type(key) ~= "number" then
					error(`DataStore: mixed table at {path}`)
				end
			elseif type(key) ~= "string" then
				error(`DataStore: non-string key {tostring(key)} at {path}`)
			end
			out[key] = jsonCopy(item, `{path}.{tostring(key)}`)
		end
		return out
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error(`DataStore: non-finite number at {path}`)
		end
		return value
	elseif kind == "string" or kind == "boolean" or kind == "nil" then
		return value
	end
	error(`DataStore: cannot store {kind} at {path}`)
end
Mock.JsonCopy = jsonCopy

-- Shared "cloud" storage that several simulated servers can use at once.
function Mock.Cloud()
	local cloud = {
		Data = {},
		Calls = 0,
		FailNext = 0,
		FailAll = false,
		FailMessage = "502: DataStore request failed",
	}
	local store = {}
	function store:UpdateAsync(key: string, transform)
		cloud.Calls += 1
		if cloud.FailAll then
			error(cloud.FailMessage)
		end
		if cloud.FailNext > 0 then
			cloud.FailNext -= 1
			error(cloud.FailMessage)
		end
		local current = jsonCopy(cloud.Data[key], key)
		local result = transform(current, nil)
		if result ~= nil then
			cloud.Data[key] = jsonCopy(result, key)
		end
		return result
	end
	cloud.Store = store
	return cloud
end

-- Players and characters ---------------------------------------------------------

function Mock.Character(position: Vector3)
	local root = {
		Name = "HumanoidRootPart",
		Position = position,
		CFrame = CFrame.new(position),
		AssemblyLinearVelocity = Vector3.zero,
		Parent = true,
	}
	function root:IsA(className)
		return className == "BasePart" or className == "Part"
	end
	local humanoid = { Health = 100, WalkSpeed = 16, FloorMaterial = Enum.Material.Grass }
	function humanoid:IsA(className)
		return className == "Humanoid"
	end
	local character = { Name = "Character", Parent = true, Attributes = {}, Root = root, Humanoid = humanoid }
	function character:FindFirstChild(name)
		if name == "HumanoidRootPart" then
			return root
		end
		return nil
	end
	function character:FindFirstChildOfClass(className)
		if className == "Humanoid" then
			return humanoid
		end
		return nil
	end
	function character:SetAttribute(key, value)
		self.Attributes[key] = value
	end
	function character:GetAttribute(key)
		return self.Attributes[key]
	end
	function character:PivotTo(target)
		root.CFrame = target
		root.Position = target.Position
	end
	return character
end

function Mock.Player(players: any, userId: number, name: string, position: Vector3?)
	local player = {
		UserId = userId,
		Name = name,
		DisplayName = name,
		Parent = players,
		Kicked = nil :: string?,
		Attributes = {},
		Character = Mock.Character(position or Vector3.new(0, 43, 0)),
	}
	function player:Kick(message)
		self.Kicked = message or "kicked"
		self.Parent = nil
	end
	function player:GetNetworkPing()
		return 0.05
	end
	function player:SetAttribute(key, value)
		self.Attributes[key] = value
	end
	function player:GetAttribute(key)
		return self.Attributes[key]
	end
	function player:MoveTo(position: Vector3)
		self.Character.Root.Position = position
		self.Character.Root.CFrame = CFrame.new(position)
	end
	return player
end

-- Services ---------------------------------------------------------------------

function Mock.Services(options: { [string]: any })
	local players = { CharacterAutoLoads = true, List = {} }
	players.PlayerAdded = Mock.Signal()
	players.PlayerRemoving = Mock.Signal()
	function players:GetPlayers()
		return table.clone(self.List)
	end
	function players:GetPlayerByUserId(userId)
		for _, player in self.List do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end
	function players:GetPlayerFromCharacter(character)
		for _, player in self.List do
			if player.Character == character then
				return player
			end
		end
		return nil
	end

	local runService = {
		Heartbeat = Mock.Signal(),
		RenderStepped = Mock.Signal(),
		Stepped = Mock.Signal(),
	}
	function runService:IsServer()
		return true
	end
	function runService:IsClient()
		return false
	end
	function runService:IsStudio()
		return options.IsStudio == true
	end

	local guid = 0
	local http = {}
	function http:GenerateGUID()
		guid += 1
		return `guid-{guid}`
	end
	function http:JSONEncode(value)
		return serde.encode("json", value)
	end
	function http:JSONDecode(text)
		return serde.decode("json", text)
	end

	local dataStores = {}
	function dataStores:GetDataStore(_name)
		if options.DataStoreUnavailable then
			error(options.DataStoreUnavailable)
		end
		return options.Cloud and options.Cloud.Store
	end
	function dataStores:GetRequestBudgetForRequestType()
		return 100
	end

	local collection = {}
	function collection:GetTagged()
		return {}
	end
	function collection:GetInstanceAddedSignal()
		return Mock.Signal()
	end
	function collection:GetInstanceRemovedSignal()
		return Mock.Signal()
	end

	local lighting = roblox.Instance.new("Lighting")

	return {
		Players = players,
		RunService = runService,
		HttpService = http,
		DataStoreService = dataStores,
		CollectionService = collection,
		Lighting = lighting,
	}
end

function Mock.Workspace(clock: any)
	local terrain = { Name = "Terrain" }
	function terrain:FindFirstChild()
		return nil
	end
	local ws = { Name = "Workspace", Terrain = terrain }
	function ws:GetServerTimeNow()
		return clock.Server
	end
	function ws:Raycast()
		return nil
	end
	function ws:GetPartBoundsInBox()
		return {}
	end
	function ws:FindFirstChild()
		return nil
	end
	return ws
end

Mock.task = task

return Mock
