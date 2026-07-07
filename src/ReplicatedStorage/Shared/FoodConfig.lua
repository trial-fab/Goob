--!strict
-- =============================================================================
-- FoodConfig — the food catalog (session-2 values; rationale in
-- docs/economy.md).
--
-- [Contract] Owns: the food catalog — basic feed (Goo-purchased) and special
--   foods (Crystal Berries, Tide Kelp, ... — gathered items, Profile.Foods),
--   their feed values, taming uses, and shrine-offering values.
-- [Contract] Never: a currency (special foods are ITEMS — materials are food
--   items, not a new currency, §2).
-- [Contract] Binds: DESIGN.md §2 gathering, §3 currency map.
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file).
--
-- basic_feed is not an inventory item: the feed prompt spends Goo directly at
-- GrowthConfig.FeedCost. Special foods are the gathered items with three uses
-- (§2 — same item, three sinks, no fifth currency):
--   feed     FeedValue counts as N basic feeds AND costs no Goo — the §2
--            "premium feed (stage-up discount)". FeedValue 2: at ~12 gathered
--            foods/day a higher value let expeditions pay for every stage-up
--            and zeroed the food Goo-sink in the sim — 2 keeps it a discount
--   taming   the only way to befriend a wild slime (its FavoriteFood,
--            SlimeConfig; TameCost items consumed on the successful feed)
--   shrine   ZoneConfig shrines consume OfferingFoods of the zone's food

local FoodConfig = {}

export type Food = {
	Id: string,
	Name: string,
	SourceZone: string, -- ZoneConfig zone whose nodes grow it
	FeedValue: number, -- counts as this many basic feeds (Goo-free)
	ShrineValue: number, -- offering units contributed per item
}

local function food(f: Food): Food
	return table.freeze(f) :: Food
end

FoodConfig.Foods = table.freeze({
	sun_petal = food({
		Id = "sun_petal",
		Name = "Sun Petal",
		SourceZone = "meadow_wilds",
		FeedValue = 2,
		ShrineValue = 1,
	}),
	crystal_berry = food({
		Id = "crystal_berry",
		Name = "Crystal Berry",
		SourceZone = "crystal_caves",
		FeedValue = 2,
		ShrineValue = 1,
	}),
	tide_kelp = food({
		Id = "tide_kelp",
		Name = "Tide Kelp",
		SourceZone = "tide_pools",
		FeedValue = 2,
		ShrineValue = 1,
	}),
	ember_fruit = food({
		Id = "ember_fruit",
		Name = "Ember Fruit",
		SourceZone = "volcanic_springs",
		FeedValue = 2,
		ShrineValue = 1,
	}),
})

-- Items of the favorite food a successful befriend consumes (wild slime's
-- FavoriteFood is per-species in SlimeConfig; wrong-food attempts consume 1
-- and return a hint — WildSlimeService, session 3). At ~6 foods per
-- expedition, discovery + 3 favorites lands the first befriend in session 2
-- (§3: "befriend likely session 2 — a reason to return").
FoodConfig.TameCost = 3

function FoodConfig.Get(id: string): Food
	local f = (FoodConfig.Foods :: { [string]: Food })[id]
	assert(f ~= nil, "unknown food id: " .. id)
	return f
end

return table.freeze(FoodConfig)
