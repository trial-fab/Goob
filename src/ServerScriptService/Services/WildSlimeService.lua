--!strict
-- =============================================================================
-- WildSlimeService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: server-rolled wild slime spawns per zone (spawn tables from
--   ZoneConfig), befriend attempts (favorite-food check, food debit, nature
--   roll) and results, and wild-exclusive species availability.
-- [Contract] Never: combat (befriend by feeding, never fought); never client-
--   influenced spawn or befriend rolls; befriends validated via ZoneService
--   unlock/ability state, never position (Befriend <=1/s).
-- [Contract] Binds: DESIGN.md §2 wild slimes, §5 Anti-exploit posture.
-- =============================================================================

local WildSlimeService = {}

function WildSlimeService.Init()
	-- Stub: intentionally no behavior this session.
end

return WildSlimeService
