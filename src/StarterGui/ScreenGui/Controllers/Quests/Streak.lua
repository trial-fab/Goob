--!strict
-- =============================================================================
-- Quests/Streak — the 7-day streak calendar modal.
-- [Contract] Owns: rendering the DailyRewardConfig calendar (DayCell clones,
--   current day highlighted via state), auto-showing on join when a claim is
--   available, and the ClaimDailyReward round trip (incl. the day-7 hatch
--   payload handoff to the reveal overlay pattern).
-- [Contract] Never: constructs GuiObjects (clones DayCell); never decides
--   claimability locally beyond DISPLAY (the server validates the claim).
-- =============================================================================
--
-- Studio hand-off: ScreenGui.StreakModal (Frame, hidden) with:
--   Days        Frame
--     DayCell   Frame template (Visible = false): DayLabel, RewardLabel
--   ClaimButton TextButton
--   ResultLabel TextLabel
--   Close       button (GuiNames.Close)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GuiNames = require(Shared:WaitForChild("GuiNames"))
local DailyRewardConfig = require(Shared:WaitForChild("DailyRewardConfig"))

local Streak = {}

local ctxRef: { [string]: any } = {}
local claiming = false
local autoShown = false

local function rewardText(reward: DailyRewardConfig.Reward): string
	if reward.Goo then
		return reward.Goo .. " Goo"
	end
	if reward.GooMinutes then
		return reward.GooMinutes .. " min of Goo"
	end
	if reward.Gems then
		return reward.Gems .. " Gems"
	end
	if reward.EggId then
		return "Exclusive Egg!"
	end
	if reward.Food then
		local parts = {}
		for foodId, count in reward.Food :: { [string]: number } do
			table.insert(parts, ("%d %s"):format(count, foodId))
		end
		return table.concat(parts, ", ")
	end
	return "?"
end

local function modal(): Frame?
	local gui = ctxRef.gui :: ScreenGui
	local found = gui:FindFirstChild(GuiNames.StreakModal)
	return if found and found:IsA("Frame") then found else nil
end

local function render()
	local frame = modal()
	if not frame then
		return
	end
	local days = frame:FindFirstChild("Days")
	local template = if days then days:FindFirstChild("DayCell") else nil
	if not (days and template and template:IsA("Frame")) then
		return
	end
	for _, child in days:GetChildren() do
		if child ~= template and child.Name:sub(1, 8) == "DayCell_" then
			child:Destroy()
		end
	end
	local streak = (ctxRef.state.Get().Streak or {}) :: { [string]: any }
	local today = math.floor(os.time() / 86400)
	local claimable = (streak.Last or 0) < today
	-- The day THIS claim would grant (streak advance or reset — mirror of the
	-- server rule, display only).
	local nextDay = if (streak.Last or 0) == today - 1 then ((streak.Day or 0) % 7) + 1 else 1
	local highlight = if claimable then nextDay else (streak.Day or 0)

	for day, reward in DailyRewardConfig.Days :: { DailyRewardConfig.Reward } do
		local cell = template:Clone()
		cell.Name = "DayCell_" .. day
		cell.LayoutOrder = day
		cell.Visible = true
		local dayLabel = cell:FindFirstChild("DayLabel")
		if dayLabel and dayLabel:IsA("TextLabel") then
			dayLabel.Text = if day == highlight then "» Day " .. day else "Day " .. day
		end
		local rewardLabel = cell:FindFirstChild("RewardLabel")
		if rewardLabel and rewardLabel:IsA("TextLabel") then
			rewardLabel.Text = rewardText(reward)
		end
		cell.Parent = days
	end

	local claim = frame:FindFirstChild("ClaimButton")
	if claim and claim:IsA("GuiButton") then
		claim.Visible = claimable
	end
end

local function wire(frame: Frame, slot: { [string]: any })
	local claim = frame:FindFirstChild("ClaimButton")
	if claim and claim:IsA("GuiButton") and not claim:GetAttribute("StreakWired") then
		claim:SetAttribute("StreakWired", true)
		claim.Activated:Connect(function()
			if claiming then
				return
			end
			claiming = true
			local result = Net.invoke(Net.Names.ClaimDailyReward)
			claiming = false
			local live = modal()
			if not live or typeof(result) ~= "table" then
				return
			end
			local resultLabel = live:FindFirstChild("ResultLabel")
			if resultLabel and resultLabel:IsA("TextLabel") then
				if result.success then
					local granted = (result.granted or {}) :: { [string]: any }
					resultLabel.Text = ("Day %d claimed!%s"):format(
						result.day or 0,
						if granted.Hatch then " Your streak egg hatched!" else ""
					)
				else
					resultLabel.Text = result.message or "Come back tomorrow!"
				end
			end
			render()
		end)
	end
	local close = frame:FindFirstChild(GuiNames.Close, true)
	if close and close:IsA("GuiButton") and not close:GetAttribute("StreakWired") then
		close:SetAttribute("StreakWired", true)
		close.Activated:Connect(function()
			frame.Visible = false
			slot.close()
		end)
	end
end

function Streak.Init(ctx: { [string]: any })
	ctxRef = ctx
	local gui = ctx.gui :: ScreenGui

	local slot
	slot = ctx.modals.register("Streak", function()
		local frame = modal()
		if frame then
			frame.Visible = false
		end
	end, function()
		local frame = modal()
		if frame then
			wire(frame, slot)
			render()
			frame.Visible = true
		end
	end)

	-- Auto-open once per session when a claim is waiting (§7.14 "on join when
	-- claimable") — as soon as both the state and the template exist.
	ctx.state.OnChanged(function(state)
		if autoShown then
			return
		end
		local streak = (state.Streak or {}) :: { [string]: any }
		local today = math.floor(os.time() / 86400)
		if (streak.Last or 0) < today and modal() ~= nil then
			autoShown = true
			ctx.modals.request("Streak")
		end
	end)
	local _ = gui -- template arrival is handled lazily via modal()
end

return Streak
