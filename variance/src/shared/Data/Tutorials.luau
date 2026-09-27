-- Orientation and advanced seminars, as scripts for Core/TutorialDirector.
--
-- A lesson is a real match on the real engine with forced Loads, forced draws
-- and an action filter, so everything the player learns behaves exactly as it
-- will in a live Trial. Subject 1 is the player, subject 2 is PROXY.
--
-- Beat fields
--   Title, Say   coach text (short, one idea per beat)
--   Focus        what to highlight: Device, Counts, Track, Probability, Integrity,
--                Opponent, FireSelf, FireOther, Slot:<InstrumentId>, Instruments
--   Allow        player actions permitted during the beat:
--                FireSelf, FireOpponent, Use:<InstrumentId>, Any
--   Advance      Continue | Action | PlayerTurn | Quiz | TrialEnd | MatchEnd | Finish
--   Proxy        scripted PROXY actions queued when the beat starts
--   Setup        { Reveal = {cell indices the player learns} }
--   Quiz         { Question, Options, Answer, Explain }
--   Free         PROXY thinks for itself and any action is allowed

local Tutorials = {}

Tutorials.Basic = {
	Id = "Basic",
	Name = "ORIENTATION",
	Description = "Learn the Arbiter, the cells, turns, odds and your first instruments.",
	Reward = { XP = 150, Marks = 100 },
	Rules = {
		TrialsToWin = 3,
		TurnTimer = 0,
		Forced = {
			Loads = { "CH", "HC", "CCH", "HCC", "HCC", "HCH" },
			Starters = { 1, 1, 1, 1, 1, 1 },
			Draws = {
				[3] = { [1] = { "Lens", "Ejector" }, [2] = {} },
				[4] = { [1] = { "Suture", "Capacitor" }, [2] = {} },
				[5] = { [1] = { "Clamp" }, [2] = {} },
				[6] = { [1] = { "Lens", "Inverter" }, [2] = {} },
			},
		},
	},
	Beats = {
		{
			Title = "THE ARBITER",
			Say = "This is the Arbiter. Each Load it is filled with cells: CHARGED or HOLLOW.",
			Focus = "Device",
			Advance = "Continue",
		},
		{
			Say = "The count is announced, never the order. This Load: 1 CHARGED, 1 HOLLOW.",
			Focus = "Counts",
			Advance = "Continue",
		},
		{
			Say = "Integrity is your health. You both have 2. At zero, you lose the Trial.",
			Focus = "Integrity",
			Advance = "Continue",
		},
		{
			Say = "It's your turn. Fire at PROXY.",
			Focus = "FireOther",
			Allow = { "FireOpponent" },
			Advance = "Action",
		},
		{
			Say = "CHARGED. PROXY loses 1 Integrity. Firing at an opponent always ends your turn. Watch PROXY.",
			Focus = "Opponent",
			Proxy = { "FireSelf" },
			Advance = "PlayerTurn",
		},
		{
			Title = "KEEPING THE TURN",
			Say = "PROXY fired at itself and the cell was HOLLOW, so it kept the Arbiter. A HOLLOW shot at yourself is the only way to keep your turn.",
			Focus = "Device",
			Advance = "Continue",
		},
		{
			Say = "New Load: 1 CHARGED, 1 HOLLOW. The odds are 50%. Fire at yourself.",
			Focus = "FireSelf",
			Allow = { "FireSelf" },
			Advance = "Action",
		},
		{
			Title = "ODDS",
			Say = "HOLLOW: you keep the turn. One cell remains, and one CHARGED was loaded. The odds are now 100%.",
			Focus = "Probability",
			Advance = "Continue",
		},
		{
			Say = "Certainty. Fire at PROXY.",
			Focus = "FireOther",
			Allow = { "FireOpponent" },
			Advance = "TrialEnd",
		},
		{
			Title = "TRIAL II",
			Say = "Integrity rises every Trial. This Load: 2 CHARGED, 1 HOLLOW. That's a 67% chance the loaded cell is CHARGED.",
			Focus = "Probability",
			Advance = "Continue",
		},
		{
			Title = "INSTRUMENTS",
			Say = "You've been issued instruments. Use the LENS to see the loaded cell. Only you will see it.",
			Focus = "Slot:Lens",
			Allow = { "Use:Lens" },
			Advance = "Action",
		},
		{
			Say = "The Lens shows CHARGED. Fire at PROXY.",
			Focus = "FireOther",
			Allow = { "FireOpponent" },
			Advance = "Action",
		},
		{
			Say = "Now PROXY has to guess.",
			Focus = "Opponent",
			Proxy = { "FireOpponent" },
			Advance = "PlayerTurn",
		},
		{
			Say = "One cell left, and both CHARGED cells are spent. It must be HOLLOW. Fire at yourself to keep the turn.",
			Focus = "FireSelf",
			Allow = { "FireSelf" },
			Advance = "Action",
		},
		{
			Say = "An EJECTOR throws out the loaded cell without firing it, and everyone sees what it was. Use it.",
			Focus = "Slot:Ejector",
			Allow = { "Use:Ejector" },
			Advance = "Action",
		},
		{
			Say = "You're hurt. A SUTURE restores 1 Integrity.",
			Focus = "Slot:Suture",
			Allow = { "Use:Suture" },
			Advance = "Action",
		},
		{
			Say = "Two CHARGED cells remain. A CAPACITOR doubles the damage of your next CHARGED shot. Prime it.",
			Focus = "Slot:Capacitor",
			Allow = { "Use:Capacitor" },
			Advance = "Action",
		},
		{
			Say = "Fire at PROXY.",
			Focus = "FireOther",
			Allow = { "FireOpponent" },
			Advance = "Action",
		},
		{
			Say = "Double damage. PROXY takes its shot with the last cell.",
			Focus = "Opponent",
			Proxy = { "FireOpponent" },
			Advance = "PlayerTurn",
		},
		{
			Say = "A CLAMP makes your opponent lose their next turn. Use it now.",
			Focus = "Slot:Clamp",
			Allow = { "Use:Clamp" },
			Advance = "Action",
		},
		{
			Say = "2 CHARGED, 1 HOLLOW: 67%. Fire at PROXY.",
			Focus = "FireOther",
			Allow = { "FireOpponent" },
			Advance = "PlayerTurn",
		},
		{
			Say = "HOLLOW, a miss. But PROXY was clamped, so the Arbiter came straight back. Finish the Trial.",
			Focus = "FireOther",
			Allow = { "FireOpponent" },
			Advance = "TrialEnd",
		},
		{
			Title = "TRIAL III",
			Say = "Some instruments change the cells themselves. First, look: use the LENS.",
			Focus = "Slot:Lens",
			Allow = { "Use:Lens" },
			Advance = "Action",
		},
		{
			Say = "HOLLOW. An INVERTER flips the loaded cell, so it becomes CHARGED, and PROXY won't know. Use it.",
			Focus = "Slot:Inverter",
			Allow = { "Use:Inverter" },
			Advance = "Action",
		},
		{
			Say = "It's CHARGED now. Fire at PROXY.",
			Focus = "FireOther",
			Allow = { "FireOpponent" },
			Advance = "Action",
		},
		{
			Say = "PROXY gambles on itself.",
			Focus = "Opponent",
			Proxy = { "FireSelf" },
			Advance = "PlayerTurn",
		},
		{
			Say = "That was CHARGED, so the last cell is HOLLOW. Fire at yourself.",
			Focus = "FireSelf",
			Allow = { "FireSelf" },
			Advance = "Action",
		},
		{
			Title = "MORE INSTRUMENTS",
			Say = "SONAR reveals a later cell. ROTOR turns the next three. DAMPENER absorbs a hit. OVERCLOCK lets you act again after a shot.",
			Focus = "Instruments",
			Advance = "Continue",
		},
		{
			Title = "RARE INSTRUMENTS",
			Say = "Rare instruments are powerful and dangerous: UNSTABLE SERUM, POWER TAP, TETHER, SCRAMBLER. Read the tooltip before you trust one.",
			Focus = "Instruments",
			Advance = "Continue",
		},
		{
			Title = "LIVE TRIAL",
			Say = "From here, PROXY thinks for itself. Win this Trial to finish Orientation.",
			Focus = "Device",
			Free = true,
			Advance = "MatchEnd",
		},
	},
}

