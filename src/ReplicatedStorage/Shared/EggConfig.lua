--!strict
-- =============================================================================
-- EggConfig — egg lines, costs, odds (values tuned by tools/economy_sim.luau,
-- session 2; rationale in docs/economy.md).
--
-- [Contract] Owns: egg lines, costs, and odds tables — the SINGLE source the
--   server rolls from AND the odds popup renders. Per-egg outcome lists with
--   exact percentages that sum to 100 (validated at load).
-- [Contract] Never: two copies of any odds table (client/server drift here is
--   a policy violation, not just a bug — disclosed odds MUST be the real odds,
--   §4); never luck math (the luck stack modifies rolls in HatchService and is
--   disclosed numerically via BoostService state).
-- [Contract] Binds: DESIGN.md §2 eggs, §4 fairness commitments, §8 W6.
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file).
--
-- Odds percentages are quantized to 0.25 steps. That is deliberate: quarters
-- are exact IEEE-754 binary fractions, so the load-time sum below can assert
-- == 100 EXACTLY, with no epsilon to hide a drifted table behind. Keep the
-- quantization when editing.
--
-- Cost(n) = BaseCost * CostGrowth^n, n = eggs of this line already bought
-- (lifetime, survives Molt — Molt resets Goo, not egg-price ladders; the
-- ladder is the §3 "next-egg 3-4 min early -> 15-20 min at line-end" stretch
-- and resetting it would reopen the idle-inflation valve).

local EggConfig = {}

export type Egg = {
	Id: string,
	Name: string,
	Line: string, -- SlimeConfig line this egg draws from
	BaseCost: number, -- Goo (0 = not purchasable: starter / reward eggs)
	CostGrowth: number, -- per-purchase price multiplier (1 = flat)
	Purchasable: boolean, -- false: granted by onboarding/streak, never sold
	Odds: { [string]: number }, -- speciesId -> exact percent; sums to exactly 100
}

local function egg(e: Egg): Egg
	e.Odds = table.freeze(e.Odds)
	return table.freeze(e) :: Egg
end

EggConfig.Eggs = table.freeze({
	-- Free onboarding egg: guaranteed starter, hatches in minute 1 (§3).
	starter_egg = egg({
		Id = "starter_egg",
		Name = "Starter Egg",
		Line = "Meadow",
		BaseCost = 0,
		CostGrowth = 1,
		Purchasable = false,
		Odds = { meadow_mossy = 100 },
	}),

	meadow_egg = egg({
		Id = "meadow_egg",
		Name = "Meadow Egg",
		Line = "Meadow",
		BaseCost = 60, -- ~60s of starter production: egg #2 lands in minute 2-3 (§3)
		CostGrowth = 1.6, -- steep on purpose: session 1 ends ~8 slimes, tail waits 10-20 min (§3)
		Purchasable = true,
		Odds = {
			meadow_mossy = 46,
			meadow_dewy = 34,
			meadow_clover = 16,
			meadow_honeydew = 4, -- first Rare: expected ~25 eggs -> week 1 (§3)
		},
	}),

	cave_egg = egg({
		Id = "cave_egg",
		Name = "Cave Egg",
		Line = "Cave",
		BaseCost = 100000, -- ~a day-1 overnight save: the line wall lands day 1-2 (§3)
		CostGrowth = 1.22, -- mid-line buys ride offline piles; steeper growth priced them at 20+ min of gps
		Purchasable = true,
		Odds = {
			cave_pebble = 42,
			cave_glowcap = 33,
			cave_geode = 20,
			cave_echo = 5, -- first Epic chase (week 2 beat §3)
		},
	}),

	ocean_egg = egg({
		Id = "ocean_egg",
		Name = "Ocean Egg",
		Line = "Ocean",
		BaseCost = 12000000, -- ~half a day-4 daily take: Ocean opens day 4-6 (§3 week 1)
		CostGrowth = 1.22,
		Purchasable = true,
		Odds = {
			ocean_bubble = 46, -- carries WaterWalk: Tide Pools access rides the commons
			ocean_kelpy = 26,
			ocean_coral = 19,
			ocean_pearl = 9,
		},
	}),

	volcano_egg = egg({
		Id = "volcano_egg",
		Name = "Volcano Egg",
		Line = "Volcano",
		BaseCost = 2500000000, -- ~a day-9 daily take: Volcano opens week 2 (§3; 150M fell day 6)
		CostGrowth = 1.30, -- the last line: its tail is the month-end grind by design
		Purchasable = true,
		Odds = {
			volcano_cinder = 57,
			volcano_magma = 25,
			volcano_obsidian = 14.5,
			volcano_solar = 3.5, -- the hatchable Legendary; ~29 eggs expected
		},
	}),

	-- Day-7 streak exclusive (DailyRewardConfig): skewed toward the Meadow rare
	-- a week-old player is still missing. Never purchasable.
	streak_egg = egg({
		Id = "streak_egg",
		Name = "Streak Egg",
		Line = "Meadow",
		BaseCost = 0,
		CostGrowth = 1,
		Purchasable = false,
		Odds = {
			meadow_dewy = 20,
			meadow_clover = 45,
			meadow_honeydew = 35,
		},
	}),
})

-- Pure lookup with loud failure (same pattern as SlimeConfig.Get).
function EggConfig.Get(id: string): Egg
	local e = (EggConfig.Eggs :: { [string]: Egg })[id]
	assert(e ~= nil, "unknown egg id: " .. id)
	return e
end

-- Cost of the (n+1)th egg of a line, n = already bought. THE price function —
-- HatchService charges it, the shop UI displays it, the sim buys with it.
function EggConfig.Cost(id: string, boughtCount: number): number
	local e = EggConfig.Get(id)
	return math.floor(e.BaseCost * e.CostGrowth ^ boughtCount + 0.5)
end

-- Load-time validation (the [Contract] "validated at load" clause). Runs on
-- require in every environment — Studio, live servers, and the CLI sim all
-- refuse to start on a bad table. Species-id existence is cross-config and
-- lives in tools/config_check.luau (configs never require each other).
for id, e in EggConfig.Eggs :: { [string]: Egg } do
	local sum = 0
	for speciesId, percent in e.Odds do
		assert(percent > 0, ("%s: %s has non-positive odds"):format(id, speciesId))
		assert(percent % 0.25 == 0, ("%s: %s odds %.4f not on the 0.25 grid"):format(id, speciesId, percent))
		sum += percent
	end
	assert(sum == 100, ("%s: odds sum to %.6f, must be exactly 100"):format(id, sum))
end

return table.freeze(EggConfig)
