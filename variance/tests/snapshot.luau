--# selene: allow(global_usage, unused_variable, shadowing)
-- Scene snapshots: runs the real server and client on the runtime mock and
-- writes what one client would see (every visible part with joint-resolved
-- world frames, lights, lighting, the camera, and the on-screen GUI tree) as
-- JSON, one file per frame. tools/render renders them to PNG.
--
--   luaurun tests/snapshot.luau <scenario> <outdir>
--
-- Scenarios: lobby, seat (solo match from the lobby through the intro to the
-- first turn), match (a few turns in), results.

-- "--phone" anywhere in the arguments: a landscape phone (844 x 390, touch).
local phone = false
do
	local rest = {}
	for _, a in arg or {} do
		if a == "--phone" then
			phone = true
		else
			table.insert(rest, a)
		end
	end
	arg = rest
end
local scenario = arg[1] or "seat"
local outDir = arg[2] or "snapshots"

local loaded = {}
local function mockModule(name: string)
	if loaded[name] then
		return loaded[name]
	end
	local path = "tests/mock/" .. name .. ".luau"
	local source = __readfile(path)
	assert(source, "missing " .. path)
	local parent = setmetatable({}, {
		__index = function(_, child)
			return { __mock = child }
		end,
	})
	local env = setmetatable({
		script = { Parent = parent },
		require = function(ref)
			return mockModule(ref.__mock)
		end,
	}, { __index = _G })
	local value = __compile(source, "@" .. path, env)()
	loaded[name] = value
	return value
end

local World = mockModule("World")
local Scheduler = World.Scheduler
local Instances = World.Instances
local D = Instances.data
Scheduler.deferEvents = true

Scheduler.onError = function(ctx, err, trace)
	print("ERROR [" .. (ctx and ctx.Name or "?") .. "] " .. tostring(err))
	print(trace)
end

if phone then
	Instances.viewport = World.Types.Vector2.new(844, 390)
end
local world = World.new({ Verbose = false })
if phone then
	local uis = D[world.Services.UserInputService].Props
	uis.TouchEnabled = true
	uis.KeyboardEnabled = false
	uis.MouseEnabled = false
end

local function ctl(ctx, name: string)
	return world:require(ctx, ctx.Player.PlayerScripts.VarianceClient.Controllers[name])
end

local function run(ctx, fn, ...)
	local done, results = false, nil
	Scheduler.spawnIn(ctx, function(...)
		results = table.pack(pcall(fn, ...))
		done = true
	end, ...)
	Scheduler.runUntil(function()
		return done
	end, 90)
	assert(done, "timed out")
	assert(results[1], results[2])
	return table.unpack(results, 2, results.n)
end

local function request(ctx, endpoint: string, ...)
	local args = table.pack(...)
	return run(ctx, function()
		return ctl(ctx, "NetworkClient"):request(endpoint, table.unpack(args, 1, args.n))
	end)
end

---------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------

local function num(n: number): string
	if n ~= n then
		return "0"
	elseif n == math.huge or n == -math.huge then
		return if n > 0 then "1e9" else "-1e9"
	end
	local s = string.format("%.4f", n):gsub("%.?0+$", "")
	return if s == "" or s == "-" then "0" else s
end

local encode
local function encodeString(s: string): string
	return '"'
		.. s:gsub('[%c"\\]', function(c)
			if c == '"' then
				return '\\"'
			elseif c == "\\" then
				return "\\\\"
			elseif c == "\n" then
				return "\\n"
			end
			return string.format("\\u%04x", string.byte(c))
		end)
		.. '"'
