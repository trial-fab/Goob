--!strict
-- =============================================================================
-- EggController — thin orchestrator for the egg shop domain.
-- [Contract] Owns: the egg shop modal, the policy-required odds popup (exact
--   percentages from EggConfig — the same table the server rolls from), and
--   the hatch reveal overlay (DESIGN.md §7.2/7.3).
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

ctx.hatchReveal = require(script.Parent:WaitForChild("HatchReveal")) :: any
ctx.oddsPopup = require(script.Parent:WaitForChild("OddsPopup")) :: any
ctx.eggShop = require(script.Parent:WaitForChild("EggShop")) :: any

ctx.hatchReveal.Init(ctx)
ctx.oddsPopup.Init(ctx)
ctx.eggShop.Init(ctx)
