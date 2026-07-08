--!strict
-- =============================================================================
-- ExploreController — thin orchestrator for the exploration domain.
-- [Contract] Owns: the explore panel (zone list + unlock requirements + today's
--   surge + shrine cooldowns), befriend food-offer picker, shrine offering flow
--   with odds display, gathering-node prompts (DESIGN.md §7.7-7.9).
--
-- [Contract] Pattern (all client domains): a thin orchestrator (this file) +
--   focused ctx-based ModuleScripts it coordinates. Call modules through their
--   ctx.<module> handle — NEVER re-alias them as top-level locals (the
--   200-local-cap lesson, WORKFLOW.md).
-- [Contract] Never: constructs GuiObjects — ALL UI instances are authored by
--   the user in Studio; code owns logic only (WORKFLOW.md). New UI needs a
--   default-color Studio template handed off for styling.
-- =============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ctx = {} :: { [string]: any }
ctx.gui = script:FindFirstAncestorOfClass("ScreenGui") :: ScreenGui
ctx.state = require(Shared:WaitForChild("ClientState")) :: any
ctx.modals = require(script.Parent.Parent:WaitForChild("Modals"):WaitForChild("ModalCoordinator")) :: any

ctx.zonePanel = require(script.Parent:WaitForChild("ZonePanel")) :: any
ctx.befriend = require(script.Parent:WaitForChild("Befriend")) :: any
ctx.gather = require(script.Parent:WaitForChild("Gather")) :: any
ctx.shrine = require(script.Parent:WaitForChild("Shrine")) :: any

ctx.zonePanel.Init(ctx)
ctx.befriend.Init(ctx)
ctx.gather.Init(ctx)
ctx.shrine.Init(ctx)
