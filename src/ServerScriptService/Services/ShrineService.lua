--!strict
-- =============================================================================
-- ShrineService — mutation-shrine rolls (the earned luck road).
--
-- [Contract] Owns: mutation-shrine rolls — offering validation (special foods +
--   one owned slime), the boosted server-side mutation roll, per-player shrine
--   cooldowns (Profile.Zones.ShrineCooldowns), and odds disclosure data.
-- [Contract] Never: rolls a slime that is Locked, equipped, or mid-trade; never
--   client-side odds; cooldowns live server-side only.
-- [Contract] Binds: DESIGN.md §2 mutation shrines, §3 (shrine-farming risk), §5.
-- =============================================================================
--
-- One shrine per zone (ZoneConfig.Shrine): the shrineId IS the zoneId. The
-- offering is OfferingFoods items of the zone's own special food. Rolls use
-- MutationConfig.Rolls.Shrine (the ~5× earned road) and only ever UPGRADE —
-- the same keep-better rule as stage-ups; a roll can never strip a mutation.
-- Odds disclosure: the client renders MutationConfig.Rolls.Shrine directly
-- (shown before every roll even though unpaid rolls don't require it, §2).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local ZoneConfig = require(Shared:WaitForChild("ZoneConfig"))
local FoodConfig = require(Shared:WaitForChild("FoodConfig"))
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local SlimeService = require(script.Parent:WaitForChild("SlimeService"))
local HatchService = require(script.Parent:WaitForChild("HatchService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))
local QuestService = require(script.Parent:WaitForChild("QuestService"))

local Zones = ZoneConfig.Zones :: { [string]: ZoneConfig.Zone }
local Mutations = MutationConfig.Mutations :: { [string]: MutationConfig.Mutation }

local ShrineService = {}

local function onShrineRoll(player: Player, zoneId: string, slimeId: string): { [string]: any }
	local data = DataService.GetData(player)
	if not data then
		return { success = false, message = "Loading..." }
	end
	local zone = Zones[zoneId]
	if not zone then
		return { success = false, message = "Unknown shrine." }
	end

	-- State validation, never position (§5).
	local ok, why = ZoneService.CanAccess(player, zoneId)
	if not ok then
		return { success = false, message = why }
	end

	local now = os.time()
	local readyAt = data.Zones.ShrineCooldowns[zoneId] or 0
	if now < readyAt then
		return { success = false, message = "The shrine is dormant.", readyIn = readyAt - now }
	end

	local record = data.Slimes[slimeId] :: SlimeService.SlimeRecord?
	if not record then
		return { success = false, message = "Unknown slime." }
	end
	if SlimeService.IsHeld(data, slimeId) then
		return { success = false, message = "That slime is locked, equipped, or busy." }
	end
	if record.Mu == "void" then
		return { success = false, message = "Void slimes can't mutate further." }
	end

	local foodId = zone.FoodId
	local needed = zone.Shrine.OfferingFoods
	if (data.Foods[foodId] or 0) < needed then
		local food = FoodConfig.Get(foodId)
		return { success = false, message = ("The shrine wants %d %s."):format(needed, food.Name) }
	end

	-- Everything validated: consume the offering, arm the cooldown, roll.
	-- The slime is held for exactly this mutation window (busy guards a
	-- concurrent trade-offer race on the same id).
	SlimeService.SetBusy(slimeId, true)
	data.Foods[foodId] -= needed
	data.Zones.ShrineCooldowns[zoneId] = now + zone.Shrine.CooldownSeconds

	local rolled = HatchService.RollMutation(MutationConfig.Rolls.Shrine, 1)
	local upgraded = false
	if Mutations[rolled].Tier > Mutations[record.Mu].Tier then
		record.Mu = rolled
		upgraded = true
		SlimeService.Discover(data, record.Sp, rolled)
		SlimeService.RefreshModel(player, slimeId)
	end
	SlimeService.SetBusy(slimeId, false)

	QuestService.Progress(player, "Shrine", 1)
	DataService.ForceSave(player) -- shrine roll is on the §5 force-save list
	SlimeService.PushState(player)

	return {
		success = true,
		rolled = rolled,
		upgraded = upgraded,
		mutation = record.Mu,
		cooldown = zone.Shrine.CooldownSeconds,
	}
end

function ShrineService.Init()
	Net.onInvoke(Net.Names.ShrineRoll, onShrineRoll, {
		budget = 1,
		window = 2,
		validator = Net.T.args(Net.T.string(40), Net.T.guid),
	})
end

return ShrineService
