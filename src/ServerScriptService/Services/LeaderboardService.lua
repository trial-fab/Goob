--!strict
-- =============================================================================
-- LeaderboardService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: the global OrderedDataStore boards (Total Goo Earned,
--   Rarest Slime score, Index Completion, Coziest Ranch likes), ~90s refresh,
--   and the hub board payloads.
-- [Contract] Never: board writes from unvalidated state (stats come from the
--   profile); Coziest Ranch grants status only, never power.
-- [Contract] Binds: DESIGN.md §2 trading & social (leaderboards).
-- =============================================================================

local LeaderboardService = {}

function LeaderboardService.Init()
	-- Stub: intentionally no behavior this session.
end

return LeaderboardService
