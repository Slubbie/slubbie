-- Per-player token buckets: each remote gets `burst` requests at once, refilling at `perSecond`.

local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type Limiter = typeof(setmetatable(
	{} :: { burst: number, rate: number, buckets: { [Player]: { tokens: number, at: number } } },
	RateLimiter
))

local all: { Limiter } = {}

function RateLimiter.new(burst: number, perSecond: number): Limiter
	local self = setmetatable({ burst = burst, rate = perSecond, buckets = {} }, RateLimiter)
	table.insert(all, self)
	return self
end

function RateLimiter.Allow(self: Limiter, player: Player): boolean
	local now = os.clock()
	local bucket = self.buckets[player]
	if not bucket then
		bucket = { tokens = self.burst, at = now }
		self.buckets[player] = bucket
	end
	bucket.tokens = math.min(self.burst, bucket.tokens + (now - bucket.at) * self.rate)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

Players.PlayerRemoving:Connect(function(player)
	for _, limiter in all do
		limiter.buckets[player] = nil
	end
end)

return RateLimiter
