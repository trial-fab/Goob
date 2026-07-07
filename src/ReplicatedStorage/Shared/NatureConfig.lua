--!strict
-- =============================================================================
-- NatureConfig — the 12 natures (session-2 values).
--
-- [Contract] Owns: the 12 natures — uniform 1/12 roll (disclosed in odds
--   popups), each nature's wander-personality parameters (drives WanderSim),
--   and its ONE +-10% exploration-stat modifier (gather speed, encounter luck,
--   or follow speed).
-- [Contract] Never: Goo production effects — THE hard rule. Natures are
--   personality + attachment + trade granularity, never economy (§2).
-- [Contract] Binds: DESIGN.md §2 natures (hard rule), §5 wander sim.
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file).
--
-- Exactly ONE Exploration modifier per nature, on one of three stats, inside
-- the +-10% band — config_check asserts all three properties, plus the absence
-- of any production-shaped field. Modifiers are balanced in pairs (each stat
-- gets +10/+5/-5/-10) so no nature is strictly best and "nature hunting" stays
-- a preference chase, not a power chase.
--
-- Wander params are consumed by WanderSim (session 3) and are deliberately
-- coarse 0..1 biases — determinism and exact feel live in the sim, data here:
--   HopPower    relative hop height (1 = baseline)
--   Pace        wander speed bias (1 = baseline)
--   NapBias     0..1 chance-weight of picking a nap behavior
--   SocialBias  0..1 weight toward visitors / other slimes
--   BlobBias     0..1 weight toward goo blobs and food decor
--   PetsForHeart pets needed for the heart reaction (attachment flavor)

local NatureConfig = {}

export type ExplorationStat = "GatherSpeed" | "EncounterLuck" | "FollowSpeed"

export type Nature = {
	Id: string,
	Name: string,
	Blurb: string, -- one-liner the SlimeCard/odds popup shows
	Exploration: { Stat: ExplorationStat, Mult: number }, -- the ONE +-10% modifier
	Wander: {
		HopPower: number,
		Pace: number,
		NapBias: number,
		SocialBias: number,
		BlobBias: number,
		PetsForHeart: number,
	},
}

local function nature(n: Nature): Nature
	n.Exploration = table.freeze(n.Exploration)
	n.Wander = table.freeze(n.Wander)
	return table.freeze(n) :: Nature
end

NatureConfig.Natures = table.freeze({
	-- GatherSpeed pair-set
	greedy = nature({
		Id = "greedy",
		Name = "Greedy",
		Blurb = "Beelines to goo blobs.",
		Exploration = { Stat = "GatherSpeed", Mult = 1.10 },
		Wander = { HopPower = 1, Pace = 1.15, NapBias = 0.05, SocialBias = 0.1, BlobBias = 0.9, PetsForHeart = 2 },
	}),
	hungry = nature({
		Id = "hungry",
		Name = "Hungry",
		Blurb = "Always first to the feed bowl.",
		Exploration = { Stat = "GatherSpeed", Mult = 1.05 },
		Wander = { HopPower = 1, Pace = 1.05, NapBias = 0.1, SocialBias = 0.2, BlobBias = 0.75, PetsForHeart = 2 },
	}),
	shy = nature({
		Id = "shy",
		Name = "Shy",
		Blurb = "Keeps to the quiet corners.",
		Exploration = { Stat = "GatherSpeed", Mult = 0.95 },
		Wander = { HopPower = 0.9, Pace = 0.9, NapBias = 0.2, SocialBias = 0.05, BlobBias = 0.4, PetsForHeart = 3 },
	}),
	sleepy = nature({
		Id = "sleepy",
		Name = "Sleepy",
		Blurb = "Naps anywhere warm.",
		Exploration = { Stat = "GatherSpeed", Mult = 0.90 },
		Wander = { HopPower = 0.8, Pace = 0.7, NapBias = 0.6, SocialBias = 0.15, BlobBias = 0.3, PetsForHeart = 2 },
	}),

	-- EncounterLuck pair-set
	curious = nature({
		Id = "curious",
		Name = "Curious",
		Blurb = "Follows every visitor around.",
		Exploration = { Stat = "EncounterLuck", Mult = 1.10 },
		Wander = { HopPower = 1, Pace = 1.1, NapBias = 0.05, SocialBias = 0.85, BlobBias = 0.4, PetsForHeart = 1 },
	}),
	brave = nature({
		Id = "brave",
		Name = "Brave",
		Blurb = "Leads the pack into anything.",
		Exploration = { Stat = "EncounterLuck", Mult = 1.05 },
		Wander = { HopPower = 1.1, Pace = 1.1, NapBias = 0.05, SocialBias = 0.5, BlobBias = 0.5, PetsForHeart = 2 },
	}),
	grumpy = nature({
		Id = "grumpy",
		Name = "Grumpy",
		Blurb = "Three pets before you get a heart.",
		Exploration = { Stat = "EncounterLuck", Mult = 0.95 },
		Wander = { HopPower = 0.9, Pace = 0.85, NapBias = 0.25, SocialBias = 0.1, BlobBias = 0.5, PetsForHeart = 3 },
	}),
	timid = nature({
		Id = "timid",
		Name = "Timid",
		Blurb = "Startles at its own squish.",
		Exploration = { Stat = "EncounterLuck", Mult = 0.90 },
		Wander = { HopPower = 0.8, Pace = 0.95, NapBias = 0.15, SocialBias = 0.05, BlobBias = 0.35, PetsForHeart = 2 },
	}),

	-- FollowSpeed pair-set
	zippy = nature({
		Id = "zippy",
		Name = "Zippy",
		Blurb = "Never stops bouncing off the walls.",
		Exploration = { Stat = "FollowSpeed", Mult = 1.10 },
		Wander = { HopPower = 1.2, Pace = 1.4, NapBias = 0.02, SocialBias = 0.3, BlobBias = 0.5, PetsForHeart = 2 },
	}),
	bouncy = nature({
		Id = "bouncy",
		Name = "Bouncy",
		Blurb = "Hops twice as high as it needs to.",
		Exploration = { Stat = "FollowSpeed", Mult = 1.05 },
		Wander = { HopPower = 1.5, Pace = 1.1, NapBias = 0.05, SocialBias = 0.3, BlobBias = 0.5, PetsForHeart = 2 },
	}),
	proud = nature({
		Id = "proud",
		Name = "Proud",
		Blurb = "Poses whenever someone looks.",
		Exploration = { Stat = "FollowSpeed", Mult = 0.95 },
		Wander = { HopPower = 1, Pace = 0.9, NapBias = 0.1, SocialBias = 0.6, BlobBias = 0.3, PetsForHeart = 3 },
	}),
	lazy = nature({
		Id = "lazy",
		Name = "Lazy",
		Blurb = "Moves only when it must.",
		Exploration = { Stat = "FollowSpeed", Mult = 0.90 },
		Wander = { HopPower = 0.7, Pace = 0.6, NapBias = 0.5, SocialBias = 0.2, BlobBias = 0.45, PetsForHeart = 2 },
	}),
})

-- Uniform roll, disclosed in every odds popup (§2). 1/12 is not a finite
-- decimal, so the popup renders this string rather than a rounded number
-- pretending to be exact.
NatureConfig.RollDisclosure = "Each nature: 1 in 12"

return table.freeze(NatureConfig)
