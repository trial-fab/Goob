--!strict
-- =============================================================================
-- SquadService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: the equipped-squad roster (EquipSquad validation vs owned
--   slimes + SquadSlots), slot milestone progression (2 -> 4), and answering
--   ability claims ("does this player have Access ability X equipped?") for
--   ZoneService — from server state, never client claims.
-- [Contract] Never: sells slots (progression-only — an equip-slot pass is
--   selling power, deliberately absent, §4); never replicates follower motion
--   (client sim); abilities NEVER affect production (hard rule).
-- [Contract] Binds: DESIGN.md §2 equipped squad, §4 (no equip-slot pass), §5.
-- =============================================================================

local SquadService = {}

function SquadService.Init()
	-- Stub: intentionally no behavior this session.
end

return SquadService
