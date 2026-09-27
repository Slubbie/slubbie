-- Developer tools on the client. Only players the server marks as allowed
-- (Config.Debug: Studio, or listed admins) ever receive the "Debug" push; for
-- everyone else this controller stays inert, and the server re-checks every
-- command anyway.
--
-- F8 toggles the debug panel (UI/Screens/DebugPanel).

local UserInputService = game:GetService("UserInputService")

local DebugController = {}
DebugController.Allowed = false

function DebugController:Init(controllers)
	self.Controllers = controllers
end

-- Runs a server debug command. Returns (ok, message).
function DebugController:run(name: string, args: { [string]: any }?): (boolean, any)
	if not DebugController.Allowed then
		return false, "Not permitted."
	end
	return self.Controllers.NetworkClient:request("Debug.Command", name, args or {})
end

function DebugController:Start()
	self.Controllers.NetworkClient:onPush("Debug", function(data)
		DebugController.Allowed = data and data.Allowed == true
		if DebugController.Allowed then
			self.Controllers.UIController:toast("DEBUG TOOLS", "Press F8 for the debug panel.", "Info")
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not DebugController.Allowed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F8 then
			local ui = self.Controllers.UIController
			local panel = ui:screen("DebugPanel")
			if panel then
				if panel.Visible then
					panel:Close()
				else
					panel:Open()
				end
			end
		end
	end)
end

return DebugController
