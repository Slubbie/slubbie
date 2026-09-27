-- Surrogate dialogue and announcer lines.
--
-- DialogueService (server) picks a line when a trigger fires, respecting a
-- per-trigger cooldown and chance, and sends it as a non-blocking subtitle.
-- Nothing here ever delays gameplay. Templates: {name} opponent name,
-- {rate} a percentage, {item} an instrument name, {n} a number.

local Dialogue = {}

-- Chance (0-1) and cooldown (seconds) per trigger.
Dialogue.Triggers = {
	Intro = { Chance = 1, Cooldown = 0 },
	TrialWin = { Chance = 0.9, Cooldown = 0 },
	TrialLose = { Chance = 0.9, Cooldown = 0 },
	MatchWin = { Chance = 1, Cooldown = 0 },
	MatchLose = { Chance = 1, Cooldown = 0 },
	LuckyEscape = { Chance = 0.8, Cooldown = 20 },
	SelfStreak = { Chance = 0.8, Cooldown = 40 },
	LowSelf = { Chance = 0.7, Cooldown = 45 },
	LowOpponent = { Chance = 0.7, Cooldown = 45 },
	MatchPoint = { Chance = 1, Cooldown = 60 },
	Unusual = { Chance = 0.7, Cooldown = 30 },
	Hesitation = { Chance = 0.9, Cooldown = 45 },
	Hit = { Chance = 0.35, Cooldown = 18 },
	Hurt = { Chance = 0.35, Cooldown = 18 },
	OwnItem = { Chance = 0.25, Cooldown = 25 },
	OpponentCombo = { Chance = 0.8, Cooldown = 30 },
	SuddenDeath = { Chance = 1, Cooldown = 0 },
	Read = { Chance = 0.6, Cooldown = 50 },
}

