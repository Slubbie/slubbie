-- The client's copy of its own profile (read-only: the server owns it).
-- Updated from "Profile" pushes; everything else reads it through here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Variance.Util.Signal)

local ProfileController = {}
ProfileController.Changed = Signal.new() -- (profile)
ProfileController.Data = nil

function ProfileController:Init(controllers)
	self.Controllers = controllers
end

function ProfileController:get()
	return ProfileController.Data
end

function ProfileController:owns(id: string): boolean
	local data = ProfileController.Data
	return data ~= nil and data.Cosmetics.Owned[id] == true
end

function ProfileController:equipped(category: string): string?
	local data = ProfileController.Data
	return data and data.Cosmetics.Equipped[category] or nil
end

function ProfileController:refresh()
	local ok, result = self.Controllers.NetworkClient:request("Profile.Get")
	if ok and type(result) == "table" then
		ProfileController.Data = result
		ProfileController.Changed:Fire(result)
	end
end

function ProfileController:Start()
	self.Controllers.NetworkClient:onPush("Profile", function(data)
		ProfileController.Data = data
		ProfileController.Changed:Fire(data)
	end)
	task.spawn(function()
		self:refresh()
	end)
end

return ProfileController
