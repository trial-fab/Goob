--!strict
-- =============================================================================
-- DailyRewardConfig — the 7-day streak calendar (session-2 values).
--
-- [Contract] Owns: the 7-day streak calendar table (Goo -> food -> Gems ->
--   day-7 exclusive egg) consumed by DailyRewardService and the streak modal.
-- [Contract] Never: logic (data only; claim/reset rules live in the service).
-- [Contract] Binds: DESIGN.md §2 daily streak, §6 reuse map (PORT-AS-IS shape).
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file).
--
-- Goo rewards are GOO-MINUTES (minutes of the claimer's current gps, computed
-- by DailyRewardService at claim time), not flat Goo — a day-1 player and a
-- week-3 player both feel the claim, and the streak never becomes either a
-- rounding error or a faucet (§3). Food/Gems/egg are flat: they're
-- progression-neutral by design.

local DailyRewardConfig = {}

export type Reward = {
	Goo: number?, -- flat Goo (day 1 only: gps-scaled Goo at minute 0 would buy the first eggs instantly)
	GooMinutes: number?, -- minutes of current gps, service-computed
	Food: { [string]: number }?, -- FoodConfig id -> count
	Gems: number?,
	EggId: string?, -- EggConfig id, granted unhatched
}

local function day(r: Reward): Reward
	if r.Food then
		r.Food = table.freeze(r.Food)
	end
	return table.freeze(r) :: Reward
end

-- Index = streak day. Escalates Goo -> food -> Gems -> exclusive egg (§2).
DailyRewardConfig.Days = table.freeze({
	day({ Goo = 50 }), -- under one egg: a hello, not a head start
	day({ Food = { sun_petal = 3 } }),
	day({ GooMinutes = 8 }),
	day({ Food = { crystal_berry = 3 } }),
	day({ Gems = 10 }), -- the free-Gems drip (§3 currency map)
	day({ GooMinutes = 12 }),
	day({ EggId = "streak_egg" }), -- day-7 exclusive egg (EggConfig, never sold)
})

return table.freeze(DailyRewardConfig)
