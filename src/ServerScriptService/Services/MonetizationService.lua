--!strict
-- =============================================================================
-- MonetizationService — STUB (scaffold session 1; implement session 3 — ADAPT
-- from ClickGame WITH the receipt fix).
--
-- [Contract] Owns: ProcessReceipt (grant via the owning service ->
--   DataService.RecordReceipt -> THEN PurchaseGranted), gamepass ownership
--   checks, and the MonetizationConfig product catalog wiring.
-- [Contract] Never: a separate receipt DataStore (§8 W2 — receipts buffer in
--   the session-locked profile so grant + record is one atomic save); never
--   acks a receipt it failed to record; never grants from client claims; no
--   Goo packs, no equip-slot pass (§4).
-- [Contract] Binds: DESIGN.md §4, §8 W2.
-- =============================================================================

local MonetizationService = {}

function MonetizationService.Init()
	-- Stub: intentionally no behavior this session.
end

return MonetizationService
