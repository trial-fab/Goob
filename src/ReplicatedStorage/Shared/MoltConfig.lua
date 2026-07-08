--!strict
-- =============================================================================
-- MoltConfig — the Molt (rebirth) requirement ladder (NEW in session 3;
-- additive to the DESIGN §5 tree — docs/economy.md flagged the 500M ×5
-- recommendation as needing a config home that is NOT GrowthConfig, whose
-- contract is the life-stage ladder).
--
-- [Contract] Owns: the lifetime-Goo requirement to Molt and its per-Molt
--   growth factor, plus the reset contract documentation (Molt resets Goo +
--   Ranch.Slots ONLY; Slimes/Index/Gems/Cosmetics/Decor/Zones/egg ladders/slot
--   prices persist — the Run/Persistent partition, §5).
-- [Contract] Never: the production multiplier (that is
--   ProductionFormula.MoltMult — one formula, one module, §8 W6); never the
--   reset execution (the v1 service that owns Molt() enforces this table).
-- [Contract] Binds: DESIGN.md §2 Rebirth ("Molt"), §3 risk 1; docs/economy.md
--   "Molt (sim-modeled)".
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file).
--
-- Requirement(n) = LifetimeGooBase * RequirementGrowth^n, n = Molts already
-- taken, measured against LIFETIME Goo earned (Stats.GooEarned) — a flat
-- requirement would allow instant re-molts off the post-Molt production
-- spike. Tuned in session 2: Molt #1 lands ~day 10, #5 by week 3-4 (the §3
-- weeks-2-4 beat); growth ×5 keeps the cadence roughly constant against the
-- linear (1 + molts) multiplier. Molt is v1, not MVP (§9 M1 exclusion) — this
-- table ships early only because the sim's pacing verdicts depend on it.

local MoltConfig = {}

MoltConfig.LifetimeGooBase = 500000000 -- 500M lifetime Goo earned for Molt #1
MoltConfig.RequirementGrowth = 5 -- requirement ×5 per Molt taken

-- Lifetime Goo earned required for the (molts+1)th Molt.
function MoltConfig.Requirement(molts: number): number
	assert(molts >= 0, "molts must be >= 0")
	return MoltConfig.LifetimeGooBase * MoltConfig.RequirementGrowth ^ molts
end

return table.freeze(MoltConfig)
