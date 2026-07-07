--!strict
-- =============================================================================
-- BoostService — STUB (scaffold session 1; implement session 3 — ADAPT from
-- ClickGame).
--
-- [Contract] Owns: timed boosts (2x Goo self, Gather Boost self, server-wide
--   Luck Boost with buyer announcement) via the WorldEventMultipliers pattern;
--   boost state, stacking rules, and expiry.
-- [Contract] Never: boosts that grant exclusive power (convenience/luck only,
--   §4); luck boosts apply to hatch AND wild-encounter AND shrine odds, and
--   must surface numerically in every odds popup (policy).
-- [Contract] Binds: DESIGN.md §4 dev products, §6 reuse map.
-- =============================================================================

local BoostService = {}

function BoostService.Init()
	-- Stub: intentionally no behavior this session.
end

return BoostService
