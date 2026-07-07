--!strict
-- =============================================================================
-- DecorService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: decor purchase (Goo/Gem tiers), grid placement validation
--   (plot-relative snap, bounds, overlap) for Profile.Ranch.Decor, recall, and
--   ranch likes (one per visitor per plot).
-- [Contract] Never: production effects of ANY kind (decor is cosmetic-only —
--   the hard rule that makes it the economy's open-ended sink, §3); never
--   authors decor geometry (Studio-authored; behavior-affinity tags live in
--   DecorConfig for the client wander sim).
-- [Contract] Binds: DESIGN.md §2 decor build mode, §3 inflation mitigation.
-- =============================================================================

local DecorService = {}

function DecorService.Init()
	-- Stub: intentionally no behavior this session.
end

return DecorService
