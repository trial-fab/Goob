--!strict
-- =============================================================================
-- QuestConfig — daily quests + playtime ladder (session-2 values).
--
-- [Contract] Owns: daily quest definitions ("hatch 5 eggs", "feed 10 times",
--   "befriend a wild slime", "gather 20 Crystal Berries") — goal type,
--   target count, reward — and the playtime-ladder claim table (5/15/30/45 min).
-- [Contract] Never: logic (assignment/progress/claims live in QuestService).
-- [Contract] Binds: DESIGN.md §2 retention mechanics.
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file).
--
-- Goo rewards are GOO-MINUTES (same scheme and reason as DailyRewardConfig:
-- QuestService multiplies by the player's gps at claim). Quest income is tuned
-- to ~15-20 goo-minutes/day total — a felt bonus, never a faucet that competes
-- with the ranch (§3). QuestService deals DailyCount quests/day from the pool,
-- no repeats.

local QuestConfig = {}

export type GoalKind = "Hatch" | "Feed" | "CollectBlobs" | "Befriend" | "Gather" | "StageUp" | "Shrine"

export type Reward = {
	GooMinutes: number?,
	Food: { [string]: number }?, -- FoodConfig id -> count
	Gems: number?,
}

export type Quest = {
	Id: string,
	Text: string, -- tracker row text ("%d" = target count)
	Goal: GoalKind,
	Count: number,
	Reward: Reward,
}

local function quest(q: Quest): Quest
	if q.Reward.Food then
		q.Reward.Food = table.freeze(q.Reward.Food)
	end
	q.Reward = table.freeze(q.Reward)
	return table.freeze(q) :: Quest
end

QuestConfig.DailyCount = 3

QuestConfig.DailyPool = table.freeze({
	quest({
		Id = "hatch_eggs",
		Text = "Hatch %d eggs",
		Goal = "Hatch",
		Count = 3,
		Reward = { GooMinutes = 6 },
	}),
	quest({
		Id = "feed_slimes",
		Text = "Feed your slimes %d times",
		Goal = "Feed",
		Count = 10,
		Reward = { GooMinutes = 6 },
	}),
	quest({
		Id = "collect_blobs",
		Text = "Collect %d goo blobs",
		Goal = "CollectBlobs",
		Count = 30,
		Reward = { GooMinutes = 4 },
	}),
	quest({
		Id = "befriend_wild",
		Text = "Befriend %d wild slime",
		Goal = "Befriend",
		Count = 1,
		Reward = { Gems = 5 }, -- exploration quests pay Gems/food, not Goo
	}),
	quest({
		Id = "gather_foods",
		Text = "Gather %d special foods",
		Goal = "Gather",
		Count = 12,
		Reward = { GooMinutes = 5 },
	}),
	quest({
		Id = "stage_up",
		Text = "Grow %d slimes a life stage",
		Goal = "StageUp",
		Count = 2,
		Reward = { GooMinutes = 8 },
	}),
	quest({
		Id = "shrine_roll",
		Text = "Make %d shrine offering",
		Goal = "Shrine",
		Count = 1,
		Reward = { Food = { sun_petal = 2 } },
	}),
})

-- Weekly chest: complete this many dailies across the week -> Gems (§3).
QuestConfig.WeeklyChest = table.freeze({ DailiesRequired = 15, Gems = 25 })

-- Session playtime ladder (§2): minutes -> claim.
QuestConfig.PlaytimeLadder = table.freeze({
	table.freeze({ Minutes = 5, Reward = table.freeze({ GooMinutes = 2 } :: Reward) }),
	table.freeze({ Minutes = 15, Reward = table.freeze({ GooMinutes = 4 } :: Reward) }),
	table.freeze({ Minutes = 30, Reward = table.freeze({ GooMinutes = 6 } :: Reward) }),
	table.freeze({ Minutes = 45, Reward = table.freeze({ Gems = 3 } :: Reward) }),
})

return table.freeze(QuestConfig)
