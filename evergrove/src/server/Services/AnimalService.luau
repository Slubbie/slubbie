-- Livestock: buying, housing, daily care, happiness, friendship, products,
-- selling, naming and riding.
--
-- profile.Farm.Animals[aid] = {
--   Sp   species id           Nm  name            G  genes (Lib/Genetics)
--   Pe   personality id       Home placed uid     Born unix
--   Hap  happiness 0-100      Fr  friendship 0-1000
--   Fed  day index last fed   Pet / Br  day index last petted / brushed
--   Tr   day index of last treat
--   Last game time the current product cycle started
--   Rd   products ready (count, capped)   RdQ quality of the ready product
--   Upd  game time happiness was last updated
--   Bred game time last bred    Preg { Due, G, Sire } while expecting
-- }
--
-- Everything is computed lazily from timestamps (`settle`), so animals cost
-- nothing while nobody looks and progress correctly while you're offline
-- (at most Animals.OfflineCycles products accrue).
--
-- Rendering: each animal has a tiny anchor part in the farm's Animals folder
-- with attributes (species, coat, pattern, size, name, mood, ready...). The
-- client builds the model and animates wandering/idles around its home.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Animals = require(Shared.Config.Animals)
local Net = require(Shared.Lib.Net)
local Signal = require(Shared.Lib.Signal)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Genetics = require(Shared.Lib.Genetics)
local GameTime = require(Shared.Lib.GameTime)
local WeatherMath = require(Shared.Lib.WeatherMath)
local QualityMath = require(Shared.Lib.QualityMath)
local Stats = require(Shared.Lib.Stats)
local RNG = require(Shared.Lib.RNG)
local Format = require(Shared.Lib.Format)

local S = require(script.Parent)

local HOUR = GameTime.HOUR
local ANIMAL_REACH = 40
local random = Random.new()

local AnimalService = {}
AnimalService.Produced = Signal.new() -- (player, aid, stack) collected
AnimalService.Born = Signal.new() -- (player, aid)

local speciesById: { [string]: any } = {}
for _, species in Animals.List do
	speciesById[species.Id] = species
end
local personalityById: { [string]: any } = {}
for _, p in Animals.Personalities do
	personalityById[p.Id] = p
end

-- Helpers ------------------------------------------------------------------------------------------------

function AnimalService.Species(id: string)
	return speciesById[id]
end

local function personality(animal: any)
	return personalityById[animal.Pe] or Animals.Personalities[1]
end

local function homeDef(profile: any, uid: string?)
	local record = uid and profile.Farm.Placed[uid]
	local def = record and Registry.Placeables[record.Id]
	if def and def.Function and def.Function.Kind == "Animal" then
		return def, record
	end
	return nil, nil
end

function AnimalService.Residents(profile: any, uid: string): number
	local n = 0
	for _, animal in profile.Farm.Animals do
		if animal.Home == uid then
			n += 1
		end
	end
	return n
end

function AnimalService.Count(profile: any): number
	local n = 0
	for _ in profile.Farm.Animals do
		n += 1
	end
	return n
end

local function badWeather(t: number): boolean
	local def = WeatherMath.Def(WeatherMath.Current(t))
	return def ~= nil and (def.Animals < 0 or def.Visual.Wind >= 0.8 or def.Hazard ~= nil)
end

-- Is the animal's home on a Pasture parcel (happier animals)?
local function onPasture(profile: any, animal: any): boolean
	local record = profile.Farm.Placed[animal.Home]
	if not record then
		return false
	end
	local gx, gz = S.Building.CenterTile(record)
	local row, col = S.Farm.ParcelOf(gx, gz)
	if not row then
		return false
	end
	local ptype = S.Farm.ParcelType(row :: number, col :: number)
	return table.find(ptype.Tags, "Pasture") ~= nil
end

-- Product interval in game seconds.
function AnimalService.Interval(profile: any, animal: any): number
	local species = speciesById[animal.Sp]
	local rate = 1 + Stats.Effect(profile, "ProductSpeed") + (animal.G.Speed or 5) * 0.02
	rate *= personality(animal).Rate or 1
	return species.Interval * HOUR / math.max(0.2, rate)
end

