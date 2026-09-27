-- Keeps chat from leaking hidden information in competitive play.
--
-- In ranked, tournament and free-for-all matches, messages from spectators and
-- from subjects already eliminated from that match are not delivered to the
-- subjects still playing it. Everyone else chats normally. Uses the
-- TextChatService channel callback, so it applies to the built-in chat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Variance.Config)

local ChatGuardService = {}

function ChatGuardService:Init(services)
	self.Services = services
end

local function competitive(match): boolean
	local rules = match.State.Rules
	return rules.Ranked or match.Info.Tournament or #match.State.Order > 2 or (rules.SpectatorDelay or 0) > 0
end

-- True if `sender` may not talk to `recipient` right now.
function ChatGuardService:blocked(sender: Player, recipient: Player): boolean
	if not Config.Spectate.MuteSpectatorsInCompetitive then
		return false
	end
	local services = self.Services
	local match = services.MatchService:matchOf(recipient)
	if match == nil or match.Finished or not competitive(match) then
		return false
	end
	local recipientId = services.MatchService:subjectOf(match, recipient)
	if recipientId == nil or match.State.Subjects[recipientId].Eliminated then
		return false
	end
	-- Spectators of this match.
	if match.Spectators[sender] then
		return true
	end
	-- Eliminated subjects of this match.
	local senderId = services.MatchService:subjectOf(match, sender)
	if senderId and match.State.Subjects[senderId].Eliminated then
		return true
	end
	return false
end

local function hook(self, channel: TextChannel)
	local ok, err = pcall(function()
		channel.ShouldDeliverCallback = function(message: TextChatMessage, textSource: TextSource)
			local fromSource = message.TextSource
			if fromSource == nil then
				return true
			end
			local sender = Players:GetPlayerByUserId(fromSource.UserId)
			local recipient = Players:GetPlayerByUserId(textSource.UserId)
			if sender == nil or recipient == nil or sender == recipient then
				return true
			end
			return not self:blocked(sender, recipient)
		end
	end)
	if not ok then
		warn("[VARIANCE/ChatGuard] could not hook channel: " .. tostring(err))
	end
end

function ChatGuardService:Start()
	task.spawn(function()
		local channels = TextChatService:WaitForChild("TextChannels", 30)
		if channels == nil then
			return
		end
		for _, child in channels:GetChildren() do
			if child:IsA("TextChannel") then
				hook(self, child)
			end
		end
		channels.ChildAdded:Connect(function(child)
			if child:IsA("TextChannel") then
				hook(self, child)
			end
		end)
	end)
end

return ChatGuardService
