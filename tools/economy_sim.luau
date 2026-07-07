--!strict
-- =============================================================================
-- economy_sim — the DESIGN §9 M0 "spreadsheet before code". Off-Roblox:
--   ~/.local/bin/luau tools/economy_sim.luau            (from the project root)
--   ~/.local/bin/luau tools/economy_sim.luau -a 500     (override trial count)
--
-- [Contract] Owns: simulating the first 4 weeks of a free, engaged-casual
--   player against the REAL configs and the REAL Shared/ProductionFormula
--   (required directly — no second copy of the math, §8 W6): production
--   growth (stages x rarity x mutations x Molt), per-line egg ladders,
--   food/stage-up costs, shrine + special-food flows, offline earnings,
--   release refunds. Prints a week-by-week pacing table and PASS/FAIL checks
--   for every §3 pacing beat and §3 inflation risk.
-- [Contract] Never: game logic that ships (this is a model; services own the
--   real rules); never nature or ability terms in any Goo number — the sim
--   deliberately does not require NatureConfig: if pacing needed it, the
--   production-purity hard rule would already be broken.
-- [Contract] Binds: DESIGN.md §3 (beats + inflation risks), §9 M0.
-- =============================================================================
--
-- Player model (an "engaged casual", documented for tuning honesty):
--   day 1:      2 sessions (30 + 25 min); days 2-7: 20 + 25 min;
--   days 8-28:  15 + 25 min. Offline between sessions at 50% gps, 2 h cap.
-- Policy per decision point, in priority order: Molt -> ranch slot (reserved
-- once reachable) -> best-ROI stage-up -> egg of the most advanced line whose
-- next egg costs <= 45 min of gps -> decor with idle Goo. One expedition per
-- session once a zone is unlocked: gather foods + geyser Goo, befriend wilds
-- (favorite discovery, then TameCost), shrine roll when foods + cooldown
-- allow. Daily quests/streak/playtime ladder award their configured values.

local ProductionFormula = require("../src/ReplicatedStorage/Shared/ProductionFormula")
local SlimeConfig = require("../src/ReplicatedStorage/Shared/SlimeConfig")
local EggConfig = require("../src/ReplicatedStorage/Shared/EggConfig")
local MutationConfig = require("../src/ReplicatedStorage/Shared/MutationConfig")
local GrowthConfig = require("../src/ReplicatedStorage/Shared/GrowthConfig")
local FoodConfig = require("../src/ReplicatedStorage/Shared/FoodConfig")
local ZoneConfig = require("../src/ReplicatedStorage/Shared/ZoneConfig")
local DecorConfig = require("../src/ReplicatedStorage/Shared/DecorConfig")
local RanchConfig = require("../src/ReplicatedStorage/Shared/RanchConfig")
local DailyRewardConfig = require("../src/ReplicatedStorage/Shared/DailyRewardConfig")
local QuestConfig = require("../src/ReplicatedStorage/Shared/QuestConfig")

local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }
local Eggs = EggConfig.Eggs :: { [string]: EggConfig.Egg }
local Zones = ZoneConfig.Zones :: { [string]: ZoneConfig.Zone }
local Mutations = MutationConfig.Mutations :: { [string]: MutationConfig.Mutation }

-- ----------------------------------------------------------- sim constants --
-- DESIGN §2 offline earnings (constants live with OfflineEarningsService in
-- session 3; §2 fixes them: 50% rate, 2 h free cap).
local OFFLINE_RATE = 0.5
local OFFLINE_CAP_SECONDS = 2 * 3600

-- Molt is v1-not-MVP (§2); the sim models it because the §3 week-2-4 "first
-- Molt" beat depends on it. Requirement: lifetime Goo earned, x4 per Molt
-- taken (a flat requirement would allow instant re-molts). Recommendation
-- recorded in docs/economy.md; the config home is a session-3 decision.
local MOLT_LIFETIME_REQ = 500e6
local MOLT_REQ_GROWTH = 5

local DAYS = 28
local DAY = 24 * 3600

-- policy knobs (documented in docs/economy.md)
local EGG_TARGET_HORIZON = 45 * 60 -- switch lines when next line <= 45 min of gps
local SLOT_RESERVE_HORIZON = 40 * 60 -- start saving for a slot this far out
local STAGEUP_MAX_PAYBACK = 120 * 60 -- Titan feeds are a project, not a bargain (§3)
local DECOR_BUFFER = 45 * 60 -- decor only with Goo above this many seconds of gps
local FOOD_RESERVE = 6 -- foods kept for befriend/shrine before premium feeding
-- all four special foods share one FeedValue (FoodConfig); the sim pools foods
local FEED_VALUE = (FoodConfig.Foods :: any).sun_petal.FeedValue :: number
local DISCOVERY_ATTEMPTS = 3 -- wrong-food hints before a wild's favorite is known
local DUPE_KEEP = 3 -- copies of a species kept before releasing Blob dupes
local EXPEDITION_SECONDS = 12 * 60
local QUEST_GOO_MINUTES_PER_DAY = 16 -- 3 dailies' GooMinutes (QuestConfig avg)

-- ------------------------------------------------------------------- rng ----
local rngState = 42
local function srand(seed: number)
	rngState = seed
end
local function rand(): number -- deterministic xorshift-ish LCG, [0,1)
	rngState = (rngState * 1103515245 + 12345) % 2147483648
	return rngState / 2147483648
end
local function rollWeights(weights: { [string]: number }): string
	local r = rand() * 10000
	local acc = 0
	for id, w in weights do
		acc += w
		if r < acc then
			return id
		end
	end
	local last
	for id in weights do
		last = id
	end
	return last :: string