-- Bring happiness and products up to `t`.
local function settle(player: Player, profile: any, animal: any, t: number)
	local species = speciesById[animal.Sp]
	if not species then
		return
	end
	local today = GameTime.DayIndex(t)
	-- Happiness drifts toward a target set by care.
	local last = animal.Upd or t
	local hours = math.clamp((t - last) / HOUR, 0, 24 * 3)
	if hours > 0 then
		local pers = personality(animal)
		local delta = 0
		local fedRecently = (animal.Fed or -99) >= today - 1
		if not fedRecently then
			delta += Animals.HungryHappinessPerHour * hours
		else
			-- Content animals slowly get happier on their own.
			delta += 0.6 * hours * (pers.Happiness or 1)
		end
		if species.Outside and badWeather(t) then
			-- Animals shelter indoors, but storms still unsettle them.
			delta += Animals.BadWeatherHappiness * 0.3 * hours
		end
		if onPasture(profile, animal) then
			delta += 0.3 * hours
		end
		animal.Hap = math.clamp((animal.Hap or 60) + delta, 0, 100)
	end
	animal.Upd = t
	-- Products: one per interval while fed; capped.
	animal.Last = animal.Last or t
	local interval = AnimalService.Interval(profile, animal)
	local cycles = math.floor((t - animal.Last) / interval)
	if cycles > 0 then
		local fedRecently = (animal.Fed or -99) >= GameTime.DayIndex(animal.Last + interval) - 1
		local cap = Animals.OfflineCycles
		if fedRecently and (animal.Hap or 0) >= 10 then
			local before = animal.Rd or 0
			animal.Rd = math.min(cap, before + cycles)
			if animal.Rd > before then
				animal.RdQ = AnimalService.QualityFor(profile, animal)
			end
		end
		animal.Last += cycles * interval
		if t - animal.Last > interval then
			animal.Last = t
		end
	end
	-- Pregnancy
	if animal.Preg and t >= animal.Preg.Due then
		AnimalService.Deliver(player, profile, animal)
	end
end

function AnimalService.QualityFor(profile: any, animal: any): number
	local pers = personality(animal)
	local score = 0.2
		+ 0.3 * (animal.Hap or 0) / 100
		+ 0.35 * (animal.Fr or 0) / Animals.MaxFriendship
		+ 0.1 * (animal.G.Yield or 5) / 10
		+ (pers.Quality or 0)
		+ Stats.Effect(profile, "AnimalQuality") / 10
	if (animal.Fed or -99) >= GameTime.DayIndex(GameTime.Now()) and animal.Prem then
		score += 0.05 -- premium feed today
	end
	return QualityMath.TierFor(math.clamp(score, 0, 1), 6)
end

-- Product for this animal (coat products, flavoured honey).
local function productId(profile: any, animal: any): string
	local species = speciesById[animal.Sp]
	local phenotype = Genetics.Phenotype(animal.Sp, animal.G)
	local override = species.CoatProducts and species.CoatProducts[phenotype.Coat.Id]
	if override and Registry.Items[override] then
		return override
	end
	if animal.Sp == "bee" then
		-- Flavoured by the most common flower growing near the apiary.
		local record = profile.Farm.Placed[animal.Home]
		if record then
			local def = Registry.Placeables[record.Id]
			local cx, cz = S.Building.CenterTile(record)
			local r = (def and def.Radius or 6) + 2
			local counts = {}
			for key, tile in profile.Farm.Tiles do
				if tile.C and Registry.HasTag(tile.C.Id, "Flower") then
					local gx, gz = S.Farm.ParseKey(key)
					if math.abs(gx - cx) <= r and math.abs(gz - cz) <= r then
						counts[tile.C.Id] = (counts[tile.C.Id] or 0) + 1
					end
				end
			end
			local best, bestN = nil, 0
			for id, n in counts do
				if n > bestN then
					best, bestN = id, n
				end
			end
			if best and Registry.Items["honey_" .. best] then
				return "honey_" .. best
			end
		end
	end
	return species.Product
end

-- Anchors ---------------------------------------------------------------------------------------------------

local anchors: { [Player]: { [string]: BasePart } } = {}

local function mood(animal: any, today: number): string
	if (animal.Fed or -99) < today - 1 then
		return "Hungry"
	elseif (animal.Hap or 0) >= 80 then
		return "Joyful"
	elseif (animal.Hap or 0) >= 50 then
		return "Content"
	elseif (animal.Hap or 0) >= 25 then
		return "Glum"
	end
	return "Sad"
