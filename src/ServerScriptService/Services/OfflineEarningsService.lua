--!strict
-- =============================================================================
-- OfflineEarningsService — offline accrual + the welcome-back claim.
--
-- [Contract] Owns: snapshotting GetGps at save (via Profile.LastSeen), the
--   offline accrual math (50% rate, 2h free / 8h VIP cap), and the claim-modal
--   payload + ClaimOfflineEarnings validation.
-- [Contract] Never: accrual from client-reported absence; caps/rates live here
--   (server), the claim is idempotent (cleared on grant).
-- [Contract] Binds: DESIGN.md §2 offline earnings, §6 reuse map.
-- =============================================================================
--
-- These constants ARE the §2 numbers; tools/economy_sim.luau hardcodes the
-- same ones by design (docs/economy.md session-3 wiring notes) — change them
-- BOTH or the pacing verdicts lie.
--
-- gps is recomputed from the loaded profile (roster × formula) rather than
-- snapshotted at save: the profile already determines it exactly, and a
-- recompute can't drift from a stale snapshot. Accrued Goo persists in
-- OfflinePendingGoo until claimed, so leaving before the claim loses nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local ProductionService = require(script.Parent:WaitForChild("ProductionService"))

local OFFLINE_RATE = 0.5 -- §2: Goo accrues offline at 50%
local CAP_SECONDS_FREE = 2 * 3600
local CAP_SECONDS_VIP = 8 * 3600 -- VIP pass (MonetizationService, session 4)

local OfflineEarningsService = {}

local function hasVip(_player: Player): boolean
	return false -- MonetizationService installs the real check (session 4)
end

function OfflineEarningsService.Init()
	DataService.OnProfileLoaded(function(player, data)
		if data.LastSeen > 0 then
			local away = os.time() - data.LastSeen
			local cap = if hasVip(player) then CAP_SECONDS_VIP else CAP_SECONDS_FREE
			local seconds = math.clamp(away, 0, cap)
			local earned = math.floor(ProductionService.GetGps(player) * seconds * OFFLINE_RATE)
			if earned > 0 then
				data.OfflinePendingGoo += earned
			end
		end
		-- Consume the window immediately (one atomic in-memory change with the
		-- accrual): a crash-rejoin can't double-accrue the same absence.
		data.LastSeen = os.time()

		if data.OfflinePendingGoo > 0 then
			Net.fireClient(Net.Names.OfflineEarningsReady, player, {
				Amount = data.OfflinePendingGoo,
			})
		end
	end)

	Net.onInvoke(Net.Names.ClaimOfflineEarnings, function(player: Player)
		local data = DataService.GetData(player)
		if not data then
			return { success = false, message = "Loading..." }
		end
		local amount = data.OfflinePendingGoo
		if amount <= 0 then
			return { success = false, message = "Nothing to claim." }
		end
		data.OfflinePendingGoo = 0
		data.Goo += amount
		data.Stats.GooEarned += amount
		player:SetAttribute(Attrs.Goo, data.Goo)
		return { success = true, amount = amount, goo = data.Goo }
	end, {
		budget = 2,
		window = 5,
		validator = Net.T.none,
	})
end

-- Test seam (Studio verification + TestCommandService !offline): accrue as if
-- the player had been away `seconds` — the exact production math, no waiting.
function OfflineEarningsService._simulateAway(player: Player, seconds: number): number
	local data = DataService.GetData(player)
	if not data then
		return 0
	end
	local cap = if hasVip(player) then CAP_SECONDS_VIP else CAP_SECONDS_FREE
	local capped = math.clamp(seconds, 0, cap)
	local earned = math.floor(ProductionService.GetGps(player) * capped * OFFLINE_RATE)
	data.OfflinePendingGoo += earned
	if data.OfflinePendingGoo > 0 then
		Net.fireClient(Net.Names.OfflineEarningsReady, player, { Amount = data.OfflinePendingGoo })
	end
	return earned
end

return OfflineEarningsService
