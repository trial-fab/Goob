--!strict
-- =============================================================================
-- ProductionService — ONE production loop per player, blob records, GetGps.
--
-- [Contract] Owns: ONE production loop per player (never per slime — §8 W5),
--   GetGps(player) as the server authority on goo-per-second, goo-blob spawn
--   records (id, plot, value) that CollectService validates claims against, and
--   the ONE batched per-player ProductionEarnings push per tick.
-- [Contract] Never: per-slime coroutines/loops; never replicates per-slime
--   production ticks; never computes the multiplier chain itself (that lives in
--   Shared/ProductionFormula — §8 W6); natures/abilities/decor/cosmetics NEVER
--   affect production (hard rule).
-- [Contract] Binds: DESIGN.md §5 Networking (replication cost control), §8 W5/W6.
-- =============================================================================
--
-- Flow: one server heartbeat accrues gps × dt per player into a pending pool;
-- every BLOB_INTERVAL the pool becomes ONE goo-blob record on the player's
-- plot (the §2 tap-to-collect verb; batched — never per slime). At the blob
-- cap the pool merges into the newest blob instead ("blobs grow"), so an AFK
-- ranch banks value in bounded records and replicates nothing per tick.
-- Balance changes ONLY through CollectService claims (and offline earnings).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local SlimeConfig = require(Shared:WaitForChild("SlimeConfig"))
local GrowthConfig = require(Shared:WaitForChild("GrowthConfig"))
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))
local ProductionFormula = require(Shared:WaitForChild("ProductionFormula"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }
local Mutations = MutationConfig.Mutations :: { [string]: MutationConfig.Mutation }

local TICK_SECONDS = 1
local BLOB_INTERVAL = 8 -- ~the §1 "collect goo blobs (30s)" micro-cadence
local BLOB_CAP = 25 -- outstanding records per plot; overflow merges (bounded)

local ProductionService = {}

export type Blob = {
	Id: string,
	Value: number,
	X: number, -- plot-local offset from the Base center (presentation hint;
	Z: number, -- the VALUE is the authority, the position is cosmetic)
}

type PlayerState = {
	pending: number, -- accrued Goo not yet in a blob
	sinceBlob: number,
	blobs: { Blob }, -- newest last
	lastGps: number,
}

local states: { [Player]: PlayerState } = {}
local rng = Random.new()

-- ---------------------------------------------------------------------------

-- Server-wide event multiplier hook. M1 ships no server events; EventService
-- (session 4) will own a WorldEventMultipliers container and this reads it.
local function eventMult(): number
	return 1
end

-- Gamepass multiplier hook (VIP ×1.25 — MonetizationService, session 4).
local function passMult(_player: Player): number
	return 1
end

-- THE server authority on a player's goo-per-second. Recomputed from the
-- profile every call — no cache to fall out of sync with roster/stage/
-- mutation/Molt changes. 16 slimes × 12 players at 1 Hz is nothing.
function ProductionService.GetGps(player: Player): number
	local data = DataService.GetData(player)
	if not data then
		return 0
	end
	local total = 0
	for _, slimeId in data.Ranch.Roster do
		local record = data.Slimes[slimeId]
		if record then
			local species = Species[record.Sp]
			local mutation = Mutations[record.Mu]
			if species and mutation then
				total += ProductionFormula.Gps({
					Base = species.Base,
					StageMult = GrowthConfig.Stages[record.St].Mult,
					MutationMult = mutation.Mult,
					Molts = data.Molts,
					EventMult = eventMult(),
					PassMult = passMult(player),
				})
			end
		end
	end
	return total
end

-- ---------------------------------------------------------------------------
-- Blob records (the value authority CollectService validates against).
-- ---------------------------------------------------------------------------

local function spawnBlob(player: Player, state: PlayerState)
	local value = math.floor(state.pending)
	if value < 1 then
		return
	end
	state.pending -= value

	if #state.blobs >= BLOB_CAP then
		local newest = state.blobs[#state.blobs]
		newest.Value += value
		Net.fireClient(Net.Names.BlobSpawned, player, newest, true) -- grew, not new
		return
	end

	local base = PlotService.GetBase(player)
	local hw = if base then base.Size.X * 0.4 else 10
	local hd = if base then base.Size.Z * 0.4 else 10
	local blob: Blob = {
		Id = HttpService:GenerateGUID(false),
		Value = value,
		X = rng:NextNumber(-hw, hw),
		Z = rng:NextNumber(-hd, hd),
	}
	table.insert(state.blobs, blob)
	Net.fireClient(Net.Names.BlobSpawned, player, blob, false)
end

-- Claim a blob for its server-known value (CollectService's authority). nil =
-- no such record for THIS player (wrong id, double-claim, or someone else's).
function ProductionService.TakeBlob(player: Player, blobId: string): number?
	local state = states[player]
	if not state then
		return nil
	end
	for index, blob in state.blobs do
		if blob.Id == blobId then
			table.remove(state.blobs, index)
			return blob.Value
		end
	end
	return nil
end

function ProductionService.GetBlobs(player: Player): { Blob }
	local state = states[player]
	return if state then state.blobs else {}
end

-- ---------------------------------------------------------------------------

function ProductionService.Init()
	DataService.OnProfileLoaded(function(player)
		states[player] = { pending = 0, sinceBlob = 0, blobs = {}, lastGps = -1 }
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- Uncollected blob value is NOT lost on leave: it never left the
		-- profile-side economy (blobs are unrealized production; offline
		-- earnings restart from LastSeen).
		states[player] = nil
	end)

	-- THE loop. One task for the whole server; every player's accrual and
	-- blob batching happens here (§8 W5 — never per unit, never per player
	-- coroutine).
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			for player, state in states do
				local gps = ProductionService.GetGps(player)
				state.pending += gps * TICK_SECONDS
				state.sinceBlob += TICK_SECONDS

				if gps ~= state.lastGps then
					state.lastGps = gps
					player:SetAttribute(Attrs.Gps, gps)
				end

				if state.sinceBlob >= BLOB_INTERVAL then
					state.sinceBlob = 0
					spawnBlob(player, state)
					-- ONE batched per-player push per blob tick (§8 W5): the
					-- client renders per-slime dribble FX from this alone.
					Net.fireClient(Net.Names.ProductionEarnings, player, { Gps = gps })
				end
			end
		end
	end)
end

return ProductionService
