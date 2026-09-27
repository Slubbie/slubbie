-- Game configuration root.
--
-- Every balancing number and every piece of content lives in the ModuleScripts
-- inside this folder, one per domain. Code requires the domain it needs directly
-- (require(Shared.Config.Crops)) for type information; this table also lazily
-- exposes them (Config.Crops) for convenience in tooling and the admin panel.
--
-- Adding content (a crop, fish, NPC, machine, quest...) means adding an entry to
-- the relevant module: registries, collections, shops and the UI pick it up
-- automatically. Run the test suite (see README) after editing: it validates
-- every cross-reference between modules.

local Config = {}

setmetatable(Config, {
	__index = function(self, key)
		local child = script:FindFirstChild(key)
		if child and child:IsA("ModuleScript") then
			local value = (require :: any)(child)
			rawset(self, key, value)
			return value
		end
		error("Config." .. tostring(key) .. " does not exist", 2)
	end,
})

return Config
