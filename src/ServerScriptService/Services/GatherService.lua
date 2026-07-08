--!strict
-- =============================================================================
-- GatherService — node cooldowns + server-derived yields.
--
-- [Contract] Owns: gathering-node state — server-owned cooldowns and yields
--   (goo geysers, special-food plants), validated per claim via ZoneService.
-- [Contract] Never: client-timed respawns; never yields as a new currency
--   (special foods are ITEMS in Profile.Foods, §2/§3); Gather <=3/s.
-- [Contract] Binds: DESIGN.md §2 gathering nodes, §3 currency map.
-- =============================================================================
--
-- Node identity: "<zoneId>/<nodeConfigId>/<n>", n = 1..Node.Count — the id
-- space comes straight from ZoneConfig, so the server knows every legal node
-- without the world existing. Studio names each node part with its id
-- (docs/studio-handoff.md); the client reads the name to send the claim.
-- Cooldowns are SERVER-WIDE per node (players compete for ready nodes — a
-- social nudge, and no per-player cooldown table to grow).
--
-- Goo geysers yield seconds-of-the-harvester's-gps (ZoneConfig contract) so
-- expedition Goo stays a stable topping at every progression point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local ZoneConfig = require(Shared:WaitForChild("ZoneConfig"))
local FoodConfig = require(Shared:WaitForChild("FoodConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local SlimeService = require(script.Parent:WaitForChild("SlimeService"))
local ProductionService = require(script.Parent:WaitForChild("ProductionService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))
local QuestService = require(script.Parent:WaitForChild("QuestService"))

local Zones = ZoneConfig.Zones :: { [string]: ZoneConfig.Zone }

local GatherService = {}

type NodeState = {
	Zone: ZoneConfig.Zone,
	Config: ZoneConfig.Node,
	ReadyAt: number,
}

local nodes: { [string]: NodeState } = {}
local rng = Random.new()

local function buildNodeRegistry()
	for zoneId, zone in Zones do
		for _, nodeConfig in zone.Nodes do
			for n = 1, nodeConfig.Count do
				nodes[("%s/%s/%d"):format(zoneId, nodeConfig.Id, n)] = {
					Zone = zone,
					Config = nodeConfig,
					ReadyAt = 0,
				}
			end
		end
	end
end

local function onGatherNode(player: Player, nodeId: string): { [string]: any }
	local data = DataService.GetData(player)
	if not data then
		return { success = false, message = "Loading..." }
	end
	local node = nodes[nodeId]
	if not node then
		return { success = false, message = "Unknown node." }
	end

	-- State validation, never position (§5).
	local ok, why = ZoneService.CanAccess(player, node.Zone.Id)
	if not ok then
		return { success = false, message = why }
	end

	local now = os.time()
	if now < node.ReadyAt then
		return { success = false, message = "Not ready yet.", readyIn = node.ReadyAt - now }
	end
	node.ReadyAt = now + node.Config.CooldownSeconds

	local surging = ZoneService.IsSurging(node.Zone.Id)
	local yieldMult = if surging then ZoneConfig.DailySurge.NodeYieldMult else 1

	if node.Config.Kind == "Goo" then
		local seconds = node.Config.YieldGpsSeconds or 0
		-- Server-derived value: the harvester's own gps × the configured
		-- seconds (floor 1 so a roster-less explorer still sees the verb work).
		local value = math.max(1, math.floor(ProductionService.GetGps(player) * seconds * yieldMult))
		data.Goo += value
		data.Stats.GooEarned += value
		player:SetAttribute(Attrs.Goo, data.Goo)
		return { success = true, kind = "Goo", value = value, goo = data.Goo, cooldown = node.Config.CooldownSeconds }
	end

	local foodId = node.Config.FoodId :: string
	-- Surge NodeYieldMult on items is probabilistic (1.5 -> 50% chance of a
	-- second item) so the long-run rate matches the configured multiplier.
	local count = 1
	if yieldMult > 1 and rng:NextNumber() < yieldMult - 1 then
		count = 2
	end
	data.Foods[foodId] = (data.Foods[foodId] or 0) + count
	QuestService.Progress(player, "Gather", count)
	SlimeService.PushState(player) -- Foods changed; the Explore UI renders it
	return {
		success = true,
		kind = "Food",
		foodId = foodId,
		foodName = FoodConfig.Get(foodId).Name,
		count = count,
		cooldown = node.Config.CooldownSeconds,
	}
end

function GatherService.Init()
	buildNodeRegistry()
	Net.onInvoke(Net.Names.GatherNode, onGatherNode, {
		budget = 3, -- §5 anti-exploit posture: Gather <=3/s
		window = 1,
		validator = Net.T.args(Net.T.string(80)),
	})
end

return GatherService
