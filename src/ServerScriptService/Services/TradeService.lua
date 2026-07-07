--!strict
-- =============================================================================
-- TradeService — STUB (scaffold session 1; implement session 3 — the crown
-- jewel: get this right or nothing else matters).
--
-- [Contract] Owns: the escrowed trade state machine (Invited -> Negotiating ->
--   BothConfirmed(3s lock) -> BothAccepted -> Committing -> Done/Aborted), the
--   commit protocol (validate ownership/locks/squad/shrine, write tradeId +
--   payload to BOTH TradeHistories AND move slime records in one in-memory
--   mutation, force-save both), trade rate limits (1 active, 20/day), and the
--   ~30-min-playtime trust gate.
-- [Contract] Never: cross-server trades (both profiles session-locked by THIS
--   server — the constraint that removes the dupe surface); never currency in
--   trades at MVP (the #1 scam/dupe vector); never commits without both
--   sessions active (DataService.IsSessionActive); tradeIds make commits
--   idempotent and are NEVER reused.
-- [Contract] Binds: DESIGN.md §5 Trading integrity — re-read it before ANY
--   change here; §2 trust rails; §9 M2 exit-gate dupe tests.
-- =============================================================================

local TradeService = {}

function TradeService.Init()
	-- Stub: intentionally no behavior this session.
end

return TradeService
