--!strict
-- =============================================================================
-- ZoneService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: per-player zone unlock state, the access check every zone
--   reward remote calls (unlock + equipped-Access-ability, from SquadService's
--   server-side roster), and the daily zone rotation (surge).
-- [Contract] Never: validates by physical position or barriers — geography is
--   presentation; a teleport exploit past a locked door yields NOTHING (§5).
-- [Contract] Binds: DESIGN.md §2 Exploration (zones), §5 zone-access validation.
-- =============================================================================

local ZoneService = {}

function ZoneService.Init()
	-- Stub: intentionally no behavior this session.
end

return ZoneService
