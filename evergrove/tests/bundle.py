#!/usr/bin/env python3
"""Bundle src/shared into a single Luau file that runs under the standalone
`luau` CLI, with a tiny fake Roblox instance tree and API stubs, then append a
test file and run it.

Usage:  python3 tests/bundle.py [tests/spec.luau] [--luau /path/to/luau]

Why: the shared modules (configs, registry, crop/market/genetics math) are
pure Luau. Running them outside Studio lets us validate every cross-reference
between config modules and unit-test the game math on every change.
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHARED = os.path.join(ROOT, "src", "shared")
OUT = os.path.join(ROOT, "tests", ".bundle.luau")

PRELUDE = r'''
-- ===== fake Roblox runtime (tests only) =====
local __warnings = {}
function warn(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	table.insert(__warnings, table.concat(parts, " "))
end

local Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x, y, z)
	local v = setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
	v.Magnitude = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	return v
end
Vector3.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3.__mul = function(a, b)
	if type(a) == "number" then return Vector3.new(b.X * a, b.Y * a, b.Z * a) end
	if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3.__tostring = function(v) return string.format("(%g, %g, %g)", v.X, v.Y, v.Z) end

local Color3 = {}
Color3.__index = Color3
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3) end
function Color3.fromRGB(r, g, b) return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHex(hex)
	hex = string.gsub(hex, "#", "")
	assert(#hex == 6, "bad hex colour " .. hex)
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end
function Color3:Lerp(o, t) return Color3.new(self.R + (o.R - self.R) * t, self.G + (o.G - self.G) * t, self.B + (o.B - self.B) * t) end

local Random = {}
Random.__index = Random
function Random.new(seed)
	local s = math.floor(seed or os.clock() * 1e6) % 2147483647
	if s <= 0 then s = s + 2147483646 end
	return setmetatable({ s = s }, Random)
end
function Random:_next()
	self.s = (self.s * 48271) % 2147483647
	return self.s / 2147483647
end
function Random:NextNumber(lo, hi)
	local x = self:_next()
	if lo then return lo + (hi - lo) * x end
	return x
end
function Random:NextInteger(lo, hi)
	return lo + math.floor(self:_next() * (hi - lo + 1))
end

local __typeof = typeof
function typeof(v)
	local mt = getmetatable(v)
	if mt == Vector3 then return "Vector3" end
	if mt == Color3 then return "Color3" end
	if mt == Random then return "Random" end
	if type(v) == "table" and rawget(v, "__isInstance") then return "Instance" end
	return __typeof(v)
end

task = {
	spawn = function(fn, ...) local co = coroutine.create(fn); coroutine.resume(co, ...); return co end,
	defer = function(fn, ...) return task.spawn(fn, ...) end,
	delay = function(_, fn, ...) return task.spawn(fn, ...) end,
	wait = function() return 0 end,
	cancel = function() end,
}

-- Fake instances ------------------------------------------------------------------
local Node = {}
local function makeNode(name, className, parent)
	local node = { __isInstance = true, Name = name, ClassName = className, Parent = parent, __children = {}, __attributes = {} }
	setmetatable(node, Node)
	if parent then parent.__children[name] = node end
	return node
end
Node.__index = function(self, key)
	local method = Node[key]
	if method then return method end
	local child = rawget(self, "__children")[key]
	if child then return child end
	return nil
end
function Node:FindFirstChild(name) return self.__children[name] end
function Node:WaitForChild(name) return assert(self.__children[name], "WaitForChild: missing " .. tostring(name)) end
function Node:IsA(className) return self.ClassName == className end
function Node:GetChildren() local out = {} for _, c in self.__children do table.insert(out, c) end return out end
function Node:GetAttribute(key) return self.__attributes[key] end
function Node:SetAttribute(key, value) self.__attributes[key] = value end
function Node:GetFullName() if self.Parent then return self.Parent:GetFullName() .. "." .. self.Name end return self.Name end

local GAME = makeNode("game", "DataModel", nil)
local ReplicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", GAME)
local Players = makeNode("Players", "Players", GAME)
function Players:GetPlayers() return {} end
Players.PlayerRemoving = { Connect = function() return { Disconnect = function() end } end }
Players.PlayerAdded = Players.PlayerRemoving
local RunService = makeNode("RunService", "RunService", GAME)
local __isServer = true
function RunService:IsServer() return __isServer end
function RunService:IsClient() return not __isServer end
function RunService:IsStudio() return true end
local Workspace = makeNode("Workspace", "Workspace", GAME)
__serverTime = 1790467200 + 3600 * 5
function Workspace:GetServerTimeNow() return __serverTime end
workspace = Workspace
function GAME:GetService(name)
	local svc = self.__children[name]
	if not svc then svc = makeNode(name, name, self) end
	return svc
end
game = GAME

local __fakeRemote = { Connect = function() return { Disconnect = function() end } end }
Instance = {
	new = function(className)
		local node = makeNode(className, className, nil)
		node.OnServerEvent = __fakeRemote
		node.OnClientEvent = __fakeRemote
		local mt = getmetatable(node)
		return setmetatable(node, {
			__index = mt.__index,
			__newindex = function(t, k, v)
				if k == "Parent" and v then
					rawset(t, "Parent", v)
					v.__children[rawget(t, "Name")] = t
				else
					rawset(t, k, v)
				end
			end,
		})
	end,
}

-- Module loading ----------------------------------------------------------------------
local __loaders = {}
local __cache = {}
local __loading = {}
local function __require(target)
	if type(target) ~= "table" or not rawget(target, "__isInstance") then
		error("require expects a ModuleScript instance, got " .. tostring(target), 2)
	end
	local cached = __cache[target]
	if cached ~= nil then return cached end
	local loader = __loaders[target]
	if not loader then error("no module at " .. target:GetFullName(), 2) end
	if __loading[target] then error("circular require of " .. target:GetFullName(), 2) end
	__loading[target] = true
	local result = loader(target)
	__loading[target] = nil
	__cache[target] = result
	return result
end
require = __require
'''


def build_tree(path, parent_expr, lines, loaders, rel=""):
    """Create fake instances mirroring Rojo's rules for a directory."""
    entries = sorted(os.listdir(path))
    for entry in entries:
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            init = None
            for candidate in ("init.luau", "init.lua"):
                if os.path.exists(os.path.join(full, candidate)):
                    init = os.path.join(full, candidate)
            var = "N_" + re.sub(r"[^A-Za-z0-9_]", "_", rel + "_" + entry)
            cls = "ModuleScript" if init else "Folder"
            lines.append(f'local {var} = makeNode("{entry}", "{cls}", {parent_expr})')
            if init:
                loaders.append((var, init))
            build_tree(full, var, lines, loaders, rel + "_" + entry)
        elif entry.endswith(".luau") or entry.endswith(".lua"):
            stem = entry.rsplit(".", 1)[0]
            if stem in ("init",) or stem.endswith(".server") or stem.endswith(".client"):
                continue
            var = "N_" + re.sub(r"[^A-Za-z0-9_]", "_", rel + "_" + stem)
            lines.append(f'local {var} = makeNode("{stem}", "ModuleScript", {parent_expr})')
            loaders.append((var, full))


def transform(source):
    # `export type` is only legal at the top level; inside our wrapper function it
    # becomes a plain local type alias.
    source = re.sub(r"^export type", "type", source, flags=re.M)
    return source


def main():
    spec = "tests/spec.luau"
    luau = os.environ.get("LUAU", "luau")
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--luau":
            luau = args[i + 1]
            i += 2
            continue
        spec = args[i]
        i += 1

    lines = [PRELUDE]
    loaders = []
    lines.append('local N_Shared = makeNode("Shared", "Folder", ReplicatedStorage)')
    build_tree(SHARED, "N_Shared", lines, loaders)
    for var, path in loaders:
        with open(path, encoding="utf-8") as f:
            source = transform(f.read())
        lines.append(f"__loaders[{var}] = function(script)")
        lines.append(source)
        lines.append("end")
    lines.append("SHARED = N_Shared")
    with open(os.path.join(ROOT, spec), encoding="utf-8") as f:
        lines.append(f.read())
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    result = subprocess.run([luau, OUT])
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
