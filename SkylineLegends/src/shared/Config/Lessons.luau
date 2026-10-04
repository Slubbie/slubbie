-- Interactive lessons in the Guildhall Training Yard.
--
-- Each lesson is a small station: step onto its pad and a card shows the
-- technique, its input for your device, and two steps: perform the move, then
-- combine it with something you already know. Advanced stations unlock with
-- their ability.

export type LessonStep = { Text: string, Action: string?, Chain: { string }?, Count: number? }
export type Lesson = {
	Id: string,
	Name: string,
	Ability: string?,
	Advanced: boolean?,
	Input: string, -- input action name shown with your device's glyph
	Steps: { LessonStep },
	Layout: string, -- station geometry built by the Hub builder
}

local Lessons: { Lesson } = {
	{
		Id = "l_sprint",
		Name = "Run and Jump",
		Input = "Jump",
		Layout = "Gaps",
		Steps = {
			{ Text = "Hold Sprint and jump across the gap.", Action = "Jump" },
			{ Text = "Jump just before you land to jump again instantly. Clear all three gaps.", Action = "Jump", Count = 3 },
		},
	},
	{
		Id = "l_vault",
		Name = "Vault",
		Ability = "Vault",
		Input = "Jump",
		Layout = "Vaults",
		Steps = {
			{ Text = "Run at the low wall and press Jump to vault it.", Action = "Vault" },
			{ Text = "Vault both walls without slowing down.", Action = "Vault", Count = 2 },
		},
	},
	{
		Id = "l_slide",
		Name = "Slide",
		Ability = "Slide",
		Input = "Crouch",
		Layout = "Slides",
		Steps = {
			{ Text = "Sprint, then press Crouch to slide under the striped beam.", Action = "Slide" },
			{ Text = "Slide, then jump out of the slide to keep its speed.", Chain = { "Slide", "SlideJump" } },
		},
	},
	{
		Id = "l_ledge",
		Name = "Ledge Grab and Mantle",
		Ability = "LedgeGrab",
		Input = "Jump",
		Layout = "Ledges",
		Steps = {
			{ Text = "Jump at the high ledge to catch it.", Action = "LedgeGrab" },
			{ Text = "Push forward to mantle up. Shimmy sideways along the rail if you like.", Action = "Mantle" },
		},
	},
	{
		Id = "l_climb",
		Name = "Climb",
		Ability = "Climb",
		Input = "Jump",
		Layout = "Climb",
		Steps = {
			{ Text = "Walk into the ladder to start climbing. Climb to the top.", Action = "Climb" },
			{ Text = "Press Jump while climbing to hop up faster.", Action = "ClimbHop" },
		},
	},
	{
		Id = "l_wallrun",
		Name = "Wall Run",
		Ability = "WallRun",
		Input = "Jump",
		Layout = "WallRun",
		Steps = {
			{ Text = "Sprint and jump toward the chevron wall at a shallow angle to run along it.", Action = "WallRun" },
			{ Text = "Press Jump during the run to leap off and reach the far platform.", Action = "WallJump" },
		},
	},
	{
		Id = "l_walljump",
		Name = "Wall Kick",
		Ability = "WallJump",
		Input = "Jump",
		Layout = "Shaft",
		Steps = {
			{ Text = "Jump into the shaft, then press Jump beside a wall to kick off it.", Action = "WallKick" },
			{ Text = "Kick between both walls to reach the top.", Action = "WallKick", Count = 3 },
		},
	},
	{
		Id = "l_balance",
		Name = "Balance",
		Ability = "Balance",
		Input = "Move",
		Layout = "Beam",
		Steps = {
			{ Text = "Walk onto the beam. Steer against the sway shown under you.", Action = "Balance" },
			{ Text = "If you slip, you'll catch the beam. Climb back up and finish the crossing.", Action = "Balance", Count = 2 },
		},
	},
	{
		Id = "l_roll",
		Name = "Landing Roll",
		Ability = "Roll",
		Input = "Crouch",
		Layout = "Drop",
		Steps = {
			{ Text = "Drop from the tower and press Crouch just before you land to roll.", Action = "Roll" },
			{ Text = "Roll, then keep sprinting. A clean roll keeps all your speed.", Chain = { "Roll", "Jump" } },
		},
	},
	{
		Id = "l_zip",
		Name = "Ziplines and Ropes",
		Ability = "Zipline",
		Input = "Jump",
		Layout = "Lines",
		Steps = {
			{ Text = "Jump into the cable to ride the zipline.", Action = "Zipline" },
			{ Text = "Jump off the line into the rope swing, then jump to release.", Chain = { "Zipline", "RopeSwing" } },
		},
	},
	-- Advanced stations
	{
		Id = "l_double",
		Name = "Double Jump",
		Ability = "DoubleJump",
		Advanced = true,
		Input = "Jump",
		Layout = "Gaps",
		Steps = {
			{ Text = "Jump, then jump again in mid-air to cross the wide gap.", Action = "DoubleJump" },
			{ Text = "Wall run, then double jump off the end of the wall.", Chain = { "WallRun", "DoubleJump" } },
		},
	},
	{
		Id = "l_dash",
		Name = "Directional Dash",
		Ability = "Dash",
		Advanced = true,
		Input = "Dash",
		Layout = "Gaps",
		Steps = {
			{ Text = "Jump, then Dash toward the far platform.", Action = "Dash" },
			{ Text = "Double jump, then dash: the longest jump you can make.", Chain = { "DoubleJump", "Dash" } },
		},
	},
	{
		Id = "l_grapple",
		Name = "Grapple Swing",
		Ability = "Grapple",
		Advanced = true,
		Input = "Grapple",
		Layout = "Anchors",
		Steps = {
			{ Text = "Look toward the ring anchor and press Grapple to swing.", Action = "Grapple" },
			{ Text = "Release at the bottom of the swing, then grapple the next ring.", Action = "Grapple", Count = 2 },
		},
	},
	{
		Id = "l_pull",
		Name = "Grapple Pull",
		Ability = "GrapplePull",
		Advanced = true,
		Input = "Grapple",
		Layout = "Pull",
		Steps = {
			{ Text = "Grapple the diamond anchor to be pulled straight up to it.", Action = "Pull" },
			{ Text = "Pull, then wall run off the far tower.", Chain = { "Pull", "WallRun" } },
		},
	},
	{
		Id = "l_leap",
		Name = "Ledge Leap",
		Ability = "LedgeLeap",
		Advanced = true,
		Input = "Jump",
		Layout = "Stacked",
		Steps = {
			{ Text = "Hang from the ledge and press Jump with forward held to leap to the one above.", Action = "LedgeLeap" },
			{ Text = "Leap up two ledges in a row.", Chain = { "LedgeLeap", "LedgeLeap" } },
		},
	},
}

local Module = {}
Module.List = Lessons
Module.ById = {} :: { [string]: Lesson }
for _, lesson in Lessons do
	Module.ById[lesson.Id] = lesson
end

function Module.BasicCount(): number
	local count = 0
	for _, lesson in Lessons do
		if not lesson.Advanced then
			count += 1
		end
	end
	return count
end

return Module
