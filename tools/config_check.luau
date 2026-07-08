--!strict
-- =============================================================================
-- config_check — cross-config economy assertions (session 2). Off-Roblox:
--   ~/.local/bin/luau tools/config_check.luau        (from the project root)
--
-- [Contract] Owns: every economy invariant that spans MORE than one config
--   (per-config invariants fail at require, inside the configs themselves):
--   id cross-references, egg odds vs species, refund caps vs expected egg
--   costs (§3 risk 3), the no-printer margins, and production purity — no
--   nature/ability/decor term can reach ProductionFormula.
-- [Contract] Never: game logic or tuning judgment — this file asserts the
--   contract, tools/economy_sim.luau judges the pacing.
-- [Contract] Binds: DESIGN.md §2 hard rules, §3 inflation risks, §4 fairness.
-- =============================================================================

local SlimeConfig = require("../src/ReplicatedStorage/Shared/SlimeConfig")
local EggConfig = require("../src/ReplicatedStorage/Shared/EggConfig")
local MutationConfig = require("../src/ReplicatedStorage/Shared/MutationConfig")
local NatureConfig = require("../src/ReplicatedStorage/Shared/NatureConfig")
local GrowthConfig = require("../src/ReplicatedStorage/Shared/GrowthConfig")
local FoodConfig = require("../src/ReplicatedStorage/Shared/FoodConfig")
local AbilityConfig = require("../src/ReplicatedStorage/Shared/AbilityConfig")
local ZoneConfig = require("../src/ReplicatedStorage/Shared/ZoneConfig")
local DecorConfig = require("../src/ReplicatedStorage/Shared/DecorConfig")
local RanchConfig = require("../src/ReplicatedStorage/Shared/RanchConfig")
local DailyRewardConfig = require("../src/ReplicatedStorage/Shared/DailyRewardConfig")
local QuestConfig = require("../src/ReplicatedStorage/Shared/QuestConfig")
local ProductionFormula = require("../src/ReplicatedStorage/Shared/ProductionFormula")
local MoltConfig = require("../src/ReplicatedStorage/Shared/MoltConfig")

local failures = 0
local function check(ok: boolean, label: string)
	if ok then
		print(("  PASS  %s"):format(label))
	else
		failures += 1
		print(("  FAIL  %s"):format(label))
	end
end

local function keysOf(t: { [string]: any }): { [string]: boolean }
	local keys = {}
	for k in t do
		keys[k] = true
	end
	return keys
end

local function exactKeys(t: { [string]: any }, allowed: { string }): boolean
	local seen = keysOf(t)
	for _, k in allowed do
		seen[k] = nil
	end
	return next(seen) == nil
end

local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }
local Eggs = EggConfig.Eggs :: { [string]: EggConfig.Egg }
local Zones = ZoneConfig.Zones :: { [string]: ZoneConfig.Zone }
local Foods = FoodConfig.Foods :: { [string]: FoodConfig.Food }
local Natures = NatureConfig.Natures :: { [string]: NatureConfig.Nature }
local Catalog = DecorConfig.Catalog :: { [string]: DecorConfig.Decor }

-- ---------------------------------------------------------------- species --
print("SlimeConfig")
do
	local total, wild = 0, 0
	local tiers: { [string]: number } = {}
	local perLine: { [string]: { hatch: number, wild: number } } = {}
	local accessKeySet: { [string]: boolean } = {}
	for _, k in AbilityConfig.AccessKeys :: { string } do
		accessKeySet[k] = true
	end
	local ok = true
	for id, s in Species do
		total += 1
		tiers[s.Rarity] = (tiers[s.Rarity] or 0) + 1
		local line = perLine[s.Line] or { hatch = 0, wild = 0 }
		perLine[s.Line] = line
		if s.Hatchable then
			line.hatch += 1
			ok = ok and s.RefundGoo > 0 and s.FavoriteFood == nil and s.RefundFood == nil
		else
			line.wild += 1
			-- wild-exclusives refund FOOD, never Goo (§3 risk 3)
			ok = ok and s.RefundGoo == 0 and s.FavoriteFood ~= nil and s.RefundFood ~= nil
			ok = ok and Foods[s.FavoriteFood :: string] ~= nil
		end
		wild += if s.Hatchable then 0 else 1
		ok = ok and s.Base > 0 and s.Id == id
		if s.Ability == "Access" then
			ok = ok and s.AccessKey ~= nil and accessKeySet[s.AccessKey :: string] == true
		else
			ok = ok and s.AccessKey == nil
		end
	end
	check(total >= 18 and total <= 24, ("18-24 species (%d)"):format(total))
	local tierCount = 0
	for _ in tiers do
		tierCount += 1
	end
	check(tierCount == 5, "all 5 rarity tiers present")
	local linesOk = true
	local lineCount = 0
	for _, counts in perLine do
		lineCount += 1
		linesOk = linesOk and counts.hatch >= 1 and counts.wild >= 1
	end
	check(lineCount == 4, "4 lines")
	check(linesOk, "every line has hatchable AND wild-exclusive species (§2)")
	check(wild >= 4, ("wild-exclusive channel is real (%d species)"):format(wild))
	check(ok, "per-species field integrity (ids, refund shape, access keys)")
