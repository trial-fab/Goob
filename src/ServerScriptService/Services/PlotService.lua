--!strict
-- =============================================================================
-- PlotService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: assignment/release of the 12 radial wedge plots around the
--   hub, plot bounds queries, and plot ownership lookups (userId <-> plot).
-- [Contract] Never: slime placement (slimes free-roam — there is no placement,
--   §2 Ranch); never authors plot geometry (Studio-authored world, WORKFLOW.md).
-- [Contract] Binds: DESIGN.md §2 Ranch & world, §5 (radial wedges, SheetService
--   descendant), §6 reuse map.
-- =============================================================================

local PlotService = {}

function PlotService.Init()
	-- Stub: intentionally no behavior this session.
end

return PlotService
