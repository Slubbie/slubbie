-- Client-side message bus between gameplay systems and the interface, so
-- neither has to require the other.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local Bus = {
	OpenPage = Signal.new(), -- (page, args?) open a menu page
	ClosePages = Signal.new(), -- ()
	PageChanged = Signal.new(), -- (page or nil)
	CoursePreview = Signal.new(), -- (courseId)
	CourseResults = Signal.new(), -- (result, run)
	Countdown = Signal.new(), -- (startAt server time, label?)
	Split = Signal.new(), -- (index, seconds, delta?)
	Dialogue = Signal.new(), -- (npcId, response)
	Notify = Signal.new(), -- (payload) toasts, banners, unlock cards
	Banner = Signal.new(), -- (title, subtitle?, color?)
	Confirm = Signal.new(), -- (title, text, options { { Text, Callback } })
	Hint = Signal.new(), -- (text or nil) contextual input hint line
	Objective = Signal.new(), -- () pinned objectives changed
	Mode = Signal.new(), -- (kind, data) race/relay/tower/endless state for the HUD
	Lesson = Signal.new(), -- (lesson or nil, stepIndex, progress)
	Timer = Signal.new(), -- (seconds or nil) quest/contract countdown
	Carry = Signal.new(), -- (carrying, fragile)
}

return Bus
