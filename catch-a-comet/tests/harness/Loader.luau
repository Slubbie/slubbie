-- Loads the game's ModuleScripts from disk with Roblox-style requires.
--
-- The Rojo tree is mirrored as lightweight "virtual instances" (Name,
-- Parent, children by index, FindFirstChild, WaitForChild…), so code like
-- require(script.Parent.Parent.Data.ProfileSchema) or
-- ReplicatedStorage:WaitForChild("Shared") works unchanged. Every Loader
-- has its own module cache, so each simulated server starts fresh.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Mock = require("./Mock")

local Loader = {}
Loader.__index = Loader

local Node = {}

local NodeMethods = {}

function NodeMethods.FindFirstChild(self, name)
	return rawget(self, "__children")[name]
end

function NodeMethods.WaitForChild(self, name)
	local child = rawget(self, "__children")[name]
	if not child then
		error(`WaitForChild: {name} is not a child of {rawget(self, "__name")}`)
	end
	return child
end

function NodeMethods.GetChildren(self)
	local list = {}
	for _, child in rawget(self, "__children") do
		table.insert(list, child)
	end
	return list
end

function NodeMethods.IsA(self, className)
	return className == "Instance" or className == rawget(self, "__class")
end

function NodeMethods.GetFullName(self)
	local parent = rawget(self, "__parent")
	return if parent then `{parent:GetFullName()}.{rawget(self, "__name")}` else rawget(self, "__name")
end

Node.__index = function(self, key)
	if NodeMethods[key] then
		return NodeMethods[key]
	elseif key == "Name" then
		return rawget(self, "__name")
	elseif key == "Parent" then
		return rawget(self, "__parent")
	elseif key == "ClassName" then
		return rawget(self, "__class")
	end
	local child = rawget(self, "__children")[key]
	if child then
		return child
	end
	error(`{tostring(key)} is not a valid member of {rawget(self, "__name")}`, 2)
end
Node.__tostring = function(self)
	return rawget(self, "__name")
end

local function newNode(name: string, class: string, parent: any?, path: string?)
	local node =
		setmetatable({ __name = name, __class = class, __parent = parent, __children = {}, __path = path }, Node)
	if parent then
		rawget(parent, "__children")[name] = node
	end
	return node
end
Loader.NewNode = newNode

local function mount(dir: string, parent: any)
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			mount(path, newNode(entry, "Folder", parent))
		elseif entry:match("%.luau$") then
			local name = entry:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
			local class = if entry:match("%.server%.luau$")
				then "Script"
				elseif entry:match("%.client%.luau$") then "LocalScript"
				else "ModuleScript"
			newNode(name, class, parent, path)
		end
	end
end

function Loader.new(root: string, options: { [string]: any }?)
	local self = setmetatable({}, Loader)
	local o = options or {}
	self.Clock = o.Clock or Mock.Clock()
	self.Services = Mock.Services(o)
	self.Workspace = Mock.Workspace(self.Clock)
	self.Cache = {}
	self.Warnings = {}

	local replicated = newNode("ReplicatedStorage", "ReplicatedStorage", nil)
	mount(`{root}/src/shared`, newNode("Shared", "Folder", replicated))
	local serverScripts = newNode("ServerScriptService", "ServerScriptService", nil)
	mount(`{root}/src/server`, newNode("Server", "Folder", serverScripts))
	self.ReplicatedStorage = replicated
	self.ServerScriptService = serverScripts

	local services = self.Services
	services.ReplicatedStorage = replicated
	services.ServerScriptService = serverScripts
	services.Workspace = self.Workspace

	local game = { BindToClose = function() end, JobId = "", PlaceId = 0 }
	function game:GetService(name)
		local service = services[name]
		if service == nil then
			error(`mock game has no service {name}`)
		end
		return service
	end
	self.Game = game

	local quiet = o.Quiet ~= false
	local warnings = self.Warnings
	local globals = {
		game = game,
		workspace = self.Workspace,
		task = task,
		Random = Mock.Random,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring(select(i, ...)))
			end
			table.insert(warnings, table.concat(parts, " "))
			if not quiet then
				print("[warn]", ...)
			end
		end,
		RaycastParams = {
			new = function()
				return {}
			end,
		},
		TweenInfo = {
			new = function(time, style, direction)
				return { Time = time or 1, EasingStyle = style, EasingDirection = direction }
			end,
		},
		OverlapParams = {
			new = function()
				return {}
			end,
		},
	}
	for key, value in roblox do
		if type(key) == "string" and key:sub(1, 1):match("%u") then
			globals[key] = value
		end
	end
	self.Globals = globals
	return self
end

-- Requires a virtual ModuleScript (or a path like "Shared.GameConfig").
function Loader:require(target: any): any
	if type(target) == "string" then
		local node = nil
		local first, rest = target:match("^(%w+)%.(.+)$")
		if first == "Shared" then
			node = self.ReplicatedStorage.Shared
		elseif first == "Server" then
			node = self.ServerScriptService.Server
		end
		assert(node and rest, `bad module path {target}`)
		for part in rest:gmatch("[^%.]+") do
			node = node[part]
		end
		target = node
	end
	local path = rawget(target, "__path")
	assert(path, `{tostring(target)} is not a module`)
	local cached = self.Cache[target]
	if cached ~= nil then
		return cached.Value
	end
	-- Lune replaces the environment's metatable when it injects its own
	-- globals, so the game globals are copied in as plain fields.
	local env = table.clone(self.Globals)
	env.script = target
	env.require = function(module)
		return self:require(module)
	end
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = env })
	local value = chunk()
	self.Cache[target] = { Value = value }
	return value
end

return Loader
