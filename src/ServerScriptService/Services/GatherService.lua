--!strict
-- =============================================================================
-- GatherService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: gathering-node state — server-owned cooldowns and yields
--   (goo geysers, special-food plants), validated per claim via ZoneService.
-- [Contract] Never: client-timed respawns; never yields as a new currency
--   (special foods are ITEMS in Profile.Foods, §2/§3); Gather <=3/s.
-- [Contract] Binds: DESIGN.md §2 gathering nodes, §3 currency map.
-- =============================================================================

local GatherService = {}

function GatherService.Init()
	-- Stub: intentionally no behavior this session.
end

return GatherService
