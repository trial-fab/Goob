--!strict
-- =============================================================================
-- AnalyticsService — STUB (scaffold session 1; implement session 2/3).
--
-- [Contract] Owns: funnel + economy instrumentation (Roblox Funnel/Economy
--   events): FTUE step funnel, hatch/feed/befriend/trade counts, Goo faucet/
--   sink totals, and the server-side sanity assertions with alarms (Goo delta
--   vs GetGps headroom, mutation rate vs disclosed odds, duplicate-GUID
--   detector).
-- [Contract] Never: gameplay effects; never optional (§8 W8: analytics ships
--   in MVP — pacing claims are guesses without it).
-- [Contract] Binds: DESIGN.md §5 Anti-exploit posture, §8 W8.
-- =============================================================================

local AnalyticsService = {}

function AnalyticsService.Init()
	-- Stub: intentionally no behavior this session.
end

return AnalyticsService
