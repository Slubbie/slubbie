-- Service locator.
--
-- Every server system is a ModuleScript in this folder returning a table with
-- optional Init() and Start(). Services reach each other through this table
-- at call time (S.Inventory.Add(...)), never at require time, so there are no
-- require cycles and the load order only matters for Init/Start.
--
--   local S = require(script.Parent)
--   S.Data.Get(player)

local Services = {}

local NAMES = {
	-- short name → module name
	Security = "SecurityService",
	Data = "DataService",
	Notify = "NotifyService",
	Time = "TimeService",
	Season = "SeasonService",
	Weather = "WeatherService",
	World = "WorldService",
	Player = "PlayerService",
	Inventory = "InventoryService",
	Item = "ItemService",
	Permission = "PermissionService",
	Farm = "FarmService",
	Soil = "SoilService",
	Crop = "CropService",
	Building = "BuildingService",
	Decoration = "DecorationService",
	Tool = "ToolService",
	Machine = "MachineService",
	Automation = "AutomationService",
	Animal = "AnimalService",
	Breeding = "BreedingService",
	Crafting = "CraftingService",
	Market = "MarketService",
	Economy = "EconomyService",
	Skill = "SkillService",
	Friendship = "FriendshipService",
	NPC = "NPCService",
	Quest = "QuestService",
	Collection = "CollectionBookService",
	Achievement = "AchievementService",
	Mining = "MiningService",
	Foraging = "ForagingService",
	Fishing = "FishingService",
	Town = "TownService",
	Festival = "EventService",
	Multiplayer = "MultiplayerService",
	Trading = "TradingService",
	Guild = "GuildService",
	Mail = "MailService",
	Daily = "DailyService",
	Store = "StoreService",
	Tutorial = "TutorialService",
	Admin = "AdminDebugService",
}

-- Init/Start order: data and clock first, gameplay next, then social/meta systems.
Services.Order = {
	"Security",
	"Data",
	"Notify",
	"Time",
	"Season",
	"Weather",
	"World",
	"Player",
	"Inventory",
	"Item",
	"Permission",
	"Skill",
	"Collection",
	"Achievement",
	"Quest",
	"Farm",
	"Soil",
	"Crop",
	"Building",
	"Decoration",
	"Machine",
	"Automation",
	"Animal",
	"Breeding",
	"Tool",
	"Crafting",
	"Market",
	"Economy",
	"Friendship",
	"NPC",
	"Mining",
	"Foraging",
	"Fishing",
	"Town",
	"Festival",
	"Multiplayer",
	"Trading",
	"Guild",
	"Mail",
	"Daily",
	"Store",
	"Tutorial",
	"Admin",
}

local loaded: { [string]: any } = {}

setmetatable(Services, {
	__index = function(_, key)
		local cached = loaded[key]
		if cached then
			return cached
		end
		local moduleName = NAMES[key]
		if not moduleName then
			error("Unknown service '" .. tostring(key) .. "'", 2)
		end
		local module = script:FindFirstChild(moduleName)
		assert(module and module:IsA("ModuleScript"), "Missing service module " .. moduleName)
		local service = (require :: any)(module)
		loaded[key] = service
		return service
	end,
})

-- Require, Init and Start every service in order. Errors in one service are
-- reported but don't stop the others from starting.
function Services.Boot()
	local started = os.clock()
	for _, key in Services.Order do
		local service = Services[key]
		if type(service.Init) == "function" then
			local ok, err = pcall(service.Init)
			if not ok then
				warn(string.format("[Evergrove] %s.Init failed: %s", key, tostring(err)))
			end
		end
	end
	for _, key in Services.Order do
		local service = Services[key]
		if type(service.Start) == "function" then
			local ok, err = pcall(service.Start)
			if not ok then
				warn(string.format("[Evergrove] %s.Start failed: %s", key, tostring(err)))
			end
		end
	end
	print(string.format("[Evergrove] %d services started in %.2fs", #Services.Order, os.clock() - started))
end

return Services
