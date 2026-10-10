-- Creature ownership: sealed comet cores, opening them, the collection
-- record, release and lock/favourite flags.
--
-- Rewards are rolled here, on the server, with the server's Random at the
-- moment a core is opened. Opening removes the core and adds the creature in
-- one non-yielding step, so a disconnect during the reveal animation can
-- neither lose nor duplicate the creature (the animation is cosmetic and
-- runs after the grant).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureDefinitions = require(Shared.CreatureDefinitions)
local EconomyMath = require(Shared.EconomyMath)
local GameConfig = require(Shared.GameConfig)
local ProfileTypes = require(Shared.ProfileTypes)
local RarityConfig = require(Shared.RarityConfig)
local Signal = require(Shared.Signal)

local ProfileSchema = require(script.Parent.Parent.Data.ProfileSchema)

local CreatureService = { Name = "CreatureService" }

-- (player, core)
CreatureService.CoreGranted = Signal.new()
-- (player, core, creature, isNewSpecies)
CreatureService.CoreOpened = Signal.new()
-- (player, creature, isNewSpecies)
CreatureService.CreatureObtained = Signal.new()
-- (player, creatureId)
CreatureService.CreatureReleased = Signal.new()

local services: { [string]: any } = {}

-- Server-side randomness. Tests may swap this for a seeded or scripted RNG.
CreatureService.Random = Random.new()

function CreatureService.CountCreatures(profile: ProfileTypes.Profile): number
	local count = 0
	for _ in profile.Creatures do
		count += 1
	end
	return count
end

function CreatureService.CountCores(profile: ProfileTypes.Profile): number
	local count = 0
	for _ in profile.Cores do
		count += 1
	end
	return count
end

function CreatureService.GetCreature(player: Player, creatureId: string): ProfileTypes.CreatureRecord?
	local profile = services.PlayerDataService.GetProfile(player)
	return profile and profile.Creatures[creatureId]
end

-- The habitat slot (as a string key) holding a creature, if any.
function CreatureService.FindSlot(profile: ProfileTypes.Profile, creatureId: string): string?
	for slot, id in profile.EquippedCreatures do
		if id == creatureId then
			return slot
		end
	end
	return nil
end

