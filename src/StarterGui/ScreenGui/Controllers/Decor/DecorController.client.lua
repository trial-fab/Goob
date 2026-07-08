--!strict
-- =============================================================================
-- DecorController — thin orchestrator for the decor build-mode domain.
-- [Contract] Owns: the decor build mode — the ported Build View top-down camera
--   + grid ghost preview + placement stack (ClickGame BuildViewCamera/
--   GridPlacement adapted), catalog drawer wiring (DESIGN.md §7.10, §6).
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

ctx.buildCamera = require(script.Parent:WaitForChild("BuildCamera")) :: any
ctx.placement = require(script.Parent:WaitForChild("Placement")) :: any
ctx.catalog = require(script.Parent:WaitForChild("Catalog")) :: any

ctx.buildCamera.Init(ctx)
ctx.placement.Init(ctx)
ctx.catalog.Init(ctx)
