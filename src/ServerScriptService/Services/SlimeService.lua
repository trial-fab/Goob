--!strict
-- =============================================================================
-- SlimeService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: slime instance lifecycle — minting slime GUIDs (server-side,
--   at hatch/befriend, NEVER reused), spawning/despawning slime Models with the
--   replicated attributes (SlimeId/SpeciesId/Mutation/Stage/Nature/OwnerUserId),
--   and the ranch/storage roster state machine.
-- [Contract] Never: Humanoid rigs (one anchored mesh; clients animate with
--   Tweens); never paths/moves ranch slimes (wander is a deterministic client
--   sim — the server owns rosters only and replicates no motion); never trusts
--   a client-supplied slimeId without an ownership check.
-- [Contract] Binds: DESIGN.md §5 topology/perf budget + ranch wander sim, §2.
-- =============================================================================

local SlimeService = {}

function SlimeService.Init()
	-- Stub: intentionally no behavior this session.
end

return SlimeService