end

-- ------------------------------------------------------------------- eggs --
print("EggConfig")
do
	local ok, coverOk = true, true
	local covered: { [string]: boolean } = {}
	for id, e in Eggs do
		local sum = 0
		for speciesId, percent in e.Odds do
			local s = Species[speciesId]
			ok = ok and s ~= nil and s.Hatchable and s.Line == e.Line
			sum += percent
			covered[speciesId] = true
		end
		ok = ok and sum == 100 -- re-asserting the load-time invariant on principle
		ok = ok and (e.Purchasable == (e.BaseCost > 0))
	end
	for id, s in Species do
		if s.Hatchable and not covered[id] then
			coverOk = false
			print("    uncovered hatchable species: " .. id)
		end
	end
	check(ok, "odds reference hatchable, line-matching species; sums exactly 100")
	check(coverOk, "every hatchable species drops from at least one egg")
end

-- -------------------------------------------------- refund caps (§3 r3) ---
print("Release refunds vs expected egg costs (§3 risk 3)")
do
	local stageMax = GrowthConfig.Stages[#GrowthConfig.Stages]
	local capOk, printerOk, titanOk = true, true, true
	for id, e in Eggs do
		if not e.Purchasable then
			continue
		end
		local expectedRefund = 0
		local expectedBase = 0
		for speciesId, percent in e.Odds do
			local s = Species[speciesId]
			local p = percent / 100
			-- expected eggs to first copy = 1/p at (conservatively) base price
			local expectedCost = e.BaseCost / p
			if s.RefundGoo >= 0.30 * expectedCost then
				capOk = false
				print(("    %s: refund %d >= 30%% of expected cost %.0f"):format(speciesId, s.RefundGoo, expectedCost))
			end
			expectedRefund += p * s.RefundGoo
			expectedBase += p * s.Base
		end
		-- hatch->release printer: expected Blob refund per egg must stay a token
		if expectedRefund >= 0.15 * e.BaseCost then
			printerOk = false
			print(("    %s: E[blob refund] %.0f >= 15%% of cost %d"):format(id, expectedRefund, e.BaseCost))
		end
		-- feed->release printer: even a Titan release must return less than the
		-- egg alone, with margin (food invested comes on top of this)
		if expectedRefund * stageMax.RefundMult >= 0.70 * e.BaseCost then
			titanOk = false
			print(
				("    %s: E[titan refund] %.0f >= 70%% of cost %d"):format(
					id,
					expectedRefund * stageMax.RefundMult,
					e.BaseCost
				)
			)
		end
	end
	check(capOk, "per-rarity refund < 30% of expected egg cost")
	check(printerOk, "expected Blob refund per egg < 15% of egg cost (no hatch printer)")
	check(titanOk, "expected Titan refund per egg < 70% of egg cost (no feed printer)")
end

-- ---------------------------------------------------------------- growth --
print("GrowthConfig")
do
	local stages = GrowthConfig.Stages
	check(
		#stages == 4 and stages[1].Mult == 1 and stages[2].Mult == 3 and stages[3].Mult == 9 and stages[4].Mult == 27,
		"stage multipliers exactly x1/x3/x9/x27 (§2)"
	)
	local upsOk = true
	local prevRefund = 0
	for i, st in stages do
		upsOk = upsOk and st.RefundMult >= prevRefund and st.RefundMult <= 4
		prevRefund = st.RefundMult
	end
	for i, up in GrowthConfig.StageUps do
		upsOk = upsOk and up.From == i and up.Feeds > 0 and up.FeedCostSecondsOfBase > 0 and up.TimerSeconds > 0
	end
	check(#GrowthConfig.StageUps == 3 and upsOk, "stage-up ladder shape (feeds/costs/timers positive, ordered)")
	local feedOk = true
	for stage, up in GrowthConfig.StageUps do
		for _, base in { 1, 42, 517.5 } do
			feedOk = feedOk and GrowthConfig.FeedCost(base, stage) == math.ceil(base * up.FeedCostSecondsOfBase)
		end
	end
	check(feedOk, "FeedCost = ceil(base x FeedCostSecondsOfBase) at every stage")
end

-- --------------------------------------------------------------- natures --
print("NatureConfig (hard rule: exploration only, §2)")
do
	local count = 0
	local statLevels: { [string]: { [number]: number } } = {}
	local shapeOk = true
	for id, n in Natures do
		count += 1
		shapeOk = shapeOk and exactKeys(n :: any, { "Id", "Name", "Blurb", "Exploration", "Wander" })
		shapeOk = shapeOk and exactKeys(n.Exploration :: any, { "Stat", "Mult" })
		shapeOk = shapeOk
			and exactKeys(n.Wander :: any, { "HopPower", "Pace", "NapBias", "SocialBias", "BlobBias", "PetsForHeart" })
		local m = n.Exploration.Mult
		shapeOk = shapeOk and m >= 0.90 and m <= 1.10 and m ~= 1
		local levels = statLevels[n.Exploration.Stat] or {}
		statLevels[n.Exploration.Stat] = levels
		levels[m] = (levels[m] or 0) + 1
	end
	check(count == 12, ("exactly 12 natures (%d)"):format(count))
	check(shapeOk, "each nature: exact field set, ONE modifier, inside the +-10% band")
	local balanced = true
	for _, stat in { "GatherSpeed", "EncounterLuck", "FollowSpeed" } do
		local levels = statLevels[stat]
		balanced = balanced
			and levels ~= nil
			and levels[1.10] == 1
			and levels[1.05] == 1
			and levels[0.95] == 1
			and levels[0.90] == 1
	end
	check(balanced, "modifiers balanced per stat (+10/+5/-5/-10 each)")
end

-- ------------------------------------------------- production purity (§2) --
print("Production purity (species x stage x mutation x Molt ONLY)")
do
	check(
		exactKeys(ProductionFormula :: any, { "Gps", "MoltMult" }),
		"ProductionFormula exposes Gps + MoltMult and nothing else"
	)
	local base = ProductionFormula.Gps({ Base = 7, StageMult = 9, MutationMult = 5, Molts = 2 })
	check(base == 7 * 9 * 5 * 3, "Gps = base x stage x mutation x (1 + molts)")
	check(
		ProductionFormula.Gps({ Base = 7, StageMult = 9, MutationMult = 5, Molts = 2 }) == base,
		"Gps is pure (same args, same result)"
	)
	-- no production-shaped field hides in the exploration/cosmetic configs
	local clean = true
	local function scan(label: string, t: any)
		for k, v in t :: { [string]: any } do
			if type(v) == "table" then
				scan(label .. "." .. tostring(k), v)
			elseif type(k) == "string" and (k:find("Goo") or k:find("Prod") or k:find("Gps")) then
				-- DecorConfig.CostGoo is a SINK (player pays Goo), the one sanctioned Goo field
				if not (k == "CostGoo") then
					clean = false
					print(("    production-shaped field: %s.%s"):format(label, k))
				end
			end
		end
	end
	scan("NatureConfig", NatureConfig.Natures)
	scan("AbilityConfig", AbilityConfig.Families)
	scan("DecorConfig", DecorConfig.Catalog)
	check(clean, "no Goo/production field in Nature/Ability/Decor configs")
end

-- ----------------------------------------------------------- zones/foods --
print("ZoneConfig / FoodConfig")
do
	local ok = true
	local prevOwned = 0
	local ordered: { ZoneConfig.Zone } = {}
	for _, z in Zones do
		ordered[z.Order] = z
	end
	for order = 1, 4 do
		local z = ordered[order]
		ok = ok and z ~= nil
		if z == nil then
			continue
		end
		ok = ok and Foods[z.FoodId] ~= nil and Foods[z.FoodId].SourceZone == z.Id
		ok = ok and z.Unlock.SlimesOwned >= prevOwned
		prevOwned = z.Unlock.SlimesOwned
		ok = ok and (order == 1) == (z.Unlock.AccessKey == nil) -- zone 1 free, 2+ keyed
		for speciesId, _ in z.WildSpawns do
			local s = Species[speciesId]
			ok = ok and s ~= nil and not s.Hatchable and s.Line ~= nil
		end
		for _, node in z.Nodes do
			if node.Kind == "Food" then
				ok = ok and node.FoodId ~= nil and Foods[node.FoodId :: string] ~= nil
			else
				ok = ok and node.YieldGpsSeconds ~= nil and (node.YieldGpsSeconds :: number) > 0
			end
		end
	end
	-- every access key is carried by at least one HATCHABLE species (a zone
	-- whose key only wild slimes carry would deadlock progression)
	for _, key in AbilityConfig.AccessKeys :: { string } do
		local carried = false
		for _, s in Species do
			if s.Hatchable and s.AccessKey == key then
				carried = true
			end
		end
		ok = ok and carried
	end
	check(ok, "zone ladder ordered; keys hatchable; foods/spawns/nodes cross-reference")
end

-- ------------------------------------------------------------- decor etc --
print("DecorConfig / RanchConfig / rewards")
do
	local ok = true
	for id, d in Catalog do
		local goo, gems = d.CostGoo, d.CostGems
		ok = ok and ((goo ~= nil) ~= (gems ~= nil)) -- exactly one price
		ok = ok and d.PartBudget <= 20 -- §8 W7 build contract
		ok = ok and d.Footprint.W >= 1 and d.Footprint.D >= 1
	end
	check(ok, "decor: one price each, part budget <= 20, sane footprints")

	local slotsOk = true
	local prev = 0
	for slot = RanchConfig.SlotsBase + 1, RanchConfig.SlotsMax do
		local cost = (RanchConfig.SlotCosts :: { [number]: number })[slot]
		slotsOk = slotsOk and cost ~= nil and cost > prev
		prev = cost or prev
	end
	check(slotsOk, "ranch slots 9..16 all priced, strictly increasing")

	local rewardOk = #DailyRewardConfig.Days == 7
	for _, r in DailyRewardConfig.Days do
		if r.Food then
			for foodId in r.Food :: { [string]: number } do
				rewardOk = rewardOk and Foods[foodId] ~= nil
			end
		end
		if r.EggId then
			rewardOk = rewardOk and Eggs[r.EggId :: string] ~= nil and not Eggs[r.EggId :: string].Purchasable
		end
	end
	for _, q in QuestConfig.DailyPool do
		if q.Reward.Food then
			for foodId in q.Reward.Food :: { [string]: number } do
				rewardOk = rewardOk and Foods[foodId] ~= nil
			end
		end
	end
	check(rewardOk, "streak calendar (7 days) + quest rewards reference real ids")
end

-- ------------------------------------------------------------------- molt --
print("MoltConfig")
do
	-- The sim's week-2-4 "first Molt" verdicts assume exactly these numbers
	-- (docs/economy.md): a drifted requirement silently re-tunes the month.
	check(MoltConfig.LifetimeGooBase == 500000000, "Molt requirement base is the tuned 500M")
	check(MoltConfig.RequirementGrowth > 1, "Molt requirement grows per Molt (no instant re-molts)")
	check(
		MoltConfig.Requirement(1) == MoltConfig.LifetimeGooBase * MoltConfig.RequirementGrowth,
		"Requirement(n) follows base * growth^n"
	)
	-- The multiplier itself must stay ProductionFormula's linear ladder (§3
	-- risk 1: 2^molts was rejected); MoltConfig must never grow its own copy.
	check(ProductionFormula.MoltMult(3) == 4, "MoltMult stays linear (1 + molts)")
	check((MoltConfig :: any).Mult == nil and (MoltConfig :: any).MoltMult == nil, "MoltConfig carries no multiplier")
end

print("")
if failures == 0 then
	print("config_check: ALL CHECKS PASSED")
else
	print(("config_check: %d FAILURE(S)"):format(failures))
end
if failures > 0 then
	error("config_check failed", 0)
end