end

function AnimalService.Render(player: Player, aid: string)
	local profile = S.Data.Get(player)
	local farm = S.Farm.Get(player)
	if not profile or not farm then
		return
	end
	local animal = profile.Farm.Animals[aid]
	anchors[player] = anchors[player] or {}
	local part = anchors[player][aid]
	if not animal then
		if part then
			part:Destroy()
			anchors[player][aid] = nil
		end
		return
	end
	local homePos = S.Building.WorldPosition(player, animal.Home)
	if not homePos then
		return
	end
	if not part then
		local p = Instance.new("Part")
		p.Name = aid
		p.Size = Vector3.new(1, 1, 1)
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = farm.Animals
		anchors[player][aid] = p
		part = p
	end
	local record = profile.Farm.Placed[animal.Home]
	local def = record and Registry.Placeables[record.Id]
	part.Position = homePos
	local phenotype = Genetics.Phenotype(animal.Sp, animal.G)
	local today = GameTime.DayIndex(GameTime.Now())
	local attrs = {
		Sp = animal.Sp,
		Nm = animal.Nm,
		Coat = phenotype.Coat.Id,
		Pattern = phenotype.Pattern.Id,
		Size = math.floor(phenotype.Size * 100) / 100,
		Pe = animal.Pe,
		Mood = mood(animal, today),
		Ready = (animal.Rd or 0) > 0,
		Baby = (os.time() - (animal.Born or 0)) < 3 * 3600,
		Preg = animal.Preg ~= nil,
		Home = animal.Home,
		HomeW = def and def.Size[1] * 4 or 12,
		HomeD = def and def.Size[2] * 4 or 12,
		HomeRy = record and record.Ry or 0,
		Outside = speciesById[animal.Sp].Outside == true,
		Owner = player.UserId,
		Rare = Genetics.AnimalRarity(animal.Sp, animal.G),
	}
	for name, value in attrs do
		if part:GetAttribute(name) ~= value then
			part:SetAttribute(name, value)
		end
	end
end

