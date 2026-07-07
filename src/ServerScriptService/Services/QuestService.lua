--!strict
-- =============================================================================
-- QuestService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: daily quest assignment (3/day from QuestConfig), progress
--   tracking hooks other services call, and claim validation (ClaimQuest).
-- [Contract] Never: client-reported progress; rewards are server-derived from
--   QuestConfig.
-- [Contract] Binds: DESIGN.md §2 retention mechanics.
-- =============================================================================

local QuestService = {}

function QuestService.Init()
	-- Stub: intentionally no behavior this session.
end

return QuestService
