--!strict
-- =============================================================================
-- HudController — thin orchestrator for the persistent HUD domain.
-- [Contract] Owns: the persistent HUD — Goo/Gems counters (image icon + bare
--   NumberFormat number, driven by the Attrs.Goo/Gems projections), offline-
--   earnings claim toast, event banner strip (DESIGN.md §7.1). Also boots
--   Shared/ClientState (the one Init call for the whole screen).
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

ctx.state.Init() -- the whole screen's one ClientState boot

ctx.counters = require(script.Parent:WaitForChild("Counters")) :: any
ctx.offlineToast = require(script.Parent:WaitForChild("OfflineToast")) :: any

ctx.counters.Init(ctx)
ctx.offlineToast.Init(ctx)
