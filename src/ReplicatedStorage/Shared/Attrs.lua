--!strict
-- =============================================================================
-- Attrs — single source of truth for cross-file instance-attribute names.
--
-- [Contract] Owns: the canonical spelling of every attribute shared across 2+
--   files. Reference one as `Attrs.OpenModal`; a typo'd key resolves to nil,
--   which Get/SetAttribute rejects loudly at the call site.
-- [Contract] Never: holds attribute VALUES or truth — attributes are write-
--   through UI projections of the profile table and are NEVER read back at save
--   time (DESIGN.md §8 W3). Per-file private flags stay as local literals.
-- [Contract] Binds: DESIGN.md §5 (replication as attributes), §8 W3.
-- =============================================================================
--
-- Grows with sessions 2–3. Scope rule (inherited from ClickGame): only names
-- shared across files belong here (server writes / client reads, or written and
-- watched by separate controllers).

return table.freeze({
	-- UI / button / modal state (IconButton + ModalCoordinator contracts)
	Active = "Active",
	IconOnly = "IconOnly",
	Open = "Open",
	OpenModal = "OpenModal",
	AnimationsEnabled = "AnimationsEnabled",

	-- slime Model replication (server writes on the slime Model; clients read to
	-- render/animate — DESIGN.md §5 "slime state replicates as attributes")
	SlimeId = "SlimeId",
	SpeciesId = "SpeciesId",
	Mutation = "Mutation",
	Stage = "Stage",
	Nature = "Nature",
	OwnerUserId = "OwnerUserId",

	-- HUD projections (server writes on the Player; profile table is the truth)
	Goo = "Goo",
	Gems = "Gems",
	Gps = "Gps", -- ProductionService writes; HUD renders NumberFormat.rate

	-- world projections
	PlotIndex = "PlotIndex", -- PlotService writes on the Player (1..12)
	SquadJson = "SquadJson", -- SquadService writes on the Player; every client's
	-- follower sim reads it to render other players' parades (composition only —
	-- motion itself is never replicated)

	-- client-local UI state (written/read on the ScreenGui by controllers)
	PlacementActive = "PlacementActive", -- Decor build mode owns camera/input

	-- debug / test harness (TestCommandService writes; tests read)
	DebugPingCount = "DebugPingCount",
})
