--!strict
-- =============================================================================
-- Squad/SquadBar — the equipped-slime chips docked by the bottom bar.
-- [Contract] Owns: rendering the local squad (ClientState) as SquadChip
--   clones; a chip tap opens the Inventory modal (squad management lives
--   there — DESIGN.md §7.6).
-- [Contract] Never: constructs GuiObjects (clones the SquadChip template);
--   never equips/unequips itself (Inventory owns the EquipSquad round trip).
-- =============================================================================
--
-- Studio hand-off: ScreenGui.SquadBar (Frame) with SquadChip template
-- (Visible = false): NameLabel, StageLabel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SlimeConfig = require(Shared:WaitForChild("SlimeConfig"))
local GrowthConfig = require(Shared:WaitForChild("GrowthConfig"))

local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }

local BAR_NAME = "SquadBar" -- single-controller lookup

local SquadBar = {}

local warned = false

function SquadBar.Init(ctx: { [string]: any })
	local gui = ctx.gui :: ScreenGui

	local function render(state: { [string]: any })
		local bar = gui:FindFirstChild(BAR_NAME)
		local template = if bar then bar:FindFirstChild("SquadChip") else nil
		if not (bar and template and template:IsA("Frame")) then
			if not warned and next(state) ~= nil then
				warned = true
				warn("Squad/SquadBar: SquadBar.SquadChip template not authored yet — chips pending Studio UI.")
			end
			return
		end
		for _, child in bar:GetChildren() do
			if child ~= template and child.Name:sub(1, 10) == "SquadChip_" then
				child:Destroy()
			end
		end
		local slimes = (state.Slimes or {}) :: { [string]: any }
		for order, slimeId in (state.Squad or {}) :: { string } do
			local record = slimes[slimeId]
			if record then
				local chip = template:Clone()
				chip.Name = "SquadChip_" .. slimeId
				chip.LayoutOrder = order
				chip.Visible = true
				local name = chip:FindFirstChild("NameLabel")
				if name and name:IsA("TextLabel") then
					local species = Species[record.Sp]
					name.Text = record.Nm or (if species then species.Name else record.Sp)
				end
				local stage = chip:FindFirstChild("StageLabel")
				if stage and stage:IsA("TextLabel") then
					stage.Text = GrowthConfig.Stages[record.St].Name
				end
				local button = chip:FindFirstChildWhichIsA("GuiButton", true)
				if button then
					button.Activated:Connect(function()
						ctx.modals.request("Inventory")
					end)
				end
				chip.Parent = bar
			end
		end
	end

	ctx.state.OnChanged(render)
end

return SquadBar
