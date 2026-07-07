--!strict
-- =============================================================================
-- HatchService — STUB (scaffold session 1; implement session 3).
--
-- [Contract] Owns: egg purchase (BuyEgg RemoteFunction) — Goo/Gem debit, the
--   server-side species/mutation/nature rolls, the first-session pity roll
--   (guaranteed Shiny by hatch #7), the luck-modifier stack (pass/boost/event),
--   Triple Hatch, and handing the new slime to SlimeService.
-- [Contract] Never: client-side rolls of any kind; never odds that diverge from
--   EggConfig (the SINGLE source both the server rolls from and the odds popup
--   renders — the disclosed odds ARE the real odds, §4 fairness).
-- [Contract] Binds: DESIGN.md §2 hatch flow, §4 fairness commitments, §5
--   Anti-exploit posture (BuyEgg <=3/s).
-- =============================================================================

local HatchService = {}

function HatchService.Init()
	-- Stub: intentionally no behavior this session.
end

return HatchService
