-- The mailbox: quest rewards, contract payments, festival prizes, NPC letters,
-- compensation and gifts from friends.
--
-- Capacity is enforced safely: mail beyond the box's capacity waits in an
-- overflow queue and moves in as you claim/delete, so attachments are never
-- lost. Mail to players who aren't on this server goes to a small DataStore
-- inbox that's merged into their mailbox the next time they join.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Social = require(Shared.Config.Social)
local Net = require(Shared.Lib.Net)
local ItemUtil = require(Shared.Lib.ItemUtil)
local GameTime = require(Shared.Lib.GameTime)

local S = require(script.Parent)

local CFG = Social.Mail

local MailService = {}

local inbox: DataStore? = nil
pcall(function()
	inbox = DataStoreService:GetDataStore("Evergrove_Inbox_v1")
end)

export type Mail = {
	Id: string,
	From: string,
	Subject: string,
	Body: string?,
	Items: { ItemUtil.Stack }?,
	Coins: number?,
	Tokens: number?,
	Title: string?,
	At: number,
	Read: boolean?,
	Claimed: boolean?,
}

local function hasAttachments(mail: any): boolean
	return not mail.Claimed and ((mail.Items and #mail.Items > 0) or (mail.Coins or 0) > 0 or (mail.Tokens or 0) > 0 or mail.Title ~= nil)
end

local function promote(profile: any)
	local box = profile.Mail
	while #box.List < CFG.Capacity and #box.Overflow > 0 do
		table.insert(box.List, table.remove(box.Overflow, 1))
	end
end

-- Deliver mail to an online player's profile.
function MailService.Send(player: Player, mail: { [string]: any })
	local profile = S.Data.Get(player)
	if not profile then
		return false
	end
	local box = profile.Mail
	box.Next = (box.Next or 1) + 1
	local entry = {
		Id = tostring(box.Next) .. "_" .. tostring(os.time() % 100000),
		From = mail.From or "Evergrove Post",
		Subject = mail.Subject or "",
		Body = mail.Body,
		Items = mail.Items,
		Coins = mail.Coins,
		Tokens = mail.Tokens,
		Title = if type(mail.Title) == "string" then mail.Title else nil,
		At = GameTime.Now(),
	}
	if #box.List < CFG.Capacity then
		table.insert(box.List, entry)
	else
		-- Make room by dropping the oldest read mail without attachments.
		for i, old in box.List do
			if old.Read and not hasAttachments(old) then
				table.remove(box.List, i)
				break
			end
		end
		if #box.List < CFG.Capacity then
			table.insert(box.List, entry)
		else
			table.insert(box.Overflow, entry)
			if #box.Overflow > CFG.OverflowCapacity then
				-- Only ever discard overflow mail that has nothing attached.
				for i, old in box.Overflow do
					if not hasAttachments(old) then
						table.remove(box.Overflow, i)
						break
					end
				end
			end
		end
	end
	S.Data.Changed(player, "Mail")
	S.Notify.Toast(player, "✉️ " .. entry.Subject, "Info")
	return true
end

-- Deliver mail to any user id (online here → directly; otherwise via the inbox store).
function MailService.SendTo(userId: number, mail: { [string]: any })
	local online = Players:GetPlayerByUserId(userId)
	if online and S.Data.IsLoaded(online) then
		return MailService.Send(online, mail)
	end
	if not inbox then
		return false
	end
	local ok = pcall(function()
		(inbox :: DataStore):UpdateAsync("i_" .. userId, function(old)
			local list = if type(old) == "table" then old else {}
			if #list >= 100 then
				return nil
			end
			table.insert(list, mail)
			return list
		end)
	end)
	return ok
end

local function pullInbox(player: Player)
	if not inbox or player.UserId <= 0 then
		return
	end
	local pulled = nil
	pcall(function()
		(inbox :: DataStore):UpdateAsync("i_" .. player.UserId, function(old)
			pulled = old
			return {}
		end)
	end)
	if type(pulled) == "table" then
		for _, mail in pulled do
			if type(mail) == "table" then
				MailService.Send(player, mail)
			end
		end
	end
end

local function find(profile: any, id: string): (any?, number?)
	for i, mail in profile.Mail.List do
		if mail.Id == id then
			return mail, i
		end
	end
	return nil, nil
end

local function claim(player: Player, id: string)
	local profile = S.Data.Get(player)
	local mail = profile and find(profile, id)
	if not profile or not mail then
		return false, "No such mail"
	end
	if not hasAttachments(mail) then
		return false, "Nothing to claim"
	end
	if mail.Items and #mail.Items > 0 and not S.Inventory.CanFit(player, mail.Items) then
		return false, "Make room in your bag first"
	end
	mail.Claimed = true
	mail.Read = true
	for _, stack in mail.Items or {} do
		if ItemUtil.Valid(stack) then
			S.Inventory.Add(player, stack, { Silent = true, NoMail = true })
		end
	end
	if (mail.Coins or 0) > 0 then
		S.Economy.AddCoins(player, mail.Coins, mail.From)
	end
	if (mail.Tokens or 0) > 0 then
		S.Economy.AddTokens(player, mail.Tokens)
	end
	if mail.Title then
		profile.Titles[mail.Title] = true
		S.Data.Changed(player, "Titles")
		S.Notify.Toast(player, "🏷️ New title: " .. mail.Title, "Success")
	end
	S.Notify.Reward(player, mail.Items or {}, mail.Coins or 0, mail.From)
	S.Data.Changed(player, "Mail")
	return true
end

local function claimAll(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	local claimed, skipped = 0, 0
	for _, mail in table.clone(profile.Mail.List) do
		if hasAttachments(mail) then
			if claim(player, mail.Id) then
				claimed += 1
			else
				skipped += 1
			end
		end
	end
	promote(profile)
	S.Data.Changed(player, "Mail")
	if claimed == 0 and skipped > 0 then
		return false, "Your bag is full"
	end
	return true, { Claimed = claimed, Skipped = skipped }
end

local function delete(player: Player, id: string)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	local mail, index = find(profile, id)
	if not mail or not index then
		return false, "No such mail"
	end
	if hasAttachments(mail) then
		return false, "Claim the attachments first"
	end
	table.remove(profile.Mail.List, index)
	promote(profile)
	S.Data.Changed(player, "Mail")
	return true
end

local function read(player: Player, id: string)
	local profile = S.Data.Get(player)
	local mail = profile and find(profile, id)
	if not mail then
		return false
	end
	mail.Read = true
	S.Data.Changed(player, "Mail")
	return true
end

function MailService.Init()
	Net.Handle("MailClaim", claim)
	Net.Handle("MailClaimAll", claimAll)
	Net.Handle("MailDelete", delete)
	Net.Handle("MailRead", read)
end

function MailService.Start()
	S.Data.Loaded:Connect(function(player, profile, info)
		promote(profile)
		task.spawn(pullInbox, player)
		if info.New then
			MailService.Send(player, {
				From = "Mabel Thornbury",
				Subject = "Welcome to Evergrove!",
				Body = "Dear new farmer,\n\nThe old plot is yours now. I left you some seeds and a few tools. Till, plant, water, and be patient — the valley rewards those who care.\n\nCome find me if you need anything.\n\n— Mabel",
				Items = { ItemUtil.New("seed_strawberry", 4), ItemUtil.New("quality_fertilizer", 2) },
				Coins = 100,
			})
		end
	end)
end

return MailService
