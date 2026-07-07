--!strict
-- =============================================================================
-- ShrineService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: mutation-shrine rolls — offering validation (special foods +
--   one owned slime), the boosted server-side mutation roll, per-player shrine
--   cooldowns (Profile.Zones.ShrineCooldowns), and odds disclosure data.
-- [Contract] Never: rolls a slime that is Locked, equipped, or mid-trade; never
--   client-side odds; cooldowns live server-side only.
-- [Contract] Binds: DESIGN.md §2 mutation shrines, §3 (shrine-farming risk), §5.
-- =============================================================================

local ShrineService = {}

function ShrineService.Init()
	-- Stub: intentionally no behavior this session.
end

return ShrineService
