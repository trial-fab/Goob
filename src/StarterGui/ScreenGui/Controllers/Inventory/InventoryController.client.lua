--!strict
-- =============================================================================
-- InventoryController — thin orchestrator for the inventory domain.
-- [Contract] Owns: the slime-card grid modal — Ranch/Store toggle, Equip,
--   Release, Lock, Rename actions (all server-validated via Net RemoteFunctions;
--   DESIGN.md §7.4).
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

ctx.grid = require(script.Parent:WaitForChild("InventoryGrid")) :: any
ctx.grid.Init(ctx)
