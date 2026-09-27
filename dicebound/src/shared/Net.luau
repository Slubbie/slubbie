-- Every remote in one place. The server creates them; clients wait for them.
-- Client → server requests are RemoteFunctions that always return a table:
--   { ok = true, ... }  or  { ok = false, err = "message for the player", code = "Optional" }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FUNCTIONS = {
	"Roll", -- (auto: boolean) → outcome
	"Sell", -- (selection: { [stackKey] = qty }, confirmHighValue: boolean) → sale summary
	"SellAll", -- (includeHighValue: boolean) → sale summary
	"SetLock", -- (stackKey: string, locked: boolean)
	"BuyUpgrade", -- (upgradeId: string, expectedLevel: number)
	"SkipTutorial", -- ()
	"SaveSettings", -- (settings: { [string]: any })
}

local EVENTS = {
	"State", -- server → client: full public state after any change
	"Notify", -- server → client: (text, kind)
	"OpenPanel", -- server → client: (panelName, regionId) from world prompts
	"Announce", -- server → all clients: (playerName, itemId, mutation) for Legendary+ finds
}

local Net = { Functions = {}, Events = {} }

local folder: Instance
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in FUNCTIONS do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

for _, name in FUNCTIONS do
	Net.Functions[name] = folder:WaitForChild(name) :: RemoteFunction
end
for _, name in EVENTS do
	Net.Events[name] = folder:WaitForChild(name) :: RemoteEvent
end

return Net
