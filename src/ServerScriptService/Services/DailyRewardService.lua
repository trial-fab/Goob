--!strict
-- =============================================================================
-- DailyRewardService — the 7-day streak calendar.
--
-- [Contract] Owns: the escalating 7-day streak calendar (state in
--   Profile.Streak), claim validation, and streak reset rules.
-- [Contract] Never: rewards other than DailyRewardConfig's table; never client
--   clock trust (server day boundaries).
-- [Contract] Binds: DESIGN.md §2 daily streak, §6 reuse map.
-- =============================================================================
--
-- Rules (ClickGame pattern, new table): one claim per UTC day. Claiming on the
-- day after the last claim advances the streak (wrapping 7 -> 1 to keep the
-- calendar escalating forever); any gap resets to day 1. Day 7's exclusive
-- egg hatches through HatchService (server rolls, same as any egg) and the
-- hatch result rides back in the claim response.
--
-- Profile.Streak shape (owned here): { Last = daystamp, Day = 1..7 }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local DailyRewardConfig = require(Shared:WaitForChild("DailyRewardConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local SlimeService = require(script.Parent:WaitForChild("SlimeService"))
local HatchService = require(script.Parent:WaitForChild("HatchService"))
local ProductionService = require(script.Parent:WaitForChild("ProductionService"))

local DailyRewardService = {}

local function dayStamp(): number
	return math.floor(os.time() / 86400)
end

local function onClaimDailyReward(player: Player): { [string]: any }
	local data = DataService.GetData(player)
	if not data then
		return { success = false, message = "Loading..." }
	end
	local streak = data.Streak :: { [string]: any }
	local today = dayStamp()
	local last = streak.Last or 0
	if last >= today then
		return { success = false, message = "Come back tomorrow!" }
	end

	local day: number
	if last == today - 1 then
		day = ((streak.Day or 0) % #DailyRewardConfig.Days) + 1 -- 7 wraps to 1
	else
		day = 1 -- missed a day: streak resets (§2)
	end
	streak.Last = today
	streak.Day = day

	local reward = DailyRewardConfig.Days[day]
	local granted: { [string]: any } = { Day = day }

	if reward.Goo then
		-- Day 1 only: flat Goo (a gps-scaled grant at t=0 broke the §3 beat).
		data.Goo += reward.Goo
		data.Stats.GooEarned += reward.Goo
		granted.Goo = reward.Goo
	end
	if reward.GooMinutes then
		local goo = math.floor(ProductionService.GetGps(player) * 60 * reward.GooMinutes)
		data.Goo += goo
		data.Stats.GooEarned += goo
		granted.Goo = goo
	end
	if reward.Gems then
		data.Gems += reward.Gems
		granted.Gems = reward.Gems
	end
	if reward.Food then
		for foodId, count in reward.Food :: { [string]: number } do
			data.Foods[foodId] = (data.Foods[foodId] or 0) + count
		end
		granted.Food = reward.Food
	end
	player:SetAttribute(Attrs.Goo, data.Goo)
	player:SetAttribute(Attrs.Gems, data.Gems)

	if reward.EggId then
		-- Day 7: the streak-exclusive egg, hatched right here (grant + hatch
		-- force-saves inside HatchGranted). Storage-full players still bank
		-- the streak day; the egg is the one thing that can't fit.
		local hatch = HatchService.HatchGranted(player, reward.EggId)
		granted.Hatch = hatch
		if not hatch then
			granted.HatchBlocked = "storage full"
		end
	end

	DataService.ForceSave(player)
	SlimeService.PushState(player)
	return { success = true, day = day, granted = granted }
end

function DailyRewardService.Init()
	Net.onInvoke(Net.Names.ClaimDailyReward, onClaimDailyReward, {
		budget = 2,
		window = 5,
		validator = Net.T.none,
	})
end

return DailyRewardService
