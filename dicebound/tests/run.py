#!/usr/bin/env python3
"""Runs the pure-logic Luau tests outside Roblox.

It bundles the shared modules and server/Core modules into one Luau file with a tiny fake
Instance tree (so `script.Parent.X` and `game:GetService("ReplicatedStorage")` work), appends a
test file, and runs it with the `luau` CLI.

Usage:  python3 tests/run.py [path/to/luau] [test file ...]
Defaults to `luau` on PATH and every tests/*.test.luau file.
"""

import glob
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (instance path, file) for every module the tests may require.
MOUNTS = [
    ("ReplicatedStorage/Dicebound", os.path.join(ROOT, "src/shared")),
    ("ServerScriptService/Dicebound/Core", os.path.join(ROOT, "src/server/Core")),
]

PRELUDE = r"""
-- Fake Instance tree ---------------------------------------------------------
local Fake = {}
local function node(name, parent)
	local n = setmetatable({ Name = name, Parent = parent, __children = {} }, Fake)
	if parent then parent.__children[name] = n end
	return n
end
Fake.__index = function(self, key)
	local method = rawget(Fake, key)
	if method then return method end
	local child = rawget(self, "__children")[key]
	if child then return child end
	error("fake instance " .. rawget(self, "Name") .. " has no child " .. tostring(key), 2)
end
function Fake.WaitForChild(self, name) return self.__children[name] end
function Fake.FindFirstChild(self, name) return self.__children[name] end
function Fake.GetService(self, name) return self.__children[name] or node(name, self) end

local DataModel = node("game", nil)
game = DataModel
local sources = {}
local cache = {}
local function mount(path, fn)
	local current = DataModel
	for part in string.gmatch(path, "[^/]+") do
		current = current.__children[part] or node(part, current)
	end
	sources[current] = fn
end
local realRequire = require
require = function(target)
	if type(target) == "table" and sources[target] then
		if cache[target] == nil then
			cache[target] = sources[target](target)
		end
		return cache[target]
	end
	return realRequire(target)
end
"""


def module_path(mount_path, base, file):
    rel = os.path.relpath(file, base)
    parts = rel[: -len(".luau")].split(os.sep)
    if parts[-1] == "init":
        parts = parts[:-1]
    return "/".join([mount_path] + parts)


def build(test_files):
    out = [PRELUDE]
    for mount_path, base in MOUNTS:
        for file in sorted(glob.glob(os.path.join(base, "**/*.luau"), recursive=True)):
            path = module_path(mount_path, base, file)
            with open(file, encoding="utf-8") as fh:
                source = fh.read()
            out.append(f"mount({path!r}, function(script)\n{source}\nend)\n")
    with open(os.path.join(ROOT, "tests/TestLib.luau"), encoding="utf-8") as fh:
        out.append(f"local T = (function()\n{fh.read()}\nend)()\n")
    for test in test_files:
        with open(test, encoding="utf-8") as fh:
            out.append(f"do -- {os.path.basename(test)}\n{fh.read()}\nend\n")
    out.append("T.Finish()\n")
    return "\n".join(out)


def main():
    args = sys.argv[1:]
    luau = "luau"
    if args and not args[0].endswith(".luau"):
        luau = args.pop(0)
    tests = args or sorted(glob.glob(os.path.join(ROOT, "tests/*.test.luau")))
    bundle = os.path.join(ROOT, "tests/.bundle.luau")
    with open(bundle, "w", encoding="utf-8") as fh:
        fh.write(build(tests))
    result = subprocess.run([luau, bundle])
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
