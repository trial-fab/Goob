--!strict
-- =============================================================================
-- SquadController — thin orchestrator for the squad domain.
-- [Contract] Owns: the equipped-squad chips bar and the client follower sim
--   (spring-follow, no collisions, tween-animated — replicates nothing;
--   DESIGN.md §5 follower sim, §7.6).
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

ctx.squadBar = require(script.Parent:WaitForChild("SquadBar")) :: any
ctx.followers = require(script.Parent:WaitForChild("Followers")) :: any

ctx.squadBar.Init(ctx)
ctx.followers.Init(ctx)
