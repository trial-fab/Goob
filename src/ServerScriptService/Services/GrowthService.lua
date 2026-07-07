--!strict
-- =============================================================================
-- GrowthService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: feeding (FeedSlime — food costs from GrowthConfig, server-
--   debited), stage-up timers (Blob->Slime->Jumbo->Titan), and the stage-up
--   mutation re-roll (the comeback hook).
-- [Contract] Never: stage multipliers other than GrowthConfig's ×1/×3/×9/×27
--   chain applied via Shared/ProductionFormula; never skips a stage's food cost
--   (Instant-Grow skips the TIMER only, §4).
-- [Contract] Binds: DESIGN.md §2 life stages, §5 (Feed <=5/s).
-- =============================================================================

local GrowthService = {}

function GrowthService.Init()
	-- Stub: intentionally no behavior this session.
end

return GrowthService
