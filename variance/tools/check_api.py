#!/usr/bin/env python3
"""Static Roblox API checker for VARIANCE.

Validates, against the Roblox API as published in the @rbxts/types package
(generated from Roblox's API dump):
  * every Enum.<Type>.<Item> reference
  * every Instance.new("<Class>") and game:GetService("<Class>")
  * property writes / method calls on locals created with Instance.new(...)
    in the same file (e.g. `local p = Instance.new("Part"); p.Anchord = true`)

Usage:
  npm pack @rbxts/types && tar xzf rbxts-types-*.tgz
  python3 tools/check_api.py path/to/package/include/generated src
"""

import os
import re
import sys


def parse_enums(path):
    enums = {}
    current = None
    depth_ns = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\s{4}export namespace (\w+) \{", line)
            if m:
                current = m.group(1)
                enums[current] = set()
                continue
            if current:
                m = re.match(r"\s{8}export const (\w+): \w+;", line)
                if m:
                    enums[current].add(m.group(1))
    return enums


def parse_classes(paths):
    classes = {}
    parents = {}
    current = None
    for path in paths:
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"interface (\w+)(?:<.*?>)?(?: extends (\w+))?", line)
                if m:
                    current = m.group(1)
                    classes.setdefault(current, set())
                    if m.group(2):
                        parents[current] = [p.strip() for p in m.group(2).split(",")]
                    continue
                if line.startswith("}"):
                    current = None
                    continue
                if current:
                    m = re.match(r"\s{4}(?:readonly )?(\w+)\??(?:\(|:|<)", line)
                    if m:
                        classes[current].add(m.group(1))
    return classes, parents


def members_of(cls, classes, parents, seen=None):
    seen = seen or set()
    if cls in seen:
        return set()
    seen.add(cls)
    out = set(classes.get(cls, set()))
    for p in parents.get(cls, []):
        out |= members_of(p, classes, parents, seen)
    return out


def main():
    gen = sys.argv[1]
    roots = sys.argv[2:]
    enums = parse_enums(os.path.join(gen, "enums.d.ts"))
    classes, parents = parse_classes([os.path.join(gen, "None.d.ts"), os.path.join(gen, "PluginSecurity.d.ts")])
    # Universal Instance members that the typings express elsewhere.
    extra = {"Name", "Parent", "ClassName", "Destroy", "Clone", "IsA", "FindFirstChild", "WaitForChild",
             "GetChildren", "GetDescendants", "SetAttribute", "GetAttribute", "FindFirstChildOfClass",
             "FindFirstChildWhichIsA", "FindFirstAncestor", "FindFirstAncestorOfClass", "IsDescendantOf",
             "GetPropertyChangedSignal", "Changed", "ChildAdded", "ChildRemoved", "DescendantAdded",
             "DescendantRemoving", "AncestryChanged", "Destroying", "ClearAllChildren", "GetAttributes",
             "GetAttributeChangedSignal", "AddTag", "HasTag", "RemoveTag", "GetTags", "Archivable"}
    problems = []
    files = []
    for root in roots:
        for dirpath, _, names in os.walk(root):
            for n in names:
                if n.endswith(".luau") or n.endswith(".lua"):
                    files.append(os.path.join(dirpath, n))
    enum_re = re.compile(r"Enum\.(\w+)\.(\w+)")
    new_re = re.compile(r"(?:local\s+)?(\w+)\s*=\s*Instance\.new\(\"(\w+)\"")
    service_re = re.compile(r"GetService\(\"(\w+)\"\)")
    for path in files:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        lines = text.split("\n")
        for i, line in enumerate(lines, 1):
            code = line.split("--", 1)[0]
            for m in enum_re.finditer(code):
                t, item = m.group(1), m.group(2)
                if t in ("GetEnums",):
                    continue
                if t not in enums:
                    problems.append(f"{path}:{i}: unknown enum Enum.{t}")
                elif item not in enums[t] and item not in ("GetEnumItems", "FromName", "FromValue"):
                    problems.append(f"{path}:{i}: unknown enum item Enum.{t}.{item}")
            for m in re.finditer(r"Instance\.new\(\"(\w+)\"", code):
                if m.group(1) not in classes:
                    problems.append(f"{path}:{i}: unknown class {m.group(1)}")
            for m in service_re.finditer(code):
                if m.group(1) not in classes:
                    problems.append(f"{path}:{i}: unknown service {m.group(1)}")
        # Track locals created with Instance.new; a use is checked against the
        # nearest preceding assignment of that name (names get reused).
        assignments = {}
        for i, line in enumerate(lines, 1):
            code = line.split("--", 1)[0]
            m = new_re.search(code)
            if m:
                assignments.setdefault(m.group(1), []).append((i, m.group(2)))
        # Any other binding of the same name (a new local, a parameter, a
        # plain reassignment) ends the tracking from that line on.
        for var, spots in list(assignments.items()):
            rebind = re.compile(
                r"(?:\blocal\s+" + re.escape(var) + r"\b(?!\s*=\s*Instance\.new)"
                r"|\bfunction\b[^(]*\([^)]*\b" + re.escape(var) + r"\b"
                r"|^\s*" + re.escape(var) + r"\s*=(?!=)(?!\s*Instance\.new))"
            )
            for i, line in enumerate(lines, 1):
                code = line.split("--", 1)[0]
                if rebind.search(code) and not new_re.search(code):
                    spots.append((i, None))
            spots.sort()
        for var, spots in assignments.items():
            pat = re.compile(r"(?<![\w.:])" + re.escape(var) + r"([.:])(\w+)")
            for i, line in enumerate(lines, 1):
                current = None
                for line_no, cls in spots:
                    if line_no <= i:
                        current = cls
                if current is None:
                    continue
                if current is None:
                    continue
                members = members_of(current, classes, parents) | extra
                code = line.split("--", 1)[0]
                for m in pat.finditer(code):
                    member = m.group(2)
                    if member not in members:
                        problems.append(f"{path}:{i}: {current} has no member '{member}' ({var}{m.group(1)}{member})")
    for p in problems:
        print(p)
    print(f"\n{len(files)} files checked, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
