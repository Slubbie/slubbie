-- Evergrove client entry point. Boots every controller (see Controllers/init).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

-- Wait for the shared code and the network folder the server creates.
ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Net")
Players.LocalPlayer:WaitForChild("PlayerGui")

-- Evergrove draws its own inventory, hotbar and player list.
for _, coreType in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health } do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreType, false)
	end)
end

local Controllers = require(script:WaitForChild("Controllers"))
Controllers.Boot()
