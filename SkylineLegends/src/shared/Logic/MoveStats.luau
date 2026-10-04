-- Effective movement attributes for a player.
--
-- Standard attributes come from Config/Movement. Skill tree effects modify a
-- copy unless the run is standardized (ranked runs, races, relays). Practice
-- assists make things more forgiving but mark the run as assisted.

local MovementConfig = require(script.Parent.Parent.Config.Movement)
local SkillTree = require(script.Parent.Parent.Config.SkillTree)

local MoveStats = {}

MoveStats.Assists = {
	{ Id = "Stamina", Name = "Endless Stamina", Text = "Stamina never runs out." },
	{ Id = "Grab", Name = "Generous Grabs", Text = "Ledges and ropes can be caught from further away." },
	{ Id = "Timing", Name = "Relaxed Timing", Text = "Longer coyote time, jump buffer and roll window." },
	{ Id = "Balance", Name = "Steady Beams", Text = "Balance beams barely sway." },
}

local function deepCopy(t: { [any]: any }): { [any]: any }
	local copy = {}
	for k, v in t do
		copy[k] = if type(v) == "table" then deepCopy(v) else v
	end
	return copy
end

local function apply(stats: { [string]: any }, path: string, op: string, amount: number)
	local container = stats
	local key = path
	local dot = string.find(path, ".", 1, true)
	if dot then
		container = stats[string.sub(path, 1, dot - 1)]
		key = string.sub(path, dot + 1)
	end
	if type(container) ~= "table" or type(container[key]) ~= "number" then
		return
	end
	if op == "Add" then
		container[key] += amount
	elseif op == "Mul" then
		container[key] *= math.max(1 + amount, 0.05)
	end
end

-- Returns (stats, perks). `ranks` maps skill ids to ranks.
function MoveStats.Compute(
	ranks: { [string]: number }?,
	standardized: boolean?,
	assists: { [string]: boolean }?
): ({ [string]: any }, { [string]: number })
	local stats = deepCopy(MovementConfig :: any)
	local perks: { [string]: number } = {}
	for nodeId, rank in (ranks or {}) :: { [string]: number } do
		local node = SkillTree.ById[nodeId]
		if node and rank > 0 then
			rank = math.min(rank, node.MaxRank)
			for _, effect in node.Effects do
				if effect[1] == "Perk" then
					perks[effect[2]] = (perks[effect[2]] or 0) + effect[3] * rank
				elseif not standardized then
					apply(stats, effect[1], effect[2], effect[3] * rank)
				end
			end
		end
	end
	if assists and not standardized then
		if assists.Stamina then
			for key in stats.Costs do
				stats.Costs[key] = 0
			end
		end
		if assists.Grab then
			stats.LedgeReach += 0.8
			stats.LedgeMaxAbove += 0.8
			stats.RopeGrabRange += 1.2
			stats.ZipGrabRange += 1.2
		end
		if assists.Timing then
			stats.CoyoteTime = math.max(stats.CoyoteTime, 0.22)
			stats.JumpBuffer = math.max(stats.JumpBuffer, 0.22)
			stats.RollWindow += 0.15
			stats.WallCoyote += 0.1
		end
		if assists.Balance then
			stats.BalanceSway *= 0.35
		end
	end
	stats.StaminaRegenDelay = math.max(stats.StaminaRegenDelay, 0.1)
	return stats, perks
end

function MoveStats.Standard(): { [string]: any }
	return deepCopy(MovementConfig :: any)
end

return MoveStats
