-- The coach panel during Orientation and seminars. One idea per beat: a line
-- of instruction, what to do next (continue, act, or answer a question), the
-- lesson's progress and a way out. Highlights on the HUD and camera pulls are
-- driven by the beat's Focus (MatchHUD and TutorialController read it).

local Kit = require(script.Parent.Parent.Kit)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)

local TutorialOverlay = {}
TutorialOverlay.__index = TutorialOverlay

local ADVANCE_TEXT = {
	Action = "Take the highlighted action.",
	PlayerTurn = "Play until it's your turn again.",
	TrialEnd = "Finish this Trial.",
	MatchEnd = "Finish the match.",
}

function TutorialOverlay.new(ui, controllers)
	local self = setmetatable({}, TutorialOverlay)
	self.UI = ui
	self.C = controllers
	self.Main = false
	self.Visible = false
	local panel = Kit.panel(ui.Hud, { Name = "Coach", Size = UDim2.fromOffset(380, 0), Position = UDim2.new(0, 16, 0.5, -40), AnchorPoint = Vector2.new(0, 0.5), Color = "Bg", Visible = false })
	panel.AutomaticSize = Enum.AutomaticSize.Y
	Kit.stroke(panel, "Accent", 1, 0)
	Kit.padding(panel, 14, 16)
	Kit.list(panel, "Y", 8)
	self.Frame = panel
	self.Header = Kit.label(panel, { Text = "", Font = "Mono", TextSize = "Tiny", Color = "Accent", LayoutOrder = 1 })
	self.Progress = Kit.bar(panel, { Size = UDim2.new(1, 0, 0, 3), LayoutOrder = 2, Value = 0 })
	self.Title = Kit.label(panel, { Text = "", Font = "Display", TextSize = "Body", LayoutOrder = 3 })
	self.Say = Kit.label(panel, { Text = "", Font = "Body", TextSize = "Body", Wrap = true, AutoY = true, LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 0) })
	self.Next = Kit.label(panel, { Text = "", Font = "Mono", TextSize = "Small", Color = "Dim", Wrap = true, AutoY = true, LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 0) })
	self.Options = Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6, Parent = panel }) :: Frame
	Kit.list(self.Options, "Y", 6)
	self.Feedback = Kit.label(panel, { Text = "", Font = "Body", TextSize = "Small", Wrap = true, AutoY = true, LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 0) })
	local row = Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 8, Parent = panel }) :: Frame
	self.ContinueButton = Kit.button(row, {
		Text = "CONTINUE",
		Style = "Primary",
		Size = UDim2.new(0.62, -4, 1, 0),
		Sound = "Confirm",
		OnClick = function()
			task.spawn(function()
				self.C.TutorialController:continue()
			end)
		end,
	})
	Kit.button(row, {
		Text = "QUIT LESSON",
		Style = "Ghost",
		Size = UDim2.new(0.38, 0, 1, 0),
		Position = UDim2.fromScale(0.62, 0),
		TextSize = "Tiny",
		OnClick = function()
			task.spawn(function()
				if Kit.confirm("QUIT LESSON", "Leave the lesson? Progress in this lesson is lost.", "QUIT", true) then
					self.C.TutorialController:quit()
				end
			end)
		end,
	})
	-- Space / A continue when a beat is waiting for it.
	controllers.InputController.Action:Connect(function(action, phase)
		if phase == "Begin" and self.Visible and action == "Back" and self.ContinueButton.Visible then
			self.C.TutorialController:continue()
		end
	end)
	return self
end

function TutorialOverlay:Open(status)
	if status == nil then
		return
	end
	local firstShow = not self.Visible
	self.Visible = true
	self.Frame.Visible = true
	local beat = status.Beat
	local changed = self.LastIndex ~= status.Index or self.LastLesson ~= status.Lesson
	self.LastIndex, self.LastLesson = status.Index, status.Lesson
	self.Header.Text = string.format("%s  ·  %d / %d", status.Name or "TRAINING", math.min(status.Index or 1, status.Count or 1), status.Count or 1)
	Kit.setBar(self.Progress, (status.Index or 1) / math.max(status.Count or 1, 1), true)
	if status.Done then
		self.Title.Text = "LESSON COMPLETE"
		self.Say.Text = "Well done. Rewards have been added to your file."
		self.Next.Text = ""
		self.ContinueButton.Visible = false
		self:clearOptions()
		return
	end
	if beat == nil then
		return
	end
	self.Title.Text = beat.Title or ""
	self.Title.Visible = beat.Title ~= nil
	if changed then
		self.Feedback.Text = ""
		-- Typewriter the line unless motion is reduced.
		local text = beat.Say or ""
		if self.C.SettingsController:get("ReducedMotion") then
			self.Say.Text = text
		else
			local token = os.clock()
			self.TypeToken = token
			task.spawn(function()
				for i = 1, #text, 3 do
					if self.TypeToken ~= token then
						return
					end
					self.Say.Text = string.sub(text, 1, i + 2)
					task.wait(0.012)
				end
				self.Say.Text = text
			end)
		end
		if not firstShow then
			Motion.punch(self.Frame, 0.02, 0.2)
		end
	end
	local advance = beat.Advance
	self.ContinueButton.Visible = advance == "Continue" or advance == "Finish"
	Kit.setText(self.ContinueButton, if advance == "Finish" then "FINISH" else "CONTINUE")
	if beat.Free then
		self.Next.Text = "Play it your way. Every action is allowed."
	else
		self.Next.Text = ADVANCE_TEXT[advance or ""] or ""
	end
	self:clearOptions()
	if beat.Quiz then
		self.Next.Text = beat.Quiz.Question
		for i, option in beat.Quiz.Options do
			Kit.button(self.Options, {
				Text = option,
				Size = UDim2.new(1, 0, 0, 34),
				LayoutOrder = i,
				TextSize = "Tiny",
				OnClick = function()
					task.spawn(function()
						local ok, result = self.C.TutorialController:answer(i)
						if ok and type(result) == "table" then
							self.Feedback.Text = (if result.Correct then "CORRECT. " else "NOT QUITE. ") .. (result.Explain or "")
							Theme.bind(self.Feedback, "TextColor3", if result.Correct then "Good" else "Warn")
						end
					end)
				end,
			})
		end
	end
	if status.LastAnswer then
		self.Feedback.Text = (if status.LastAnswer.Correct then "CORRECT. " else "NOT QUITE. ") .. (status.LastAnswer.Explain or "")
		Theme.bind(self.Feedback, "TextColor3", if status.LastAnswer.Correct then "Good" else "Warn")
	end
	if self.ContinueButton.Visible then
		self.UI:focus(self.ContinueButton)
	end
end

function TutorialOverlay:clearOptions()
	for _, child in self.Options:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function TutorialOverlay:Close()
	self.Visible = false
	self.Frame.Visible = false
	self.TypeToken = nil
end

return TutorialOverlay
