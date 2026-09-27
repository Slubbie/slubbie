-- Watching other Trials: the live list, joining a table as a spectator and the
-- spectator's camera controls (orbit, or ride along in any seat).
--
-- Spectators receive public information only, delayed in competitive modes
-- (the server does the delaying); this controller never sees anything a
-- player's private view contains.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Variance.Util.Signal)

local SpectatorController = {}
SpectatorController.Changed = Signal.new()

local viewIndex = 0 -- 0 = orbit, n = seat of the n-th subject

function SpectatorController:Init(controllers)
	self.Controllers = controllers
end

function SpectatorController:list(): { { [string]: any } }
	local ok, result = self.Controllers.NetworkClient:request("Spectate.List")
	if ok and type(result) == "table" then
		return result
	end
	return {}
end

function SpectatorController:watch(matchId: string): (boolean, string?)
	local ok, err = self.Controllers.NetworkClient:request("Spectate.Start", matchId)
	if not ok then
		self.Controllers.UIController:toast("CAN'T WATCH", tostring(err), "Warn")
		return false, err
	end
	viewIndex = 0
	self.Controllers.UIController:close()
	return true
end

function SpectatorController:stop()
	self.Controllers.NetworkClient:request("Spectate.Stop")
end

function SpectatorController:active(): boolean
	return self.Controllers.MatchClient:spectating()
end

-- Cycles orbit -> seat 1 -> seat 2 -> ... -> orbit.
function SpectatorController:cycle(direction: number)
	local client = self.Controllers.MatchClient
	local scene = client.Scene
	if scene == nil or not scene.Spectating then
		return
	end
	local ids = {}
	for id in scene.Subjects do
		table.insert(ids, id)
	end
	table.sort(ids)
	viewIndex = (viewIndex + direction) % (#ids + 1)
	local camera = self.Controllers.CameraController
	if viewIndex == 0 then
		camera:spectateSeat(nil)
	else
		camera:spectateSeat(scene.Subjects[ids[viewIndex]].Seat)
	end
	SpectatorController.Changed:Fire(
		viewIndex == 0 and "ORBIT" or string.upper(scene.Subjects[ids[viewIndex]].Name or "SEAT")
	)
end

function SpectatorController:Start()
	self.Controllers.InputController.Action:Connect(function(action, phase)
		if phase ~= "Begin" or not self:active() then
			return
		end
		if action == "NextTarget" or action == "CycleTarget" or action == "NextSlot" then
			self:cycle(1)
		elseif action == "PrevTarget" or action == "PrevSlot" then
			self:cycle(-1)
		elseif action == "Back" then
			self:stop()
		end
	end)
end

return SpectatorController
