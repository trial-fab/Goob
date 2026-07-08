--!strict
-- =============================================================================
-- Quests/Tracker — daily quest rows + claims (tracker and modal share rows).
-- [Contract] Owns: rendering the active dailies (QuestProgress pushes +
--   ClientState) as QuestRow clones in both the edge tracker and the Quests
--   modal, and the ClaimQuest round trip.
-- [Contract] Never: constructs GuiObjects (clones QuestRow); never tracks
--   progress locally (the server's numbers are the display).
-- =============================================================================
--
-- Studio hand-off: ScreenGui.QuestTracker (Frame; the collapsible edge strip)
-- and ScreenGui.QuestsModal (Frame, hidden), EACH with:
--   Rows        Frame
--     QuestRow  Frame template (Visible = false): TextLabel_, ProgressLabel,
--               ClaimButton
--   QuestsModal additionally: Close button (GuiNames.Close).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GuiNames = require(Shared:WaitForChild("GuiNames"))
local QuestConfig = require(Shared:WaitForChild("QuestConfig"))

local TRACKER_NAME = "QuestTracker" -- single-controller lookups

local Tracker = {}

local questById: { [string]: QuestConfig.Quest } = {}
for _, quest in QuestConfig.DailyPool :: { QuestConfig.Quest } do
	questById[quest.Id] = quest
end

local ctxRef: { [string]: any } = {}
local latestQuests: { [string]: any } = {}
local claiming = false
local warned = false

local function renderInto(container: Instance)
	local rows = container:FindFirstChild("Rows")
	local template = if rows then rows:FindFirstChild("QuestRow") else nil
	if not (rows and template and template:IsA("Frame")) then
		return false
	end
	for _, child in rows:GetChildren() do
		if child ~= template and child.Name:sub(1, 9) == "QuestRow_" then
			child:Destroy()
		end
	end
	for order, entry in (latestQuests.Active or {}) :: { any } do
		local quest = questById[entry.Id]
		if quest then
			local row = template:Clone()
			row.Name = "QuestRow_" .. entry.Id
			row.LayoutOrder = order
			row.Visible = true
			local text = row:FindFirstChild("TextLabel_")
			if text and text:IsA("TextLabel") then
				text.Text = quest.Text:format(quest.Count)
			end
			local progress = row:FindFirstChild("ProgressLabel")
			if progress and progress:IsA("TextLabel") then
				progress.Text = if entry.C then "Claimed" else ("%d/%d"):format(entry.P, quest.Count)
			end
			local claim = row:FindFirstChild("ClaimButton")
			if claim and claim:IsA("GuiButton") then
				claim.Visible = not entry.C and entry.P >= quest.Count
				claim.Activated:Connect(function()
					if claiming then
						return
					end
					claiming = true
					Net.invoke(Net.Names.ClaimQuest, entry.Id)
					claiming = false
					-- The claim's QuestProgress push re-renders everything.
				end)
			end
			row.Parent = rows
		end
	end
	return true
end

local function renderAll()
	local gui = ctxRef.gui :: ScreenGui
	local any = false
	for _, name in { TRACKER_NAME, GuiNames.QuestsModal } do
		local container = gui:FindFirstChild(name)
		if container then
			any = renderInto(container) or any
		end
	end
	if not any and not warned and (latestQuests.Active ~= nil) then
		warned = true
		warn("Quests/Tracker: QuestTracker/QuestsModal templates not authored yet — quest UI pending.")
	end
end

function Tracker.Init(ctx: { [string]: any })
	ctxRef = ctx
	local gui = ctx.gui :: ScreenGui

	local slot = ctx.modals.register("Quests", function()
		local modal = gui:FindFirstChild(GuiNames.QuestsModal)
		if modal and modal:IsA("Frame") then
			modal.Visible = false
		end
	end, function()
		local modal = gui:FindFirstChild(GuiNames.QuestsModal)
		if modal and modal:IsA("Frame") then
			modal.Visible = true
		end
		renderAll()
	end)

	local function wireClose(modal: Instance)
		local close = modal:FindFirstChild(GuiNames.Close, true)
		if close and close:IsA("GuiButton") and not close:GetAttribute("QuestsWired") then
			close:SetAttribute("QuestsWired", true)
			close.Activated:Connect(function()
				if modal:IsA("Frame") then
					modal.Visible = false
				end
				slot.close()
			end)
		end
	end
	local existing = gui:FindFirstChild(GuiNames.QuestsModal)
	if existing then
		wireClose(existing)
	end
	gui.ChildAdded:Connect(function(child)
		if child.Name == GuiNames.QuestsModal then
			task.defer(wireClose, child)
		end
	end)

	-- Live pushes (progress, claims, playtime rungs) and full state syncs.
	Net.on(Net.Names.QuestProgress, function(payload: { [string]: any })
		if typeof(payload) == "table" and typeof(payload.Quests) == "table" then
			latestQuests = payload.Quests
			renderAll()
		end
	end)
	ctx.state.OnChanged(function(state)
		if typeof(state.Quests) == "table" then
			latestQuests = state.Quests
			renderAll()
		end
	end)
end

return Tracker
