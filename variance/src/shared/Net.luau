-- The network contract. Every remote lives here; the server creates them and
-- clients wait for them. Kept deliberately small:
--
--   Act      RemoteEvent            client -> server   gameplay actions (fire / use)
--   Request  RemoteFunction         client -> server   everything else, by endpoint
--   Match    RemoteEvent            server -> client   match events, snapshots, pacing
--   Push     RemoteEvent            server -> client   profile, lobby, queue, notices
--   Look     UnreliableRemoteEvent  both ways          seated head direction (presence)
--
-- Every inbound payload is validated by server/Services/NetworkService.luau
-- against the schemas below before any handler sees it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.FolderName = "VarianceNet"

-- Request endpoints and their argument schemas.
-- Types: "string" (Max length), "number" (Min/Max/Integer), "boolean", "table",
-- "any". A trailing "?" makes an argument optional.
Net.Endpoints = {
	["Profile.Get"] = {},
	["Settings.Save"] = { "table" },
	["Queue.Join"] = { "string" },
	["Queue.Leave"] = {},
	["Solo.Start"] = { "string", "string" },
	["Endurance.Start"] = {},
	["Solo.Quick"] = {},
	["Sandbox.Start"] = { "table" },
	["Tutorial.Start"] = { "string" },
	["Tutorial.Continue"] = {},
	["Tutorial.Answer"] = { "number" },
	["Tutorial.Quit"] = {},
	["Lobby.Create"] = {},
	["Lobby.Join"] = { "string" },
	["Lobby.Leave"] = {},
	["Lobby.SetRules"] = { "table" },
	["Lobby.SetReady"] = { "boolean" },
	["Lobby.SetFormat"] = { "string" },
	["Lobby.Start"] = {},
	["Lobby.Kick"] = { "number" },
	["Lobby.AddBot"] = { "string", "string" },
	["Lobby.RemoveBot"] = { "number" },
	["Match.Sync"] = {},
	["Match.Ready"] = {},
	["Match.Forfeit"] = {},
	["Match.Rematch"] = { "boolean" },
	["Match.Emote"] = { "string" },
	["Match.Leave"] = {},
	["Spectate.List"] = {},
	["Spectate.Start"] = { "string" },
	["Spectate.Stop"] = {},
	["Cosmetics.Equip"] = { "string", "string" },
	["Cosmetics.Buy"] = { "string" },
	["Challenges.Claim"] = { "string", "number" },
	["Lore.Read"] = { "string" },
	["Leaderboard.Get"] = { "string" },
	["History.Get"] = {},
	["Reconnect.Accept"] = {},
	["Reconnect.Decline"] = {},
	["Shop.Prompt"] = { "string" },
	["Debug.Command"] = { "string", "table?" },
}

local folder: Folder

local function make(className: string, name: string)
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(Net.FolderName) :: Folder
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = Net.FolderName
		make("RemoteEvent", "Act")
		make("RemoteFunction", "Request")
		make("RemoteEvent", "Match")
		make("RemoteEvent", "Push")
		local ok = pcall(make, "UnreliableRemoteEvent", "Look")
		if not ok then
			-- Older engines: fall back to a reliable remote with the same name.
			make("RemoteEvent", "Look")
		end
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild(Net.FolderName) :: Folder
end

Net.Act = folder:WaitForChild("Act") :: RemoteEvent
Net.Request = folder:WaitForChild("Request") :: RemoteFunction
Net.Match = folder:WaitForChild("Match") :: RemoteEvent
Net.Push = folder:WaitForChild("Push") :: RemoteEvent
Net.Look = folder:WaitForChild("Look") :: any

return Net