-- Rolls a species and mutation for a biome. Server only.
function CreatureService.Roll(biomeId: string, modifiers: RarityConfig.Modifiers?): (string, string)
	local rng = CreatureService.Random
	local rarity = RarityConfig.RollRarity(rng, modifiers)
	local pool = CreatureDefinitions.Pool(biomeId, rarity)
	if #pool == 0 then
		-- Validation prevents this; fall back safely rather than erroring.
		warn(`[Creature] Empty pool for {biomeId}/{rarity}; using the starter species`)
		pool = { GameConfig.Tutorial.StarterSpecies }
	end
	local species = pool[math.floor(rng:NextNumber() * #pool) + 1] or pool[#pool]
	local mutation = RarityConfig.RollMutation(rng, modifiers)
	return species, mutation
end

-- Adds a sealed core. Returns the core, or nil and a reason (storage full).
function CreatureService.GrantCore(
	player: Player,
	kind: string,
	biomeId: string,
	cometType: string,
	quality: number
): (ProfileTypes.CoreRecord?, string?)
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return nil, "NotReady"
	end
	if CreatureService.CountCores(profile) >= GameConfig.Inventory.MaxCores then
		return nil, "CoreStorageFull"
	end
	local serial = profile.NextCoreSerial
	profile.NextCoreSerial += 1
	local core: ProfileTypes.CoreRecord = {
		Id = ProfileSchema.CoreId(serial),
		Kind = kind,
		Biome = biomeId,
		CometType = cometType,
		Quality = math.clamp(quality, 0, 1),
		Obtained = os.time(),
	}
	profile.Cores[core.Id] = core
	services.ReplicationService.Set(player, { "Cores", core.Id }, core)
	services.ReplicationService.Set(player, { "NextCoreSerial" }, profile.NextCoreSerial)
	CreatureService.CoreGranted:Fire(player, core)
	return core, nil
end

-- Creates a creature record (used by OpenCore and future systems such as events).
function CreatureService.AddCreature(
	player: Player,
	speciesId: string,
	mutation: string,
	origin: string,
	biomeId: string
): (ProfileTypes.CreatureRecord?, boolean, string?)
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return nil, false, "NotReady"
	end
	if not CreatureDefinitions.IsSpecies(speciesId) or not RarityConfig.IsMutation(mutation) then
		return nil, false, "InvalidCreature"
	end
	if CreatureService.CountCreatures(profile) >= GameConfig.Inventory.MaxCreatures then
		return nil, false, "InventoryFull"
	end
	local serial = profile.NextCreatureSerial
	profile.NextCreatureSerial += 1
	local id = ProfileSchema.CreatureId(player.UserId, serial)
	assert(profile.Creatures[id] == nil, "creature id collision")
	local now = os.time()
	local creature: ProfileTypes.CreatureRecord = {
		Id = id,
		Species = speciesId,
		Mutation = mutation,
		Bond = 1,
		Obtained = now,
		Locked = origin == "Starter",
		Favorite = false,
		Origin = origin,
		Biome = biomeId,
	}
	profile.Creatures[id] = creature

	local discovery = profile.DiscoveredSpecies[speciesId]
	local isNew = discovery == nil
	if isNew then
		discovery = { First = now, Count = 0, Mutations = {} }
		profile.DiscoveredSpecies[speciesId] = discovery
	end
	assert(discovery)
	discovery.Count += 1
	discovery.Mutations[mutation] = true

	services.ReplicationService.Set(player, { "Creatures", id }, creature)
	services.ReplicationService.Set(player, { "NextCreatureSerial" }, profile.NextCreatureSerial)
	services.ReplicationService.Set(player, { "DiscoveredSpecies", speciesId }, discovery)
	CreatureService.CreatureObtained:Fire(player, creature, isNew)
	return creature, isNew, nil
end

-- Opens a sealed core: rolls the creature and swaps core → creature atomically.
function CreatureService.OpenCore(player: Player, coreId: string): { [string]: any }
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "NotReady" }
	end
	local core = profile.Cores[coreId]
	if not core then
		return { Ok = false, Reason = "NoSuchCore" }
	end
	if CreatureService.CountCreatures(profile) >= GameConfig.Inventory.MaxCreatures then
		return { Ok = false, Reason = "InventoryFull" }
	end

	local speciesId, mutation
	if core.Kind == "Starter" then
		speciesId, mutation = GameConfig.Tutorial.StarterSpecies, "Standard"
	else
		speciesId, mutation = CreatureService.Roll(core.Biome)
	end

	-- No yields from here until the creature exists.
	profile.Cores[coreId] = nil
	services.ReplicationService.Set(player, { "Cores", coreId }, nil)
	local creature, isNew, reason = CreatureService.AddCreature(
		player,
		speciesId,
		mutation,
		if core.Kind == "Starter" then "Starter" else "Capture",
		core.Biome
	)
	if not creature then
		-- Put the core back; nothing was lost.
		profile.Cores[coreId] = core
		services.ReplicationService.Set(player, { "Cores", coreId }, core)
		return { Ok = false, Reason = reason }
	end
	profile.Stats.CoresOpened = (profile.Stats.CoresOpened or 0) + 1
	CreatureService.CoreOpened:Fire(player, core, creature, isNew)

	local species = CreatureDefinitions.Get(speciesId)
	local rarityIndex = if species then RarityConfig.RarityIndex(species.Rarity) else 1
	if rarityIndex >= RarityConfig.RarityIndex("Epic") or mutation ~= "Standard" then
		-- Valuable: save soon rather than waiting for the next autosave.
		services.PlayerDataService.RequestSave(player)
		services.AnalyticsService.Custom(player, "RareDiscovery", rarityIndex)
	end
	return { Ok = true, Creature = creature, IsNew = isNew, Core = core }
end

-- Releases a creature for a little Stardust. Locked, favourite and deployed
-- creatures are protected.
function CreatureService.Release(player: Player, creatureId: string): { [string]: any }
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "NotReady" }
	end
	local creature = profile.Creatures[creatureId]
	if not creature then
		return { Ok = false, Reason = "NotOwned" }
	end
	if creature.Locked or creature.Favorite then
		return { Ok = false, Reason = "Protected" }
	end
	if CreatureService.FindSlot(profile, creatureId) then
		return { Ok = false, Reason = "Deployed" }
	end
	local value = EconomyMath.ReleaseValue(creature)
	profile.Creatures[creatureId] = nil
	services.ReplicationService.Set(player, { "Creatures", creatureId }, nil)
	services.EconomyService.Grant(player, "Stardust", value, "Release")
	CreatureService.CreatureReleased:Fire(player, creatureId)
	return { Ok = true, Stardust = value }
end

function CreatureService.SetFlag(player: Player, creatureId: string, flag: string, value: boolean): { [string]: any }
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "NotReady" }
	end
	local creature = profile.Creatures[creatureId]
	if not creature then
		return { Ok = false, Reason = "NotOwned" }
	end
	if flag ~= "Locked" and flag ~= "Favorite" then
		return { Ok = false, Reason = "BadFlag" }
	end
	(creature :: any)[flag] = value
	services.ReplicationService.Set(player, { "Creatures", creatureId, flag }, value)
	return { Ok = true }
end

function CreatureService.Init(registry: { [string]: any })
	services = registry
end

function CreatureService.Start()
	local security = services.SecurityService
	security.BindFunction("OpenComet", function(player, coreId)
		return CreatureService.OpenCore(player, coreId)
	end)
	security.BindFunction("ReleaseCreature", function(player, creatureId)
		return CreatureService.Release(player, creatureId)
	end)
	security.BindFunction("SetCreatureFlag", function(player, creatureId, flag, value)
		return CreatureService.SetFlag(player, creatureId, flag, value)
	end)
end

return CreatureService
