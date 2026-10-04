-- Compact ghost replays.
--
-- A ghost is sampled at a fixed rate. Each frame stores position (0.1 stud
-- precision), yaw (2° steps) and the movement state, delta-encoded as integers
-- so a two-minute run is a few tens of kilobytes of JSON in a DataStore.

local GhostCodec = {}

GhostCodec.Rate = 15 -- frames per second
GhostCodec.MaxSeconds = 600
GhostCodec.States = {
	"Ground",
	"Crouch",
	"Slide",
	"Roll",
	"Stumble",
	"Air",
	"WallRun",
	"WallClimb",
	"Ledge",
	"Climb",
	"Balance",
	"Zipline",
	"Swing",
	"Pull",
	"Vault",
	"Mantle",
	"Dash",
}
local stateIndex = {}
for index, name in GhostCodec.States do
	stateIndex[name] = index
end

export type Frame = { X: number, Y: number, Z: number, Yaw: number, State: string }
export type Encoded = { V: number, Rate: number, N: number, D: { number }, Splits: { number }?, Time: number? }

function GhostCodec.Encode(frames: { Frame }, splits: { number }?, totalTime: number?): Encoded
	local data = table.create(#frames * 5)
	local px, py, pz, pyaw, pstate = 0, 0, 0, 0, 0
	for _, frame in frames do
		local x = math.floor(frame.X * 10 + 0.5)
		local y = math.floor(frame.Y * 10 + 0.5)
		local z = math.floor(frame.Z * 10 + 0.5)
		local yaw = math.floor(((frame.Yaw % 360) / 2) + 0.5) % 180
		local state = stateIndex[frame.State] or 1
		table.insert(data, x - px)
		table.insert(data, y - py)
		table.insert(data, z - pz)
		table.insert(data, yaw - pyaw)
		table.insert(data, state - pstate)
		px, py, pz, pyaw, pstate = x, y, z, yaw, state
	end
	return { V = 1, Rate = GhostCodec.Rate, N = #frames, D = data, Splits = splits, Time = totalTime }
end

function GhostCodec.Decode(encoded: any): { Frame }?
	if type(encoded) ~= "table" or type(encoded.D) ~= "table" or type(encoded.N) ~= "number" then
		return nil
	end
	local data = encoded.D
	if #data < encoded.N * 5 then
		return nil
	end
	local frames = table.create(encoded.N)
	local x, y, z, yaw, state = 0, 0, 0, 0, 0
	for i = 0, encoded.N - 1 do
		local base = i * 5
		x += data[base + 1]
		y += data[base + 2]
		z += data[base + 3]
		yaw += data[base + 4]
		state += data[base + 5]
		frames[i + 1] = {
			X = x / 10,
			Y = y / 10,
			Z = z / 10,
			Yaw = yaw * 2,
			State = GhostCodec.States[state] or "Ground",
		}
	end
	return frames
end

-- Basic shape checks before the server stores a submitted ghost.
function GhostCodec.Validate(encoded: any, expectedSeconds: number): boolean
	if type(encoded) ~= "table" or type(encoded.D) ~= "table" or type(encoded.N) ~= "number" then
		return false
	end
	if encoded.Rate ~= GhostCodec.Rate or encoded.N < 1 then
		return false
	end
	if #encoded.D ~= encoded.N * 5 then
		return false
	end
	local seconds = encoded.N / GhostCodec.Rate
	if seconds > GhostCodec.MaxSeconds or math.abs(seconds - expectedSeconds) > 3 then
		return false
	end
	for _, value in encoded.D do
		if type(value) ~= "number" or value ~= value or math.abs(value) > 1e6 then
			return false
		end
	end
	return true
end

return GhostCodec
