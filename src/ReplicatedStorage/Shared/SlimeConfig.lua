--!strict
-- =============================================================================
-- SlimeConfig — the species catalog (values tuned by tools/economy_sim.luau,
-- session 2; rationale in docs/economy.md).
--
-- [Contract] Owns: the species catalog — id, display name, line (Meadow/Cave/
--   Ocean/Volcano), rarity tier (Common..Legendary), base Goo production,
--   ability family, and hatchable vs wild-exclusive.
-- [Contract] Never: balance numbers before the economy spreadsheet signs them
--   off (§9 M0 — retuning after players hold inventory is 10x harder); never
--   logic — data + pure lookups only. Replicated: clients read it for UI.
-- [Contract] Binds: DESIGN.md §2 slimes & collection, §3, §5 tree.
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file). Cross-config
-- references (egg odds, zone spawn tables, favorite foods) are string ids,
-- validated by tools/config_check.luau and at load in EggConfig.
--
-- Base = Goo/s at Blob stage with no mutation/Molt. ProductionFormula is the
-- ONLY place Base is combined with multipliers. Ladder shape: ~x2.4 per rarity
-- step inside a line, ~x6-8 between lines at equal rarity (each new line
-- obsoletes the last one's commons, not its rares — dupes stay tradeable).
--
-- RefundGoo = Goo returned for releasing a HATCHABLE species at Blob stage
-- (GrowthConfig.Stages[n].RefundMult scales it up for grown slimes). Values
-- are a rarity-keyed fraction of the line egg's base cost (C 4% / U 9% /
-- R 12% / E 18% / L 20%) — big enough to read as a "sell" verb, small enough
-- that the expected refund per egg stays under ~15% of the egg price (the §3
-- release-refund printer check, asserted by config_check). Wild-exclusive
-- species refund FOOD, never Goo (§3 risk 3): RefundGoo = 0, RefundFood pays
-- back one of their favorite food.

local SlimeConfig = {}

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
export type Line = "Meadow" | "Cave" | "Ocean" | "Volcano"
export type AbilityFamily = "Mobility" | "Access" | "Gathering" | "Luck"

export type Species = {
	Id: string,
	Name: string,
	Line: Line,
	Rarity: Rarity,
	Base: number, -- Goo/s at Blob, unmutated, no Molt
	Ability: AbilityFamily,
	AccessKey: string?, -- Access family only: which door key (AbilityConfig.AccessKeys)
	Hatchable: boolean, -- false = wild-exclusive (befriend in zones only)
	FavoriteFood: string?, -- wild-exclusive only: FoodConfig id that tames it
	RefundGoo: number, -- release refund at Blob (0 for wild-exclusives)
	RefundFood: { [string]: number }?, -- wild-exclusives: food returned on release
}

SlimeConfig.Rarities = table.freeze({
	Common = table.freeze({ Order = 1, Color = "Grey" }),
	Uncommon = table.freeze({ Order = 2, Color = "Green" }),
	Rare = table.freeze({ Order = 3, Color = "Blue" }),
	Epic = table.freeze({ Order = 4, Color = "Purple" }),
	Legendary = table.freeze({ Order = 5, Color = "Gold" }),
})

local function species(s: Species): Species
	return table.freeze(s) :: Species
end

