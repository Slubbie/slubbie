-- Ranked Standing: transparent Elo (Core/Rating.luau), seasons, placements,
-- anti-abuse and abandon penalties. Rewards are cosmetic only.
--
-- Anti-abuse rules
--   * Rated games against the same opponent are capped per 24h window
--     (Config.Ranked.SameOpponentLimit); extra games are played unrated.
--   * A match that ends by forfeit within Config.Ranked.MinMatchSeconds does
--     not raise the winner's rating (prevents farming quick leavers).
--   * Leaving an active ranked match is a full-K loss plus an abandon strike.
--     Strikes lock the ranked queue for escalating periods and decay after
--     clean matches. The penalty is applied at the moment of leaving (while the
--     profile is still loaded) and refunded if the subject reconnects in time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Rating = require(ReplicatedStorage.Variance.Core.Rating)
local TableUtil = require(ReplicatedStorage.Variance.Util.TableUtil)

local RankedService = {}

function RankedService:Init(services)
	self.Services = services
end

local function season()
	return Config.Ranked.Season
end

-- Handles a season change for a freshly loaded profile.
function RankedService:checkSeason(player: Player)
	local rolled = false
	self.Services.DataService:update(player, function(data)
		local r = data.Ranked
		if r.Season ~= season().Id then
			if (r.SeasonGames or 0) > 0 then
				r.SeasonPeaks[r.Season] = r.SeasonPeak or r.Rating
			end
			r.Season = season().Id
			r.Rating = Rating.softReset(r.Rating)
			r.SeasonGames = 0
			r.SeasonPeak = r.Rating
			rolled = true
		end
	end)
	if rolled then
		self.Services.CosmeticService:syncGrants(player)
		self.Services.NetworkService:notify(player, "NEW SEASON", season().Name .. " has begun. Standing partially reset.", "Info")
	end
end

function RankedService:rating(player: Player): number
	local profile = self.Services.DataService:get(player)
	return profile and profile.Data.Ranked.Rating or Rating.Start
end

function RankedService:canQueue(player: Player): (boolean, string?)
	local profile = self.Services.DataService:get(player)
	if profile == nil then
		return false, "Profile not ready."
	end
	if profile.Guest then
		return false, "Ranked needs a saved profile."
	end
	local remaining = profile.Data.Ranked.LockoutUntil - os.time()
	if remaining > 0 then
		return false, string.format("%s (%dm left)", Config.Ranked.LockoutMessage, math.ceil(remaining / 60))
	end
	return true
end

function RankedService:info(player: Player)
	local profile = self.Services.DataService:get(player)
	if profile == nil then
		return nil
	end
	local r = profile.Data.Ranked
	local placed = (r.SeasonGames or 0) >= Rating.Placements
	return {
		Rating = r.Rating,
		Division = Rating.division(r.Rating),
		Placed = placed,
		PlacementsLeft = math.max(0, Rating.Placements - (r.SeasonGames or 0)),
		SeasonGames = r.SeasonGames or 0,
		Games = r.Games,
		Wins = r.Wins,
		Peak = r.Peak,
		SeasonPeak = r.SeasonPeak or r.Rating,
		K = Rating.kFactor(r.Games),
		Season = { Id = season().Id, Name = season().Name, EndsIn = math.max(0, season().Ends - os.time()) },
		History = r.History,
		Strikes = r.Strikes,
		LockoutRemaining = math.max(0, r.LockoutUntil - os.time()),
	}
end

-- What a win or loss would do, shown on the versus card before a ranked match.
function RankedService:preview(player: Player, opponentRating: number)
	local profile = self.Services.DataService:get(player)
	if profile == nil then
		return nil
	end
	local r = profile.Data.Ranked
	local k = Rating.kFactor(r.Games)
	local _, win = Rating.update(r.Rating, opponentRating, 1, k)
	local _, loss = Rating.update(r.Rating, opponentRating, 0, k)
	return {
		Rating = r.Rating,
		Opponent = opponentRating,
		Expected = Rating.expected(r.Rating, opponentRating),
		K = k,
		Win = win,
		Loss = loss,
	}
end

local function applyChange(data, newRating: number, delta: number, won: boolean)
	local r = data.Ranked
	r.Rating = newRating
	r.Games += 1
	r.SeasonGames = (r.SeasonGames or 0) + 1
	if won then
		r.Wins += 1
	end
	r.Peak = math.max(r.Peak, newRating)
	r.SeasonPeak = math.max(r.SeasonPeak or newRating, newRating)
	table.insert(r.History, { Time = os.time(), Rating = newRating, Delta = delta })
	TableUtil.trimFront(r.History, Config.Data.RatingHistoryLimit)
