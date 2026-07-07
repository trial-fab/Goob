--!strict
-- =============================================================================
-- Server — the entry point. Requires every service and Inits them in order.
--
-- [Contract] Owns: the explicit service init order — and nothing else. No game
--   logic lives here, ever.
-- [Contract] Never: skips a service, reorders without reading the comments
--   below, or lets a service self-initialize at require time (Init() is the
--   only side-effecting entry point a service may have).
-- [Contract] Binds: DESIGN.md §5 Service/module layout.
-- =============================================================================

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

-- Tier 0 — infrastructure. RateLimiter installs itself into Net; Net refuses
-- server-side remote registrations until then, so it MUST run before any
-- service that calls Net.on/onInvoke.
local RateLimiter = require(Services:WaitForChild("RateLimiter"))
-- Tier 1 — persistence. Session-locked profiles; everything below reads and
-- writes player state through it.
local DataService = require(Services:WaitForChild("DataService"))
-- Tier 2 — instrumentation (stub). Early so later services can log from day one
-- (§8 W8: analytics ships in MVP, not later).
local AnalyticsService = require(Services:WaitForChild("AnalyticsService"))
-- Tier 3 — world & ranch: plots before slimes, slimes before the systems that
-- act on them, production before collection (blob records must exist first).
local PlotService = require(Services:WaitForChild("PlotService"))
local SlimeService = require(Services:WaitForChild("SlimeService"))
local ProductionService = require(Services:WaitForChild("ProductionService"))
local CollectService = require(Services:WaitForChild("CollectService"))
local HatchService = require(Services:WaitForChild("HatchService"))
local GrowthService = require(Services:WaitForChild("GrowthService"))
-- Tier 4 — exploration: zone unlock state first; the reward services (wilds,
-- nodes, shrines) validate against it; squads validate ability claims last.
local ZoneService = require(Services:WaitForChild("ZoneService"))
local WildSlimeService = require(Services:WaitForChild("WildSlimeService"))
local GatherService = require(Services:WaitForChild("GatherService"))
local ShrineService = require(Services:WaitForChild("ShrineService"))
local SquadService = require(Services:WaitForChild("SquadService"))
-- Tier 5 — expression & social.
local DecorService = require(Services:WaitForChild("DecorService"))
local TradeService = require(Services:WaitForChild("TradeService"))
-- Tier 6 — retention.
local QuestService = require(Services:WaitForChild("QuestService"))
local DailyRewardService = require(Services:WaitForChild("DailyRewardService"))
local OfflineEarningsService = require(Services:WaitForChild("OfflineEarningsService"))
local LeaderboardService = require(Services:WaitForChild("LeaderboardService"))
local EventService = require(Services:WaitForChild("EventService"))
-- Tier 7 — monetization. BoostService before MonetizationService: receipts
-- grant boosts, so the boost pipeline must exist when ProcessReceipt binds.
local BoostService = require(Services:WaitForChild("BoostService"))
local MonetizationService = require(Services:WaitForChild("MonetizationService"))
-- Tier 8 — debug. Last: it may reach into any service above.
local TestCommandService = require(Services:WaitForChild("TestCommandService"))

RateLimiter.Init()
DataService.Init()
AnalyticsService.Init()
PlotService.Init()
SlimeService.Init()
ProductionService.Init()
CollectService.Init()
HatchService.Init()
GrowthService.Init()
ZoneService.Init()
WildSlimeService.Init()
GatherService.Init()
ShrineService.Init()
SquadService.Init()
DecorService.Init()
TradeService.Init()
QuestService.Init()
DailyRewardService.Init()
OfflineEarningsService.Init()
LeaderboardService.Init()
EventService.Init()
BoostService.Init()
MonetizationService.Init()
TestCommandService.Init()

print("[SlimeGame] server started — all services initialized")
