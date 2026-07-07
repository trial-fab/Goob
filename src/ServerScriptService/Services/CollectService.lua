--!strict
-- =============================================================================
-- CollectService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: validating goo-blob claims — client says "collect blob id";
--   server checks the blob record exists, the plot is the claimant's, and the
--   claim rate; then grants the server-known value and retires the record.
-- [Contract] Never: grants from client-supplied amounts (the blob record is the
--   value authority); never trusts position.
-- [Contract] Binds: DESIGN.md §5 server authority (goo-blob collection), §5
--   Anti-exploit posture (Collect <=10/s).
-- =============================================================================

local CollectService = {}

function CollectService.Init()
	-- Stub: intentionally no behavior this session.
end

return CollectService
