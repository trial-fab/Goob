--!strict
-- =============================================================================
-- Explore/ZonePanel — the zone ladder panel.
-- [Contract] Owns: rendering ZoneConfig's ladder as ZoneRow clones — unlock
--   state (from ClientState), unlock requirements (slimes owned + Access key),
--   today's surging zone, and the player's shrine cooldowns.
-- [Contract] Never: constructs GuiObjects (clones the ZoneRow template);
--   never decides access (the server's CanAccess is the authority — this
--   renders what StateSync says).
-- =============================================================================
--
-- Studio hand-off: ScreenGui.ExplorePanel (Frame, hidden) with:
--   Rows       Frame/ScrollingFrame
--     ZoneRow  Frame template (Visible = false): NameLabel, ReqLabel,
--              SurgeLabel, ShrineLabel
--   Close      button (GuiNames.Close)
--
-- The surge zone is computed the same way the server computes it (UTC day —
-- deterministic, so no remote needed just to label a row).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GuiNames = require(Shared:WaitForChild("GuiNames"))
local ZoneConfig = require(Shared:WaitForChild("ZoneConfig"))

local Zones = ZoneConfig.Zones :: { [string]: ZoneConfig.Zone }

local ZonePanel = {}

local visible = false
local warned = false

local orderedZoneIds: { string } = {}
for id in Zones do
	table.insert(orderedZoneIds, id)
end
table.sort(orderedZoneIds, function(a, b)
	return Zones[a].Order < Zones[b].Order
end)

local function surgeZoneId(): string
	local day = math.floor(os.time() / 86400)
	return orderedZoneIds[day % #orderedZoneIds + 1]
end

function ZonePanel.Init(ctx: { [string]: any })
	local gui = ctx.gui :: ScreenGui

	local function frame(): Frame?
		local found = gui:FindFirstChild(GuiNames.ExplorePanel)
		return if found and found:IsA("Frame") then found else nil
	end

	local function render()
		local panel = frame()
		if not (visible and panel) then
			return
		end
		local rows = panel:FindFirstChild("Rows")
		local template = if rows then rows:FindFirstChild("ZoneRow") else nil
		if not (rows and template and template:IsA("Frame")) then
			if not warned then
				warned = true
				warn("Explore/ZonePanel: ExplorePanel.Rows.ZoneRow template not authored yet.")
			end
			return
		end
		for _, child in rows:GetChildren() do
			if child ~= template and child.Name:sub(1, 8) == "ZoneRow_" then
				child:Destroy()
			end
		end

		local state = ctx.state.Get()
		local unlocked = ((state.Zones or {}).Unlocked or {}) :: { [string]: boolean }
		local cooldowns = ((state.Zones or {}).ShrineCooldowns or {}) :: { [string]: number }
		local surging = surgeZoneId()

		for order, zoneId in orderedZoneIds do
			local zone = Zones[zoneId]
			local row = template:Clone()
			row.Name = "ZoneRow_" .. zoneId
			row.LayoutOrder = order
			row.Visible = true

			local name = row:FindFirstChild("NameLabel")
			if name and name:IsA("TextLabel") then
				name.Text = zone.Name
			end
			local req = row:FindFirstChild("ReqLabel")
			if req and req:IsA("TextLabel") then
				if unlocked[zoneId] then
					req.Text = if zone.Unlock.AccessKey
						then ("Unlocked — bring a %s slime"):format(zone.Unlock.AccessKey)
						else "Unlocked"
				else
					local text = ("Own %d slimes"):format(zone.Unlock.SlimesOwned)
					if zone.Unlock.AccessKey then
						text ..= (" + equip a %s slime"):format(zone.Unlock.AccessKey)
					end
					req.Text = text
				end
			end
			local surge = row:FindFirstChild("SurgeLabel")
			if surge and surge:IsA("TextLabel") then
				surge.Text = if zoneId == surging then "SURGING today!" else ""
			end
			local shrineLabel = row:FindFirstChild("ShrineLabel")
			if shrineLabel and shrineLabel:IsA("TextLabel") then
				local readyAt = cooldowns[zoneId] or 0
				local wait = readyAt - os.time()
				shrineLabel.Text = if wait > 0 then ("Shrine in %dm"):format(math.ceil(wait / 60)) else "Shrine ready"
			end
			row.Parent = rows
		end
	end

	local slot = ctx.modals.register("Explore", function()
		visible = false
		local panel = frame()
		if panel then
			panel.Visible = false
		end
	end, function()
		visible = true
		local panel = frame()
		if panel then
			panel.Visible = true
		end
		render()
	end)

	local function wireClose(panel: Frame)
		local close = panel:FindFirstChild(GuiNames.Close, true)
		if close and close:IsA("GuiButton") and not close:GetAttribute("ExploreWired") then
			close:SetAttribute("ExploreWired", true)
			close.Activated:Connect(function()
				visible = false
				panel.Visible = false
				slot.close()
			end)
		end
	end
	local existing = frame()
	if existing then
		wireClose(existing)
	end
	gui.ChildAdded:Connect(function(child)
		if child.Name == GuiNames.ExplorePanel and child:IsA("Frame") then
			task.defer(wireClose, child)
		end
	end)

	ctx.state.OnChanged(function()
		render()
	end)
end

return ZonePanel
