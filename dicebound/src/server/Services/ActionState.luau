-- Explicit per-player action state. Request handlers mark the player Busy while they run so an
-- action can never interleave with another one, even if a future change adds a yield. Roll
-- timing lives here too, so the cooldown is enforced by the server rather than the client.

local Players = game:GetService("Players")

export type State = {
	Busy: boolean,
	NextRollAt: number, -- os.clock() time when the next roll is allowed
	RollId: number, -- increments per accepted roll; lets the client order animations
}

local ActionState = {}

local states: { [Player]: State } = {}

function ActionState.Get(player: Player): State
	local state = states[player]
	if not state then
		state = { Busy = false, NextRollAt = 0, RollId = 0 }
		states[player] = state
	end
	return state
end

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

return ActionState