Tutorials.Seminars = {
	{
		Id = "Conditional",
		Name = "CONDITIONAL PROBABILITY",
		Description = "How knowing one cell changes the odds of every other.",
		Reward = { XP = 60, Marks = 40 },
		Rules = {
			TrialsToWin = 1,
			TurnTimer = 0,
			FixedIntegrity = 3,
			Forced = { Loads = { "HHCC" }, Starters = { 1 }, Draws = {} },
		},
		Beats = {
			{
				Say = "Four cells: 2 CHARGED, 2 HOLLOW. With nothing else to go on, the loaded cell is 50% CHARGED.",
				Focus = "Probability",
				Advance = "Continue",
			},
			{
				Say = "Suppose you learn that cell 3 is CHARGED, as a SONAR might tell you. Your chamber track now shows it.",
				Focus = "Track",
				Setup = { Reveal = { 3 } },
				Advance = "Continue",
			},
			{
				Say = "Think it through.",
				Focus = "Track",
				Advance = "Quiz",
				Quiz = {
					Question = "What is the chance the loaded cell is CHARGED now?",
					Options = { "50%", "33%", "67%", "25%" },
					Answer = 2,
					Explain = "One CHARGED is accounted for. That leaves 1 CHARGED among the 3 cells you don't know: 1 in 3.",
				},
			},
			{
				Say = "At 33%, firing at yourself is favoured: a 67% chance to keep the turn. Fire at yourself.",
				Focus = "FireSelf",
				Allow = { "FireSelf" },
				Advance = "Action",
			},
			{
				Say = "HOLLOW. The odds just changed again.",
				Focus = "Probability",
				Advance = "Quiz",
				Quiz = {
					Question = "Cell 1 was HOLLOW. What is the chance the new loaded cell is CHARGED?",
					Options = { "50%", "0%", "33%", "100%" },
					Answer = 1,
					Explain = "Two cells you don't know are left, and one CHARGED is unaccounted for among them.",
				},
			},
			{
				Say = "Every shot changes the odds. Track what is left, not what was loaded.",
				Focus = "Track",
				Advance = "Finish",
			},
		},
	},
	{
		Id = "Information",
		Name = "INFORMATION ADVANTAGE",
		Description = "What your opponent knows, and what they only think they know.",
		Reward = { XP = 60, Marks = 40 },
		Rules = {
			TrialsToWin = 1,
			TurnTimer = 0,
			FixedIntegrity = 3,
			Forced = {
				Loads = { "CHH" },
				Starters = { 1 },
				Draws = { [1] = { [1] = { "Lens", "Inverter" }, [2] = {} } },
			},
		},
		Beats = {
			{
				Say = "Information is only worth something if it changes what you do. 1 CHARGED, 2 HOLLOW: 33%.",
				Focus = "Probability",
				Advance = "Continue",
			},
			{
				Say = "Use the LENS.",
				Focus = "Slot:Lens",
				Allow = { "Use:Lens" },
				Advance = "Action",
			},
			{
				Say = "CHARGED. Now think about PROXY.",
				Focus = "Opponent",
				Advance = "Quiz",
				Quiz = {
					Question = "PROXY saw you use a Lens. What does PROXY know about the loaded cell?",
					Options = { "That it's CHARGED", "That it's HOLLOW", "Nothing, until you act" },
					Answer = 3,
					Explain = "Opponents see that you looked, not what you saw. Your next action may give it away.",
				},
			},
			{
				Say = "INVERT it: the CHARGED becomes HOLLOW, and you still know exactly what it is.",
				Focus = "Slot:Inverter",
				Allow = { "Use:Inverter" },
				Advance = "Action",
			},
			{
				Say = "PROXY only knows a cell was flipped. You know it's HOLLOW. Fire at yourself and keep the turn.",
				Focus = "FireSelf",
				Allow = { "FireSelf" },
				Advance = "Action",
			},
			{
				Say = "That's an information advantage: the same Arbiter, two different games.",
				Focus = "Device",
				Advance = "Finish",
			},
		},
	},
	{
		Id = "TurnEconomy",
		Name = "TURN ECONOMY",
		Description = "Why the Arbiter in your hands is worth more than a guess.",
		Reward = { XP = 60, Marks = 40 },
		Rules = {
			TrialsToWin = 1,
			TurnTimer = 0,
			FixedIntegrity = 2,
			Forced = { Loads = { "HHC" }, Starters = { 1 }, Draws = { [1] = { [1] = { "Overclock" }, [2] = {} } } },
		},
		Beats = {
			{
				Say = "Your turn is a resource. Every HOLLOW you fire at yourself is another action before PROXY gets one.",
				Focus = "Device",
				Advance = "Continue",
			},
			{
				Say = "1 CHARGED, 2 HOLLOW.",
				Focus = "Probability",
				Advance = "Quiz",
				Quiz = {
					Question = "Who should you fire at?",
					Options = { "PROXY: a 33% chance to hit", "Yourself: a 67% chance to keep the turn" },
					Answer = 2,
					Explain = "At low odds, fire at yourself: you probably keep the Arbiter, and the odds on the next cell rise.",
				},
			},
			{
				Say = "Fire at yourself.",
				Focus = "FireSelf",
				Allow = { "FireSelf" },
				Advance = "Action",
			},
			{
				Say = "1 CHARGED, 1 HOLLOW left. OVERCLOCK means your next shot won't end your turn, whatever happens. Use it.",
				Focus = "Slot:Overclock",
				Allow = { "Use:Overclock" },
				Advance = "Action",
			},
			{
				Say = "Fire at PROXY. Hit or miss, you'll still hold the Arbiter.",
				Focus = "FireOther",
				Allow = { "FireOpponent" },
				Advance = "Action",
			},
			{
				Say = "A miss, but it's still your turn, and the last cell must be CHARGED. Finish.",
				Focus = "FireOther",
				Allow = { "FireOpponent" },
				Advance = "Action",
			},
			{
				Say = "Tempo wins Trials as often as damage does.",
				Focus = "Device",
				Advance = "Finish",
			},
		},
	},
	{
		Id = "Sequencing",
		Name = "INVENTORY SEQUENCING",
		Description = "The order you spend instruments in matters.",
		Reward = { XP = 60, Marks = 40 },
		Rules = {
			TrialsToWin = 1,
			TurnTimer = 0,
			FixedIntegrity = 4,
			Forced = {
				Loads = { "CHC" },
				Starters = { 1 },
				Draws = { [1] = { [1] = { "Capacitor", "Lens" }, [2] = {} } },
			},
		},
		Beats = {
			{
				Say = "You hold a CAPACITOR and a LENS.",
				Focus = "Instruments",
				Advance = "Quiz",
				Quiz = {
					Question = "Which do you use first?",
					Options = { "Capacitor, then Lens", "Lens, then Capacitor" },
					Answer = 2,
					Explain = "Look first. If the cell is HOLLOW, the Capacitor would be spent for nothing.",
				},
			},
			{
				Say = "Use the LENS.",
				Focus = "Slot:Lens",
				Allow = { "Use:Lens" },
				Advance = "Action",
			},
			{
				Say = "CHARGED. Now the CAPACITOR is certain to pay off.",
				Focus = "Slot:Capacitor",
				Allow = { "Use:Capacitor" },
				Advance = "Action",
			},
			{
				Say = "Fire at PROXY.",
				Focus = "FireOther",
				Allow = { "FireOpponent" },
				Advance = "Action",
			},
			{
				Say = "Information first, commitment second.",
				Focus = "Device",
				Advance = "Finish",
			},
		},
	},
	{
		Id = "Mistakes",
		Name = "COMMON MISTAKES",
		Description = "Four ways subjects lose Trials they should win.",
		Reward = { XP = 60, Marks = 40 },
		Rules = {
			TrialsToWin = 1,
			TurnTimer = 0,
			FixedIntegrity = 3,
			Forced = { Loads = { "HCH" }, Starters = { 1 }, Draws = { [1] = { [1] = { "Suture" }, [2] = {} } } },
		},
		Beats = {
			{
				Say = "Mistake one: firing at an opponent when you know the cell is HOLLOW. You've learned the loaded cell.",
				Focus = "Track",
				Setup = { Reveal = { 1 } },
				Advance = "Quiz",
				Quiz = {
					Question = "The loaded cell is HOLLOW. What's the right play?",
					Options = { "Fire at PROXY", "Fire at yourself" },
					Answer = 2,
					Explain = "A known HOLLOW fired at yourself keeps the turn for free.",
				},
			},
			{
				Say = "Fire at yourself.",
				Focus = "FireSelf",
				Allow = { "FireSelf" },
				Advance = "Action",
			},
			{
				Say = "Mistake two: healing at full Integrity. Your SUTURE is refused, so it stays for later. Try hovering it.",
				Focus = "Slot:Suture",
				Advance = "Continue",
			},
			{
				Say = "Mistake three: forgetting the count. 1 CHARGED and 1 HOLLOW remain: 50%, not the 33% you started with.",
				Focus = "Probability",
				Advance = "Continue",
			},
			{
				Say = "Mistake four: hesitating forever. When the timer runs out, the Arbiter fires at you.",
				Focus = "Device",
				Advance = "Finish",
			},
		},
	},
}

Tutorials.ById = { Basic = Tutorials.Basic }
for _, seminar in Tutorials.Seminars do
	Tutorials.ById[seminar.Id] = seminar
end

function Tutorials.get(id: string)
	return Tutorials.ById[id]
end

return Tutorials