function AnimalService.RenderAll(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	for aid in profile.Farm.Animals do
		AnimalService.Render(player, aid)
	end
end

-- Granting / buying ----------------------------------------------------------------------------------------

local function newAid(profile: any): string
	local aid
	repeat
		aid = "a" .. RNG.Uid()
	until not profile.Farm.Animals[aid]
	return aid
end

local function freeHome(profile: any, species: any, preferred: string?): string?
	if preferred then
		local def = homeDef(profile, preferred)
		if
			def
			and def.Function.Home == species.Home
			and AnimalService.Residents(profile, preferred) < def.Function.Capacity
		then
			return preferred
		end
		return nil
	end
	for uid in profile.Farm.Placed do
		local def = homeDef(profile, uid)
		if
			def
			and def.Function.Home == species.Home
			and AnimalService.Residents(profile, uid) < def.Function.Capacity
		then
			return uid
		end
	end
	return nil
end

local function randomName(): string
	local names = {
		"Clover",
		"Biscuit",
		"Maple",
		"Pepper",
		"Hazel",
		"Juniper",
		"Poppy",
		"Nutmeg",
		"Willow",
		"Pip",
		"Button",
		"Sprout",
		"Daisy",
		"Mochi",
		"Fern",
		"Truffle",
		"Barley",
		"Olive",
		"Pumpkin",
		"Cocoa",
	}
	return names[random:NextInteger(1, #names)]
end

-- Add an animal (bought, bred, quest reward). Returns aid or nil, reason.
function AnimalService.Grant(
	player: Player,
	speciesId: string,
	genes: any?,
	opts: { Home: string?, Name: string?, Source: string? }?
): (string?, string?)
	local profile = S.Data.Get(player)
	local species = speciesById[speciesId]
	if not profile or not species then
		return nil, "Unknown animal"
	end
	local o = opts or {}
	local home = freeHome(profile, species, o.Home)
	if not home then
		return nil, "You need a " .. species.Home .. " with space for a " .. species.Name
	end
	local g = if genes and Genetics.ValidAnimal(speciesId, genes)
		then genes
		else Genetics.RandomAnimal(speciesId, random)
	local pers = RNG.WeightedEntry(Animals.Personalities, function(p)
		return p.Weight
	end, random:NextNumber())
	local aid = newAid(profile)
	local t = GameTime.Now()
	profile.Farm.Animals[aid] = {
		Sp = speciesId,
		Nm = o.Name or randomName(),
		G = g,
		Pe = (pers or Animals.Personalities[1]).Id,
		Home = home,
		Born = os.time(),
		Hap = 70,
		Fr = 0,
		Fed = GameTime.DayIndex(t),
		Last = t,
		Upd = t,
	}
	S.Data.Changed(player, "Farm", "Animals")
	AnimalService.Render(player, aid)
	local phenotype = Genetics.Phenotype(speciesId, g)
	S.Collection.Discover(
		player,
		"Animals",
		speciesId .. ":" .. phenotype.Coat.Id,
		{ Rarity = Genetics.AnimalRarity(speciesId, g) }
	)
	S.Data.MaxStat(player, "AnimalsOwned", AnimalService.Count(profile))
	S.Data.AddStat(player, "AnimalsOwnedTotal")
	return aid, nil
end

local function buy(player: Player, speciesId: string, homeUid: string)
	local profile = S.Data.Get(player)
	local species = speciesById[speciesId]
	if not profile or not species or not species.Buyable then
		return false, "That animal isn't for sale"
	end
	if not S.NPC.Near(player, "hattie") then
		return false, "Visit Hattie at the ranch to buy animals"
	end
	if Stats.SkillLevel(profile, "Ranching") < species.Level then
		return false, "Requires Ranching level " .. species.Level
	end
	local price = math.floor(species.Price * (1 - Stats.ShopDiscount(profile, "ranch")))
	if profile.Coins < price then
		return false, "Not enough coins (" .. Format.Commas(price) .. ")"
	end
	local home = freeHome(profile, species, if homeUid ~= "" then homeUid else nil)
	if not home then
		return false, "You need a " .. species.Home .. " with free space"
	end
	S.Economy.Spend(player, price, "Animal")
	local aid, why = AnimalService.Grant(player, speciesId, nil, { Home = home, Source = "Ranch" })
	if not aid then
		S.Economy.AddCoins(player, price, "Refund")
		return false, why
	end
	S.Quest.Progress(player, "BuyAnimal", speciesId, 1)
	S.Data.AddStat(player, "AnimalsBought")
	S.Notify.Banner(
		player,
		"Welcome home, " .. profile.Farm.Animals[aid].Nm .. "!",
		"Your new " .. species.Name .. " is settling into its " .. species.Home .. ".",
		"Animal",
		species.Icon
	)
	return true, aid
end

-- Care ---------------------------------------------------------------------------------------------------------

-- Resolve owner + animal for an actor within reach of its home.
local function access(actor: Player, aid: string, level: string): (Player?, any?, any?, string?)
	for owner in S.Farm.All() do
		local profile = S.Data.Get(owner)
		local animal = profile and profile.Farm.Animals[aid]
		if animal then
			if not S.Farm.CanAct(actor, owner, level) then
				return nil, nil, nil, "You need permission to care for animals here"
			end
			local position = S.Building.WorldPosition(owner, animal.Home)
			if not position or not S.Security.InReach(actor, position, ANIMAL_REACH) then
				return nil, nil, nil, "Walk closer"
			end
			return owner, profile, animal, nil
		end
	end
	return nil, nil, nil, "Animal not found"
end

local function addFriendship(profile: any, animal: any, amount: number)
	local pers = personality(animal)
	local gain = amount * (pers.Friendship or 1) * (1 + Stats.Effect(profile, "FriendshipGain") * 0.5)
	animal.Fr = math.clamp((animal.Fr or 0) + gain, 0, Animals.MaxFriendship)
end

local function feed(actor: Player, profile: any, animal: any, today: number): (boolean, string?)
	local species = speciesById[animal.Sp]
	if (animal.Fed or -99) >= today then
		return false, animal.Nm .. " has already eaten today"
	end
	-- Prefer premium feed if the species likes it and the actor has it.
	local used
	for i = #species.Feed, 1, -1 do
		local id = species.Feed[i]
		if S.Inventory.Count(actor, id) > 0 then
			used = id
			break
		end
	end
	if not used then
		return false, "You need " .. Registry.Items[species.Feed[1]].Name .. " to feed " .. animal.Nm
	end
	local save = Stats.Effect(profile, "FeedSave")
	if random:NextNumber() >= save then
		S.Inventory.Remove(actor, used, 1)
	end
	animal.Fed = today
	animal.Prem = used == "animal_feed" or nil
	animal.Hap =
		math.clamp((animal.Hap or 0) + Animals.FeedHappiness * (if used == "animal_feed" then 1.4 else 1), 0, 100)
	return true
end

local function act(actor: Player, aid: string, action: string)
	local level = if action == "Collect" then "Harvest" else "Animals"
	local owner, profile, animal, reason = access(actor, aid, level)
	if not owner then
		return false, reason
	end
	local t = GameTime.Now()
	local today = GameTime.DayIndex(t)
	settle(owner, profile, animal, t)
	local species = speciesById[animal.Sp]
	local fx = nil
	if action == "Pet" then
		if (animal.Pet or -99) >= today then
			return false, animal.Nm .. " loved the attention already today"
		end
		animal.Pet = today
		addFriendship(profile, animal, Animals.PetFriendship)
		animal.Hap = math.clamp((animal.Hap or 0) + 6, 0, 100)
		fx = "Hearts"
		S.Quest.Progress(actor, "Pet", animal.Sp, 1)
		S.Data.AddStat(actor, "AnimalsPetted")
	elseif action == "Brush" then
		if (animal.Br or -99) >= today then
			return false, animal.Nm .. " is already shiny today"
		end
		animal.Br = today
		addFriendship(profile, animal, Animals.BrushFriendship)
		animal.Hap = math.clamp((animal.Hap or 0) + 8, 0, 100)
		fx = "Sparkle"
	elseif action == "Feed" then
		local ok, why = feed(actor, profile, animal, today)
		if not ok then
			return false, why
		end
		fx = "Munch"
	elseif action == "Treat" then
		if (animal.Tr or -99) >= today then
			return false, animal.Nm .. " already had a treat today"
		end
		if not S.Inventory.Remove(actor, "treat", 1) then
			return false, "You need an Animal Treat"
		end
		animal.Tr = today
		addFriendship(profile, animal, Animals.TreatFriendship)
		animal.Hap = math.clamp((animal.Hap or 0) + 15, 0, 100)
		fx = "Hearts"
	elseif action == "Collect" then
		local ready = animal.Rd or 0
		if ready <= 0 then
			return false, animal.Nm .. " has nothing for you yet"
		end
		local stacks = AnimalService.Harvest(owner, aid, ready)
		if #stacks == 0 then
			return false, "Your bag is full"
		end
		for _, stack in stacks do
			S.Inventory.Add(
				owner,
				stack,
				{ Source = animal.Nm, Position = S.Building.WorldPosition(owner, animal.Home) }
			)
		end
		if actor ~= owner then
			S.Notify.Toast(owner, actor.DisplayName .. " collected products from " .. animal.Nm .. " for you.", "Info")
		end
		fx = "Collect"
	elseif action == "Ride" then
		if not species.Rideable then
			return false, "You can't ride a " .. species.Name
		end
		if actor ~= owner and not S.Farm.CanAct(actor, owner, "Trusted") then
			return false, "Only the owner can ride " .. animal.Nm
		end
		return AnimalService.Mount(actor, owner, aid)
	elseif action == "FeedAll" then
		-- Feed every hungry animal in this animal's building.
		local fed = 0
		local lastReason
		for otherAid, other in profile.Farm.Animals do
			if other.Home == animal.Home then
				settle(owner, profile, other, t)
				local ok, why = feed(actor, profile, other, today)
				if ok then
					fed += 1
					AnimalService.Render(owner, otherAid)
				else
					lastReason = why
				end
			end
		end
		if fed == 0 then
			return false, lastReason or "Everyone has eaten"
		end
		S.Data.Changed(owner, "Farm", "Animals")
		return true, fed
	elseif action == "CollectAll" then
		local total = 0
		for otherAid, other in profile.Farm.Animals do
			if other.Home == animal.Home then
				settle(owner, profile, other, t)
				if (other.Rd or 0) > 0 then
					for _, stack in AnimalService.Harvest(owner, otherAid, other.Rd) do
						S.Inventory.Add(owner, stack, { Source = other.Nm, Silent = true })
						total += stack.N
					end
					AnimalService.Render(owner, otherAid)
				end
			end
		end
		if total == 0 then
			return false, "Nothing to collect"
		end
		S.Notify.Toast(actor, "Collected " .. total .. " animal products", "Success")
		S.Data.Changed(owner, "Farm", "Animals")
		return true, total
	else
		return false, "Unknown action"
	end
	S.Data.Changed(owner, "Farm", "Animals")
	AnimalService.Render(owner, aid)
	if (animal.Fr or 0) >= Animals.MaxFriendship then
		local best = 0
		for _, other in profile.Farm.Animals do
			if (other.Fr or 0) >= Animals.MaxFriendship then
				best += 1
			end
		end
		S.Data.MaxStat(owner, "MaxFriendAnimals", best)
	end
	local position = S.Building.WorldPosition(owner, animal.Home)
	if position and fx then
		S.Notify.FX(position, "Animal", { Aid = aid, Kind = fx, Sound = species.Sounds[1] }, 120)
	end
	S.Tutorial.Event(actor, "Animal")
	return true, { Hap = animal.Hap, Fr = animal.Fr, Mood = mood(animal, today) }
end

-- Take up to `count` ready products from an animal (used by collectors too).
function AnimalService.Harvest(player: Player, aid: string, count: number): { any }
	local profile = S.Data.Get(player)
	local animal = profile and profile.Farm.Animals[aid]
	if not animal or (animal.Rd or 0) <= 0 then
		return {}
	end
	local species = speciesById[animal.Sp]
	local n = math.min(count, animal.Rd)
	local out = {}
	local id = productId(profile, animal)
	local quality = animal.RdQ or AnimalService.QualityFor(profile, animal)
	local total = 0
	for _ = 1, n do
		local amount = 1
		if random:NextNumber() < (animal.G.Yield or 5) / 10 * 0.25 + Stats.Effect(profile, "BonusProduct") then
			amount += 1
		end
		total += amount
	end
	local stack = ItemUtil.New(id, total, quality)
	table.insert(out, stack)
	-- Curious animals sometimes find something.
	local pers = personality(animal)
	if pers.Rare and random:NextNumber() < 0.05 * pers.Rare then
		local finds = { "treat", "acorn", "fiber", "clay", "sap", "mystery_seed" }
		local found = finds[random:NextInteger(1, #finds)]
		if Registry.Items[found] then
			table.insert(out, ItemUtil.New(found, 1))
		end
	end
	animal.Rd -= n
	animal.RdQ = nil
	addFriendship(profile, animal, 3)
	S.Data.AddStat(player, "AnimalProducts", total)
	S.Quest.Progress(player, "Collect", id, total)
	S.Skill.AddXP(player, "Ranching", math.max(2, math.floor(species.Interval / 6)) * n)
	AnimalService.Produced:Fire(player, aid, stack)
	return out
end

-- Settle and return an animal (automation uses this before collecting/feeding).
function AnimalService.Settle(player: Player, aid: string): any?
	local profile = S.Data.Get(player)
	local animal = profile and profile.Farm.Animals[aid]
	if animal then
		settle(player, profile, animal, GameTime.Now())
	end
	return animal
end

-- Feed from silo (auto-feeders). Returns true if fed.
function AnimalService.FeedFromSilo(player: Player, aid: string): boolean
	local profile = S.Data.Get(player)
	local animal = profile and profile.Farm.Animals[aid]
	if not animal then
		return false
	end
	local t = GameTime.Now()
	local today = GameTime.DayIndex(t)
	settle(player, profile, animal, t)
	if (animal.Fed or -99) >= today then
		return false
	end
	local species = speciesById[animal.Sp]
	for i = #species.Feed, 1, -1 do
		local id = species.Feed[i]
		if S.Inventory.SiloCountOf(player, id) > 0 then
			if random:NextNumber() >= Stats.Effect(profile, "FeedSave") then
				S.Inventory.SiloTake(player, id, 1)
			end
			animal.Fed = today
			animal.Prem = id == "animal_feed" or nil
			animal.Hap = math.clamp((animal.Hap or 0) + Animals.FeedHappiness, 0, 100)
			return true
		end
	end
	return false
end

-- Naming, moving and selling --------------------------------------------------------------------------------

local function rename(player: Player, aid: string, name: string)
	local profile = S.Data.Get(player)
	local animal = profile and profile.Farm.Animals[aid]
	if not animal then
		return false, "Not your animal"
	end
	local clean = Format.CleanName(name, Animals.NameMaxLength)
	if #clean < 1 then
		return false, "Too short"
	end
	local filtered = S.Multiplayer.FilterText(player, clean)
	if not filtered then
		return false, "That name isn't allowed"
	end
	animal.Nm = filtered
	S.Data.Changed(player, "Farm", "Animals")
	AnimalService.Render(player, aid)
	return true, filtered
end

local function move(player: Player, aid: string, homeUid: string)
	local profile = S.Data.Get(player)
	local animal = profile and profile.Farm.Animals[aid]
	if not animal then
		return false, "Not your animal"
	end
	local species = speciesById[animal.Sp]
	if homeUid == animal.Home then
		return false, "It already lives there"
	end
	local home = freeHome(profile, species, homeUid)
	if not home then
		return false, "That building has no room for a " .. species.Name
	end
	animal.Home = home
	S.Data.Changed(player, "Farm", "Animals")
	AnimalService.Render(player, aid)
	return true
end

function AnimalService.SellValue(profile: any, animal: any): number
	local species = speciesById[animal.Sp]
	local rarity = Genetics.AnimalRarity(animal.Sp, animal.G)
	local rarityMult = ({ Common = 1, Uncommon = 1.3, Rare = 2, Epic = 3.5, Legendary = 6, Mythic = 10 })[rarity] or 1
	local friend = 1 + (animal.Fr or 0) / Animals.MaxFriendship
	return math.floor(
		species.Price * Animals.SellFraction * friend * rarityMult * (1 + Stats.Effect(profile, "AnimalValue"))
	)
end

local function sell(player: Player, aid: string)
	local profile = S.Data.Get(player)
	local animal = profile and profile.Farm.Animals[aid]
	if not animal then
		return false, "Not your animal"
	end
	if not S.NPC.Near(player, "hattie") then
		return false, "Hattie at the ranch can rehome animals"
	end
	if animal.Preg then
		return false, animal.Nm .. " is expecting! Wait until the baby arrives."
	end
	local t = GameTime.Now()
	settle(player, profile, animal, t)
	if (animal.Rd or 0) > 0 then
		for _, stack in AnimalService.Harvest(player, aid, animal.Rd) do
			S.Inventory.Add(player, stack, { Silent = true })
		end
	end
	local value = AnimalService.SellValue(profile, animal)
	profile.Farm.Animals[aid] = nil
	S.Data.Changed(player, "Farm", "Animals")
	AnimalService.Render(player, aid)
	S.Economy.AddCoins(player, value, "Animal rehomed")
	S.Notify.Toast(player, animal.Nm .. " went to a loving new farm. +" .. Format.Coins(value), "Info")
	return true, value
end

-- Breeding delivery (called when a pregnancy is due) --------------------------------------------------------

function AnimalService.Deliver(player: Player, profile: any, animal: any)
	local preg = animal.Preg
	animal.Preg = nil
	local species = speciesById[animal.Sp]
	local aid, why = AnimalService.Grant(player, animal.Sp, preg.G, { Home = animal.Home })
	if not aid then
		aid, why = AnimalService.Grant(player, animal.Sp, preg.G)
	end
	if not aid then
		-- No room: the baby waits with its parent until there's space.
		animal.Preg = { Due = GameTime.Now() + HOUR * 6, G = preg.G, Sire = preg.Sire }
		S.Notify.Toast(player, "🍼 " .. animal.Nm .. "'s baby needs room! " .. (why or ""), "Warning")
		return
	end
	local baby = profile.Farm.Animals[aid]
	baby.Fr = 100
	S.Data.AddStat(player, "AnimalsBred")
	S.Quest.Progress(player, "Breed", animal.Sp, 1)
	S.Skill.AddXP(player, "Ranching", 40)
	local phenotype = Genetics.Phenotype(animal.Sp, preg.G)
	S.Notify.Banner(
		player,
		"A baby " .. species.Name .. " was born!",
		"Say hello to "
			.. baby.Nm
			.. " — "
			.. phenotype.Coat.Name
			.. " coat, "
			.. phenotype.Pattern.Name
			.. " pattern.",
		"Animal",
		species.Icon
	)
	AnimalService.Born:Fire(player, aid)
end

-- Riding ----------------------------------------------------------------------------------------------------------

local riding: { [Player]: { Owner: Player, Aid: string } } = {}

function AnimalService.Mount(rider: Player, owner: Player, aid: string): (boolean, any)
	local character = rider.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local profile = S.Data.Get(owner)
	local animal = profile and profile.Farm.Animals[aid]
	if not humanoid or not animal then
		return false, "Can't ride right now"
	end
	if character:GetAttribute("Vehicle") then
		return false, "Put away your equipment first"
	end
	local phenotype = Genetics.Phenotype(animal.Sp, animal.G)
	character:SetAttribute("Riding", animal.Sp)
	character:SetAttribute("RideCoat", phenotype.Coat.Id)
	character:SetAttribute("RideName", animal.Nm)
	-- Faster horses with better Speed genes and friendship.
	humanoid.WalkSpeed = 30 + (animal.G.Speed or 5) * 1.2 + (animal.Fr or 0) / 100
	humanoid.JumpPower = 60
	riding[rider] = { Owner = owner, Aid = aid }
	addFriendship(profile, animal, 1)
	return true, { Riding = aid }
end

function AnimalService.Dismount(player: Player)
	local character = player.Character
	riding[player] = nil
	if character and character:GetAttribute("Riding") then
		character:SetAttribute("Riding", nil)
		character:SetAttribute("RideCoat", nil)
		character:SetAttribute("RideName", nil)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.JumpPower = 50
		end
		S.Player.ApplyWalkSpeed(player)
	end
end

-- Lifecycle ----------------------------------------------------------------------------------------------------

function AnimalService.Init()
	Net.Handle("AnimalBuy", buy)
	Net.Handle("AnimalAct", function(player, aid, action)
		if action == "Dismount" then
			AnimalService.Dismount(player)
			return true
		end
		return act(player, aid, action)
	end)
	Net.Handle("AnimalName", rename)
	Net.Handle("AnimalMove", move)
	Net.Handle("AnimalSell", sell)
end

function AnimalService.Start()
	S.Farm.Ready:Connect(function(player)
		local profile = S.Data.Get(player)
		if not profile then
			return
		end
		local t = GameTime.Now()
		for aid, animal in profile.Farm.Animals do
			if not speciesById[animal.Sp] or not Genetics.ValidAnimal(animal.Sp, animal.G) then
				warn("[Evergrove] Dropping invalid animal", aid, "for", player.Name)
				profile.Farm.Animals[aid] = nil
			else
				-- Homeless animals (building removed by an old bug) find a new home or wait in the yard.
				if not homeDef(profile, animal.Home) then
					animal.Home = freeHome(profile, speciesById[animal.Sp]) or animal.Home
				end
				settle(player, profile, animal, t)
			end
		end
		AnimalService.RenderAll(player)
	end)
	S.Farm.Released:Connect(function(player)
		anchors[player] = nil
	end)
	S.Building.Moved:Connect(function(player, uid)
		local profile = S.Data.Get(player)
		if profile then
			for aid, animal in profile.Farm.Animals do
				if animal.Home == uid then
					AnimalService.Render(player, aid)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		riding[player] = nil
	end)
	-- Hourly: settle every animal so moods/products stay current for viewers.
	S.Time.Hour:Connect(function()
		local t = GameTime.Now()
		for player in S.Farm.All() do
			local profile = S.Data.Get(player)
			if profile then
				local any = false
				for aid, animal in profile.Farm.Animals do
					settle(player, profile, animal, t)
					AnimalService.Render(player, aid)
					any = true
				end
				if any then
					S.Data.Changed(player, "Farm", "Animals")
				end
			end
		end
	end)
	-- Riders who wander off their mount's farm keep riding; dying/resetting dismounts.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			riding[player] = nil
		end)
	end)
end

return AnimalService
