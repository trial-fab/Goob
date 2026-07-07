--!strict
-- =============================================================================
-- DecorConfig — the decor catalog (session-2 values; rationale in
-- docs/economy.md).
--
-- [Contract] Owns: the decor catalog — costs (Goo bulk tiers / Gem-Robux
--   prestige tiers), grid footprints, and behavior-affinity tags (trampoline,
--   pond, heat lamp...) the client wander sim weights slimes toward.
-- [Contract] Never: production effects (decor is cosmetic-only, hard rule §2);
--   never part budgets above the Studio build contract (decor <=20 parts, §8 W7).
-- [Contract] Binds: DESIGN.md §2 decor build mode, §3 (open-ended sink).
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file).
--
-- This catalog is the economy's OPEN-ENDED sink (§3 risk 1's structural fix):
-- Goo prices ladder from pocket change to Titan-project money so there is
-- always a next thing to want, at every wealth level. Footprints are grid
-- cells (Build View grid, 4-stud cells). PartBudget is the Studio build
-- contract ceiling per piece — config_check asserts <= 20 (§8 W7).
--
-- Affinity is the WanderSim behavior tag (§2 interactive decor): slimes whose
-- behavior matches the tag weight toward the piece. It changes what the ranch
-- looks like DOING — never what it earns.

local DecorConfig = {}

export type Affinity = "Bounce" | "Swim" | "Nap" | "Play" | "Perch"

export type Decor = {
	Id: string,
	Name: string,
	CostGoo: number?, -- Goo tier (bulk catalog)
	CostGems: number?, -- Gem tier (prestige pieces); exactly one cost is set
	Footprint: { W: number, D: number }, -- grid cells
	PartBudget: number, -- max parts, Studio build contract (<= 20)
	Affinity: Affinity?, -- nil = pure scenery
}

local function decor(d: Decor): Decor
	d.Footprint = table.freeze(d.Footprint)
	return table.freeze(d) :: Decor
end

DecorConfig.Catalog = table.freeze({
	-- Goo tier — the bottomless bulk catalog, cheap to absurd
	picket_fence = decor({
		Id = "picket_fence",
		Name = "Picket Fence",
		CostGoo = 400,
		Footprint = { W = 2, D = 1 },
		PartBudget = 6,
	}),
	stone_path = decor({
		Id = "stone_path",
		Name = "Stone Path",
		CostGoo = 650,
		Footprint = { W = 1, D = 1 },
		PartBudget = 4,
	}),
	flower_bed = decor({
		Id = "flower_bed",
		Name = "Flower Bed",
		CostGoo = 900,
		Footprint = { W = 2, D = 1 },
		PartBudget = 10,
	}),
	berry_bush = decor({
		Id = "berry_bush",
		Name = "Berry Bush",
		CostGoo = 1500,
		Footprint = { W = 1, D = 1 },
		PartBudget = 8,
		Affinity = "Perch", -- snack-spot flavor; Hungry/Greedy slimes idle here
	}),
	mushroom_ring = decor({
		Id = "mushroom_ring",
		Name = "Mushroom Ring",
		CostGoo = 2500,
		Footprint = { W = 2, D = 2 },
		PartBudget = 12,
		Affinity = "Nap",
	}),
	trampoline = decor({
		Id = "trampoline",
		Name = "Trampoline",
		CostGoo = 6000,
		Footprint = { W = 2, D = 2 },
		PartBudget = 10,
		Affinity = "Bounce", -- the MVP proof piece: slimes actually bounce on it
	}),
	slime_slide = decor({
		Id = "slime_slide",
		Name = "Slime Slide",
		CostGoo = 15000,
		Footprint = { W = 2, D = 3 },
		PartBudget = 14,
		Affinity = "Play",
	}),
	pond = decor({
		Id = "pond",
		Name = "Pond",
		CostGoo = 40000,
		Footprint = { W = 3, D = 3 },
		PartBudget = 12,
		Affinity = "Swim", -- Ocean-line slimes swim; the second MVP proof piece
	}),
	heat_lamp = decor({
		Id = "heat_lamp",
		Name = "Heat Lamp",
		CostGoo = 100000,
		Footprint = { W = 1, D = 1 },
		PartBudget = 8,
		Affinity = "Nap", -- Sleepy slimes cluster under it (§2)
	}),
	crystal_lantern = decor({
		Id = "crystal_lantern",
		Name = "Crystal Lantern",
		CostGoo = 250000,
		Footprint = { W = 1, D = 1 },
		PartBudget = 10,
	}),
	geyser_fountain = decor({
		Id = "geyser_fountain",
		Name = "Geyser Fountain",
		CostGoo = 600000,
		Footprint = { W = 2, D = 2 },
		PartBudget = 16,
		Affinity = "Play",
	}),
	cloud_swing = decor({
		Id = "cloud_swing",
		Name = "Cloud Swing",
		CostGoo = 1500000,
		Footprint = { W = 2, D = 1 },
		PartBudget = 12,
		Affinity = "Play",
	}),
	rainbow_arch = decor({
		Id = "rainbow_arch",
		Name = "Rainbow Arch",
		CostGoo = 4000000,
		Footprint = { W = 3, D = 1 },
		PartBudget = 14,
	}),
	golden_statue = decor({
		Id = "golden_statue",
		Name = "Golden Slime Statue",
		CostGoo = 10000000,
		Footprint = { W = 2, D = 2 },
		PartBudget = 16,
		Affinity = "Perch",
	}),
	titan_throne = decor({
		Id = "titan_throne",
		Name = "Titan Throne",
		CostGoo = 25000000, -- the week-4+ flex; sits above a Volcano egg on purpose
		Footprint = { W = 3, D = 3 },
		PartBudget = 20,
		Affinity = "Perch",
	}),

	-- Gem tier — prestige pieces (Gems are earned free slowly or bought, §3)
	star_projector = decor({
		Id = "star_projector",
		Name = "Star Projector",
		CostGems = 250,
		Footprint = { W = 1, D = 1 },
		PartBudget = 10,
	}),
	aurora_lamp = decor({
		Id = "aurora_lamp",
		Name = "Aurora Lamp",
		CostGems = 450,
		Footprint = { W = 1, D = 1 },
		PartBudget = 12,
		Affinity = "Nap",
	}),
	comet_fountain = decor({
		Id = "comet_fountain",
		Name = "Comet Fountain",
		CostGems = 800,
		Footprint = { W = 2, D = 2 },
		PartBudget = 18,
		Affinity = "Play",
	}),
})

function DecorConfig.Get(id: string): Decor
	local d = (DecorConfig.Catalog :: { [string]: Decor })[id]
	assert(d ~= nil, "unknown decor id: " .. id)
	return d
end

return table.freeze(DecorConfig)
