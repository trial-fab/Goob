--!strict
-- =============================================================================
-- WanderSim — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: the deterministic ranch wander simulation — pure functions
--   from (slime GUID seed, synchronized epoch, nature params, plot bounds,
--   decor affinity tags) -> position/pose over time. Client-run on every
--   client; server-checkable because it is deterministic.
-- [Contract] Never: replication (motion costs ZERO network — the server owns
--   rosters only); never per-frame Heartbeat writes for idle motion (looping
--   Tweens — idle render-throttle rule); never non-deterministic inputs
--   (os.clock, math.random without the GUID seed).
-- [Contract] Binds: DESIGN.md §5 ranch wander sim + follower sim, §1 (M0 perf
--   spike validates the rig budget BEFORE caps are final).
-- =============================================================================

local WanderSim = {}

return WanderSim
