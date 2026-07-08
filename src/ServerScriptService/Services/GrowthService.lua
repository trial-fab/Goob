--!strict
-- =============================================================================
-- GrowthService — feeding, stage timers, stage-up mutation re-rolls.
--
-- [Contract] Owns: feeding (FeedSlime — food costs from GrowthConfig, server-
--   debited), stage-up timers (Blob->Slime->Jumbo->Titan), and the stage-up
--   mutation re-roll (the comeback hook).
-- [Contract] Never: stage multipliers other than GrowthConfig's ×1/×3/×9/×27
--   chain applied via Shared/ProductionFormula; never skips a stage's food cost
--   (Instant-Grow skips the TIMER only, §4).
-- [Contract] Binds: DESIGN.md §2 life stages, §5 (Feed <=5/s).
-- =============================================================================
--
-- A stage-up needs BOTH: Fed >= StageUps[stage].Feeds AND real time in the
-- current stage >= TimerSeconds (offline counts — record.StT is the anchor;
-- the timers are the inflation backbone, docs/economy.md finding 1). The
-- check runs lazily: at every feed, on profile load (offline elapse), and on
-- one slow sweep for fed-complete slimes whose timer matures mid-session —
-- ONE loop for all players, never per slime.
--
-- Stage-up mutation rolls only ever UPGRADE (keep the better of current vs
-- rolled — a re-roll can never strip a Void; MutationConfig contract).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local SlimeConfig = require(Shared:WaitForChild("SlimeConfig"))
local GrowthConfig = require(Shared:WaitForChild("GrowthConfig"))
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))
local FoodConfig = require(Shared:WaitForChild("FoodConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local SlimeService = require(script.Parent:WaitForChild("SlimeService"))
local HatchService = require(script.Parent:WaitForChild("HatchService"))
local QuestService = require(script.Parent:WaitForChild("QuestService"))

local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }
local Mutations = MutationConfig.Mutations :: { [string]: MutationConfig.Mutation }
local Foods = FoodConfig.Foods :: { [string]: FoodConfig.Food }

local SWEEP_SECONDS = 30
local MAX_STAGE = #GrowthConfig.Stages

local GrowthService = {}

-- Attempt the stage-up; returns a result table when it happened. Rolls the
-- keep-better mutation, refreshes model/state, and force-saves (a stage-up is
-- a permanent multiplier + a mutation roll — crash-loss would be felt).
local function tryStageUp(player: Player, data: DataService.ProfileData, slimeId: string): { [string]: any }?
	local record = data.Slimes[slimeId] :: SlimeService.SlimeRecord?
	if not record or record.St >= MAX_STAGE then
		return nil
	end
	local up = GrowthConfig.StageUps[record.St]
	if record.Fed < up.Feeds or os.time() - record.StT < up.TimerSeconds then
		return nil
	end

	record.St += 1
	record.Fed = 0
	record.StT = os.time()

	local rolled = HatchService.RollMutation(MutationConfig.Rolls.StageUp, 1)
	local upgraded = false
	if Mutations[rolled].Tier > Mutations[record.Mu].Tier then
		record.Mu = rolled
		upgraded = true
		SlimeService.Discover(data, record.Sp, rolled)
	end

	SlimeService.RefreshModel(player, slimeId)
	QuestService.Progress(player, "StageUp", 1)
	DataService.ForceSave(player)
	SlimeService.PushState(player)

	return {
		Stage = record.St,
		StageName = GrowthConfig.Stages[record.St].Name,
		Mutation = record.Mu,
		MutationUpgraded = upgraded,
	}
end

local function onFeedSlime(player: Player, slimeId: string, foodId: string?): { [string]: any }
	local data = DataService.GetData(player)
	local record = if data then data.Slimes[slimeId] :: SlimeService.SlimeRecord? else nil
	if not (data and record) then
		return { success = false, message = "Unknown slime." }
	end
	if record.St >= MAX_STAGE then
		return { success = false, message = "Titans are fully grown." }
	end
	if SlimeService.IsBusy(slimeId) then
		return { success = false, message = "That slime is busy." }
	end

	local up = GrowthConfig.StageUps[record.St]
	local species = Species[record.Sp]
	local gooCost = 0

	if foodId ~= nil then
		-- Premium feed: a gathered item substitutes FeedValue basic feeds and
		-- costs no Goo (§2 special foods; FoodConfig contract).
		local food = Foods[foodId]
		if not food then
			return { success = false, message = "Unknown food." }
		end
		if (data.Foods[foodId] or 0) < 1 then
			return { success = false, message = "You don't have any " .. food.Name .. "." }
		end
		data.Foods[foodId] -= 1
		record.Fed = math.min(record.Fed + food.FeedValue, up.Feeds)
	else
		-- Basic feed: Goo at THE one price function (GrowthConfig.FeedCost —
		-- the prompt displays it, the sim spends it, this charges it).
		gooCost = GrowthConfig.FeedCost(species.Base, record.St)
		if data.Goo < gooCost then
			return { success = false, message = "Not enough Goo." }
		end
		data.Goo -= gooCost
		player:SetAttribute(Attrs.Goo, data.Goo)
		record.Fed = math.min(record.Fed + 1, up.Feeds)
	end

	QuestService.Progress(player, "Feed", 1)
	local stageUp = tryStageUp(player, data, slimeId) -- pushes state when it fires
	if not stageUp then
		SlimeService.PushState(player)
	end

	local remainingTimer = math.max(0, up.TimerSeconds - (os.time() - record.StT))
	return {
		success = true,
		cost = gooCost,
		goo = data.Goo,
		fed = record.Fed,
		feedsNeeded = up.Feeds,
		timerRemaining = if stageUp then 0 else remainingTimer,
		stageUp = stageUp,
	}
end

function GrowthService.Init()
	-- Offline timers: stage-ups whose clock matured while away land on load.
	DataService.OnProfileLoaded(function(player, data)
		for slimeId in data.Slimes do
			tryStageUp(player, data, slimeId)
		end
	end)

	-- Mid-session maturation sweep: fed-complete slimes whose timer expires
	-- without another feed. One loop for the whole server.
	task.spawn(function()
		while true do
			task.wait(SWEEP_SECONDS)
			for _, player in Players:GetPlayers() do
				local data = DataService.GetData(player)
				if data then
					for slimeId, record in data.Slimes do
						local r = record :: SlimeService.SlimeRecord
						if r.St < MAX_STAGE and r.Fed >= GrowthConfig.StageUps[r.St].Feeds then
							tryStageUp(player, data, slimeId)
						end
					end
				end
			end
		end
	end)

	Net.onInvoke(Net.Names.FeedSlime, onFeedSlime, {
		budget = 5, -- §5 anti-exploit posture: Feed <=5/s
		window = 1,
		validator = Net.T.args(Net.T.guid, Net.T.optional(Net.T.string(40))),
	})
end

return GrowthService
