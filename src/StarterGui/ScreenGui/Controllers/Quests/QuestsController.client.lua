--!strict
-- =============================================================================
-- QuestsController — thin orchestrator for the quests domain.
-- [Contract] Owns: the collapsible quest tracker + quest modal + daily streak
--   calendar modal (DESIGN.md §7.13/7.14).
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

ctx.tracker = require(script.Parent:WaitForChild("Tracker")) :: any
ctx.streak = require(script.Parent:WaitForChild("Streak")) :: any

ctx.tracker.Init(ctx)
ctx.streak.Init(ctx)
