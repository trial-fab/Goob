--!strict
-- =============================================================================
-- GrowthConfig — the life-stage ladder (session-2 values; rationale in
-- docs/economy.md).
--
-- [Contract] Owns: the life-stage ladder Blob -> Slime -> Jumbo -> Titan —
--   stage production multipliers (x1/x3/x9/x27), per-stage food costs (scaling
--   with stage — Titan feeds are expensive, an inflation sink §3), stage-up
--   real-time timers, and model scale per stage.
-- [Contract] Never: multipliers applied anywhere but ProductionFormula.
-- [Contract] Binds: DESIGN.md §2 life stages, §3 pacing.
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file).
--
-- Feed costs are expressed in SECONDS OF THE SLIME'S OWN BASE OUTPUT
-- (FeedCostSecondsOfBase): one feed for a Base-42 Geode costs 42x more Goo
-- than for a Base-1 Mossy. This keeps stage-up payback time identical across
-- every species and line with a single tuning knob — and it is why food is a
-- sink that SCALES with the economy instead of inflating away (§3 risk 1).
-- Mutation/Molt multipliers deliberately do NOT raise feed costs: a lucky roll
-- makes growing that slime a bargain, which is what makes mutations exciting.
--
-- Total stage-up food cost (Feeds x FeedCostSecondsOfBase, in seconds of the
-- slime's own base output) and payback after the x3 jump:
--   Blob->Slime   240s of base = ~4 min of Blob output,   pays back in ~2 min
--     (cheap on purpose: it competes with 100-300 Goo eggs for the same early
--      pocket money and must win before minute 10 — the §3 beat)
--   Slime->Jumbo  5400s of base = ~30 min of Slime output, pays back in ~15 min
--   Jumbo->Titan 72000s of base = ~2.2 h of Jumbo output, pays back in ~67 min
--     (deliberately a PROJECT, not a bargain: Titan feeds are the §3 "food
--      costs scale with stage" inflation sink — players do it for the x27,
--      not the ROI)
-- TimerSeconds is minimum REAL time in the current stage (offline counts;
-- Instant-Grow skips the timer, never the food): 5 min gets the first stage-up
-- inside the minute-10 beat; 24 h / 72 h make Jumbo a week-1 arrival and Titan
-- the week-2-4 feeding project (§3) — the timers, not the food, are what stop
-- the x9/x27 multipliers from compounding into day-1 idle inflation (the first
-- sim run proved they do: whole-ranch Jumbo on day 1 ran the curve ~100x hot).

local GrowthConfig = {}

export type Stage = {
	Stage: number,
	Name: string,
	Mult: number, -- production multiplier (ProductionFormula StageMult term)
	ModelScale: number, -- Studio model scale at this stage
	RefundMult: number, -- scales SlimeConfig RefundGoo on release at this stage
}

export type StageUp = {
	From: number,
	Feeds: number, -- feed interactions required
	FeedCostSecondsOfBase: number, -- Goo per feed = ceil(species.Base * this)
	TimerSeconds: number, -- min real-time age in current stage before advancing
}

GrowthConfig.Stages = table.freeze({
	table.freeze({ Stage = 1, Name = "Blob", Mult = 1, ModelScale = 0.6, RefundMult = 1 }),
	table.freeze({ Stage = 2, Name = "Slime", Mult = 3, ModelScale = 1.0, RefundMult = 2 }),
	table.freeze({ Stage = 3, Name = "Jumbo", Mult = 9, ModelScale = 1.6, RefundMult = 3 }),
	-- RefundMult tops out at 4 while stage mult reaches 27 and food invested is
	-- ~16000s of base: releasing a grown slime returns a token, never the
	-- investment (no feed->release printer; config_check asserts the margin).
	table.freeze({ Stage = 4, Name = "Titan", Mult = 27, ModelScale = 2.6, RefundMult = 4 }),
})

GrowthConfig.StageUps = table.freeze({
	table.freeze({ From = 1, Feeds = 5, FeedCostSecondsOfBase = 48, TimerSeconds = 300 }),
	table.freeze({ From = 2, Feeds = 15, FeedCostSecondsOfBase = 360, TimerSeconds = 86400 }),
	table.freeze({ From = 3, Feeds = 40, FeedCostSecondsOfBase = 1800, TimerSeconds = 259200 }),
})

-- Pure lookup: Goo cost of ONE feed for a species at a stage. GrowthService
-- charges it, the feed prompt displays it, the sim spends it — one function.
function GrowthConfig.FeedCost(speciesBase: number, fromStage: number): number
	local up = GrowthConfig.StageUps[fromStage]
	assert(up ~= nil, "no stage-up from stage " .. fromStage)
	return math.ceil(speciesBase * up.FeedCostSecondsOfBase)
end

return table.freeze(GrowthConfig)
