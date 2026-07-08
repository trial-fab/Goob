--!strict
-- =============================================================================
-- Explore/Shrine — the shrine offering flow with odds display.
-- [Contract] Owns: the shrine prompt (Studio ZoneShrine attribute contract),
--   the ShrinePanel (slime picker + offering summary + the disclosed
--   MutationConfig.Rolls.Shrine odds — shown before EVERY roll, §2), and the
--   ShrineRoll round trip.
-- [Contract] Never: constructs GuiObjects (clones templates); never computes
--   its own odds numbers — it renders MutationConfig verbatim (§4 posture).
-- =============================================================================
--
-- Studio hand-off: shrine part under Workspace.Zones.<zoneId> with string
-- attribute ShrineZone = zoneId. ScreenGui.ShrinePanel (Frame, hidden) with:
--   TitleLabel   TextLabel (offering requirement)
--   OddsLabel    TextLabel (disclosed roll odds line)
--   Rows         Frame — SlimeRow template (Visible = false): NameLabel,
--                RollButton
--   ResultLabel  TextLabel
--   Close        button (GuiNames.Close)

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GuiNames = require(Shared:WaitForChild("GuiNames"))
local ZoneConfig = require(Shared:WaitForChild("ZoneConfig"))
local FoodConfig = require(Shared:WaitForChild("FoodConfig"))
local SlimeConfig = require(Shared:WaitForChild("SlimeConfig"))
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))

local Zones = ZoneConfig.Zones :: { [string]: ZoneConfig.Zone }
local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }
local Mutations = MutationConfig.Mutations :: { [string]: MutationConfig.Mutation }

local PANEL_NAME = "ShrinePanel" -- single-controller lookup

local Shrine = {}

local ctxRef: { [string]: any } = {}
local currentZoneId: string? = nil
local rolling = false

-- The disclosed shrine odds, verbatim from the table the server rolls
-- (weights are integer basis points, so /100 is exact).
local function oddsLine(): string
	local rolls = MutationConfig.Rolls.Shrine :: { [string]: number }
	local ids = {}
	for id in rolls do
		if id ~= "none" then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		return rolls[a] > rolls[b]
	end)
	local parts = {}
	for _, id in ids do
		table.insert(parts, ("%s %g%%"):format(Mutations[id].Name, rolls[id] / 100))
	end
	return table.concat(parts, " · ")
end

local function panel(): Frame?
	local gui = ctxRef.gui :: ScreenGui
	local found = gui:FindFirstChild(PANEL_NAME)
	return if found and found:IsA("Frame") then found else nil
end

local function setLabel(frame: Frame, name: string, text: string)
	local label = frame:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function renderPanel()
	local frame = panel()
	local zoneId = currentZoneId
	if not (frame and zoneId) then
		return
	end
	local zone = Zones[zoneId]
	local food = FoodConfig.Get(zone.FoodId)
	setLabel(frame, "TitleLabel", ("%s Shrine — offer %d %s"):format(zone.Name, zone.Shrine.OfferingFoods, food.Name))
	setLabel(frame, "OddsLabel", oddsLine())

	local rows = frame:FindFirstChild("Rows")
	local template = if rows then rows:FindFirstChild("SlimeRow") else nil
	if not (rows and template and template:IsA("Frame")) then
		warn("Explore/Shrine: ShrinePanel.Rows.SlimeRow template not authored yet.")
		return
	end
	for _, child in rows:GetChildren() do
		if child ~= template and child.Name:sub(1, 9) == "SlimeRow_" then
			child:Destroy()
		end
	end

	local state = ctxRef.state.Get()
	local slimes = (state.Slimes or {}) :: { [string]: any }
	local squad = (state.Squad or {}) :: { string }
	local order = 0
	for slimeId, record in slimes do
		-- Mirror the server's eligibility for a clean picker (the server
		-- still re-validates): not locked, not equipped, not already Void.
		if not record.Lk and record.Mu ~= "void" and not table.find(squad, slimeId) then
			order += 1
			local row = template:Clone()
			row.Name = "SlimeRow_" .. slimeId
			row.LayoutOrder = order
			row.Visible = true
			local name = row:FindFirstChild("NameLabel")
			if name and name:IsA("TextLabel") then
				local species = Species[record.Sp]
				local mutation = Mutations[record.Mu]
				local label = record.Nm or (if species then species.Name else record.Sp)
				if mutation and mutation.Tier > 0 then
					label = mutation.Name .. " " .. label
				end
				name.Text = label
			end
			local roll = row:FindFirstChild("RollButton")
			if roll and roll:IsA("GuiButton") then
				roll.Activated:Connect(function()
					if rolling or not currentZoneId then
						return
					end
					rolling = true
					local result = Net.invoke(Net.Names.ShrineRoll, currentZoneId, slimeId)
					rolling = false
					local live = panel()
					if not live or typeof(result) ~= "table" then
						return
					end
					if result.success then
						setLabel(
							live,
							"ResultLabel",
							if result.upgraded
								then "The shrine glows... " .. Mutations[result.mutation].Name .. "!"
								else "The shrine dims. No change this time."
						)
						renderPanel()
					else
						setLabel(live, "ResultLabel", result.message or "The shrine is dormant.")
					end
				end)
			end
			row.Parent = rows
		end
	end
end

local function openPanel(zoneId: string)
	currentZoneId = zoneId
	local frame = panel()
	if not frame then
		warn("Explore/Shrine: ShrinePanel template not authored yet — shrine UI pending.")
		return
	end
	setLabel(frame, "ResultLabel", "")
	renderPanel()
	local close = frame:FindFirstChild(GuiNames.Close, true)
	if close and close:IsA("GuiButton") and not close:GetAttribute("ShrineWired") then
		close:SetAttribute("ShrineWired", true)
		close.Activated:Connect(function()
			frame.Visible = false
			currentZoneId = nil
		end)
	end
	frame.Visible = true
end

local function attach(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local zoneId = part:GetAttribute("ShrineZone")
	if typeof(zoneId) ~= "string" or not Zones[zoneId] then
		return
	end
	if part:FindFirstChild("ShrinePrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShrinePrompt"
	prompt.ActionText = "Make an offering"
	prompt.ObjectText = "Mutation Shrine"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 14
	prompt.Parent = part
	prompt.Triggered:Connect(function()
		openPanel(zoneId)
	end)
end

function Shrine.Init(ctx: { [string]: any })
	ctxRef = ctx
	task.spawn(function()
		local zones = Workspace:WaitForChild("Zones", 60)
		if not zones then
			return
		end
		for _, descendant in zones:GetDescendants() do
			attach(descendant)
		end
		zones.DescendantAdded:Connect(function(descendant)
			task.defer(attach, descendant)
		end)
	end)
end

return Shrine
