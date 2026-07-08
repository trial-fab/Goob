--!strict
-- =============================================================================
-- QuestService — daily quests, progress hooks, playtime ladder.
--
-- [Contract] Owns: daily quest assignment (3/day from QuestConfig), progress
--   tracking hooks other services call, and claim validation (ClaimQuest).
--   Also the session playtime ladder and Stats.PlayTimeMin (the trade gate's
--   clock).
-- [Contract] Never: client-reported progress; rewards are server-derived from
--   QuestConfig.
-- [Contract] Binds: DESIGN.md §2 retention mechanics.
-- =============================================================================
--
-- GooMinutes rewards are multiplied by the claimer's gps AT CLAIM TIME
-- (docs/economy.md session-3 wiring notes) — a day-1 player and a week-3
-- player both feel the claim. Day boundaries are UTC daystamps; the weekly
-- chest window is the UTC week of the daystamp.
--
-- Profile.Quests shape (owned here):
--   { Day = daystamp, Active = { { Id, P = progress, C = claimed } },
--     WeekStart = weekstamp, WeeklyCount = dailies completed this week }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local QuestConfig = require(Shared:WaitForChild("QuestConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local ProductionService = require(script.Parent:WaitForChild("ProductionService"))

local QuestService = {}

local rng = Random.new()
-- Session minutes + claimed playtime rungs, in-memory (per session by design).
local sessionMinutes: { [Player]: number } = {}

local questById: { [string]: QuestConfig.Quest } = {}
for _, quest in QuestConfig.DailyPool :: { QuestConfig.Quest } do
	questById[quest.Id] = quest
end

local function dayStamp(): number
	return math.floor(os.time() / 86400)
end

-- Deal today's quests if the stored day is stale. Distinct picks from the pool.
local function ensureDaily(data: DataService.ProfileData)
	local quests = data.Quests :: { [string]: any }
	local today = dayStamp()
	if quests.Day ~= today then
		local pool = table.clone(QuestConfig.DailyPool :: { QuestConfig.Quest })
		local active = {}
		for _ = 1, math.min(QuestConfig.DailyCount, #pool) do
			local pick = table.remove(pool, rng:NextInteger(1, #pool)) :: QuestConfig.Quest
			table.insert(active, { Id = pick.Id, P = 0, C = false })
		end
		quests.Day = today
		quests.Active = active
	end
	local week = math.floor(today / 7)
	if quests.WeekStart ~= week then
		quests.WeekStart = week
		quests.WeeklyCount = 0
	end
end

local function pushQuests(player: Player, data: DataService.ProfileData)
	Net.fireClient(Net.Names.QuestProgress, player, { Quests = data.Quests })
end

-- Grant one QuestConfig.Reward. GooMinutes scale by gps at claim (the whole
-- point of the goo-minutes scheme); Gems/Food are flat by design.
local function grantReward(player: Player, data: DataService.ProfileData, reward: QuestConfig.Reward): { [string]: any }
	local granted: { [string]: any } = {}
	if reward.GooMinutes then
		local goo = math.floor(ProductionService.GetGps(player) * 60 * reward.GooMinutes)
		data.Goo += goo
		data.Stats.GooEarned += goo
		player:SetAttribute(Attrs.Goo, data.Goo)
		granted.Goo = goo
	end
	if reward.Gems then
		data.Gems += reward.Gems
		player:SetAttribute(Attrs.Gems, data.Gems)
		granted.Gems = reward.Gems
	end
	if reward.Food then
		for foodId, count in reward.Food :: { [string]: number } do
			data.Foods[foodId] = (data.Foods[foodId] or 0) + count
		end
		granted.Food = reward.Food
	end
	return granted
end

-- The hook every service calls (Hatch/Feed/CollectBlobs/Befriend/Gather/
-- StageUp/Shrine). Progress is always server-observed, never client-claimed.
function QuestService.Progress(player: Player, goal: string, amount: number)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	ensureDaily(data)
	local changed = false
	for _, entry in data.Quests.Active :: { any } do
		local quest = questById[entry.Id]
		if quest and quest.Goal == goal and not entry.C and entry.P < quest.Count then
			entry.P = math.min(entry.P + amount, quest.Count)
			changed = true
		end
	end
	if changed then
		pushQuests(player, data)
	end
end

local function onClaimQuest(player: Player, questId: string): { [string]: any }
	local data = DataService.GetData(player)
	if not data then
		return { success = false, message = "Loading..." }
	end
	ensureDaily(data)
	for _, entry in data.Quests.Active :: { any } do
		if entry.Id == questId then
			local quest = questById[questId]
			if not quest then
				return { success = false, message = "Unknown quest." }
			end
			if entry.C then
				return { success = false, message = "Already claimed." }
			end
			if entry.P < quest.Count then
				return { success = false, message = "Not done yet." }
			end
			entry.C = true
			local granted = grantReward(player, data, quest.Reward)

			-- Weekly chest (§3 free-Gems drip): dailies completed this week.
			data.Quests.WeeklyCount = (data.Quests.WeeklyCount or 0) + 1
			local chest = nil
			if data.Quests.WeeklyCount == QuestConfig.WeeklyChest.DailiesRequired then
				data.Gems += QuestConfig.WeeklyChest.Gems
				player:SetAttribute(Attrs.Gems, data.Gems)
				chest = QuestConfig.WeeklyChest.Gems
			end

			DataService.ForceSave(player)
			pushQuests(player, data)
			return { success = true, granted = granted, weeklyChestGems = chest }
		end
	end
	return { success = false, message = "That quest isn't active." }
end

function QuestService.Init()
	DataService.OnProfileLoaded(function(player, data)
		ensureDaily(data)
		sessionMinutes[player] = 0
		pushQuests(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessionMinutes[player] = nil
	end)

	-- One minute-loop for the whole server: lifetime playtime (the §2 trade
	-- gate's clock) + the session playtime ladder (auto-granted small claims;
	-- the QuestProgress push doubles as the toast signal).
	task.spawn(function()
		while true do
			task.wait(60)
			for player, minutes in sessionMinutes do
				local data = DataService.GetData(player)
				if data then
					sessionMinutes[player] = minutes + 1
					data.Stats.PlayTimeMin += 1
					for _, rung in QuestConfig.PlaytimeLadder :: { any } do
						if rung.Minutes == sessionMinutes[player] then
							local granted = grantReward(player, data, rung.Reward)
							Net.fireClient(Net.Names.QuestProgress, player, {
								Playtime = { Minutes = rung.Minutes, Granted = granted },
							})
						end
					end
				end
			end
		end
	end)

	Net.onInvoke(Net.Names.ClaimQuest, onClaimQuest, {
		budget = 3,
		window = 1,
		validator = Net.T.args(Net.T.string(40)),
	})
end

return QuestService
