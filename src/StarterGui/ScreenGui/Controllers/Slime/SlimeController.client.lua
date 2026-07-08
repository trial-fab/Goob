--!strict
-- =============================================================================
-- SlimeController — thin orchestrator for the ranch-slime domain.
-- [Contract] Owns: rendering/animating ranch slimes from the WanderSim (looping
--   Tweens, never per-frame Heartbeat writes), the ProximityPrompt radial
--   (Feed/Pet/Info), goo-blob rendering + collection, and LOD swaps (DESIGN.md
--   §5 perf budget, §7.5).
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

ctx.ranchRender = require(script.Parent:WaitForChild("RanchRender")) :: any
ctx.blobs = require(script.Parent:WaitForChild("Blobs")) :: any
ctx.interact = require(script.Parent:WaitForChild("Interact")) :: any

ctx.ranchRender.Init(ctx)
ctx.blobs.Init(ctx)
ctx.interact.Init(ctx)
