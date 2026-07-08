--!strict
-- =============================================================================
-- Hud/Counters — binds the Goo/Gems/Gps attribute projections to HUD labels.
-- [Contract] Owns: rendering Attrs.Goo/Gems/Gps onto the Studio-authored HUD
--   labels (GuiNames.GooLabel/GemsLabel/GpsLabel) via NumberFormat. Bare
--   numbers only — currency icons are Studio-authored images beside them.
-- [Contract] Never: constructs GuiObjects; never reads state anywhere but the
--   Player attributes (the write-through projections, §8 W3).
-- =============================================================================
--
-- Studio hand-off (docs/studio-handoff.md): ScreenGui.HudFrame with children
-- GooLabel, GemsLabel, GpsLabel (TextLabels; icons are sibling ImageLabels).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Attrs = require(Shared:WaitForChild("Attrs"))
local GuiNames = require(Shared:WaitForChild("GuiNames"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Counters = {}

local warned = false

local function findLabel(gui: ScreenGui, name: string): TextLabel?
	local hud = gui:FindFirstChild(GuiNames.HudFrame)
	local label = if hud then hud:FindFirstChild(name) else nil
	if not label and not warned then
		warned = true
		warn("Hud/Counters: HudFrame templates not authored yet — counters pending Studio UI.")
	end
	return if label and label:IsA("TextLabel") then label else nil
end

function Counters.Init(ctx: { [string]: any })
	local player = Players.LocalPlayer
	local gui = ctx.gui :: ScreenGui

	local function bind(attr: string, labelName: string, format: (value: any) -> string)
		local function render()
			local label = findLabel(gui, labelName)
			if label then
				label.Text = format(player:GetAttribute(attr))
			end
		end
		player:GetAttributeChangedSignal(attr):Connect(render)
		render()
	end

	bind(Attrs.Goo, GuiNames.GooLabel, function(value)
		return NumberFormat.abbreviate(value or 0)
	end)
	bind(Attrs.Gems, GuiNames.GemsLabel, function(value)
		return NumberFormat.abbreviate(value or 0)
	end)
	bind(Attrs.Gps, GuiNames.GpsLabel, function(value)
		return NumberFormat.rate(value or 0)
	end)
end

return Counters
