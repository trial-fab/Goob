--!strict
-- =============================================================================
-- ZoneConfig — the zone ladder (session-2 values; rationale in
-- docs/economy.md).
--
-- [Contract] Owns: the zone ladder (Meadow Wilds -> Crystal Caves -> Tide
--   Pools -> Volcanic Springs) — unlock requirements (which Access ability +
--   progression), wild-spawn tables, gathering-node tables/cooldowns, shrine
--   parameters, and daily-rotation weights.
-- [Contract] Never: physical geometry (Studio-authored; barriers are
--   presentation — validation is state-based in ZoneService).
-- [Contract] Binds: DESIGN.md §2 exploration, §5 zone-access validation.
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file).
--
-- Goo geyser yields are expressed in SECONDS OF THE PLAYER'S CURRENT GPS
-- (YieldGpsSeconds) and computed server-side by GatherService at harvest time.
-- Flat Goo numbers would be either broken at week 1 or worthless at week 4;
-- gps-seconds make expedition income a stable fraction of ranch income at
-- every progression point (~10-15% for an active explorer) — exploration's
-- Goo is a topping, ACQUISITION is its real paycheck (§1 loop table).
--
-- Wild spawn weights are per-10000 like MutationConfig rolls (validated at
-- load). Unlock = SlimesOwned threshold AND (for zones 2+) an equipped slime
-- carrying the AccessKey — both checked server-side from profile + squad
-- state, never from position (§5).

local ZoneConfig = {}

export type Node = {
	Id: string,
	Kind: "Goo" | "Food",
	YieldGpsSeconds: number?, -- Goo nodes: seconds of the harvester's gps
	FoodId: string?, -- Food nodes: FoodConfig id, 1 item per harvest
	CooldownSeconds: number, -- server-side respawn per node
	Count: number, -- nodes of this type placed in the zone (Studio authors positions)
}

export type Zone = {
	Id: string,
	Name: string,
	Order: number, -- ladder position, drives Explore-panel sort + rotation
	Unlock: { SlimesOwned: number, AccessKey: string? },
	FoodId: string, -- the zone's special food (FoodConfig)
	Nodes: { Node },
	WildSpawns: { [string]: number }, -- speciesId -> weight (per 10000)
	SpawnIntervalSeconds: { Min: number, Max: number }, -- server-rolled spawn cadence
	Shrine: { OfferingFoods: number, CooldownSeconds: number },
}

local function zone(z: Zone): Zone
	local nodes = table.clone(z.Nodes)
	for i, n in nodes do
		nodes[i] = table.freeze(n)
	end
	z.Nodes = table.freeze(nodes)
	z.Unlock = table.freeze(z.Unlock)
	z.WildSpawns = table.freeze(z.WildSpawns)
	z.SpawnIntervalSeconds = table.freeze(z.SpawnIntervalSeconds)
	z.Shrine = table.freeze(z.Shrine)
	return table.freeze(z) :: Zone
end

ZoneConfig.Zones = table.freeze({
	meadow_wilds = zone({
		Id = "meadow_wilds",
		Name = "Meadow Wilds",
		Order = 1,
		Unlock = { SlimesOwned = 8 }, -- the §3 session-1 beat; no key for zone 1
		FoodId = "sun_petal",
		Nodes = {
			{ Id = "goo_geyser", Kind = "Goo", YieldGpsSeconds = 45, CooldownSeconds = 180, Count = 3 },
			{ Id = "sun_petal_plant", Kind = "Food", FoodId = "sun_petal", CooldownSeconds = 240, Count = 4 },
		},
		WildSpawns = { meadow_thistle = 10000 },
		SpawnIntervalSeconds = { Min = 120, Max = 240 },
		Shrine = { OfferingFoods = 3, CooldownSeconds = 14400 }, -- 4 h: ~1-2 earned rolls/day
	}),

	crystal_caves = zone({
		Id = "crystal_caves",
		Name = "Crystal Caves",
		Order = 2,
		Unlock = { SlimesOwned = 12, AccessKey = "Burrow" }, -- Clover is the ticket
		FoodId = "crystal_berry",
		Nodes = {
			{ Id = "goo_geyser", Kind = "Goo", YieldGpsSeconds = 50, CooldownSeconds = 180, Count = 3 },
			{ Id = "crystal_berry_bush", Kind = "Food", FoodId = "crystal_berry", CooldownSeconds = 240, Count = 4 },
		},
		WildSpawns = { cave_stalag = 8000, cave_wisp = 2000 },
		SpawnIntervalSeconds = { Min = 150, Max = 300 },
		Shrine = { OfferingFoods = 3, CooldownSeconds = 14400 },
	}),

	tide_pools = zone({
		Id = "tide_pools",
		Name = "Tide Pools",
		Order = 3,
		Unlock = { SlimesOwned = 16, AccessKey = "WaterWalk" }, -- Bubble carries it
		FoodId = "tide_kelp",
		Nodes = {
			{ Id = "goo_geyser", Kind = "Goo", YieldGpsSeconds = 55, CooldownSeconds = 180, Count = 3 },
			{ Id = "tide_kelp_bed", Kind = "Food", FoodId = "tide_kelp", CooldownSeconds = 240, Count = 4 },
		},
		WildSpawns = { ocean_marina = 10000 },
		SpawnIntervalSeconds = { Min = 180, Max = 330 },
		Shrine = { OfferingFoods = 3, CooldownSeconds = 14400 },
	}),

	volcanic_springs = zone({
		Id = "volcanic_springs",
		Name = "Volcanic Springs",
		Order = 4,
		Unlock = { SlimesOwned = 20, AccessKey = "HeatShield" }, -- Cinder carries it
		FoodId = "ember_fruit",
		Nodes = {
			{ Id = "goo_geyser", Kind = "Goo", YieldGpsSeconds = 60, CooldownSeconds = 180, Count = 3 },
			{ Id = "ember_fruit_vine", Kind = "Food", FoodId = "ember_fruit", CooldownSeconds = 240, Count = 4 },
		},
		WildSpawns = { volcano_ashen = 8500, volcano_nova = 1500 },
		SpawnIntervalSeconds = { Min = 180, Max = 360 },
		Shrine = { OfferingFoods = 3, CooldownSeconds = 14400 },
	}),
})

-- Daily zone rotation (§2): one zone per day surges. Uniform pick, effects
-- applied by ZoneService/EventService.
ZoneConfig.DailySurge = table.freeze({
	SpawnRateMult = 2, -- wild spawns twice as often
	NodeYieldMult = 1.5, -- geysers and plants
})

function ZoneConfig.Get(id: string): Zone
	local z = (ZoneConfig.Zones :: { [string]: Zone })[id]
	assert(z ~= nil, "unknown zone id: " .. id)
	return z
end

-- Load-time validation: spawn weights sum to exactly 10000 (same posture as
-- MutationConfig; species-id existence is cross-config -> config_check).
for id, z in ZoneConfig.Zones :: { [string]: Zone } do
	local sum = 0
	for _, weight in z.WildSpawns do
		assert(weight == math.floor(weight) and weight > 0, id .. ": bad spawn weight")
		sum += weight
	end
	assert(sum == 10000, ("%s: spawn weights sum to %d, must be exactly 10000"):format(id, sum))
end

return table.freeze(ZoneConfig)
