--!strict
-- =============================================================================
-- HatchService — egg purchase + the server-side rolls.
--
-- [Contract] Owns: egg purchase (BuyEgg RemoteFunction) — Goo/Gem debit, the
--   server-side species/mutation/nature rolls, the first-session pity roll
--   (guaranteed Shiny by hatch #7), the luck-modifier stack (pass/boost/event),
--   Triple Hatch, and handing the new slime to SlimeService.
-- [Contract] Never: client-side rolls of any kind; never odds that diverge from
--   EggConfig (the SINGLE source both the server rolls from and the odds popup
--   renders — the disclosed odds ARE the real odds, §4 fairness).
-- [Contract] Binds: DESIGN.md §2 hatch flow, §4 fairness commitments, §5
--   Anti-exploit posture (BuyEgg <=3/s).
-- =============================================================================
--
-- Pricing: EggConfig.Cost(id, EggCounts[id]) — the per-line LIFETIME ladder
-- (survives Molt; docs/economy.md session-3 wiring notes). Rolls walk the
-- disclosed tables in sorted-key order so the mapping from RNG to outcome is
-- reproducible in audits (mutation-rate-vs-disclosed-odds assertion, §5).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))
local NatureConfig = require(Shared:WaitForChild("NatureConfig"))
local RanchConfig = require(Shared:WaitForChild("RanchConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local SlimeService = require(script.Parent:WaitForChild("SlimeService"))
local QuestService = require(script.Parent:WaitForChild("QuestService"))

local Eggs = EggConfig.Eggs :: { [string]: EggConfig.Egg }
local Mutations = MutationConfig.Mutations :: { [string]: MutationConfig.Mutation }

local HatchService = {}

local rng = Random.new()

-- Sorted key lists so weighted walks are order-stable (pairs order is not).
local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local natureIds = sortedKeys(NatureConfig.Natures :: { [string]: any })

-- ---------------------------------------------------------------------------
-- Rolls. All server-side, straight off the disclosed config tables.
-- ---------------------------------------------------------------------------

local function rollSpecies(egg: EggConfig.Egg): string
	local r = rng:NextNumber() * 100
	local acc = 0
	local keys = sortedKeys(egg.Odds)
	for _, speciesId in keys do
		acc += egg.Odds[speciesId]
		if r < acc then
			return speciesId
		end
	end
	return keys[#keys] -- float-edge fallback (r == 100 - epsilon accumulation)
end

-- Weighted walk over a per-10,000 mutation table. `luckMult` scales every
-- non-"none" weight (the §4 luck stack: Lucky pass / server boosts — session 4
-- installs real providers; the DISCLOSED odds must be scaled the same way in
-- the odds popup whenever this is ≠ 1).
function HatchService.RollMutation(rolls: { [string]: number }, luckMult: number): string
	local weights: { [string]: number } = {}
	local total = 0
	for mutationId, weight in rolls do
		local w = if mutationId == "none" then weight else weight * luckMult
		weights[mutationId] = w
		total += w
	end
	local r = rng:NextNumber() * total
	local acc = 0
	local keys = sortedKeys(weights)
	for _, mutationId in keys do
		acc += weights[mutationId]
		if r < acc then
			return mutationId
		end
	end
	return "none"
end

function HatchService.RollNature(): string
	-- Uniform 1/12, exactly as every odds popup discloses (§2).
	return natureIds[rng:NextInteger(1, #natureIds)]
end

-- The luck stack (§4): pass × personal boost × server boost. All 1 until
-- MonetizationService/BoostService land (session 4 carryover).
local function luckMult(_player: Player): number
	return 1
end

-- ---------------------------------------------------------------------------
-- The hatch itself (shared by BuyEgg and granted eggs like the streak day-7).
-- ---------------------------------------------------------------------------

type HatchResult = { [string]: any }

local function hatchOne(player: Player, data: DataService.ProfileData, egg: EggConfig.Egg): HatchResult
	local speciesId = rollSpecies(egg)
	local mutation = HatchService.RollMutation(MutationConfig.Rolls.Hatch, luckMult(player))

	-- First-session pity (§3): while no hatch has ever rolled a mutation,
	-- hatch #PityFirstShinyByHatch is Shiny at minimum.
	if
		mutation == "none"
		and data.Stats.HatchMutations == 0
		and data.Stats.Hatches + 1 >= MutationConfig.PityFirstShinyByHatch
	then
		mutation = "shiny"
	end
	if Mutations[mutation].Tier > 0 then
		data.Stats.HatchMutations += 1
	end

	local nature = HatchService.RollNature()
	local slimeId, toStorage = SlimeService.Mint(player, data, speciesId, mutation, nature, "egg")
	data.Stats.Hatches += 1
	QuestService.Progress(player, "Hatch", 1)

	return {
		SlimeId = slimeId,
		SpeciesId = speciesId,
		Mutation = mutation,
		Nature = nature,
		ToStorage = toStorage,
	}
end

-- Grant-and-hatch for non-purchasable eggs (streak day 7). Charges nothing;
-- the caller owns the entitlement check. Returns the same shape as BuyEgg.
function HatchService.HatchGranted(player: Player, eggId: string): HatchResult?
	local data = DataService.GetData(player)
	local egg = Eggs[eggId]
	if not (data and egg) then
		return nil
	end
	if SlimeService.CountOwned(data) >= RanchConfig.StorageCap then
		return nil
	end
	local result = hatchOne(player, data, egg)
	DataService.ForceSave(player)
	SlimeService.PushState(player)
	return result
end

-- ---------------------------------------------------------------------------

local function onBuyEgg(player: Player, eggId: string): { [string]: any }
	local data = DataService.GetData(player)
	if not data then
		return { success = false, message = "Loading..." }
	end
	local egg = Eggs[eggId]
	if not egg then
		return { success = false, message = "Unknown egg." }
	end

	-- The free starter egg is BuyEgg's one non-purchasable path: exactly once,
	-- as the very first hatch (§3 minute-1 onboarding beat).
	if not egg.Purchasable and not (eggId == "starter_egg" and data.Stats.Hatches == 0) then
		return { success = false, message = "That egg can't be bought." }
	end

	if SlimeService.CountOwned(data) >= RanchConfig.StorageCap then
		-- Overflow blocks hatching until release/trade (§2 inventory).
		return { success = false, message = "Slime storage is full — release or trade first." }
	end

	local bought = data.EggCounts[eggId] or 0
	local cost = EggConfig.Cost(eggId, bought)
	if data.Goo < cost then
		return { success = false, message = "Not enough Goo." }
	end

	data.Goo -= cost
	data.EggCounts[eggId] = bought + 1
	player:SetAttribute(Attrs.Goo, data.Goo)

	local result = hatchOne(player, data, egg)

	-- Economy-critical: the roll outcome must survive a crash (§5 force-save
	-- list). PushState after, so the client renders the post-hatch truth.
	DataService.ForceSave(player)
	SlimeService.PushState(player)

	return { success = true, cost = cost, goo = data.Goo, slime = result }
end

function HatchService.Init()
	Net.onInvoke(Net.Names.BuyEgg, onBuyEgg, {
		budget = 3, -- §5 anti-exploit posture: BuyEgg <=3/s
		window = 1,
		validator = Net.T.args(Net.T.string(40)),
	})
end

return HatchService
