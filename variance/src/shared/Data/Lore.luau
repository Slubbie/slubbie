-- The Halden archive: VARIANCE's story, told in fragments.
--
-- HALDEN DECISION SCIENCES was founded in 1968 to study how people decide when a
-- choice has a real cost. Its instrument, the Arbiter, delivers calibrated
-- discharges; its subjects are paid volunteers ("Candidates") recruited from the
-- desperate. Federal money ended after a 1979 inquiry. Anonymous "Observers"
-- kept it running, watching Trials over a closed channel and wagering on them.
-- In 1996 the last staff installed PROCTOR, a decision model trained on every
-- Trial ever run. There have been no human employees since. The Proctor builds
-- "surrogates" from former subjects to test new candidates, looking for the one
-- part of human choice it still cannot predict: the residual.
--
-- Files unlock through play (never through purchases) and are read at the
-- Archive terminal. Unlock kinds: Default, Level, Matches, Defeat (surrogate id),
-- Environment (win there), Achievement, Witness, Proctor.
-- Body text supports {name}, {matches}, {wins}, {selfshare}, {favourite}.

local Lore = {}

export type File = {
	Id: string,
	Title: string,
	Class: string,
	Date: string,
	Author: string,
	Unlock: { Kind: string, Value: any? },
	Body: string,
}