SlimeConfig.Species = table.freeze({
	-- ---- Meadow (starter line; zone: meadow_wilds) -------------------------
	meadow_mossy = species({
		Id = "meadow_mossy",
		Name = "Mossy",
		Line = "Meadow",
		Rarity = "Common",
		Base = 1.0, -- the starter slime; the whole curve is calibrated from here
		Ability = "Gathering",
		Hatchable = true,
		RefundGoo = 2,
	}),
	meadow_dewy = species({
		Id = "meadow_dewy",
		Name = "Dewy",
		Line = "Meadow",
		Rarity = "Common",
		Base = 1.5,
		Ability = "Mobility",
		Hatchable = true,
		RefundGoo = 2,
	}),
	meadow_clover = species({
		Id = "meadow_clover",
		Name = "Clover",
		Line = "Meadow",
		Rarity = "Uncommon",
		Base = 3.6,
		Ability = "Access",
		AccessKey = "Burrow", -- opens Crystal Caves — the first zone gate players chase
		Hatchable = true,
		RefundGoo = 5,
	}),
	meadow_honeydew = species({
		Id = "meadow_honeydew",
		Name = "Honeydew",
		Line = "Meadow",
		Rarity = "Rare",
		Base = 9,
		Ability = "Luck",
		Hatchable = true,
		RefundGoo = 7,
	}),
	meadow_thistle = species({
		Id = "meadow_thistle",
		Name = "Thistle",
		Line = "Meadow",
		Rarity = "Uncommon",
		Base = 4.2,
		Ability = "Gathering",
		Hatchable = false, -- first wild-exclusive: befriendable in session 1-2 (§3)
		FavoriteFood = "sun_petal",
		RefundGoo = 0,
		RefundFood = { sun_petal = 1 },
	}),

	-- ---- Cave (zone: crystal_caves) ----------------------------------------
	cave_pebble = species({
		Id = "cave_pebble",
		Name = "Pebble",
		Line = "Cave",
		Rarity = "Common",
		Base = 7,
		Ability = "Mobility",
		Hatchable = true,
		RefundGoo = 4000,
	}),
	cave_glowcap = species({
		Id = "cave_glowcap",
		Name = "Glowcap",
		Line = "Cave",
		Rarity = "Uncommon",
		Base = 17,
		Ability = "Access",
		AccessKey = "Glow", -- opens the deep-cave shrine chamber (presentation gate)
		Hatchable = true,
		RefundGoo = 9000,
	}),
	cave_geode = species({
		Id = "cave_geode",
		Name = "Geode",
		Line = "Cave",
		Rarity = "Rare",
		Base = 42,
		Ability = "Gathering",
		Hatchable = true,
		RefundGoo = 12000,
	}),
	cave_echo = species({
		Id = "cave_echo",
		Name = "Echo",
		Line = "Cave",
		Rarity = "Epic",
		Base = 105,
		Ability = "Luck",
		Hatchable = true,
		RefundGoo = 18000,
	}),
	cave_stalag = species({
		Id = "cave_stalag",
		Name = "Stalag",
		Line = "Cave",
		Rarity = "Rare",
		Base = 50,
		Ability = "Mobility",
		Hatchable = false,
		FavoriteFood = "crystal_berry",
		RefundGoo = 0,
		RefundFood = { crystal_berry = 1 },
	}),
	cave_wisp = species({
		Id = "cave_wisp",
		Name = "Wisp",
		Line = "Cave",
		Rarity = "Epic",
		Base = 120,
		Ability = "Luck",
		Hatchable = false,
		FavoriteFood = "crystal_berry",
		RefundGoo = 0,
		RefundFood = { crystal_berry = 1 },
	}),

	-- ---- Ocean (zone: tide_pools) ------------------------------------------
	ocean_bubble = species({
		Id = "ocean_bubble",
		Name = "Bubble",
		Line = "Ocean",
		Rarity = "Uncommon",
		Base = 55,
		Ability = "Access",
		AccessKey = "WaterWalk", -- opens Tide Pools — buy Ocean eggs to explore Ocean
		Hatchable = true,
		RefundGoo = 1080000,
	}),
	ocean_kelpy = species({
		Id = "ocean_kelpy",
		Name = "Kelpy",
		Line = "Ocean",
		Rarity = "Rare",
		Base = 130,
		Ability = "Gathering",
		Hatchable = true,
		RefundGoo = 1440000,
	}),
	ocean_coral = species({
		Id = "ocean_coral",
		Name = "Coral",
		Line = "Ocean",
		Rarity = "Rare",
		Base = 160,
		Ability = "Mobility",
		Hatchable = true,
		RefundGoo = 1440000,
	}),
	ocean_pearl = species({
		Id = "ocean_pearl",
		Name = "Pearl",
		Line = "Ocean",
		Rarity = "Epic",
		Base = 400,
		Ability = "Luck",
		Hatchable = true,
		RefundGoo = 2160000,
	}),
	ocean_marina = species({
		Id = "ocean_marina",
		Name = "Marina",
		Line = "Ocean",
		Rarity = "Epic",
		Base = 460,
		Ability = "Gathering",
		Hatchable = false,
		FavoriteFood = "tide_kelp",
		RefundGoo = 0,
		RefundFood = { tide_kelp = 1 },
	}),

	-- ---- Volcano (zone: volcanic_springs) ----------------------------------
	volcano_cinder = species({
		Id = "volcano_cinder",
		Name = "Cinder",
		Line = "Volcano",
		Rarity = "Rare",
		Base = 520,
		Ability = "Access",
		AccessKey = "HeatShield", -- opens Volcanic Springs
		Hatchable = true,
		RefundGoo = 300000000,
	}),
	volcano_magma = species({
		Id = "volcano_magma",
		Name = "Magma",
		Line = "Volcano",
		Rarity = "Epic",
		Base = 1300,
		Ability = "Mobility",
		Hatchable = true,
		RefundGoo = 450000000,
	}),
	volcano_obsidian = species({
		Id = "volcano_obsidian",
		Name = "Obsidian",
		Line = "Volcano",
		Rarity = "Epic",
		Base = 1600,
		Ability = "Gathering",
		Hatchable = true,
		RefundGoo = 450000000,
	}),
	volcano_solar = species({
		Id = "volcano_solar",
		Name = "Solar",
		Line = "Volcano",
		Rarity = "Legendary",
		Base = 4000,
		Ability = "Luck",
		Hatchable = true,
		RefundGoo = 500000000,
	}),
	volcano_ashen = species({
		Id = "volcano_ashen",
		Name = "Ashen",
		Line = "Volcano",
		Rarity = "Epic",
		Base = 1800,
		Ability = "Mobility",
		Hatchable = false,
		FavoriteFood = "ember_fruit",
		RefundGoo = 0,
		RefundFood = { ember_fruit = 1 },
	}),
	volcano_nova = species({
		Id = "volcano_nova",
		Name = "Nova",
		Line = "Volcano",
		Rarity = "Legendary",
		Base = 4600,
		Ability = "Gathering",
		Hatchable = false,
		FavoriteFood = "ember_fruit",
		RefundGoo = 0,
		RefundFood = { ember_fruit = 2 },
	}),
})

-- Pure lookup: species by id, erroring loudly on typos (nil-indexing a frozen
-- table is silent; this is the sanctioned accessor).
function SlimeConfig.Get(id: string): Species
	local s = (SlimeConfig.Species :: { [string]: Species })[id]
	assert(s ~= nil, "unknown species id: " .. id)
	return s
end

return table.freeze(SlimeConfig)
