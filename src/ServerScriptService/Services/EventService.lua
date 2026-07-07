--!strict
-- =============================================================================
-- EventService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: unscheduled server events (~every 20-40 min): Slime Rain,
--   Lucky Hour-let, Wild Surge — announced server-wide, applied via the
--   WorldEventMultipliers container pattern so ProductionFormula/luck stacks
--   read one place.
-- [Contract] Never: per-player events (server-wide = social moments); event
--   multipliers flow ONLY through the shared containers, never ad-hoc buffs.
-- [Contract] Binds: DESIGN.md §2 retention (server events), §6 reuse map.
-- =============================================================================

local EventService = {}

function EventService.Init()
	-- Stub: intentionally no behavior this session.
end

return EventService
