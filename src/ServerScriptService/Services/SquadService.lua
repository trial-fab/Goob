--!strict
-- =============================================================================
-- SquadService — the equipped squad, slot milestones, ability answers.
--
-- [Contract] Owns: the equipped-squad roster (EquipSquad validation vs owned
--   slimes + SquadSlots), slot milestone progression (2 -> 4), and answering
--   ability claims ("does this player have Access ability X equipped?") for
--   ZoneService — from server state, never client claims.
-- [Contract] Never: sells slots (progression-only — an equip-slot pass is
--   selling power, deliberately absent, §4); never replicates follower motion
--   (client sim); abilities NEVER affect production (hard rule).
-- [Contract] Binds: DESIGN.md §2 equipped squad, §4 (no equip-slot pass), §5.
-- =============================================================================
--
-- Squad membership is exclusive with the producing roster (§2 inventory:
-- ranch / stored / equipped are three states): equipping removes a slime from
-- Ranch.Roster, so a follower never also earns Goo. The squad composition
-- replicates as ONE data attribute (Attrs.SquadJson) that every client's
-- follower sim renders — zero motion replication.
--
-- Slot milestones (PROVISIONAL until a design pass tunes them — they gate no
-- economy, only parade size + access convenience): slot 3 at the first
-- befriend (the session-2 exploration beat), slot 4 at 6 befriends (multiple
-- zones deep). Never sold, never Robux-adjacent (§4 "deliberately absent").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local SlimeConfig = require(Shared:WaitForChild("SlimeConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local SlimeService = require(script.Parent:WaitForChild("SlimeService"))

local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }

local BASE_SLOTS = 2
local MAX_SLOTS = 4
-- slot number -> Stats.Befriends required (see PROVISIONAL note above).
local SLOT_MILESTONES: { [number]: number } = { [3] = 1, [4] = 6 }

local SquadService = {}

-- Current earned slot count. Recomputed from Stats (monotonic), persisted to
-- data.SquadSlots so the client projection is always current.
function SquadService.GetSlots(data: DataService.ProfileData): number
	local slots = BASE_SLOTS
	for slot = BASE_SLOTS + 1, MAX_SLOTS do
		if data.Stats.Befriends >= (SLOT_MILESTONES[slot] or math.huge) then
			slots = slot
		end
	end
	data.SquadSlots = slots
	return slots
end

-- The parade composition every client's follower sim renders (data only).
local function projectSquad(player: Player, data: DataService.ProfileData)
	local entries = {}
	for _, slimeId in data.Squad do
		local record = data.Slimes[slimeId] :: SlimeService.SlimeRecord?
		if record then
			table.insert(entries, {
				Id = slimeId,
				Sp = record.Sp,
				Mu = record.Mu,
				St = record.St,
				Nt = record.Nt,
			})
		end
	end
	player:SetAttribute(Attrs.SquadJson, HttpService:JSONEncode(entries))
end

-- ZoneService's ability answer: is a slime with this AccessKey equipped NOW?
-- Reads only the server-side squad roster (never a client claim, §5).
function SquadService.HasAccessKey(player: Player, key: string): boolean
	local data = DataService.GetData(player)
	if not data then
		return false
	end
	for _, slimeId in data.Squad do
		local record = data.Slimes[slimeId]
		if record then
			local species = Species[record.Sp]
			if species and species.AccessKey == key then
				return true
			end
		end
	end
	return false
end

local function onEquipSquad(player: Player, slimeIds: { string }): { [string]: any }
	local data = DataService.GetData(player)
	if not data then
		return { success = false, message = "Loading..." }
	end
	local slots = SquadService.GetSlots(data)
	if #slimeIds > slots then
		return { success = false, message = ("You can equip %d slimes."):format(slots) }
	end

	local seen: { [string]: boolean } = {}
	for _, slimeId in slimeIds do
		if seen[slimeId] then
			return { success = false, message = "Duplicate slime in squad." }
		end
		seen[slimeId] = true
		if not data.Slimes[slimeId] then
			return { success = false, message = "Unknown slime." }
		end
		if SlimeService.IsBusy(slimeId) then
			return { success = false, message = "That slime is busy." }
		end
	end

	-- Return previously-equipped slimes to storage state (not the roster —
	-- the player re-adds producers deliberately via the inventory toggle).
	data.Squad = table.clone(slimeIds)

	-- Equipped slimes can't simultaneously produce: pull them off the roster.
	for _, slimeId in slimeIds do
		local at = table.find(data.Ranch.Roster, slimeId)
		if at then
			table.remove(data.Ranch.Roster, at)
		end
	end

	projectSquad(player, data)
	SlimeService.PushState(player)
	return { success = true, squad = data.Squad, slots = slots }
end

function SquadService.Init()
	DataService.OnProfileLoaded(function(player, data)
		SquadService.GetSlots(data)
		projectSquad(player, data)
	end)

	-- Trades/releases can remove an equipped slime: keep the projection true.
	SlimeService.OnCollectionChanged(function(player)
		local data = DataService.GetData(player)
		if data then
			SquadService.GetSlots(data)
			projectSquad(player, data)
		end
	end)

	Net.onInvoke(Net.Names.EquipSquad, onEquipSquad, {
		budget = 3,
		window = 1,
		validator = Net.T.args(Net.T.arrayOf(Net.T.guid, MAX_SLOTS)),
	})
end

return SquadService
