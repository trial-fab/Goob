--!strict
-- =============================================================================
-- MutationConfig — mutation set, multipliers, roll weights (session-2 values;
-- rationale in docs/economy.md).
--
-- [Contract] Owns: the mutation set (Shiny x2, Crystal x5, Rainbow x15, Void
--   x50), value multipliers, base roll weights, and ability-enhancement hooks
--   (a Crystal water-walker crosses lava).
-- [Contract] Never: Studio asset authoring (mutation materials/VFX are Studio-
--   authored variants; this maps ids -> variant names only).
-- [Contract] Binds: DESIGN.md §2 mutations, §3.
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file).
--
-- Roll weights are INTEGER parts-per-10000 (basis points), summing to exactly
-- 10000 per table (validated at load) — integers so the disclosed percentages
-- (weight / 100) are exact, never floats that drift from what the server rolls.
-- Three roll tables, three roads to the same chase (§2):
--   Hatch   — the gacha road (pity below softens the floor),
--   StageUp — the comeback hook: every feed project is another roll,
--   Shrine  — the earned road: expensive (foods + cooldown) but ~4x hatch odds.
-- Rolls at StageUp/Shrine only ever UPGRADE (keep the better of current vs
-- rolled — GrowthService/ShrineService enforce; a re-roll can't strip a Void).

local MutationConfig = {}

export type Mutation = {
	Id: string,
	Name: string,
	Mult: number, -- production multiplier (ProductionFormula MutationMult term)
	Tier: number, -- 0 none .. 4 void; feeds AbilityConfig mutation enhancement
	Variant: string, -- Studio-authored model/material variant name
}

export type RollTable = { [string]: number } -- mutationId -> weight (bp of 10000)

MutationConfig.Mutations = table.freeze({
	none = table.freeze({ Id = "none", Name = "", Mult = 1, Tier = 0, Variant = "Base" }),
	shiny = table.freeze({ Id = "shiny", Name = "Shiny", Mult = 2, Tier = 1, Variant = "Shiny" }),
	crystal = table.freeze({ Id = "crystal", Name = "Crystal", Mult = 5, Tier = 2, Variant = "Crystal" }),
	rainbow = table.freeze({ Id = "rainbow", Name = "Rainbow", Mult = 15, Tier = 3, Variant = "Rainbow" }),
	void = table.freeze({ Id = "void", Name = "Void", Mult = 50, Tier = 4, Variant = "Void" }),
})

MutationConfig.Rolls = table.freeze({
	Hatch = table.freeze({ none = 9270, shiny = 600, crystal = 100, rainbow = 25, void = 5 }),
	StageUp = table.freeze({ none = 9150, shiny = 700, crystal = 120, rainbow = 25, void = 5 }),
	Shrine = table.freeze({ none = 6100, shiny = 3000, crystal = 750, rainbow = 135, void = 15 }),
})

-- First-session pity (§3): if hatches 1..N-1 all rolled none, hatch N is Shiny.
-- HatchService owns the counter (Profile.Stats.Hatches vs first Shiny).
MutationConfig.PityFirstShinyByHatch = 7

-- Load-time validation: every roll table sums to exactly 10000 and only names
-- known mutations. Same fail-at-require posture as EggConfig.
for rollName, weights in MutationConfig.Rolls :: { [string]: RollTable } do
	local sum = 0
	for mutationId, weight in weights do
		assert((MutationConfig.Mutations :: { [string]: Mutation })[mutationId], rollName .. ": unknown " .. mutationId)
		assert(weight == math.floor(weight) and weight > 0, rollName .. ": non-integer weight for " .. mutationId)
		sum += weight
	end
	assert(sum == 10000, ("%s: weights sum to %d, must be exactly 10000"):format(rollName, sum))
end

return table.freeze(MutationConfig)
