-- Every movement technique, how it's introduced and when it unlocks.
--
-- Level 1 techniques are available from the first minute and are taught in the
-- Training Yard. Later tools arrive with story gear at the listed level; the
-- Advanced Training Stations in the Guildhall teach each one when it unlocks.

export type Ability = {
	Id: string,
	Name: string,
	Level: number,
	Gear: string?,
	Category: string,
	Summary: string,
	Tip: string,
	Icon: string,
	Order: number?,
}

local list: { Ability } = {
	{
		Id = "Sprint",
		Name = "Sprint",
		Level = 1,
		Category = "Ground",
		Summary = "Run faster while stamina lasts. Sprint speed is what clears long gaps.",
		Tip = "Stamina refills quickly on the ground once you stop spending it.",
		Icon = ">>",
	},
	{
		Id = "Slide",
		Name = "Slide & Crouch",
		Level = 1,
		Category = "Ground",
		Summary = "Crouch while running to slide under striped pipes. Slopes speed you up.",
		Tip = "Jump out of a slide to keep its speed. Crouch slowly through low tunnels.",
		Icon = "_",
	},
	{
		Id = "Vault",
		Name = "Vault",
		Level = 1,
		Category = "Ground",
		Summary = "Run into waist-high cover and press jump to hop over it without losing speed.",
		Tip = "Sprinting into low cover vaults it automatically.",
		Icon = "^",
	},
	{
		Id = "LedgeGrab",
		Name = "Ledge Grab & Mantle",
		Level = 1,
		Category = "Climbing",
		Summary = "Jump at a ledge to catch it. Push forward to mantle up, sideways to shimmy.",
		Tip = "Hanging drains stamina. Crouch to let go, or jump with back held to kick away.",
		Icon = "[]",
	},
	{
		Id = "Climb",
		Name = "Climb",
		Level = 1,
		Category = "Climbing",
		Summary = "Ladders, vines and mesh with a rung pattern can be climbed in any direction.",
		Tip = "Press jump while climbing to hop up. Hold back and jump to leap off.",
		Icon = "#",
	},
	{
		Id = "WallRun",
		Name = "Wall Run",
		Level = 1,
		Category = "Walls",
		Summary = "Jump at a wall at a shallow angle while moving fast to run along it.",
		Tip = "Walls with chevrons mark designed routes. Gravity grows the longer you run.",
		Icon = "//",
	},
	{
		Id = "WallJump",
		Name = "Wall Jump & Wall Kick",
		Level = 1,
		Category = "Walls",
		Summary = "Jump during a wall run to leap away, or jump beside any wall in the air to kick off it.",
		Tip = "You can't kick the same wall twice in a row. Kick between two walls to climb a shaft.",
		Icon = "<>",
	},
	{
		Id = "Balance",
		Name = "Balance",
		Level = 1,
		Category = "Traversal",
		Summary = "Walk narrow beams with dashed centre lines. Steer against the sway to stay on.",
		Tip = "Slip off and you'll catch the beam with your hands if you have stamina.",
		Icon = "=",
	},
	{
		Id = "Roll",
		Name = "Landing Roll",
		Level = 1,
		Category = "Landing",
		Summary = "Press crouch just before a big landing to roll and keep all your speed.",
		Tip = "Hard landings without a roll make you stumble.",
		Icon = "@",
	},
	{
		Id = "Zipline",
		Name = "Zipline",
		Level = 1,
		Category = "Traversal",
		Summary = "Jump into a cable to ride it. Steeper lines go faster. Jump to let go.",
		Tip = "Letting go near the end keeps your momentum for the next jump.",
		Icon = "~",
	},
	{
		Id = "RopeSwing",
		Name = "Rope Swing",
		Level = 1,
		Category = "Traversal",
		Summary = "Jump into a hanging rope to swing. Push to pump, jump to release.",
		Tip = "Release as you swing upward past the bottom for the longest flight.",
		Icon = "Y",
	},
	{
		Id = "DoubleJump",
		Name = "Double Jump",
		Level = 4,
		Gear = "Spring Soles",
		Category = "Aerial",
		Summary = "Jump again in mid-air. It refreshes when you touch ground, a wall, a ledge or a rope.",
		Tip = "A double jump can bend your direction a little: use it to correct a bad jump.",
		Icon = "^^",
	},
	{
		Id = "Dash",
		Name = "Directional Dash",
		Level = 10,
		Gear = "Kinetic Harness",
		Category = "Aerial",
		Summary = "Burst in the direction you're steering, on the ground or in the air.",
		Tip = "A dash briefly holds your height. One charge, refreshed by landing or walls.",
		Icon = "->",
	},
	{
		Id = "Grapple",
		Name = "Grapple Swing",
		Level = 16,
		Gear = "Guild Grapple",
		Category = "Aerial",
		Summary = "Hook ring anchors and swing beneath them. Hold jump to reel in.",
		Tip = "Let go at the bottom of the swing for maximum speed.",
		Icon = "(o)",
	},
	{
		Id = "GrapplePull",
		Name = "Grapple Pull",
		Level = 24,
		Gear = "Pull Coil",
		Category = "Aerial",
		Summary = "Diamond anchors yank you straight to them and pop you over the edge.",
		Tip = "Pull anchors are perfect for reaching high ledges in a hurry.",
		Icon = "<o>",
	},
	{
		Id = "LedgeLeap",
		Name = "Ledge Leap",
		Level = 30,
		Gear = "Climber's Grips",
		Category = "Climbing",
		Summary = "From a hang, jump straight up to catch a higher ledge.",
		Tip = "Chain leaps up stacked ledges without ever standing.",
		Icon = "^[]",
	},
}

local Abilities = {}
Abilities.List = list
Abilities.ById = {} :: { [string]: Ability }

for index, ability in list do
	ability.Order = index
	Abilities.ById[ability.Id] = ability
end

-- Techniques that need no unlock.
function Abilities.IsBasic(id: string): boolean
	local ability = Abilities.ById[id]
	return ability ~= nil and ability.Level <= 1
end

-- Every ability unlocked at the given level.
function Abilities.ForLevel(level: number): { [string]: boolean }
	local result = {}
	for _, ability in list do
		if ability.Level <= level then
			result[ability.Id] = true
		end
	end
	return result
end

-- All abilities (used for standardized ranked attributes where needed).
function Abilities.All(): { [string]: boolean }
	local result = {}
	for _, ability in list do
		result[ability.Id] = true
	end
	return result
end

return Abilities