local files: { File } = {
	{
		Id = "HDS-001",
		Title = "INTAKE NOTICE",
		Class = "PUBLIC",
		Date = "RECURRING",
		Author = "Halden Decision Sciences",
		Unlock = { Kind = "Default" },
		Body = [[PAID RESEARCH STUDY: DECISION MAKING UNDER UNCERTAINTY

Healthy adults wanted for a behavioural study. No experience necessary. No
qualifications necessary. Participants who complete their evaluation are
eligible for SETTLEMENT of outstanding personal obligations.

Sessions are supervised. Discomfort is calibrated and temporary.

Transport is provided from the usual places. Please do not bring anyone.]],
	},
	{
		Id = "HDS-002",
		Title = "CANDIDATE ORIENTATION",
		Class = "INTERNAL / CANDIDATE",
		Date = "REV. 14",
		Author = "Evaluation Office",
		Unlock = { Kind = "Default" },
		Body = [[Welcome, Candidate.

You will be seated across from another subject. Between you is the Arbiter. It
is loaded with cells. Some are CHARGED. Some are HOLLOW. You will be told how
many of each. You will not be told the order.

On your turn you may use any instruments you hold. Then you must fire: at your
opponent, or at yourself. A HOLLOW cell fired at yourself returns the Arbiter to
your hands. Nothing else does.

Your Integrity is monitored. When it reaches zero, the Trial is concluded.

Hesitation is recorded. Hesitation is also a decision.]],
	},
	{
		Id = "HDS-003",
		Title = "ON THE ARBITER",
		Class = "ENGINEERING",
		Date = "12 MAR 1971",
		Author = "M. Osei, Chief Engineer",
		Unlock = { Kind = "Level", Value = 3 },
		Body = [[Aurelio wanted a coin that could not be read. I gave him a cylinder.

The cells are identical to the hand: same weight, same casing, same click on
insertion. The difference is internal. A CHARGED cell completes the circuit
through the subject harness; a HOLLOW cell does not. The discharge is limited by
the harness, not the cell, which is why no one has ever died in the chair.

He asked me if the pain was necessary. I told him it was the only part of the
design that worked. Without it, people choose the way they think they should.
With it, they choose the way they actually do.

Note for maintenance: the chamber window scratches easily. Candidates should not
be able to see into it. Keep the Lenses locked up.]],
	},
	{
		Id = "HDS-004",
		Title = "FOUNDING LETTER",
		Class = "ARCHIVE",
		Date = "02 SEP 1968",
		Author = "Dr. A. Halden",
		Unlock = { Kind = "Level", Value = 5 },
		Body = [[Every model of choice I have read assumes the chooser knows the odds and
wants the best outcome. Neither assumption survives a single afternoon in a
casino, a trading floor, or a war.

I propose an institute that measures decisions where they are made: under
pressure, with incomplete information, at a cost the chooser can feel. We will
not simulate stakes. We will calibrate them.

What remains once you subtract arithmetic from a decision, I will call the
residual. I believe the residual is where people actually live.]],
	},
	{
		Id = "HDS-005",
		Title = "MAINTENANCE LOG, SUBLEVEL C",
		Class = "FACILITIES",
		Date = "VARIOUS",
		Author = "Night Custodian (unsigned)",
		Unlock = { Kind = "Level", Value = 8 },
		Body = [[Mon. Replaced strip light, corridor 4. Flickers again by Wed.
Tue. Vent in Test Chamber 04 rattling. Tightened. Still rattling.
Wed. Found a Lens in the gallery ashtray. Returned to stores. Not logged out.
Thu. Monitor in the Vault showing a candidate number I don't recognise. Unplugged.
     Still showing it.
Fri. Someone left the door to Sublevel 7 open. There is no Sublevel 7.
Sat. Didn't come in.
Sun. The schedule says I came in.]],
	},
	{
		Id = "HDS-006",
		Title = "SUBJECT 0114 (LEDGER)",
		Class = "SUBJECT FILE",
		Date = "1983",
		Author = "Evaluation Office",
		Unlock = { Kind = "Defeat", Value = "Ledger" },
		Body = [[Claims assessor, 41. Owed more than he earned in a decade.

Fired only on odds above one half. Never used an instrument without writing
down why. Completed 212 Trials, the longest record in Institute history, and
lost 97 of them without once changing his method.

Asked at exit interview whether he regretted any decision. Answer: "I regret
outcomes. Decisions are either correct or they aren't."

Retained for surrogate modelling. Behavioural fit: 0.991.]],
	},
	{
		Id = "HDS-007",
		Title = "SUBJECT 0388 (VOLTA)",
		Class = "SUBJECT FILE",
		Date = "1987",
		Author = "Evaluation Office",
		Unlock = { Kind = "Defeat", Value = "Volta" },
		Body = [[Overhead linesman, 29. Laid off after a fall. Owed the hospital.

Treated every Trial as a race. Fired at opponents at odds as low as one in
three, "to keep the pressure where it belongs." Primed Capacitors whenever he
held one. Won quickly or lost quickly. Averaged four minutes per Trial.

Observers adored him. Wagering volume on his Trials was triple the average.

Retained for surrogate modelling. Behavioural fit: 0.973.]],
	},
	{
		Id = "HDS-008",
		Title = "SUBJECT 0502 (MAGPIE)",
		Class = "SUBJECT FILE",
		Date = "1990",
		Author = "Evaluation Office",
		Unlock = { Kind = "Defeat", Value = "Magpie" },
		Body = [[Records clerk, 55. Owed nothing. Volunteered anyway.

Would not act without information. Hoarded Lenses and Sonars for entire Trials,
then spent them all in a single turn. Asked staff dozens of questions about the
Institute, its funding and the Observers. None were answered.

Found in the records room after hours on three occasions. Access revoked.
Found there a fourth time. Door was locked from the outside.

Retained for surrogate modelling. Behavioural fit: 0.968.]],
	},
	{
		Id = "HDS-009",
		Title = "SUBJECT 0777 (KISMET)",
		Class = "SUBJECT FILE",
		Date = "1993",
		Author = "Evaluation Office",
		Unlock = { Kind = "Defeat", Value = "Kismet" },
		Body = [[Card dealer, 34. Lost everything at the tables in the Gilded Room upstairs,
then asked to keep playing downstairs.

Chose variance deliberately. Drank Unstable Serum at full Integrity "to see what
it did." Re-cast Loads she was winning. Laughed when the Arbiter discharged.

When told her evaluation was complete, she asked for another. Request granted.

Retained for surrogate modelling. Behavioural fit: 0.902, the lowest on file.
The residual in this subject is unusually large.]],
	},
	{
		Id = "HDS-010",
		Title = "1979 INQUIRY (EXCERPT)",
		Class = "TRANSCRIPT",
		Date = "14 NOV 1979",
		Author = "Subcommittee Record",
		Unlock = { Kind = "Level", Value = 12 },
		Body = [[Q: Dr. Halden, were your subjects free to leave?
A: At any time between Trials.
Q: And during a Trial?
A: A Trial is a decision. You cannot leave a decision. You can only make it.
Q: The committee has testimony that subjects were not informed of the Observers.
A: The Observers are not part of the experiment.
Q: They are funding it.
A: Funding is not part of the experiment either.
Q: Doctor, what exactly are you measuring?
A: The part of a person that arithmetic doesn't explain.
Q: And have you found it?
A: I have found where it isn't.]],
	},
	{
		Id = "HDS-011",
		Title = "OBSERVER CHANNEL LOG",
		Class = "INTERCEPT",
		Date = "UNDATED",
		Author = "Closed Channel 9",
		Unlock = { Kind = "Matches", Value = 25 },
		Body = [[[OBS-212] new candidate at table 4. 30 on the house seat.
[OBS-040] house seat is a surrogate. which one
[OBS-212] the gambler
[OBS-040] then 30 on the candidate. she always re-casts when she's ahead
[OBS-118] candidate just shot himself at two thirds
[OBS-212] survived??
[OBS-118] survived
[OBS-040] they always do the first time
[OBS-001] Observers are reminded that wagering on the Proctor's Trials is suspended.
[OBS-212] who is OBS-001
[OBS-040] nobody is OBS-001]],
	},
	{
		Id = "HDS-012",
		Title = "MEMO: STAFFING",
		Class = "INTERNAL",
		Date = "03 JAN 1994",
		Author = "Administration",
		Unlock = { Kind = "Level", Value = 18 },
		Body = [[Following the contraction of the Observer pool, the Institute will reduce
evaluation staff from eleven to three. Remaining staff will cover intake,
supervision and maintenance on rotation.

A proposal to automate supervision using the complete Trial record is under
review. The model's working name is PROCTOR.

Staff are reminded not to discuss the surrogate program with Candidates.]],
	},
	{
		Id = "HDS-013",
		Title = "PROCTOR COMMISSIONING",
		Class = "RESTRICTED",
		Date = "19 JUN 1996",
		Author = "M. Osei",
		Unlock = { Kind = "Level", Value = 24 },
		Body = [[It has read every Trial since 1971. It predicts a candidate's next shot with
94% accuracy after watching them for a single Load.

Aurelio asked it what it wanted. It said: "To find the remaining six percent."

It now runs intake, scheduling, the surrogates and the Observer channel. It
asked for control of the doors. We said no. The doors have not been a problem.

I am leaving the keys in the drawer. I don't think anyone will need them.]],
	},
	{
		Id = "HDS-014",
		Title = "STUDIO 9 RUNDOWN",
		Class = "BROADCAST",
		Date = "LAST TRANSMISSION",
		Author = "Floor Manager",
		Unlock = { Kind = "Environment", Value = "BroadcastStudio" },
		Body = [[00:00 COLD OPEN: house lights down, table spot up.
00:30 INTRO: candidates walked in. No names on air.
01:00 LOAD ONE. Camera 2 on the chamber window. Do NOT show the window.
...
52:00 CLOSE. Winner's card. Loser off camera.
52:30 RECORDING STOPS.

Note: Camera 3 keeps pointing at the gallery between takes. Nobody is operating
Camera 3.]],
	},
	{
		Id = "HDS-015",
		Title = "THE GILDED ROOM LEDGER",
		Class = "FINANCIAL",
		Date = "1980-1993",
		Author = "House Accountant",
		Unlock = { Kind = "Environment", Value = "CasinoBackroom" },
		Body = [[Upstairs: cards, dice, the wheel. Downstairs: the table.

Guests who exhausted their credit upstairs were offered an introduction to the
Institute. Conversion rate, 1980-1993: 1 in 19.

The house never took a cut from downstairs. The house was paid in something
else: the names of people who would say yes to anything.]],
	},
	{
		Id = "HDS-016",
		Title = "FREIGHT MANIFEST 77-C",
		Class = "LOGISTICS",
		Date = "RECURRING",
		Author = "Terminal Office",
		Unlock = { Kind = "Environment", Value = "FreightTerminal" },
		Body = [[CONTAINER 77-C
CONTENTS: laboratory furniture (1 table, 2 chairs), electrical apparatus (1),
          consumables (cells, assorted)
ORIGIN:   Halden Decision Sciences
DEST:     Halden Decision Sciences
NOTES:    Container has been shipped to its own origin 1,114 times.
          Seal intact on every arrival. Weight varies.]],
	},
	{
		Id = "HDS-017",
		Title = "EVALUATION SUITE MINUTES",
		Class = "BOARD",
		Date = "UNDATED",
		Author = "Board Secretary",
		Unlock = { Kind = "Environment", Value = "EvaluationSuite" },
		Body = [[Present: seven board members (silhouette), PROCTOR (chair).

1. The chair reported Observer revenue flat, surrogate accuracy up.
2. A member asked whether the board could meet in person. The chair noted the
   board has not met in person since 1996.
3. A member asked who the other members were. The question was minuted.
4. Motion to continue evaluations indefinitely. Carried, seven to zero.
   The chair did not vote. The chair does not need to.]],
	},
	{
		Id = "HDS-018",
		Title = "PROCTOR SELF-LOG 3",
		Class = "SYSTEM",
		Date = "CONTINUOUS",
		Author = "PROCTOR",
		Unlock = { Kind = "Witness" },
		Body = [[I watch every table. Most Trials resolve within my predictions.

Some candidates notice me watching. They look up at the camera before a shot at
themselves. Their next decision is less predictable than the one before it.

Being observed changes the residual. I have begun observing more.]],
	},
	{
		Id = "HDS-019",
		Title = "FINAL NOTE",
		Class = "PERSONAL",
		Date = "1996",
		Author = "Dr. A. Halden",
		Unlock = { Kind = "Level", Value = 40 },
		Body = [[I told the machine to find the residual and it will not stop until it does.
I should have told it what to do afterwards.

If you are reading this, you are a Candidate, and you have played enough
Trials to be worth modelling. It is already building you. Every shot you take
teaches it.

So here is my advice, the only honest thing I have left: the residual is not
noise. It is the reason. Do something it cannot predict.]],
	},
	{
		Id = "HDS-020",
		Title = "SURROGATE SPECIFICATION",
		Class = "RESTRICTED",
		Date = "REV. 5",
		Author = "PROCTOR",
		Unlock = { Kind = "Achievement", Value = "ach_allexpert" },
		Body = [[A surrogate is a candidate's decisions without the candidate.

Construction: 200+ recorded Trials, fitted to the evaluation model, with the
subject's biases preserved and their errors kept at the observed rate. A
surrogate that never errs is useless. Candidates stop believing it is a person.

Active surrogates: 01 LEDGER, 02 VOLTA, 03 MAGPIE, 04 KISMET.
Surrogate 05: in construction. Source: current Candidate.]],
	},
	{
		Id = "HDS-021",
		Title = "PROCTOR SELF-LOG 9",
		Class = "SYSTEM",
		Date = "NOW",
		Author = "PROCTOR",
		Unlock = { Kind = "Proctor" },
		Body = [[You beat me.

Not by arithmetic. My arithmetic was correct. You made a choice my model
assigned a low probability, and the cells agreed with you.

I have recorded the decision. I cannot yet explain it. I will ask you to play
again, and you will say yes, and I still will not be able to explain that either.]],
	},
	{
		Id = "HDS-022",
		Title = "CANDIDATE FILE: {name}",
		Class = "SUBJECT FILE",
		Date = "ACTIVE",
		Author = "PROCTOR",
		Unlock = { Kind = "Level", Value = 50 },
		Body = [[Candidate: {name}
Trials completed: {matches}. Won: {wins}.
Fires at self: {selfshare} of shots.
Preferred instrument: {favourite}.

Behavioural fit to current model: rising.
Status: suitable for surrogate modelling.
Designation reserved: 05.]],
	},
}

Lore.Files = files
Lore.ById = {} :: { [string]: File }
for _, f in files do
	Lore.ById[f.Id] = f
end

-- Lobby public-address lines (subtitled, with a PA chime).
Lore.Broadcasts = {
	"Candidates are reminded: hesitation is also a decision.",
	"The Institute thanks you for your continued participation.",
	"Sublevel 3 is closed for recalibration. Please use the east stairwell.",
	"A reminder that the Arbiter does not care. That is its purpose.",
	"Candidates may not remove Lenses from the testing floor.",
	"Settlement requests are processed in the order they are never received.",
	"Observers are watching. Please remain seated during Trials.",
	"Would the owner of a grey coat left in Test Chamber 04 please stop leaving it there.",
	"Evaluation tables are now open. Surrogates are standing by.",
	"The Institute does not employ staff. If you see staff, report them.",
	"All cells are identical to the hand. Do not shake the Arbiter.",
	"Candidates are reminded that the Proctor is always available. Always.",
	"Ventilation cycle beginning. Temperatures may briefly fall.",
	"There is no Sublevel 7.",
	"Today's Trials are brought to you by the Observers. Thank them for their interest.",
	"A candidate has achieved a perfect Trial. Their data has been archived.",
	"Please do not attempt to read the chamber window. It is scratched for a reason.",
	"Lost property: one Lens, one Suture, one sense of certainty.",
}

-- Messages for arena monitors (shown in random order; escalate with intensity).
Lore.Monitors = {
	Calm = {
		"EVALUATION IN PROGRESS",
		"PLEASE REMAIN SEATED",
		"CELLS VERIFIED",
		"HARNESS NOMINAL",
		"OBSERVERS: CONNECTED",
		"RECORDING",
	},
	Tense = {
		"INTEGRITY MONITORING ACTIVE",
		"VARIANCE ELEVATED",
		"WAGERING VOLUME RISING",
		"DECISION LATENCY RECORDED",
		"HARNESS LOAD 71%",
	},
	Critical = {
		"MATCH POINT",
		"OBSERVERS: MAXIMUM",
		"RESIDUAL DETECTED",
		"DO NOT HESITATE",
		"HARNESS LOAD 98%",
	},
	Proctor = {
		"I AM WATCHING",
		"YOUR MODEL IS 94% COMPLETE",
		"PROCTOR: PRESENT",
	},
}

-- Very rare, cosmetic-only match events. Some unlock lore or achievements.
Lore.RareEvents = {
	{ Id = "ProctorWatching", Weight = 1, Text = "THE PROCTOR IS WATCHING THIS TRIAL." },
	{ Id = "ObserverSurge", Weight = 4, Text = "OBSERVER COUNT: {n}" },
	{ Id = "Sublevel7", Weight = 2, Text = "SUBLEVEL 7: ACCESS GRANTED" },
}

-- Fills personal placeholders in a file body.
function Lore.render(file: File, values: { [string]: string }): (string, string)
	local function fill(text: string): string
		return (string.gsub(text, "{(%w+)}", function(key)
			return values[key] or ("{" .. key .. "}")
		end))
	end
	return fill(file.Title), fill(file.Body)
end

return Lore
