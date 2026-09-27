-- The three-step tutorial: first roll, first sale, first upgrade. Advanced only by real,
-- server-validated actions. Pure logic over a player's Data table.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Dicebound.Config)

local Tutorial = {}

Tutorial.Steps = { "Roll", "Sell", "Upgrade" }

-- Call after a successful action. Returns the coin reward if this finished the tutorial.
function Tutorial.OnAction(data, action: string): number?
	local t = data.Tutorial
	if t.Done or Tutorial.Steps[t.Step] ~= action then
		return nil
	end
	t.Step += 1
	if t.Step > #Tutorial.Steps then
		t.Done = true
		local reward = Config.Economy.TutorialReward
		data.Coins += reward
		return reward
	end
	return nil
end

function Tutorial.Skip(data)
	data.Tutorial.Done = true
end

return Tutorial
