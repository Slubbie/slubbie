#!/usr/bin/env python3
"""Bundle the project's Luau sources with the mock engine and run a headless test.

Usage: python3 tools/headless/run.py <luau-binary> [test-script] [--out bundle.luau]

The sources are mounted into a mock DataModel following default.project.json
(src/shared -> ReplicatedStorage.Shared, src/server -> ServerScriptService.Server,
src/client -> StarterPlayer.StarterPlayerScripts.Client), then the test script
runs with the same globals a Roblox script would see.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))

MOUNTS = [
    ("src/shared", "ReplicatedStorage/Shared"),
    ("src/server", "ServerScriptService/Server"),
    ("src/client", "StarterPlayer/StarterPlayerScripts/Client"),
]


def long_string(text):
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + text + "]" + eq + "]"


def collect():
    entries = []
    for src, virtual in MOUNTS:
        base = os.path.join(ROOT, src)
        if not os.path.isdir(base):
            continue

        def walk(directory, path):
            names = sorted(os.listdir(directory))
            init = None
            for candidate, cls in (("init.server.luau", "Script"), ("init.client.luau", "LocalScript"), ("init.luau", "ModuleScript")):
                if candidate in names:
                    init = (candidate, cls)
            if init:
                with open(os.path.join(directory, init[0])) as f:
                    entries.append({"path": path, "class": init[1], "source": f.read()})
            else:
                entries.append({"path": path, "class": "Folder"})
            for name in names:
                full = os.path.join(directory, name)
                if init and name == init[0]:
                    continue
                if os.path.isdir(full):
                    walk(full, path + "/" + name)
                elif name.endswith(".luau"):
                    stem = name[: -len(".luau")]
                    cls = "ModuleScript"
                    if stem.endswith(".server"):
                        stem, cls = stem[: -len(".server")], "Script"
                    elif stem.endswith(".client"):
                        stem, cls = stem[: -len(".client")], "LocalScript"
                    with open(full) as f:
                        entries.append({"path": path + "/" + stem, "class": cls, "source": f.read()})

        walk(base, virtual)
    return entries


def main():
    luau = sys.argv[1]
    test = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else os.path.join(HERE, "test_world.luau")
    out = os.path.join(HERE, ".bundle.luau")
    if "--out" in sys.argv:
        out = sys.argv[sys.argv.index("--out") + 1]
    with open(os.path.join(HERE, "mock.luau")) as f:
        mock = f.read()
    with open(test) as f:
        test_source = f.read()
    parts = ["--!nocheck", "local Mock = (function()", mock, "end)()", "local ENTRIES = {"]
    for entry in collect():
        source = ("source = " + long_string(entry["source"]) + ",") if "source" in entry else ""
        parts.append('{ path = "%s", class = "%s", %s },' % (entry["path"], entry["class"], source))
    parts.append("}")
    parts.append("Mock.Mount(ENTRIES)")
    parts.append("local test = loadstring(" + long_string(test_source) + ', "=test")')
    parts.append("setfenv(test, setmetatable({ Mock = Mock }, { __index = Mock.Env }))")
    parts.append("test()")
    with open(out, "w") as f:
        f.write("\n".join(parts))
    result = subprocess.run([luau, out])
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
