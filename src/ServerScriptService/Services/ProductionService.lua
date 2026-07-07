--!strict
-- =============================================================================
-- ProductionService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: ONE production loop per player (never per slime — §8 W5),
--   GetGps(player) as the server authority on goo-per-second, goo-blob spawn
--   records (id, plot, value) that CollectService validates claims against, and
--   the ONE batched per-player ProductionEarnings push per tick.
-- [Contract] Never: per-slime coroutines/loops; never replicates per-slime
--   production ticks; never computes the multiplier chain itself (that lives in
--   Shared/ProductionFormula — §8 W6); natures/abilities/decor/cosmetics NEVER
--   affect production (hard rule).
-- [Contract] Binds: DESIGN.md §5 Networking (replication cost control), §8 W5/W6.
-- =============================================================================

local ProductionService = {}

function ProductionService.Init()
	-- Stub: intentionally no behavior this session.
end

return ProductionService
