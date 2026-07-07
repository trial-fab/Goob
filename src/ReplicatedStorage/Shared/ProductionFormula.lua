--!strict
-- =============================================================================
-- ProductionFormula — THE production formula (implemented session 2).
--
-- [Contract] Owns: THE production formula — base(species) x stageMult x
--   mutationMult x moltMult x eventMult x passMult — as pure functions required
--   by BOTH server (ProductionService accrual) and client (HUD/tooltip
--   display). One module, one truth.
-- [Contract] Never: a second implementation anywhere (§8 W6 — ClickGame paid
--   for client/server formula drift); never nature/ability/decor/cosmetic
--   terms (production is species x stage x mutation x Molt only — hard rule).
-- [Contract] Binds: DESIGN.md §5 tree, §8 W6, §2 hard rules.
-- =============================================================================
--
-- This module requires NOTHING and reads NOTHING but its arguments. That is
-- load-bearing twice over: (1) the off-Roblox pacing sim (tools/economy_sim.luau)
-- requires this exact file through the luau CLI, so any Roblox-only dependency
-- breaks the "spreadsheet and game share one formula" guarantee; (2) the argument
-- list IS the hard rule — there is no parameter a nature, ability, decor, or
-- cosmetic term could ride in on. Callers look up the multipliers from
-- GrowthConfig/MutationConfig and pass numbers.

local ProductionFormula = {}

export type GpsArgs = {
	Base: number, -- species base Goo/s at Blob stage (SlimeConfig.Species[id].Base)
	StageMult: number, -- GrowthConfig.Stages[stage].Mult (x1 / x3 / x9 / x27)
	MutationMult: number, -- MutationConfig.Mutations[id].Mult (x1 / x2 / x5 / x15 / x50)
	Molts: number, -- Profile.Data.Molts (count, not a multiplier)
	EventMult: number?, -- WorldEventMultipliers product (server events); default 1
	PassMult: number?, -- gamepass product, e.g. VIP 1.25 (MonetizationConfig, session 3); default 1
}

-- Molt count -> permanent production multiplier. Linear (1 + molts): the first
-- Molt doubles output (the week 2-4 "snap back" release, §3), later Molts add
-- the same absolute step so prestige stays desirable without compounding into
-- the idle-inflation risk §3 flags (2^molts was rejected for exactly that).
function ProductionFormula.MoltMult(molts: number): number
	assert(molts >= 0, "molts must be >= 0")
	return 1 + molts
end

-- Goo/s for one slime. The full formula — every term, nothing else.
function ProductionFormula.Gps(args: GpsArgs): number
	return args.Base
		* args.StageMult
		* args.MutationMult
		* ProductionFormula.MoltMult(args.Molts)
		* (args.EventMult or 1)
		* (args.PassMult or 1)
end

return table.freeze(ProductionFormula)