end

local function opponentCount(data, opponentId: number): number
	local record = data.Ranked.Opponents[tostring(opponentId)]
	if record == nil or os.time() - record.Since > Config.Ranked.SameOpponentWindow then
		return 0
	end
	return record.Count
end

local function noteOpponent(data, opponentId: number)
	local key = tostring(opponentId)
	local record = data.Ranked.Opponents[key]
	if record == nil or os.time() - record.Since > Config.Ranked.SameOpponentWindow then
		record = { Count = 0, Since = os.time() }
	end
	record.Count += 1
	data.Ranked.Opponents[key] = record
end

-- Called the moment a subject leaves an active ranked match (profile still loaded).
-- Returns a refund token so a reconnect can undo it.
function RankedService:applyAbandon(player: Player, opponentRating: number)
	local refund = nil
	self.Services.DataService:update(player, function(data)
		local r = data.Ranked
		local before = { Rating = r.Rating, Strikes = r.Strikes, LockoutUntil = r.LockoutUntil, Clean = r.CleanSinceStrike }
		local newRating, delta = Rating.abandon(r.Rating, opponentRating, r.Games)
		applyChange(data, newRating, delta, false)
		r.Strikes += 1
		r.CleanSinceStrike = 0
		r.LockoutUntil = os.time() + Rating.lockoutFor(r.Strikes)
		refund = before
	end)
	return refund
end

-- Undoes a provisional abandon penalty (the subject came back in time).
function RankedService:refundAbandon(player: Player, refund)
	if refund == nil then
		return
	end
	self.Services.DataService:update(player, function(data)
		local r = data.Ranked
		r.Rating = refund.Rating
		r.Strikes = refund.Strikes
		r.LockoutUntil = refund.LockoutUntil
		r.CleanSinceStrike = refund.Clean
		r.Games = math.max(0, r.Games - 1)
		r.SeasonGames = math.max(0, (r.SeasonGames or 0) - 1)
		table.remove(r.History)
	end)
end

-- Rates a finished 1v1 ranked match. `results` = { {Player, UserId, Won, Abandoned, RatingBefore} }.
-- Returns { [UserId] = {Delta, Rating, Rated, Note} }.
function RankedService:rateMatch(results, durationSeconds: number, endedByForfeit: boolean)
	local out = {}
	if #results ~= 2 then
		return out
	end
	local a, b = results[1], results[2]
	for _, entry in results do
		local other = entry == a and b or a
		local player = entry.Player
		if entry.Abandoned then
			-- Already penalised at the moment they left.
			out[entry.UserId] = { Delta = entry.AbandonDelta or 0, Rated = true, Note = "Abandoned" }
		elseif player and player.Parent then
			local note = nil
			local result = nil
			self.Services.DataService:update(player, function(data)
				local rated = opponentCount(data, other.UserId) < Config.Ranked.SameOpponentLimit
				noteOpponent(data, other.UserId)
				local r = data.Ranked
				local k = Rating.kFactor(r.Games)
				local newRating, delta = Rating.update(r.Rating, other.RatingBefore, entry.Won and 1 or 0, k)
				if entry.Won and endedByForfeit and durationSeconds < Config.Ranked.MinMatchSeconds then
					newRating, delta = r.Rating, 0
					note = "Opponent left early: no Standing change."
				end
				if not rated then
					newRating, delta = r.Rating, 0
					note = "Repeat opponent: this match was unrated."
				end
				applyChange(data, newRating, delta, entry.Won)
				r.CleanSinceStrike += 1
				if r.Strikes > 0 and r.CleanSinceStrike >= Config.Ranked.StrikeDecayMatches then
					r.Strikes -= 1
					r.CleanSinceStrike = 0
				end
				result = { Delta = delta, Rating = newRating, Rated = rated, Note = note }
			end)
			if result then
				out[entry.UserId] = result
				local info = self:info(player)
				if info and info.Placed then
					self.Services.LeaderboardService:submit("Standing", player.UserId, info.Rating)
				end
				self.Services.CosmeticService:syncGrants(player)
				self.Services.ProgressionService:changed(player)
			end
		end
	end
	return out
end

function RankedService:Start()
	self.Services.DataService.Loaded:Connect(function(player)
		self:checkSeason(player)
	end)
end

return RankedService
