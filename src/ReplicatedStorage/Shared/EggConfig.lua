--!strict
-- =============================================================================
-- EggConfig — STUB (scaffold session 1; values from the session-2 economy sim).
--
-- [Contract] Owns: egg lines, costs, and odds tables — the SINGLE source the
--   server rolls from AND the odds popup renders. Per-egg outcome lists with
--   exact percentages that sum to 100 (validated at load).
-- [Contract] Never: two copies of any odds table (client/server drift here is
--   a policy violation, not just a bug — disclosed odds MUST be the real odds,
--   §4); never luck math (the luck stack modifies rolls in HatchService and is
--   disclosed numerically via BoostService state).
-- [Contract] Binds: DESIGN.md §2 eggs, §4 fairness commitments, §8 W6.
-- =============================================================================

local EggConfig = {}

return EggConfig
