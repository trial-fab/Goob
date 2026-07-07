--!strict
-- =============================================================================
-- OfflineEarningsService — STUB (scaffold session 1; implement session 3 —
-- ADAPT from ClickGame).
--
-- [Contract] Owns: snapshotting GetGps at save (via Profile.LastSeen), the
--   offline accrual math (50% rate, 2h free / 8h VIP cap), and the claim-modal
--   payload + ClaimOfflineEarnings validation.
-- [Contract] Never: accrual from client-reported absence; caps/rates live here
--   (server), the claim is idempotent (cleared on grant).
-- [Contract] Binds: DESIGN.md §2 offline earnings, §6 reuse map.
-- =============================================================================

local OfflineEarningsService = {}

function OfflineEarningsService.Init()
	-- Stub: intentionally no behavior this session.
end

return OfflineEarningsService
