-- The client's copy of the player's profile, kept in sync by the server.
--
-- Read with State.Get("Courses"), listen with State.Changed (section) or
-- State.On("Courses", fn). Derived values (level, abilities) are cached here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Shared.Config.Abilities)
local Leveling = require(ReplicatedStorage.Shared.Logic.Leveling)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local State = {}

State.Profile = nil :: { [string]: any }?
State.Persistent = true
State.Loaded = Signal.new() -- ()
State.Changed = Signal.new() -- (section)

local listeners: { [string]: { (any) -> () } } = {}

function State.Get(section: string): any
	return State.Profile and State.Profile[section]
end

function State.On(section: string, fn: (any) -> ())
	local list = listeners[section]
	if not list then
		list = {}
		listeners[section] = list
	end
	table.insert(list, fn)
	if State.Profile then
		task.spawn(fn, State.Profile[section])
	end
end

local function notify(section: string)
	State.Changed:Fire(section)
	for _, fn in (listeners[section] or {}) :: { (any) -> () } do
		task.spawn(fn, State.Profile and State.Profile[section])
	end
end

function State.Level(): number
	local profile = State.Profile
	if not profile then
		return 1
	end
	return (Leveling.FromXP(profile.XP or 0))
end

function State.Abilities(): { [string]: boolean }
	return Abilities.ForLevel(State.Level())
end

function State.Has(abilityId: string): boolean
	return State.Abilities()[abilityId] == true
end

-- Block until the profile has arrived (or the timeout passes).
function State.Await(timeout: number?): boolean
	local deadline = os.clock() + (timeout or 30)
	while not State.Profile and os.clock() < deadline do
		task.wait(0.1)
	end
	return State.Profile ~= nil
end

function State.Start()
	Net.Listen("Profile.Full", function(profile, persistent)
		State.Profile = profile
		State.Persistent = persistent ~= false
		State.Loaded:Fire()
		for section in profile do
			notify(section)
		end
	end)
	Net.Listen("Profile.Section", function(section, value)
		if not State.Profile then
			return
		end
		State.Profile[section] = value
		notify(section)
	end)
	-- In case the full profile was pushed before we listened.
	task.spawn(function()
		task.wait(2)
		if not State.Profile then
			local profile, persistent = Net.Invoke("Profile.Get")
			if profile and not State.Profile then
				State.Profile = profile
				State.Persistent = persistent ~= false
				State.Loaded:Fire()
				for section in profile do
					notify(section)
				end
			end
		end
	end)
end

return State
