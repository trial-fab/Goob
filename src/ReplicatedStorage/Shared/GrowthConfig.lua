--!strict
-- =============================================================================
-- GrowthConfig — STUB (scaffold session 1; values from the session-2 sim).
--
-- [Contract] Owns: the life-stage ladder Blob -> Slime -> Jumbo -> Titan —
--   stage production multipliers (x1/x3/x9/x27), per-stage food costs (scaling
--   with stage — Titan feeds are expensive, an inflation sink §3), stage-up
--   real-time timers, and model scale per stage.
-- [Contract] Never: multipliers applied anywhere but ProductionFormula.
-- [Contract] Binds: DESIGN.md §2 life stages, §3 pacing.
-- =============================================================================

local GrowthConfig = {}

return GrowthConfig