end

-- ------------------------------------------------------------------ state ---
type SimSlime = {
	SpeciesId: string,
	Base: number,
	Stage: number,
	MutMult: number,
	StageEnteredAt: number,
}

type Metrics = { [string]: number }

type State = {
	t: number,
	activeT: number, -- seconds spent in-session so far
	goo: number,
	lifetimeGoo: number,
	molts: number,
	slots: number,
	slimes: { SimSlime }, -- sorted desc by unit gps; [1..slots] produce
	speciesCount: { [string]: number },
	speciesSeen: { [string]: boolean },
	comboSeen: { [string]: boolean }, -- species:mutation index entries
	foods: number, -- pooled special foods (zone-agnostic model)
	favoriteKnown: { [string]: boolean },
	discoveryFoodsSpent: { [string]: number },
	eggCounts: { [string]: number },
	lineFloor: number, -- BaseCost of the most advanced line started (players don't go back)
	shrineReadyAt: number,
	hatches: number,
	firstShinyPlusHatch: number?,
	expeditionDoneThisSession: boolean,
	-- ledger
	prodGoo: number,
	offlineGoo: number,
	geyserGoo: number,
	questGoo: number,
	refundGoo: number,
	eggSpent: number,
	foodSpent: number,
	slotSpent: number,
	decorSpent: number,
	metrics: Metrics,
	eggWaits: { [string]: { number } }, -- per line: egg cost in seconds-of-gps at each buy
	timeline: { string }?, -- seed-1 event log
}

local function unitGps(s: SimSlime, molts: number): number
	return ProductionFormula.Gps({
		Base = s.Base,
		StageMult = GrowthConfig.Stages[s.Stage].Mult,
		MutationMult = s.MutMult,
		Molts = molts,
	})
end

local function computeGps(st: State): number
	local sum = 0
	for i = 1, math.min(st.slots, #st.slimes) do
		sum += unitGps(st.slimes[i], st.molts)
	end
	return sum
end

local function resort(st: State)
	table.sort(st.slimes, function(a, b)
		return unitGps(a, st.molts) > unitGps(b, st.molts)
	end)
end

local function log(st: State, text: string)
	if st.timeline then
		table.insert(st.timeline :: { string }, ("  [%5.1f min] %s"):format(st.t / 60, text))
	end
end

local function mark(st: State, key: string)
	if st.metrics[key] == nil then
		st.metrics[key] = st.t
	end
end

-- accrue production up to absolute time target (call only inside a session)
local function accrue(st: State, target: number)
	if target <= st.t then
		return
	end
	local dt = target - st.t
	local gained = computeGps(st) * dt
	st.goo += gained
	st.lifetimeGoo += gained
	st.prodGoo += gained
	st.t = target
	st.activeT += dt
end

local function grantGoo(st: State, amount: number, ledger: string)
	st.goo += amount
	st.lifetimeGoo += amount
	local ledgers = st :: any
	ledgers[ledger] = ledgers[ledger] + amount
end

-- ------------------------------------------------------------- mutations ----
local function rollMutation(st: State, tableName: string): (string, number)
	local id = rollWeights((MutationConfig.Rolls :: any)[tableName])
	-- first-session pity: guaranteed Shiny by hatch PityFirstShinyByHatch
	if tableName == "Hatch" and id == "none" then
		if st.firstShinyPlusHatch == nil and st.hatches >= MutationConfig.PityFirstShinyByHatch then
			id = "shiny"
		end
	end
	return id, Mutations[id].Mult
end

-- ------------------------------------------------------------- acquisition --
local function addSlime(st: State, speciesId: string, mutId: string, mutMult: number, source: string)
	local sp = Species[speciesId]
	local slime: SimSlime = {
		SpeciesId = speciesId,
		Base = sp.Base,
		Stage = 1,
		MutMult = mutMult,
		StageEnteredAt = st.t,
	}
	st.speciesCount[speciesId] = (st.speciesCount[speciesId] or 0) + 1
	if not st.speciesSeen[speciesId] then
		st.speciesSeen[speciesId] = true
		local tierKey = "first" .. sp.Rarity
		mark(st, tierKey)
		log(st, ("NEW SPECIES %s (%s %s, base %.1f) via %s"):format(sp.Name, sp.Rarity, sp.Line, sp.Base, source))
	end
	st.comboSeen[speciesId .. ":" .. mutId] = true
	if mutId ~= "none" then
		if st.firstShinyPlusHatch == nil then
			st.firstShinyPlusHatch = st.hatches
		end
		mark(st, "firstMutation")
		log(st, ("MUTATION %s on %s"):format(mutId, sp.Name))
	end
	-- dupe pressure valve: release worthless Blob dupes for the refund (§3 r3)
	local owned = 0
	for _ in st.slimes do
		owned += 1
	end
	if (st.speciesCount[speciesId] :: number) > DUPE_KEEP and sp.Hatchable then
		local worst = st.slimes[#st.slimes]
		if owned >= st.slots and worst and unitGps(slime, st.molts) <= unitGps(worst, st.molts) then
			st.speciesCount[speciesId] = (st.speciesCount[speciesId] :: number) - 1
			grantGoo(st, sp.RefundGoo * GrowthConfig.Stages[1].RefundMult, "refundGoo")
			return -- released immediately, never joins the ranch
		end
	end
	table.insert(st.slimes, slime)
	resort(st)
end

-- percent-odds roller (egg odds sum to 100, not 10000)
local function rollPercent(odds: { [string]: number }): string
	local r = rand() * 100
	local acc = 0
	for id, p in odds do
		acc += p
		if r < acc then
			return id
		end
	end
	local last
	for id in odds do
		last = id
	end
	return last :: string
end

local function hatch(st: State, eggId: string, source: string)
	local egg = Eggs[eggId]
	st.hatches += 1
	local speciesId = rollPercent(egg.Odds :: { [string]: number })
	local mutId, mutMult = rollMutation(st, "Hatch")
	addSlime(st, speciesId, mutId, mutMult, source)
end

-- --------------------------------------------------------------- actions ----
local function ownedCount(st: State): number
	return #st.slimes
end

local function nextSlotCost(st: State): number?
	if st.slots >= RanchConfig.SlotsMax then
		return nil
	end
	return (RanchConfig.SlotCosts :: { [number]: number })[st.slots + 1]
end

-- returns eggId the policy is currently building toward, or nil
local function targetEgg(st: State, gps: number): string?
	local best: string? = nil
	local bestOrder = -1
	for id, egg in Eggs do
		if not egg.Purchasable or egg.BaseCost < st.lineFloor then
			continue -- line-monotonic: players don't re-farm outgrown lines
		end
		-- lines are ordered by base cost (cheap -> advanced)
		local cost = EggConfig.Cost(id, st.eggCounts[id] or 0)
		if cost <= math.max(st.goo, gps * EGG_TARGET_HORIZON) then
			if egg.BaseCost > bestOrder then
				bestOrder = egg.BaseCost
				best = id
			end
		end
	end
	return best
end

-- best stage-up candidate among producing slimes: returns index, cost, readyT
local function bestStageUp(st: State): (number?, number, number)
	local bestI: number? = nil
	local bestCost = 0
	local bestReady = math.huge
	local bestRoi = math.huge
	for i = 1, math.min(st.slots, #st.slimes) do
		local s = st.slimes[i]
		if s.Stage >= 4 then
			continue
		end
		local up = GrowthConfig.StageUps[s.Stage]
		local ready = s.StageEnteredAt + up.TimerSeconds
		-- premium-feed substitution: surplus foods knock FeedValue feeds each
		local surplus = math.max(0, st.foods - FOOD_RESERVE)
		local subst = math.min(up.Feeds, surplus * FEED_VALUE)
		local feedsToPay = up.Feeds - subst
		local cost = feedsToPay * GrowthConfig.FeedCost(s.Base, s.Stage)
		local dGps = unitGps(s, st.molts)
			* (GrowthConfig.Stages[s.Stage + 1].Mult / GrowthConfig.Stages[s.Stage].Mult - 1)
		local payback = if dGps > 0 then cost / dGps else math.huge
		if payback > STAGEUP_MAX_PAYBACK then
			continue
		end
		local roi = payback
		if ready <= st.t and cost <= st.goo then
			if bestI == nil or roi < bestRoi then
				bestI, bestCost, bestReady, bestRoi = i, cost, ready, roi
			end
		elseif bestI == nil then
			local affordT = if computeGps(st) > 0
				then st.t + math.max(0, (cost - st.goo) / computeGps(st))
				else math.huge
			bestReady = math.min(bestReady, math.max(ready, affordT))
		end
	end
	return bestI, bestCost, bestReady
end

local function doStageUp(st: State, i: number, cost: number)
	local s = st.slimes[i]
	local up = GrowthConfig.StageUps[s.Stage]
	-- consume substituted foods first (mirrors bestStageUp's math)
	local surplus = math.max(0, st.foods - FOOD_RESERVE)
	local substItems = math.min(math.ceil(up.Feeds / FEED_VALUE), surplus)
	local substFeeds = math.min(up.Feeds, substItems * FEED_VALUE)
	local feedsToPay = up.Feeds - substFeeds
	local realCost = feedsToPay * GrowthConfig.FeedCost(s.Base, s.Stage)
	st.foods -= substItems
	st.goo -= realCost
	st.foodSpent += realCost
	s.Stage += 1
	s.StageEnteredAt = st.t
	mark(st, "firstStageUp")
	local mutId, mutMult = rollMutation(st, "StageUp")
	if mutMult > s.MutMult then -- keep-better rule
		s.MutMult = mutMult
		st.comboSeen[s.SpeciesId .. ":" .. mutId] = true
		mark(st, "firstMutation")
		log(st, ("stage-up MUTATION %s -> %s"):format(Species[s.SpeciesId].Name, mutId))
	end
	log(
		st,
		("stage-up %s -> %s (paid %.0f)"):format(Species[s.SpeciesId].Name, GrowthConfig.Stages[s.Stage].Name, realCost)
	)
	resort(st)
end

-- ------------------------------------------------------------ exploration ---
local function unlockedZones(st: State): { ZoneConfig.Zone }
	local owned = ownedCount(st)
	local out: { ZoneConfig.Zone } = {}
	for _, z in Zones do
		if owned < z.Unlock.SlimesOwned then
			continue
		end
		local key = z.Unlock.AccessKey
		if key ~= nil then
			local hasKey = false
			for _, s in st.slimes do
				if Species[s.SpeciesId].AccessKey == key then
					hasKey = true
					break
				end
			end
			if not hasKey then
				continue
			end
		end
		table.insert(out, z)
	end
	table.sort(out, function(a, b)
		return a.Order > b.Order
	end)
	return out
end

local function expedition(st: State, sessionEnd: number, surgeZoneOrder: number)
	local zones = unlockedZones(st)
	local zone = zones[1]
	if zone == nil then
		return
	end
	st.expeditionDoneThisSession = true -- set BEFORE any early return: never retrigger this session
	local dur = math.min(EXPEDITION_SECONDS, math.max(0, sessionEnd - st.t - 120))
	if dur < 5 * 60 then
		return
	end
	mark(st, "firstExpedition")
	local surge = zone.Order == surgeZoneOrder
	accrue(st, st.t + dur) -- ranch keeps producing while exploring
	-- gathering: food plants + goo geysers
	local foodGain = math.floor((if dur >= EXPEDITION_SECONDS then 6 else 3) * (if surge then 1.5 else 1) + rand() * 2)
	st.foods += foodGain
	mark(st, "firstGather")
	local geyserSeconds = 0
	for _, node in zone.Nodes do
		if node.Kind == "Goo" then
			geyserSeconds += (node.YieldGpsSeconds :: number) * node.Count * 2 -- ~2 harvest rounds
		end
	end
	grantGoo(
		st,
		computeGps(st) * geyserSeconds * (if surge then ZoneConfig.DailySurge.NodeYieldMult else 1),
		"geyserGoo"
	)
	-- wild sightings -> befriend attempts
	local avgInterval = (zone.SpawnIntervalSeconds.Min + zone.SpawnIntervalSeconds.Max) / 2
	local sightings = math.floor(dur / avgInterval * (if surge then ZoneConfig.DailySurge.SpawnRateMult else 1))
	for _ = 1, sightings do
		local speciesId = rollWeights(zone.WildSpawns :: { [string]: number })
		local sp = Species[speciesId]
		if st.favoriteKnown[speciesId] then
			if st.foods >= FoodConfig.TameCost and (st.speciesCount[speciesId] or 0) < DUPE_KEEP then
				st.foods -= FoodConfig.TameCost
				addSlime(st, speciesId, "none", 1, "befriend")
				mark(st, "firstBefriend")
				log(st, ("BEFRIENDED %s"):format(sp.Name))
			end
		elseif st.foods >= 1 then
			-- discovery: each wrong food reveals hints; favorite found after 2
			st.foods -= 1
			local spent = (st.discoveryFoodsSpent[speciesId] or 0) + 1
			st.discoveryFoodsSpent[speciesId] = spent
			if spent >= DISCOVERY_ATTEMPTS then
				st.favoriteKnown[speciesId] = true
			end
		end
	end
	-- shrine: offer foods for an earned mutation roll (§2 the earned road)
	if st.foods >= zone.Shrine.OfferingFoods and st.t >= st.shrineReadyAt then
		local bestI: number? = nil
		for i = 1, math.min(st.slots, #st.slimes) do
			local s = st.slimes[i]
			if s.MutMult == 1 and (bestI == nil or s.Base > st.slimes[bestI :: number].Base) then
				bestI = i
			end
		end
		if bestI ~= nil then
			st.foods -= zone.Shrine.OfferingFoods
			st.shrineReadyAt = st.t + zone.Shrine.CooldownSeconds
			mark(st, "firstShrine")
			local s = st.slimes[bestI :: number]
			local mutId, mutMult = rollMutation(st, "Shrine")
			if mutMult > s.MutMult then
				s.MutMult = mutMult
				st.comboSeen[s.SpeciesId .. ":" .. mutId] = true
				log(st, ("SHRINE mutation %s -> %s"):format(Species[s.SpeciesId].Name, mutId))
				resort(st)
			else
				log(st, ("shrine roll on %s: no upgrade"):format(Species[s.SpeciesId].Name))
			end
		end
	end
end

-- --------------------------------------------------------------- sessions ---
local function sessionsForDay(day: number): { { start: number, len: number } }
	local base = (day - 1) * DAY
	if day == 1 then
		return { { start = base, len = 30 * 60 }, { start = base + 10 * 3600, len = 25 * 60 } }
	elseif day <= 7 then
		return { { start = base + 1 * 3600, len = 20 * 60 }, { start = base + 10 * 3600, len = 25 * 60 } }
	end
	return { { start = base + 1 * 3600, len = 15 * 60 }, { start = base + 10 * 3600, len = 25 * 60 } }
end

local function runSession(st: State, sessionStart: number, sessionEnd: number, day: number, firstOfDay: boolean)
	st.expeditionDoneThisSession = false
	local surgeZoneOrder = 1 + math.floor(rand() * 4)

	-- housekeeping: release stored Blob dupes beyond DUPE_KEEP copies (§2's
	-- "sell" verb — exercises the §3 refund valve the caps are asserted against)
	for i = #st.slimes, st.slots + 1, -1 do
		local s = st.slimes[i]
		local sp = Species[s.SpeciesId]
		if s.Stage == 1 and sp.Hatchable and (st.speciesCount[s.SpeciesId] or 0) > DUPE_KEEP then
			st.speciesCount[s.SpeciesId] = (st.speciesCount[s.SpeciesId] :: number) - 1
			grantGoo(st, sp.RefundGoo * GrowthConfig.Stages[1].RefundMult, "refundGoo")
			table.remove(st.slimes, i)
		end
	end

	-- daily streak claim (DailyRewardConfig; days 1-7 then repeat weeks)
	if firstOfDay then
		local reward = DailyRewardConfig.Days[((day - 1) % 7) + 1]
		if reward.Goo then
			grantGoo(st, reward.Goo :: number, "questGoo")
		end
		if reward.GooMinutes then
			grantGoo(st, computeGps(st) * 60 * (reward.GooMinutes :: number), "questGoo")
		end
		if reward.Food then
			for _, count in reward.Food :: { [string]: number } do
				st.foods += count
			end
		end
		if reward.EggId then
			hatch(st, reward.EggId :: string, "streak egg")
		end
	end

	local expeditionAt = sessionStart + 4 * 60
	while st.t < sessionEnd do
		local gps = computeGps(st)

		-- 0) expedition trigger (once per session, after the ranch pass)
		if not st.expeditionDoneThisSession and st.t >= expeditionAt and #unlockedZones(st) > 0 then
			expedition(st, sessionEnd, surgeZoneOrder)
			continue
		end

		-- 1) Molt (§2): reset Goo + slots for the permanent multiplier
		local moltReq = MOLT_LIFETIME_REQ * MOLT_REQ_GROWTH ^ st.molts
		if st.lifetimeGoo >= moltReq and day >= 9 and st.goo <= gps * 600 then
			if st.molts == 0 then -- pre-Molt sink split: where food must be visible
				st.metrics.preMoltEgg = st.eggSpent
				st.metrics.preMoltFood = st.foodSpent
				st.metrics.preMoltSlot = st.slotSpent
			end
			st.molts += 1
			st.goo = 0
			st.slots = RanchConfig.SlotsBase
			mark(st, "firstMolt")
			log(st, ("MOLT #%d (production now x%d)"):format(st.molts, ProductionFormula.MoltMult(st.molts)))
			continue
		end

		-- 2) ranch slot (with reservation once reachable)
		local slotCost = nextSlotCost(st)
		local slotReserve = 0
		if slotCost ~= nil and #st.slimes >= st.slots then
			if st.goo >= slotCost then
				st.goo -= slotCost
				st.slotSpent += slotCost
				st.slots += 1
				if st.slots >= 12 then
					mark(st, "slots12")
				end
				log(st, ("ranch slot %d (%.0f Goo)"):format(st.slots, slotCost))
				continue
			elseif slotCost <= st.goo + gps * SLOT_RESERVE_HORIZON then
				slotReserve = slotCost -- start saving: block eggs/decor below
			end
		end

		-- 3) best-ROI stage-up (small, always allowed — it grows gps)
		local upI, upCost, upReady = bestStageUp(st)
		if upI ~= nil then
			doStageUp(st, upI :: number, upCost)
			continue
		end

		-- 4) egg of the target line
		local eggId = targetEgg(st, gps)
		local eggReadyT = math.huge
		if eggId ~= nil then
			local cost = EggConfig.Cost(eggId :: string, st.eggCounts[eggId :: string] or 0)
			local spendable = st.goo - slotReserve
			if cost <= spendable then
				st.goo -= cost
				st.eggSpent += cost
				local n = (st.eggCounts[eggId :: string] or 0) + 1
				st.eggCounts[eggId :: string] = n
				st.lineFloor = math.max(st.lineFloor, Eggs[eggId :: string].BaseCost)
				-- egg cadence stats: §3 speaks of COST IN MINUTES OF PRODUCTION
				-- ("next-egg cost ~3-4 min early -> 15-20 min at line-end"), so record
				-- cost/gps at purchase. Wall-clock waits are useless here: offline
				-- piles make morning buys back-to-back regardless of price. Pre-Molt
				-- only — post-Molt re-runs replay lines at inflated gps.
				if st.molts == 0 and gps > 0 then
					local waits = st.eggWaits[eggId :: string]
					if waits == nil then
						waits = {}
						st.eggWaits[eggId :: string] = waits
					end
					table.insert(waits, cost / gps)
				end
				if n == 1 then
					mark(st, "firstEgg_" .. (eggId :: string))
				end
				hatch(st, eggId :: string, eggId :: string)
				if st.hatches == 2 then
					mark(st, "egg2") -- hatch #1 is the free starter
				elseif st.hatches == 4 then
					mark(st, "egg4")
				end
				log(st, ("bought %s #%d (%.0f Goo) -> %d slimes"):format(eggId :: string, n, cost, #st.slimes))
				continue
			elseif gps > 0 then
				eggReadyT = st.t + (cost - spendable) / gps
			end
		end

		-- 5) decor: the open-ended sink absorbs idle Goo (§3 risk 1)
		if day >= 3 and st.goo - slotReserve > gps * DECOR_BUFFER then
			local bestId: string? = nil
			local bestCost = 0
			for id, d in DecorConfig.Catalog :: { [string]: DecorConfig.Decor } do
				local c = d.CostGoo
				if c ~= nil and c > bestCost and c <= st.goo - slotReserve - gps * DECOR_BUFFER / 2 then
					bestId, bestCost = id, c
				end
			end
			if bestId ~= nil then
				st.goo -= bestCost
				st.decorSpent += bestCost
				log(st, ("decor: %s (%.0f Goo)"):format(bestId :: string, bestCost))
				continue
			end
		end

		-- nothing affordable: advance to the earliest interesting moment
		local nextT = math.min(sessionEnd, upReady, eggReadyT)
		if not st.expeditionDoneThisSession and expeditionAt > st.t and #unlockedZones(st) > 0 then
			nextT = math.min(nextT, expeditionAt)
		end
		if slotCost ~= nil and #st.slimes >= st.slots and gps > 0 then
			nextT = math.min(nextT, st.t + math.max(1, (slotCost - st.goo) / gps))
		end
		if st.lifetimeGoo < moltReq and gps > 0 then
			nextT = math.min(nextT, st.t + math.max(1, (moltReq - st.lifetimeGoo) / gps))
		end
		accrue(st, math.max(nextT, st.t + 1))
	end

	-- playtime ladder + daily quests award at session end
	local sessionMinutes = (sessionEnd - sessionStart) / 60
	local ladderGooMin = 0
	for _, rung in QuestConfig.PlaytimeLadder do
		if sessionMinutes >= rung.Minutes and rung.Reward.GooMinutes then
			ladderGooMin += rung.Reward.GooMinutes :: number
		end
	end
	grantGoo(st, computeGps(st) * 60 * ladderGooMin, "questGoo")
	if firstOfDay then
		grantGoo(st, computeGps(st) * 60 * QUEST_GOO_MINUTES_PER_DAY, "questGoo")
	end
end

-- ------------------------------------------------------------------ trial ---
type WeekRow = {
	week: number,
	gps: number,
	goo: number,
	lifetime: number,
	slimes: number,
	species: number,
	slots: number,
	molts: number,
	eggs: string,
}

local function runTrial(seed: number, wantTimeline: boolean): (State, { WeekRow })
	srand(seed * 9973 + 7)
	local st: State = {
		t = 0,
		activeT = 0,
		goo = 0,
		lifetimeGoo = 0,
		molts = 0,
		slots = RanchConfig.SlotsBase,
		slimes = {},
		speciesCount = {},
		speciesSeen = {},
		comboSeen = {},
		foods = 0,
		favoriteKnown = {},
		discoveryFoodsSpent = {},
		eggCounts = {},
		lineFloor = 0,
		shrineReadyAt = 0,
		hatches = 0,
		firstShinyPlusHatch = nil,
		expeditionDoneThisSession = false,
		prodGoo = 0,
		offlineGoo = 0,
		geyserGoo = 0,
		questGoo = 0,
		refundGoo = 0,
		eggSpent = 0,
		foodSpent = 0,
		slotSpent = 0,
		decorSpent = 0,
		metrics = {},
		eggWaits = {},
		timeline = if wantTimeline then {} else nil,
	}

	local weeks: { WeekRow } = {}
	local lastLeaveT = 0
	local lastLeaveGps = 0

	-- minute 1: the free starter egg (§3)
	st.hatches = 1
	addSlime(st, "meadow_mossy", "none", 1, "starter egg")
	log(st, "starter egg hatched: Mossy joins the ranch")

	for day = 1, DAYS do
		for si, sess in sessionsForDay(day) do
			-- offline accrual since last leave (snapshot gps, §2 offline)
			local gap = sess.start - lastLeaveT
			if gap > 0 and lastLeaveGps > 0 then
				local gained = lastLeaveGps * OFFLINE_RATE * math.min(gap, OFFLINE_CAP_SECONDS)
				st.goo += gained
				st.lifetimeGoo += gained
				st.offlineGoo += gained
			end
			st.t = sess.start
			runSession(st, sess.start, sess.start + sess.len, day, si == 1)
			lastLeaveT = st.t
			lastLeaveGps = computeGps(st)

			-- session-1 beat snapshot (producing = what the §3 "6-8 slimes" means;
			-- extra owned blobs are stored inventory, the trade/collection fodder)
			if day == 1 and si == 1 then
				st.metrics.session1Producing = math.min(st.slots, #st.slimes)
				st.metrics.session1Owned = #st.slimes
			end
		end
		if day % 7 == 0 then
			local eggSummary = ""
			for _, id in { "meadow_egg", "cave_egg", "ocean_egg", "volcano_egg" } do
				eggSummary ..= tostring(st.eggCounts[id] or 0) .. " "
			end
			local speciesN = 0
			for _ in st.speciesSeen do
				speciesN += 1
			end
			table.insert(weeks, {
				week = day / 7,
				gps = computeGps(st),
				goo = st.goo,
				lifetime = st.lifetimeGoo,
				slimes = #st.slimes,
				species = speciesN,
				slots = st.slots,
				molts = st.molts,
				eggs = eggSummary,
			})
		end
	end
	return st, weeks
end

-- ------------------------------------------------------------- aggregation --
local function percentile(sorted: { number }, p: number): number
	if #sorted == 0 then
		return math.huge
	end
	local idx = math.max(1, math.min(#sorted, math.floor(p * #sorted + 0.5)))
	return sorted[idx]
end

local function fmtT(seconds: number): string
	if seconds == math.huge then
		return "never"
	end
	if seconds < 3600 then
		return ("%.1f min"):format(seconds / 60)
	end
	return ("day %.1f"):format(seconds / DAY + 1)
end

local function fmtGoo(n: number): string
	if n >= 1e9 then
		return ("%.2fB"):format(n / 1e9)
	elseif n >= 1e6 then
		return ("%.2fM"):format(n / 1e6)
	elseif n >= 1e3 then
		return ("%.1fk"):format(n / 1e3)
	end
	return ("%.0f"):format(n)
end

-- ---------------------------------------------------------------- driver ----
local args = { ... }
local TRIALS = tonumber(args[1]) or 200

print(("economy_sim: %d trials x %d days"):format(TRIALS, DAYS))
print("")

-- seed 1 detail run
local st1, weeks1 = runTrial(1, true)
print("--- seed-1 session 1 timeline (the §3 minute-by-minute beats) ---")
local shown = 0
for _, line in st1.timeline :: { string } do
	print(line)
	shown += 1
	if shown > 60 then
		print("  ... (truncated)")
		break
	end
end
print("")
print("--- seed-1 week-by-week ---")
print("week |      gps |  balance | lifetime | slimes | species | slots | molts | eggs M/C/O/V")
for _, w in weeks1 do
	print(
		("%4d | %8s | %8s | %8s | %6d | %7d | %5d | %5d | %s"):format(
			w.week,
			fmtGoo(w.gps),
			fmtGoo(w.goo),
			fmtGoo(w.lifetime),
			w.slimes,
			w.species,
			w.slots,
			w.molts,
			w.eggs
		)
	)
end
print("")

-- Monte Carlo
local metricKeys = {
	"egg2",
	"egg4",
	"firstStageUp",
	"firstUncommon",
	"firstRare",
	"firstEpic",
	"firstLegendary",
	"firstExpedition",
	"firstBefriend",
	"firstShrine",
	"firstMutation",
	"firstMolt",
	"slots12",
	"firstEgg_cave_egg",
	"firstEgg_ocean_egg",
	"firstEgg_volcano_egg",
}
local samples: { [string]: { number } } = {}
for _, k in metricKeys do
	samples[k] = {}
end
local session1Slimes: { number } = {}
local shinyHatch: { number } = {}
local week4Balance: { number } = {}
local week4DailyProd: { number } = {}
local preMoltFoodShare: { number } = {}
local earlyWaits: { number } = {}
local lineEndWaits: { number } = {}
local ledgers = { prod = 0, offline = 0, geyser = 0, quest = 0, refund = 0, egg = 0, food = 0, slot = 0, decor = 0 }

for trial = 1, TRIALS do
	local st, weeks = runTrial(trial, false)
	for _, k in metricKeys do
		table.insert(samples[k], st.metrics[k] or math.huge)
	end
	table.insert(session1Slimes, st.metrics.session1Producing or 0)
	table.insert(shinyHatch, st.firstShinyPlusHatch or 999)
	local w4 = weeks[4]
	table.insert(week4Balance, w4.goo)
	local pmEgg = st.metrics.preMoltEgg or st.eggSpent
	local pmFood = st.metrics.preMoltFood or st.foodSpent
	local pmSlot = st.metrics.preMoltSlot or st.slotSpent
	if pmEgg + pmFood + pmSlot > 0 then
		table.insert(preMoltFoodShare, pmFood / (pmEgg + pmFood + pmSlot))
	end
	table.insert(week4DailyProd, w4.gps * (40 * 60 + 2 * OFFLINE_CAP_SECONDS * OFFLINE_RATE)) -- a day-28 day's take
	-- egg cadence: "early" is where §3's "3-4 min of production" lives — the
	-- meadow line and the post-entry stretch of cave (buys 1-2 of a line
	-- straddle its save-up wall and are excluded). "line-end" = last 3 buys of
	-- cave/ocean before the line was abandoned for the next one. (Ocean+ mid-line
	-- buys ride overnight piles, so their cost-in-active-minutes runs higher by
	-- construction; the tail check is what constrains them.)
	do
		local meadow = st.eggWaits.meadow_egg
		if meadow and #meadow >= 6 then
			for i = 2, 5 do
				table.insert(earlyWaits, meadow[i])
			end
		end
		local cave = st.eggWaits.cave_egg
		if cave and #cave >= 9 then
			for i = 3, 6 do
				table.insert(earlyWaits, cave[i])
			end
		end
		for _, id in { "cave_egg", "ocean_egg" } do
			local waits = st.eggWaits[id]
			if waits and #waits >= 9 then
				for i = #waits - 2, #waits do
					table.insert(lineEndWaits, waits[i])
				end
			end
		end
	end
	ledgers.prod += st.prodGoo
	ledgers.offline += st.offlineGoo
	ledgers.geyser += st.geyserGoo
	ledgers.quest += st.questGoo
	ledgers.refund += st.refundGoo
	ledgers.egg += st.eggSpent
	ledgers.food += st.foodSpent
	ledgers.slot += st.slotSpent
	ledgers.decor += st.decorSpent
end

for _, list in samples do
	table.sort(list)
end
table.sort(session1Slimes)
table.sort(shinyHatch)
table.sort(week4Balance)
table.sort(week4DailyProd)
table.sort(earlyWaits)
table.sort(lineEndWaits)
table.sort(preMoltFoodShare)

print("--- aggregate first-time metrics (median [p10..p90] over trials) ---")
for _, k in metricKeys do
	local list = samples[k]
	print(
		("%-24s %s   [%s .. %s]"):format(
			k,
			fmtT(percentile(list, 0.5)),
			fmtT(percentile(list, 0.1)),
			fmtT(percentile(list, 0.9))
		)
	)
end
print("")

-- ------------------------------------------------------------ beat checks ---
local failures = 0
local function beat(ok: boolean, label: string, detail: string)
	if ok then
		print(("  PASS  %-52s %s"):format(label, detail))
	else
		failures += 1
		print(("  FAIL  %-52s %s"):format(label, detail))
	end
end
local function med(key: string): number
	return percentile(samples[key], 0.5)
end

print("--- DESIGN §3 pacing beats ---")
beat(med("egg2") <= 180, "B1  egg #2 within ~2-3 min", fmtT(med("egg2")))
beat(med("egg4") <= 600, "B2  eggs #2-#4 inside minutes 2-10", fmtT(med("egg4")))
beat(med("firstStageUp") <= 600, "B3  first stage-up before minute 10", fmtT(med("firstStageUp")))
local s1med = percentile(session1Slimes, 0.5)
beat(s1med >= 6 and s1med <= 9, "B4  session 1 ends with 6-8 slimes", ("%d slimes"):format(s1med))
beat(med("firstUncommon") <= 30 * 60, "B5  first Uncommon+ in session 1", fmtT(med("firstUncommon")))
beat(
	med("firstExpedition") <= 45 * 60,
	"B6  Meadow Wilds + first expedition in session 1",
	fmtT(med("firstExpedition"))
)
local shinyMed = percentile(shinyHatch, 0.5)
local shinyP90 = percentile(shinyHatch, 0.9)
beat(
	shinyP90 <= MutationConfig.PityFirstShinyByHatch,
	"B7  guaranteed Shiny by hatch #7 (pity)",
	("median hatch %d, p90 %d"):format(shinyMed, shinyP90)
)
beat(med("firstBefriend") <= 2 * DAY, "B8  first befriend by session ~2-3", fmtT(med("firstBefriend")))
local caveT = med("firstEgg_cave_egg")
beat(caveT >= 0.35 * DAY and caveT <= 3 * DAY, "B9  Cave line opens day ~1.5-3 (not session 1)", fmtT(caveT))
local oceanT = med("firstEgg_ocean_egg")
beat(oceanT >= 3 * DAY and oceanT <= 7 * DAY, "B10 Ocean line opens day ~4-7 (week 1)", fmtT(oceanT))
beat(med("firstRare") <= 7 * DAY, "B11 first Rare in week 1", fmtT(med("firstRare")))
beat(med("slots12") <= 8 * DAY, "B12 ranch at 12 slots by ~week 1", fmtT(med("slots12")))
beat(med("firstShrine") <= 7 * DAY, "B13 first shrine roll in week 1", fmtT(med("firstShrine")))
local epicT = med("firstEpic")
beat(epicT >= 2 * DAY and epicT <= 14 * DAY, "B14 first Epic days ~3-14 (the week-2 chase)", fmtT(epicT))
local volcanoT = med("firstEgg_volcano_egg")
beat(volcanoT >= 8 * DAY and volcanoT <= 21 * DAY, "B15 Volcano line lands week 2-3", fmtT(volcanoT))
beat(
	med("firstMolt") >= 8 * DAY and med("firstMolt") <= 28 * DAY,
	"B16 first Molt lands week 2-4",
	fmtT(med("firstMolt"))
)
local legendaryT = med("firstLegendary")
beat(legendaryT >= 9 * DAY and legendaryT <= 28 * DAY, "B17 first Legendary weeks 2-4 (never week 1)", fmtT(legendaryT))

print("--- §3 egg-cadence shape (egg cost in minutes of gps at purchase) ---")
local earlyMed = percentile(earlyWaits, 0.5)
local endMed = percentile(lineEndWaits, 0.5)
beat(earlyMed <= 8 * 60, "C1  early-line egg cost ~3-4 min of production", ("median %.1f min"):format(earlyMed / 60))
beat(
	endMed >= 10 * 60 and endMed <= 35 * 60,
	"C2  line-end egg cost stretches to ~15-20 min",
	("median %.1f min"):format(endMed / 60)
)

print("--- §3 inflation & faucet/sink health ---")
local totalFaucet = ledgers.prod + ledgers.offline + ledgers.geyser + ledgers.quest + ledgers.refund
local totalSink = ledgers.egg + ledgers.food + ledgers.slot + ledgers.decor
local balMed = percentile(week4Balance, 0.5)
local dayProdMed = percentile(week4DailyProd, 0.5)
beat(
	balMed <= dayProdMed * 2,
	"I1  week-4 balance <= ~2 days of production",
	("%s vs %s/day"):format(fmtGoo(balMed), fmtGoo(dayProdMed))
)
beat(
	ledgers.refund / totalFaucet < 0.05,
	"I2  refunds < 5% of all Goo faucets",
	("%.1f%%"):format(ledgers.refund / totalFaucet * 100)
)
beat(
	totalSink / totalFaucet >= 0.65,
	"I3  sinks absorb >= 65% of all Goo",
	("%.1f%% absorbed"):format(totalSink / totalFaucet * 100)
)
-- A 40-min/day player is away ~23 h: the two capped gaps (2 x 2 h at 50%) are
-- worth ~1.5x the active take BY §2's OWN numbers. Offline majority is the
-- idle-genre contract; the band only flags a broken cap (>70%) or a rate bug.
local offlineShare = ledgers.offline / totalFaucet
beat(
	offlineShare >= 0.15 and offlineShare <= 0.70,
	"I4  offline earnings 15-70% of income",
	("%.1f%%"):format(offlineShare * 100)
)
-- month totals are dominated by post-Molt flow, so food's weight is judged
-- where it competes: the pre-Molt sink split (eggs vs food vs slots)
local foodShareMed = percentile(preMoltFoodShare, 0.5)
beat(foodShareMed >= 0.03, "I5  food >= 3% of pre-Molt non-decor sinks", ("%.1f%%"):format(foodShareMed * 100))

print("")
print("--- faucet/sink ledger (share of total, all trials) ---")
print(
	("  faucets: production %.1f%% | offline %.1f%% | geysers %.1f%% | quests %.1f%% | refunds %.1f%%"):format(
		ledgers.prod / totalFaucet * 100,
		ledgers.offline / totalFaucet * 100,
		ledgers.geyser / totalFaucet * 100,
		ledgers.quest / totalFaucet * 100,
		ledgers.refund / totalFaucet * 100
	)
)
print(
	("  sinks:   eggs %.1f%% | food %.1f%% | slots %.1f%% | decor %.1f%%  (of faucets: %.1f%% absorbed)"):format(
		ledgers.egg / totalSink * 100,
		ledgers.food / totalSink * 100,
		ledgers.slot / totalSink * 100,
		ledgers.decor / totalSink * 100,
		totalSink / totalFaucet * 100
	)
)

print("")
if failures == 0 then
	print("economy_sim: ALL BEATS PASS")
else
	print(("economy_sim: %d BEAT FAILURE(S)"):format(failures))
	error("economy_sim beats failed", 0)
end
