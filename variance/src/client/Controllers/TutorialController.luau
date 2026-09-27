-- Orientation and seminars on the client: shows the coach panel for each
-- beat, points the camera and the HUD at whatever the beat is about, and sends
-- Continue / Answer / Quit. The lesson itself runs on the server's real engine,
-- so the controller only ever reflects the status it is sent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableLayout = require(ReplicatedStorage.Variance.Visual.TableLayout)
local Signal = require(ReplicatedStorage.Variance.Util.Signal)

local TutorialController = {}
TutorialController.Changed = Signal.new() -- (status)
TutorialController.Status = nil :: { [string]: any }?

function TutorialController:Init(controllers)
	self.Controllers = controllers
end

function TutorialController:active(): boolean
	return TutorialController.Status ~= nil and not TutorialController.Status.Done
end

-- What the current beat wants highlighted (MatchHUD reads this).
function TutorialController:focus(): string?
	local status = TutorialController.Status
	return status and status.Beat and status.Beat.Focus or nil
end

-- Whether the current beat allows an action (UI hint only; the server filters).
function TutorialController:allows(kind: string, id: string?): boolean
	local status = TutorialController.Status
	local beat = status and status.Beat
	if beat == nil or beat.Free or beat.Allow == nil then
		return true
	end
	for _, allowed in beat.Allow do
		if allowed == "Any" or allowed == kind or (id and allowed == kind .. ":" .. id) then
			return true
		end
	end
	return false
end

function TutorialController:continue()
	return self.Controllers.NetworkClient:request("Tutorial.Continue")
end

function TutorialController:answer(option: number)
	return self.Controllers.NetworkClient:request("Tutorial.Answer", option)
end

function TutorialController:quit()
	return self.Controllers.NetworkClient:request("Tutorial.Quit")
end

function TutorialController:start(lessonId: string)
	local ok, err = self.Controllers.NetworkClient:request("Tutorial.Start", lessonId)
	if not ok then
		self.Controllers.UIController:toast("TRAINING", tostring(err), "Warn")
	end
	return ok
end

-- World focus: point the camera at what the beat talks about.
local function worldFocus(self, focus: string?)
	local presenter = self.Controllers.MatchPresenter
	local arena = presenter:arena()
	if focus == nil or arena == nil then
		return
	end
	local origin = arena:GetAttribute("Origin") or CFrame.identity
	local camera = self.Controllers.CameraController
	local client = self.Controllers.MatchClient
	if focus == "Device" then
		camera:focus(self.Controllers.WeaponController:current().Position, 0.7, 3)
	elseif focus == "Counts" then
		camera:focus((origin * TableLayout.rackCFrame()).Position, 0.7, 3)
	elseif focus == "Opponent" or focus == "FireOther" then
		local opponents = client:opponents()
		local head = opponents[1] and presenter:subjectHead(opponents[1])
		if head then
			camera:focus(head, 0.6, 3)
		end
	elseif focus == "Instruments" or string.sub(focus, 1, 5) == "Slot:" then
		local seat = client:info(client:you()) and client:info(client:you()).Seat or 1
		camera:focus((origin * TableLayout.trayCFrame(seat)).Position, 0.6, 3)
	end
end

function TutorialController:Start()
	local network = self.Controllers.NetworkClient
	local ui = self.Controllers.UIController
	network:onPush("Tutorial", function(status)
		local previous = TutorialController.Status
		TutorialController.Status = status
		TutorialController.Changed:Fire(status)
		if status == nil then
			ui:close("TutorialOverlay")
			return
		end
		ui:open("TutorialOverlay", status)
		local beatChanged = previous == nil or previous.Index ~= status.Index or previous.Lesson ~= status.Lesson
		if beatChanged and status.Beat then
			worldFocus(self, status.Beat.Focus)
			self.Controllers.AudioController:play("Toast")
		end
	end)
	self.Controllers.MatchClient.Ended:Connect(function()
		if TutorialController.Status and TutorialController.Status.Done then
			TutorialController.Status = nil
			TutorialController.Changed:Fire(nil)
			ui:close("TutorialOverlay")
		end
	end)
end

return TutorialController
