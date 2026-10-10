-- Session-locked profile storage on top of any UpdateAsync-capable backend
-- (a Roblox DataStore in the game, an in-memory fake in tests).
--
-- Each key holds { Data = <profile>, Meta = { Session, Heartbeat, Loads, Saves } }.
--   Load    claims the lock. If another live server holds it, waits and retries;
--           a lock with no heartbeat for LockStaleSeconds counts as abandoned.
--   Save    only writes while we still own the lock ("LockLost" otherwise),
--           refreshes the heartbeat and optionally releases the lock.
-- Every request is retried with exponential backoff on transient errors.

export type Backend = {
	UpdateAsync: (self: any, key: string, transform: (any, any?) -> any) -> any,
}

export type Options = {
	SessionId: string,
	Clock: () -> number, -- unix seconds (os.time in the game)
	Wait: (number) -> (),
	LockStaleSeconds: number,
	LoadLockRetries: number,
	LoadLockRetryDelay: number,
	MaxRequestRetries: number,
	RetryBaseDelay: number,
	-- Optional: waits until the DataStore request budget allows another call.
	WaitForBudget: (() -> ())?,
}

export type LoadResult = "Loaded" | "Locked" | "Error"
export type SaveResult = "Saved" | "LockLost" | "Error"

local ProfileStore = {}
ProfileStore.__index = ProfileStore

export type ProfileStore = typeof(setmetatable({} :: { _backend: Backend, _options: Options }, ProfileStore))

function ProfileStore.new(backend: Backend, options: Options): ProfileStore
	return setmetatable({ _backend = backend, _options = options }, ProfileStore)
end

-- Runs `request` until it succeeds or retries run out.
function ProfileStore._withRetry(self: ProfileStore, request: () -> ()): (boolean, string?)
	local options = self._options
	local lastError: string? = nil
	for attempt = 1, options.MaxRequestRetries do
		if options.WaitForBudget then
			options.WaitForBudget()
		end
		local ok, err = pcall(request)
		if ok then
			return true, nil
		end
		lastError = tostring(err)
		if attempt < options.MaxRequestRetries then
			options.Wait(options.RetryBaseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

local function asRecord(value: any): { [string]: any }
	if type(value) == "table" then
		return value
	end
	return {}
end

local function asMeta(record: { [string]: any }): { [string]: any }
	if type(record.Meta) == "table" then
		return record.Meta
	end
	return {}
end

-- Claims the session lock and returns the stored profile data (nil for a new player).
function ProfileStore.Load(self: ProfileStore, key: string): (LoadResult, any, string?)
	local options = self._options
	for attempt = 1, options.LoadLockRetries + 1 do
		local loaded, lockedBy, data = false, nil, nil
		local ok, err = self:_withRetry(function()
			self._backend:UpdateAsync(key, function(current)
				-- The transform may run more than once; reset results every time.
				loaded, lockedBy, data = false, nil, nil
				local record = asRecord(current)
				local meta = asMeta(record)
				local now = options.Clock()
				local heartbeat = tonumber(meta.Heartbeat) or 0
				if
					meta.Session ~= nil
					and meta.Session ~= options.SessionId
					and now - heartbeat < options.LockStaleSeconds
				then
					lockedBy = meta.Session
					return nil -- cancel the write; someone else is using this profile
				end
				meta.Session = options.SessionId
				meta.Heartbeat = now
				meta.Loads = (tonumber(meta.Loads) or 0) + 1
				record.Meta = meta
				data = record.Data
				loaded = true
				return record
			end)
		end)
		if not ok then
			return "Error", nil, err
		end
		if loaded then
			return "Loaded", data, nil
		end
		if lockedBy and attempt <= options.LoadLockRetries then
			options.Wait(options.LoadLockRetryDelay)
		end
	end
	return "Locked", nil, "profile is in use by another server"
end

-- Writes `data` while we hold the lock. `release` frees the lock afterwards.
function ProfileStore.Save(self: ProfileStore, key: string, data: any, release: boolean): (SaveResult, string?)
	local options = self._options
	local result: SaveResult = "Error"
	local ok, err = self:_withRetry(function()
		self._backend:UpdateAsync(key, function(current)
			local record = asRecord(current)
			local meta = asMeta(record)
			if meta.Session ~= options.SessionId then
				result = "LockLost"
				return nil
			end
			record.Data = data
			meta.Heartbeat = options.Clock()
			meta.Saves = (tonumber(meta.Saves) or 0) + 1
			if release then
				meta.Session = nil
			end
			record.Meta = meta
			result = "Saved"
			return record
		end)
	end)
	if not ok then
		return "Error", err
	end
	return result, nil
end

-- Frees the lock without changing the stored data (used when a load is abandoned).
function ProfileStore.Release(self: ProfileStore, key: string): boolean
	local options = self._options
	local ok = self:_withRetry(function()
		self._backend:UpdateAsync(key, function(current)
			local record = asRecord(current)
			local meta = asMeta(record)
			if meta.Session ~= options.SessionId then
				return nil
			end
			meta.Session = nil
			record.Meta = meta
			return record
		end)
	end)
	return ok
end

return ProfileStore
