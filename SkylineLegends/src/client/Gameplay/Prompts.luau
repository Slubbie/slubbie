-- Routes every world prompt (boards, gates, shops, course signs, people) to
-- the right screen or action, and hides prompts while you're mid-run so a
-- sign at the start line can never interrupt a sprint.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local Bus = require(script.Parent.Parent.Core.Bus)
local Controller = require(script.Parent.Parent.Movement.Controller)
local CourseClient = require(script.Parent.CourseClient)
local Modes = require(script.Parent.Modes)
local QuestClient = require(script.Parent.QuestClient)

local Prompts = {}

local BOARD_PAGES = {
	Race = "Races",
	Jobs = "Jobs",
	Courses = "Courses",
	Leaderboard = "Records",
	Achievements = "Achievements",
	Crew = "Crew",
	Tower = "Tower",
	Shop = "Shop",
	Travel = "Travel",
}

local function onTriggered(prompt: ProximityPrompt)
	local name = prompt.Name
	if name == "CoursePrompt" then
		local courseId = prompt:GetAttribute("CourseId")
		if type(courseId) == "string" then
			Bus.CoursePreview:Fire(courseId)
		end
	elseif name == "TalkPrompt" then
		local npcId = prompt:GetAttribute("Npc")
		if type(npcId) == "string" then
			QuestClient.Talk(npcId)
		end
	elseif name == "DreamPrompt" then
		Modes.StartEndless()
	elseif name == "DreamExitPrompt" then
		task.spawn(function()
			local ok, allowed, destination = pcall(Net.Invoke, "Travel.Go", "Hub")
			if ok and allowed and typeof(destination) == "CFrame" then
				Controller.Teleport(destination)
			end
		end)
	else
		local board = prompt:GetAttribute("Board")
		local page = type(board) == "string" and BOARD_PAGES[board]
		if page then
			Bus.OpenPage:Fire(page, {
				District = prompt:GetAttribute("District"),
				Destination = prompt:GetAttribute("Destination"),
			})
		end
	end
end

function Prompts.Start()
	ProximityPromptService.PromptTriggered:Connect(onTriggered)
	CourseClient.Started:Connect(function()
		ProximityPromptService.Enabled = false
	end)
	CourseClient.Ended:Connect(function()
		ProximityPromptService.Enabled = true
	end)
end

return Prompts
