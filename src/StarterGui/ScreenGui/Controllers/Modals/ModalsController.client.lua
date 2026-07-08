--!strict
-- =============================================================================
-- ModalsController — Settings + Profile modal logic.
-- [Contract] Owns: the Settings and Profile modals (ClickGame structure —
--   prefs as ScreenGui attributes) and shared modal chrome wiring. Every modal
--   registers with ModalCoordinator (sibling file) — single-open is law.
--
-- [Contract] Pattern (all client domains): a thin orchestrator (this file) +
--   focused ctx-based ModuleScripts it coordinates. Call modules through their
--   ctx.<module> handle — NEVER re-alias them as top-level locals (the
--   200-local-cap lesson, WORKFLOW.md).
-- [Contract] Never: constructs GuiObjects — ALL UI instances are authored by
--   the user in Studio; code owns logic only (WORKFLOW.md). New UI needs a
--   default-color Studio template handed off for styling.
-- =============================================================================
--
-- Studio hand-off: ScreenGui.Settings and ScreenGui.Profile (Frames, hidden
-- by default), each with a Close button (GuiNames.Close). Settings rows toggle
-- ScreenGui attributes (AnimationsEnabled ships now; rows are Studio-authored
-- with a BoolValue-free convention: a button named after the attribute).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Attrs = require(Shared:WaitForChild("Attrs"))
local GuiNames = require(Shared:WaitForChild("GuiNames"))
local Modals = require(script.Parent:WaitForChild("ModalCoordinator"))

local gui = script:FindFirstAncestorOfClass("ScreenGui") :: ScreenGui

-- Client-local prefs default on; controllers read the attribute live.
if gui:GetAttribute(Attrs.AnimationsEnabled) == nil then
	gui:SetAttribute(Attrs.AnimationsEnabled, true)
end

-- Generic simple-modal wiring: show/hide a named Frame through the
-- coordinator, wire its Close button, and its attribute-toggle buttons.
local function wireSimpleModal(frameName: string)
	local slot
	local function setVisible(visible: boolean)
		local frame = gui:FindFirstChild(frameName)
		if frame and frame:IsA("Frame") then
			frame.Visible = visible
		end
	end
	slot = Modals.register(frameName, function()
		setVisible(false)
	end, function()
		setVisible(true)
	end)

	local function wireFrame(frame: Instance)
		local close = frame:FindFirstChild(GuiNames.Close, true)
		if close and close:IsA("GuiButton") then
			close.Activated:Connect(function()
				setVisible(false)
				slot.close()
			end)
		end
		-- Settings rows: any button named exactly like a boolean ScreenGui
		-- attribute toggles it (AnimationsEnabled now; more prefs later).
		for _, descendant in frame:GetDescendants() do
			if descendant:IsA("GuiButton") and descendant.Name == Attrs.AnimationsEnabled then
				descendant.Activated:Connect(function()
					gui:SetAttribute(Attrs.AnimationsEnabled, not gui:GetAttribute(Attrs.AnimationsEnabled))
				end)
			end
		end
	end

	local existing = gui:FindFirstChild(frameName)
	if existing then
		wireFrame(existing)
	end
	gui.ChildAdded:Connect(function(child)
		if child.Name == frameName then
			task.defer(wireFrame, child)
		end
	end)
end

wireSimpleModal(GuiNames.Settings)
wireSimpleModal(GuiNames.Profile)