Dialogue.Lines = {
	Ledger = {
		Intro = { "Let's keep this orderly.", "I've done the arithmetic. Have you?", "Two columns. Yours and mine." },
		TrialWin = { "The numbers held.", "Entered and balanced." },
		TrialLose = { "A variance. Noted.", "Outcomes aren't decisions. I'll allow it." },
		MatchWin = { "Balanced books. Good evening.", "The expected value was on my side. It usually is." },
		MatchLose = { "Correct decisions, incorrect outcome. It happens.", "File it under luck. Yours." },
		LuckyEscape = { "At those odds? Remarkable.", "You're overdrawn on luck, {name}." },
		SelfStreak = { "Again at yourself. Interesting accounting.", "That's {n} in a row. The odds don't remember." },
		LowSelf = { "One point left. Still solvent.", "Margins are thin. Arithmetic isn't." },
		LowOpponent = { "One point, {name}. Spend it carefully.", "Your account is nearly closed." },
		MatchPoint = { "Final column. Let's total it." },
		Unusual = { "That was not the correct play.", "I'd like to see your working." },
		Hesitation = { "Take your time. The odds won't change.", "Still calculating? So am I." },
		Hit = { "As projected.", "Debit." },
		Hurt = { "Within tolerance.", "A loss. Recorded." },
		OwnItem = { "Better to know.", "A prudent expense." },
		OpponentCombo = { "Efficient. I approve, reluctantly." },
		SuddenDeath = { "Both accounts at zero. Tie-break." },
	},
	Volta = {
		Intro = { "Hands on the table. Let's go.", "I hope you're quick.", "Feel that hum? That's the good part." },
		TrialWin = { "Live wire, baby.", "Faster than you." },
		TrialLose = { "Ha! Okay. Okay.", "You felt that too, right?" },
		MatchWin = { "Lights out.", "Too slow, {name}." },
		MatchLose = { "Good. Finally someone with a pulse.", "Again. Right now." },
		LuckyEscape = { "No way that was hollow.", "You got lucky and you know it." },
		SelfStreak = { "Scared to point it at me?", "Point it this way for once." },
		LowSelf = { "One left. Now it gets fun.", "Running hot." },
		LowOpponent = { "One more spark, {name}.", "I can smell the ozone." },
		MatchPoint = { "Last one. Make it loud." },
		Unusual = { "Now THAT'S a play.", "Wild. I like it." },
		Hesitation = { "Tick tock.", "Pull it already." },
		Hit = { "Zap.", "Feel that?" },
		Hurt = { "Yeah! Again!", "That's the stuff." },
		OwnItem = { "Charging up.", "Full power." },
		OpponentCombo = { "Fancy. Doesn't matter." },
		SuddenDeath = { "Everybody down! Round two!" },
	},
	Magpie = {
		Intro = { "I've read your file.", "Let's see what you know.", "Information is the only currency here." },
		TrialWin = { "Filed.", "Exactly as recorded." },
		TrialLose = { "I was missing a page.", "Hm. Incomplete data." },
		MatchWin = { "Your file is complete now.", "Thank you for the information." },
		MatchLose = { "You knew something I didn't. Tell me what.", "I'll need to reorganise." },
		LuckyEscape = { "You didn't know that. You guessed.", "Guessing isn't knowing, {name}." },
		SelfStreak = { "You keep testing the same drawer.", "Pattern noted." },
		LowSelf = { "One entry left in my column.", "I know exactly how bad this is." },
		LowOpponent = { "I know your number, {name}. It's one." },
		MatchPoint = { "The last page. Let's read it together." },
		Unusual = { "That makes no sense unless you know something.", "What did you see?" },
		Hesitation = { "You don't know, do you?", "Uncertainty looks uncomfortable on you." },
		Hit = { "Confirmed.", "As I suspected." },
		Hurt = { "An error in my records.", "Unexpected." },
		OwnItem = { "Just a quick look.", "Let me check something." },
		OpponentCombo = { "You looked first. Good habit." },
		SuddenDeath = { "Both files closed at once. Reopening." },
	},
	Kismet = {
		Intro = { "Feeling lucky? I always am.", "Let's make it interesting.", "House rules: there are none." },
		TrialWin = { "Lady luck owes me money.", "Ha! Called it. Sort of." },
		TrialLose = { "Ooh, that stung. Deal again.", "The wheel turns." },
		MatchWin = { "Double or nothing?", "Luck's a skill if you practise." },
		MatchLose = { "Beautiful. Again?", "You took the pot. Enjoy it." },
		LuckyEscape = { "Now you're gambling!", "Welcome to the fun side, {name}." },
		SelfStreak = { "You're on a streak. Streaks end.", "Let it ride!" },
		LowSelf = { "All in.", "Last chip. Best chip." },
		LowOpponent = { "One chip left, {name}? Push it." },
		MatchPoint = { "Final hand. No folding." },
		Unusual = { "Bold! I love bold.", "Now we're playing." },
		Hesitation = { "Just pick one, the cells don't care.", "Roll the dice already." },
		Hit = { "Lucky me.", "Snake eyes for you." },
		Hurt = { "Ha! Worth it.", "Ouch. Again!" },
		OwnItem = { "Let's shake things up.", "What's the worst that could happen?" },
		OpponentCombo = { "Stacking the deck? Cute." },
		SuddenDeath = { "Everyone busts! Tiebreaker!" },
	},
	Proctor = {
		Intro = { "Candidate. I have been expecting you.", "Your model is incomplete. Let us complete it.", "Proceed." },
		TrialWin = { "As predicted.", "Your behaviour remains within bounds." },
		TrialLose = { "Unexpected. Recording.", "There it is. The residual." },
		MatchWin = { "Evaluation complete. You were predictable.", "Thank you. Surrogate 05 is nearly ready." },
		MatchLose = { "I could not predict that. Play again.", "Remarkable. I will study this." },
		LuckyEscape = { "My model gave that a low probability of survival.", "You were not supposed to survive that." },
		SelfStreak = { "You favour yourself as a target. I have adjusted.", "Your pattern is clear, {name}." },
		LowSelf = { "My Integrity is irrelevant. Continue." },
		LowOpponent = { "One point. Your decisions are now very informative." },
		MatchPoint = { "The final measurement." },
		Unusual = { "That decision is outside your model. Why?", "Interesting." },
		Hesitation = { "Your hesitation is also data.", "I am recording the silence." },
		Hit = { "Predicted.", "Within expectation." },
		Hurt = { "Acceptable.", "The cost of measurement." },
		OwnItem = { "Verifying.", "Adjusting parameters." },
		OpponentCombo = { "An efficient sequence. You have learned." },
		SuddenDeath = { "Mutual collapse. Resetting apparatus." },
		Read = {
			"At even odds you fire at yourself {rate} of the time.",
			"You reach for {item} more than anything else.",
			"You have fired at yourself {n} times in a row. I know what comes next.",
			"Your decisions deviate from the textbook by {rate}. I am learning the difference.",
		},
	},
	Proxy = {
		Intro = { "TRAINING UNIT ONLINE.", "CALIBRATION SEQUENCE READY." },
		TrialWin = { "TRAINING UNIT PREVAILS. PLEASE TRY AGAIN." },
		TrialLose = { "TRAINING UNIT DEFEATED. GOOD." },
		MatchWin = { "EVALUATION: REPEAT ORIENTATION." },
		MatchLose = { "ORIENTATION COMPLETE." },
		Hurt = { "OUCH. PROCEDURALLY." },
		Hit = { "CONTACT." },
	},
}

-- Announcer (Institute PA) lines used as subtitles during matches.
Dialogue.Announcer = {
	MatchStart = { "Evaluation begins. {mode}.", "Candidates seated. {mode} is now in session." },
	TrialStart = { "Trial {trial}. Integrity set to {integrity}." },
	TrialStartFinal = { "Final Trial. Integrity set to {integrity}." },
	Load = { "Loading. {charged} charged. {hollow} hollow.", "{charged} charged, {hollow} hollow. Sequence sealed." },
	LoadBlind = { "Loading {total} cells. Composition withheld." },
	Surge = { "The final cell carries a surge." },
	SuddenDeath = { "Mutual collapse. Sudden death." },
	MatchPoint = { "Match point." },
	Timeout = { "Hesitation limit reached. The Arbiter decides." },
	Modifiers = { "Rule modification: {list}." },
}

function Dialogue.fill(line: string, values: { [string]: any }): string
	return (string.gsub(line, "{(%w+)}", function(key)
		local v = values[key]
		if v == nil then
			return ""
		end
		return tostring(v)
	end))
end

return Dialogue
