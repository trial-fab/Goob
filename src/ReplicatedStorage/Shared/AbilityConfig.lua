--!strict
-- =============================================================================
-- AbilityConfig — ability families -> effect params (session-2 values).
--
-- [Contract] Owns: ability families (Mobility / Access / Gathering / Luck) —
--   family -> effect params per species family, and mutation enhancements.
-- [Contract] Never: production multipliers — abilities are exploration utility
--   ONLY (hard rule, §2); Access gating semantics belong to ZoneService (this
--   is data).
-- [Contract] Binds: DESIGN.md §2 abilities (hard rule), §5 zone validation.
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file).
--
-- A species' family is in SlimeConfig (one per species); params here apply to
-- every slime of that family, scaled two ways:
--   RarityScale     rarer species carry stronger versions of the same utility
--                   (indexed by SlimeConfig.Rarities[rarity].Order)
--   mutation        effect * (1 + MutationEffectBonusPerTier * mutation Tier) —
--                   the §2 "mutations enhance the family ability" hook that
--                   makes a Crystal water-walker functionally special
-- Every number here feeds exploration (SquadService/ZoneService validation,
-- client presentation). None of them can reach ProductionFormula — it has no
-- parameter to pass them through (config_check asserts the purity anyway).

local AbilityConfig = {}

export type FamilyParams = { [string]: number }

AbilityConfig.MutationEffectBonusPerTier = 0.15

-- Effect strength multiplier by rarity Order (Common=1 .. Legendary=5).
AbilityConfig.RarityScale = table.freeze({ 1, 1.2, 1.5, 2, 3 })

AbilityConfig.Families = table.freeze({
	Mobility = table.freeze({
		FollowSpeedMult = 1.10, -- squad moves faster with a Mobility slime equipped
		BouncePadPower = 1.0, -- launch strength on zone bounce pads (presentation)
	}),
	Gathering = table.freeze({
		MagnetRadius = 12, -- studs: goo blobs / node drops pulled to the player
		HarvestSpeedMult = 1.25, -- node harvest channel time divisor
	}),
	Luck = table.freeze({
		EncounterLuckMult = 1.10, -- wild-spawn encounter odds (WildSlimeService)
		ShrineLuckMult = 1.05, -- shrine roll odds (ShrineService, disclosed numerically)
	}),
	-- Access carries no numeric effect: its power is the key itself. Equipping
	-- the slime whose AccessKey matches a zone's requirement IS the unlock
	-- (validated server-side from the equipped roster, never from position).
	Access = table.freeze({}),
})

-- The four door keys (SlimeConfig species .AccessKey -> ZoneConfig unlock).
-- Fixed set at launch; zones and keys ship together.
AbilityConfig.AccessKeys = table.freeze({ "Burrow", "Glow", "WaterWalk", "HeatShield" })

return table.freeze(AbilityConfig)