end
function encode(v): string
	local t = type(v)
	if t == "number" then
		return num(v)
	elseif t == "string" then
		return encodeString(v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for _, x in v do
				table.insert(parts, encode(x))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, x in v do
			table.insert(parts, encodeString(tostring(k)) .. ":" .. encode(x))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

---------------------------------------------------------------------------
-- Scene capture
---------------------------------------------------------------------------

local function cfArray(cf)
	return { cf:GetComponents() }
end

local function c3(c)
	return { c.R, c.G, c.B }
end

local function prop(inst, name)
	return D[inst] and D[inst].Props[name]
end

local function effectiveTransparency(part): number
	local t = prop(part, "Transparency") or 0
	local ltm = prop(part, "LocalTransparencyModifier") or 0
	return 1 - (1 - t) * (1 - ltm)
end

-- World frames with Motor6D / Weld chains resolved (the mock stores each
-- part's own CFrame; the engine would move Part1 with its joint).
local function resolver()
	local jointOf = {}
	for _, d in world.Workspace:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("Weld") then
			local p0, p1 = prop(d, "Part0"), prop(d, "Part1")
			if p0 and p1 and prop(d, "Enabled") ~= false then
				jointOf[p1] = d
			end
		end
	end
	local cache = {}
	local function world_(part, depth)
		local cached = cache[part]
		if cached then
			return cached
		end
		local joint = jointOf[part]
		local cf
		if joint and depth < 16 then
			local p0 = prop(joint, "Part0")
			local c0 = prop(joint, "C0") or World.Types.CFrame.identity
			local c1 = prop(joint, "C1") or World.Types.CFrame.identity
			local tr = (joint:IsA("Motor6D") and prop(joint, "Transform")) or World.Types.CFrame.identity
			cf = world_(p0, depth + 1) * c0 * tr * c1:Inverse()
		else
			cf = prop(part, "CFrame") or World.Types.CFrame.identity
		end
		cache[part] = cf
		return cf
	end
	return function(part)
		return world_(part, 0)
	end
end

local function meshOf(part)
	for _, c in part:GetChildren() do
		if c:IsA("SpecialMesh") then
			return {
				Type = tostring(prop(c, "MeshType") or "Head"):match("[^%.]+$"),
				Scale = {
					(prop(c, "Scale") or World.Types.Vector3.one).X,
					(prop(c, "Scale") or World.Types.Vector3.one).Y,
					(prop(c, "Scale") or World.Types.Vector3.one).Z,
				},
			}
		elseif c:IsA("CylinderMesh") then
			return { Type = "Cylinder" }
		end
	end
	return nil
end

local function captureScene(ctx)
	local worldCF = resolver()
	local parts, lights = {}, {}
	for _, d in world.Workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Terrain" then
			local tr = effectiveTransparency(d)
			if tr < 0.98 then
				local size = prop(d, "Size") or World.Types.Vector3.one
				local shape = d.ClassName
				if d.ClassName == "Part" or d.ClassName == "SpawnLocation" or d.ClassName == "Seat" then
					shape = tostring(prop(d, "Shape") or "Block"):match("[^%.]+$")
				end
				table.insert(parts, {
					N = d.Name,
					K = shape,
					CF = cfArray(worldCF(d)),
					S = { size.X, size.Y, size.Z },
					C = c3(prop(d, "Color") or World.Types.Color3.new(0.64, 0.64, 0.64)),
					T = tr,
					M = tostring(prop(d, "Material") or "Plastic"):match("[^%.]+$"),
					R = prop(d, "Reflectance") or 0,
					Mesh = meshOf(d),
				})
			end
		elseif d:IsA("Light") and prop(d, "Enabled") ~= false then
			local parent = d.Parent
			local cf
			if parent and parent:IsA("BasePart") then
				cf = worldCF(parent)
			elseif parent and parent:IsA("Attachment") then
				local p = parent.Parent
				local base = if p and p:IsA("BasePart") then worldCF(p) else World.Types.CFrame.identity
				cf = base * (prop(parent, "CFrame") or World.Types.CFrame.identity)
			end
			if cf then
				table.insert(lights, {
					K = d.ClassName,
					CF = cfArray(cf),
					C = c3(prop(d, "Color") or World.Types.Color3.new(1, 1, 1)),
					B = prop(d, "Brightness") or 1,
					Range = prop(d, "Range") or 8,
					Angle = prop(d, "Angle") or 90,
					Face = tostring(prop(d, "Face") or "Front"):match("[^%.]+$"),
				})
			end
		end
	end
	local L = world.Services.Lighting
	local lighting = {
		Ambient = c3(prop(L, "Ambient") or World.Types.Color3.new(0.3, 0.3, 0.3)),
		OutdoorAmbient = c3(prop(L, "OutdoorAmbient") or World.Types.Color3.new(0.5, 0.5, 0.5)),
		Brightness = prop(L, "Brightness") or 2,
		ClockTime = prop(L, "ClockTime") or 14,
		FogColor = c3(prop(L, "FogColor") or World.Types.Color3.new(0.75, 0.75, 0.75)),
		FogStart = prop(L, "FogStart") or 0,
		FogEnd = prop(L, "FogEnd") or 100000,
		Exposure = prop(L, "ExposureCompensation") or 0,
		Effects = {},
	}
	for _, e in L:GetChildren() do
		if e:IsA("ColorCorrectionEffect") and prop(e, "Enabled") ~= false then
			table.insert(lighting.Effects, {
				K = "CC",
				Brightness = prop(e, "Brightness") or 0,
				Contrast = prop(e, "Contrast") or 0,
				Saturation = prop(e, "Saturation") or 0,
				Tint = c3(prop(e, "TintColor") or World.Types.Color3.new(1, 1, 1)),
			})
		elseif e:IsA("Atmosphere") then
			table.insert(lighting.Effects, {
				K = "Atmosphere",
				Density = prop(e, "Density") or 0.3,
				Color = c3(prop(e, "Color") or World.Types.Color3.new(0.78, 0.78, 0.78)),
				Haze = prop(e, "Haze") or 0,
			})
		elseif e:IsA("BlurEffect") and prop(e, "Enabled") ~= false then
			table.insert(lighting.Effects, { K = "Blur", Size = prop(e, "Size") or 0 })
		end
	end
	local cam = ctx.Camera
	return {
		Parts = parts,
		Lights = lights,
		Lighting = lighting,
		Camera = {
			CF = cfArray(prop(cam, "CFrame") or World.Types.CFrame.new(0, 10, 20)),
			Fov = prop(cam, "FieldOfView") or 70,
		},
	}
end

---------------------------------------------------------------------------
-- GUI capture (the raw tree; tools/render lays it out like the engine)
---------------------------------------------------------------------------

local GUI_PROPS = {
	"Size",
	"Position",
	"AnchorPoint",
	"BackgroundColor3",
	"BackgroundTransparency",
	"BorderSizePixel",
	"Visible",
	"ZIndex",
	"LayoutOrder",
	"ClipsDescendants",
	"Rotation",
	"AutomaticSize",
	"Text",
	"TextColor3",
	"TextTransparency",
	"TextSize",
	"TextScaled",
	"TextWrapped",
	"TextXAlignment",
	"TextYAlignment",
	"Font",
	"RichText",
	"Image",
	"ImageColor3",
	"ImageTransparency",
	"ScaleType",
	"CanvasSize",
	"Enabled",
	"DisplayOrder",
	"IgnoreGuiInset",
	"ZIndexBehavior",
	-- layouts and modifiers
	"FillDirection",
	"HorizontalAlignment",
	"VerticalAlignment",
	"SortOrder",
	"Padding",
	"PaddingTop",
	"PaddingBottom",
	"PaddingLeft",
	"PaddingRight",
	"CornerRadius",
	"Thickness",
	"Color",
	"Transparency",
	"ApplyStrokeMode",
	"CellSize",
	"CellPadding",
	"FillDirectionMaxCells",
	"AspectRatio",
	"DominantAxis",
	"AspectType",
	"MaxSize",
	"MinSize",
	"MaxTextSize",
	"MinTextSize",
	"Scale",
	"Offset",
	"Wraps",
	"HorizontalFlex",
	"VerticalFlex",
	"FlexMode",
}

local function encodeValue(v)
	local t = World.Types.typeof(v)
	if t == "UDim2" then
		return { "U2", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
	elseif t == "UDim" then
		return { "U", v.Scale, v.Offset }
	elseif t == "Vector2" then
		return { "V2", v.X, v.Y }
	elseif t == "Color3" then
		return { "C3", v.R, v.G, v.B }
	elseif t == "EnumItem" then
		return tostring(v):match("[^%.]+$")
	elseif t == "ColorSequence" then
		local kp = v.Keypoints[1]
		return { "C3", kp.Value.R, kp.Value.G, kp.Value.B }
	elseif t == "NumberSequence" then
		return v.Keypoints[1].Value
	elseif t == "number" or t == "string" or t == "boolean" then
		return v
	end
	return nil
end

local function captureGui(ctx)
	local function node(inst)
		local out = { K = inst.ClassName, N = inst.Name, P = {}, Ch = {} }
		for _, key in GUI_PROPS do
			local v = prop(inst, key)
			if v ~= nil then
				local e = encodeValue(v)
				if e ~= nil then
					out.P[key] = e
				end
			end
		end
		if inst:IsA("UIGradient") then
			local seq = prop(inst, "Color")
			if seq then
				local keys = {}
				for _, kp in seq.Keypoints do
					table.insert(keys, { kp.Time, kp.Value.R, kp.Value.G, kp.Value.B })
				end
				out.P.Keys = keys
			end
			local tseq = prop(inst, "Transparency")
			if tseq then
				local tkeys = {}
				for _, kp in tseq.Keypoints do
					table.insert(tkeys, { kp.Time, kp.Value })
				end
				out.P.TKeys = tkeys
			end
		end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			local f = prop(inst, "FontFace")
			if f then
				out.P.Weight = tostring(f.Weight):match("[^%.]+$")
				out.P.Family = tostring(f.Family)
			end
		end
		for _, c in inst:GetChildren() do
			if c:IsA("GuiBase2d") or c:IsA("UIBase") or c:IsA("UIComponent") then
				table.insert(out.Ch, node(c))
			end
		end
		return out
	end
	local roots = {}
	for _, g in ctx.Player.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") then
			table.insert(roots, node(g))
		end
	end
	return { Viewport = { Instances.viewport.X, Instances.viewport.Y }, Roots = roots }
end

local frameIndex = 0
local function snap(ctx, label: string)
	frameIndex += 1
	local name = string.format("%s/%02d_%s.json", outDir, frameIndex, label)
	local data = { Label = label, Time = Scheduler.now, Scene = captureScene(ctx), Gui = captureGui(ctx) }
	assert(__writefile(name, encode(data)), "could not write " .. name)
	print("wrote " .. name .. string.format("  (%d parts)", #data.Scene.Parts))
end

---------------------------------------------------------------------------
-- Scenarios
---------------------------------------------------------------------------

world:start()
Scheduler.run(3)
local ada, ctx = world:addPlayer(1001, "Ada")
Scheduler.run(6)
-- Dismiss the orientation offer so it doesn't cover the view.
pcall(function()
	run(ctx, function()
		ctl(ctx, "UIController"):close()
		world:require(ctx, ctx.Player.PlayerScripts.VarianceClient.UI.Kit).dismiss("Offer")
	end)
end)
Scheduler.run(1)

if scenario == "lobby" then
	snap(ctx, "lobby")
	return
end

if scenario == "screens" then
	local ui = ctl(ctx, "UIController")
	for _, name in { "Play", "Private", "Ranked", "Locker", "Archive", "Challenges", "Record", "Settings" } do
		run(ctx, function()
			ui:open(name)
		end)
		Scheduler.run(1.2)
		snap(ctx, "screen_" .. name)
		run(ctx, function()
			ui:close()
		end)
		Scheduler.run(0.5)
	end
	return
end

request(ctx, "Solo.Start", "Volta", "Standard")
if scenario == "seat" then
	local step = tonumber(arg[3]) or 0.25
	local span = tonumber(arg[4]) or 7
	local t = 0
	while t <= span do
		snap(ctx, string.format("t%05.2f", t))
		Scheduler.run(step, 60)
		t += step
	end
	return
end

if scenario == "turn" then
	-- Your turn: fire at yourself or the opponent (arg 3), then watch the
	-- surrogate's turn. Frames every `step` seconds.
	local choice = arg[3] or "FireOther"
	local step = tonumber(arg[4]) or 0.2
	local pattern = arg[5] -- e.g. "CCCC" forces the loaded cells
	local client = ctl(ctx, "MatchClient")
	Scheduler.runUntil(function()
		return client:isMyTurn() and not client:busy()
	end, 90, 60)
	if pattern then
		print(request(ctx, "Debug.Command", "Sequence", { Pattern = pattern, Now = true }))
	end
	Scheduler.run(0.5, 60)
	snap(ctx, "my_turn")
	local hud = ctl(ctx, "UIController"):screen("MatchHUD")
	run(ctx, function()
		hud:pressFire(choice, "Begin", true)
		hud:pressFire(choice, "Begin", true)
	end)
	local t = 0
	while t < 8 do
		Scheduler.run(step, 60)
		t += step
		snap(ctx, string.format("fire_%05.2f", t))
	end
	return
end

if scenario == "ending" then
	-- The winning shot of a match and the results screen: the surrogate is
	-- left on one Integrity with a CHARGED cell loaded, one Trial from losing.
	local client = ctl(ctx, "MatchClient")
	Scheduler.runUntil(function()
		return client:isMyTurn() and not client:busy()
	end, 90, 60)
	print(request(ctx, "Debug.Command", "SkipToTrial", { Trial = 2 }))
	Scheduler.runUntil(function()
		return client:isMyTurn() and not client:busy()
	end, 90, 60)
	local state = client.State
	if state then
		local s1 = state.Subjects[1]
		if s1 then
			s1.TrialWins = 1
		end
	end
	print(request(ctx, "Debug.Command", "Integrity", { Subject = 2, Value = 1 }))
	for _ = 1, 200 do
		Scheduler.runUntil(function()
			return client:isMyTurn() and not client:busy()
		end, 90, 60)
		if request(ctx, "Debug.Command", "Sequence", { Pattern = "CCCC", Now = true }) then
			break
		end
		Scheduler.run(0.2, 60)
	end
	Scheduler.run(0.5, 60)
	local hud = ctl(ctx, "UIController"):screen("MatchHUD")
	run(ctx, function()
		hud:pressFire("FireOther", "Begin", true)
		hud:pressFire("FireOther", "Begin", true)
	end)
	local t = 0
	while t < 24 do
		Scheduler.run(0.75, 60)
		t += 0.75
		snap(ctx, string.format("end_%05.2f", t))
	end
	return
end

if scenario == "results" then
	-- Plays the whole match through the HUD (fire at the likelier target),
	-- then captures the results screen as it fills in.
	local client = ctl(ctx, "MatchClient")
	local hud = ctl(ctx, "UIController"):screen("MatchHUD")
	local ui = ctl(ctx, "UIController")
	local acted = nil
	local finished = Scheduler.runUntil(function()
		if ui:currentScreen() == "PostMatch" then
			return true
		end
		if client:isMyTurn() and not client:busy() and client.TurnInfo and client.TurnInfo.Token ~= acted then
			acted = client.TurnInfo.Token
			local p = client:probability() or 0.5
			local choice = if p < 0.4 then "FireSelf" else "FireOther"
			Scheduler.spawnIn(ctx, function()
				hud:pressFire(choice, "Begin", true)
				hud:pressFire(choice, "Begin", true)
			end)
		end
		return false
	end, 1200, 30)
	print("match finished:", finished)
	for i = 1, 6 do
		Scheduler.run(0.8, 30)
		snap(ctx, string.format("results_%d", i))
	end
	return
end

if scenario == "match" then
	Scheduler.runUntil(function()
		return ctl(ctx, "MatchClient"):isMyTurn()
	end, 60, 60)
	snap(ctx, "first_turn")
	return
end
