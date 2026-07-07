--!strict
-- =============================================================================
-- DailyRewardService — STUB (scaffold session 1; implement session 3 — PORT-
-- AS-IS from ClickGame, new reward table).
--
-- [Contract] Owns: the escalating 7-day streak calendar (state in
--   Profile.Streak), claim validation, and streak reset rules.
-- [Contract] Never: rewards other than DailyRewardConfig's table; never client
--   clock trust (server day boundaries).
-- [Contract] Binds: DESIGN.md §2 daily streak, §6 reuse map.
-- =============================================================================

local DailyRewardService = {}

function DailyRewardService.Init()
	-- Stub: intentionally no behavior this session.
end

return DailyRewardService
