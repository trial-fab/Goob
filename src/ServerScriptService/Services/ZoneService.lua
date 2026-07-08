--!strict
-- =============================================================================
-- ZoneService — zone unlock state, the access check, daily rotation.
--
-- [Contract] Owns: per-player zone unlock state, the access check every zone
--   reward remote calls (unlock + equipped-Access-ability, from SquadService's
--   server-side roster), and the daily zone rotation (surge).
-- [Contract] Never: validates by physical position or barriers — geography is
--   presentation; a teleport exploit past a locked door yields NOTHING (§5).
-- [Contract] Binds: DESIGN.md §2 Exploration (zones), §5 zone-access validation.
-- =============================================================================
--
-- Two-part gate (ZoneConfig.Unlock):
--   * UNLOCK — a progression milestone (slimes owned); once reached it is
--     persisted in Profile.Zones.Unlocked and never revoked (trading away
--     slimes doesn't re-lock a zone you've reached).
--   * ACCESS — zones 2+ additionally require the matching Access-ability slime
--     EQUIPPED at reward time, answered by SquadService from server state.
-- Every reward service (gather/befriend/shrine) calls CanAccess; none of them
-- ever looks at a character position.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneConfig = require(Shared:WaitForChild("ZoneConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local SlimeService = require(script.Parent:WaitForChild("SlimeService"))
local SquadService = require(script.Parent:WaitForChild("SquadService"))

local Zones = ZoneConfig.Zones :: { [string]: ZoneConfig.Zone }

local ZoneService = {}

-- Ordered zone ids (ladder Order) for the deterministic daily surge pick.
local orderedZoneIds: { string } = {}
for id in Zones do
	table.insert(orderedZoneIds, id)
end
table.sort(orderedZoneIds, function(a, b)
	return Zones[a].Order < Zones[b].Order
end)

-- Persist any newly-reached unlock milestones. Called on load and whenever a
-- player's collection changes (SlimeService callback).
local function evaluateUnlocks(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local owned = SlimeService.CountOwned(data)
	local changed = false
	for id, zone in Zones do
		if not data.Zones.Unlocked[id] and owned >= zone.Unlock.SlimesOwned then
			data.Zones.Unlocked[id] = true
			changed = true
		end
	end
	if changed then
		SlimeService.PushState(player)
	end
end

-- THE access check (unlock + equipped ability — state, never position).
-- Returns (ok, playerFacingReason).
function ZoneService.CanAccess(player: Player, zoneId: string): (boolean, string?)
	local zone = Zones[zoneId]
	if not zone then
		return false, "Unknown zone."
	end
	local data = DataService.GetData(player)
	if not data then
		return false, "Loading..."
	end
	if not data.Zones.Unlocked[zoneId] then
		return false, ("Unlock %s by owning %d slimes."):format(zone.Name, zone.Unlock.SlimesOwned)
	end
	local key = zone.Unlock.AccessKey
	if key and not SquadService.HasAccessKey(player, key) then
		return false, ("You need a slime with the %s ability equipped."):format(key)
	end
	return true, nil
end

-- Daily surge zone (§2 rotation): deterministic from the UTC day so every
-- server agrees without coordination.
function ZoneService.GetSurgeZoneId(): string
	local day = math.floor(os.time() / 86400)
	return orderedZoneIds[day % #orderedZoneIds + 1]
end

function ZoneService.IsSurging(zoneId: string): boolean
	return ZoneService.GetSurgeZoneId() == zoneId
end

function ZoneService.Init()
	DataService.OnProfileLoaded(function(player)
		evaluateUnlocks(player)
	end)
	SlimeService.OnCollectionChanged(evaluateUnlocks)
end

-- Test seam (Studio verification only): force a zone unlocked through the
-- owning service instead of poking profile internals from the harness.
function ZoneService._forceUnlock(player: Player, zoneId: string)
	local data = DataService.GetData(player)
	if data and Zones[zoneId] then
		data.Zones.Unlocked[zoneId] = true
		SlimeService.PushState(player)
	end
end

return ZoneService
