--!strict
-- =============================================================================
-- WildSlimeService — server-rolled wild spawns + the befriend flow.
--
-- [Contract] Owns: server-rolled wild slime spawns per zone (spawn tables from
--   ZoneConfig), befriend attempts (favorite-food check, food debit, nature
--   roll) and results, and wild-exclusive species availability.
-- [Contract] Never: combat (befriend by feeding, never fought); never client-
--   influenced spawn or befriend rolls; befriends validated via ZoneService
--   unlock/ability state, never position (Befriend <=1/s).
-- [Contract] Binds: DESIGN.md §2 wild slimes, §5 Anti-exploit posture.
-- =============================================================================
--
-- Taming (§2 + FoodConfig): feeding the FAVORITE food TameCost times befriends
-- the wild slime; each attempt (right or wrong) consumes one item. Wrong foods
-- return "not interested"; after three wrong species-guesses the favorite is
-- revealed as a hint (the sim's discovery model — docs/economy.md). Favorite
-- progress is per player per SPAWN: a wild slime that despawns takes its
-- progress with it (urgency is the point).
--
-- Studio contract (docs/studio-handoff.md): optional spawn-point parts at
-- Workspace.Zones.<zoneId>.WildSpawnPoints.* — used only to POSITION the
-- shared wild model; every reward decision is id + state based.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local SlimeConfig = require(Shared:WaitForChild("SlimeConfig"))
local FoodConfig = require(Shared:WaitForChild("FoodConfig"))
local ZoneConfig = require(Shared:WaitForChild("ZoneConfig"))
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))
local RanchConfig = require(Shared:WaitForChild("RanchConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local SlimeService = require(script.Parent:WaitForChild("SlimeService"))
local HatchService = require(script.Parent:WaitForChild("HatchService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))
local QuestService = require(script.Parent:WaitForChild("QuestService"))

local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }
local Foods = FoodConfig.Foods :: { [string]: FoodConfig.Food }
local Zones = ZoneConfig.Zones :: { [string]: ZoneConfig.Zone }

local SWEEP_SECONDS = 15
local SPAWN_LIFETIME = 180 -- seconds a wild slime lingers before despawning
local MAX_ACTIVE_PER_ZONE = 2
local WRONG_GUESSES_FOR_HINT = 3

local WildSlimeService = {}

export type WildSpawn = {
	Id: string,
	ZoneId: string,
	SpeciesId: string,
	ExpiresAt: number,
}

local spawns: { [string]: WildSpawn } = {} -- wildId -> spawn
local nextSpawnAt: { [string]: number } = {} -- zoneId -> os.time()
-- [player.UserId .. wildId] -> favorite feeds so far (per spawn, in-memory).
local tameProgress: { [string]: number } = {}
-- [player.UserId .. speciesId] -> wrong feeds toward the favorite hint.
local wrongGuesses: { [string]: number } = {}

local rng = Random.new()

local function countActive(zoneId: string): number
	local count = 0
	for _, spawn in spawns do
		if spawn.ZoneId == zoneId then
			count += 1
		end
	end
	return count
end

local function rollSpecies(zone: ZoneConfig.Zone): string
	local r = rng:NextInteger(1, 10000)
	local acc = 0
	local keys = {}
	for id in zone.WildSpawns do
		table.insert(keys, id)
	end
	table.sort(keys)
	for _, speciesId in keys do
		acc += zone.WildSpawns[speciesId]
		if r <= acc then
			return speciesId
		end
	end
	return keys[#keys]
end

local function broadcast()
	local list = {}
	for _, spawn in spawns do
		table.insert(list, spawn)
	end
	Net.fireAll(Net.Names.WildSpawnChanged, list)
end

local function scheduleNext(zoneId: string)
	local zone = Zones[zoneId]
	local interval = rng:NextNumber(zone.SpawnIntervalSeconds.Min, zone.SpawnIntervalSeconds.Max)
	if ZoneService.IsSurging(zoneId) then
		interval /= ZoneConfig.DailySurge.SpawnRateMult
	end
	nextSpawnAt[zoneId] = os.time() + math.floor(interval)
end

-- Physical marker: a shared wild model at a Studio spawn point (presentation
-- only — clients attach the befriend prompt to it; rewards never check it).
local wildModels: { [string]: Model } = {}

local function spawnModel(spawn: WildSpawn)
	local zones = Workspace:FindFirstChild("Zones")
	local zoneFolder = if zones then zones:FindFirstChild(spawn.ZoneId) else nil
	local points = if zoneFolder then zoneFolder:FindFirstChild("WildSpawnPoints") else nil
	if not points then
		return -- world not authored yet; data spawn still works via the remote
	end
	local candidates = points:GetChildren()
	if #candidates == 0 then
		return
	end
	local at = candidates[rng:NextInteger(1, #candidates)]
	if not at:IsA("BasePart") then
		return
	end
	local model = Instance.new("Model")
	model.Name = "WildSlime"
	local part = Instance.new("Part")
	part.Name = "Body"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2, 2, 2)
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Studs
	part.Parent = model
	model.PrimaryPart = part
	model:SetAttribute("WildId", spawn.Id)
	model:SetAttribute("SpeciesId", spawn.SpeciesId)
	model:PivotTo(at.CFrame * CFrame.new(0, 2, 0))
	model.Parent = zoneFolder
	wildModels[spawn.Id] = model
end

local function removeSpawn(wildId: string)
	spawns[wildId] = nil
	local model = wildModels[wildId]
	if model then
		wildModels[wildId] = nil
		model:Destroy()
	end
end

local function doSpawn(zoneId: string)
	local spawn: WildSpawn = {
		Id = HttpService:GenerateGUID(false),
		ZoneId = zoneId,
		SpeciesId = rollSpecies(Zones[zoneId]),
		ExpiresAt = os.time() + SPAWN_LIFETIME,
	}
	spawns[spawn.Id] = spawn
	spawnModel(spawn)
	broadcast()
end

-- Test seam (Studio verification + TestCommandService !wild).
function WildSlimeService.ForceSpawn(zoneId: string): WildSpawn?
	if not Zones[zoneId] then
		return nil
	end
	doSpawn(zoneId)
	for _, spawn in spawns do
		if spawn.ZoneId == zoneId then
			return spawn
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------

local function onBefriendAttempt(player: Player, wildId: string, foodId: string): { [string]: any }
	local data = DataService.GetData(player)
	if not data then
		return { success = false, message = "Loading..." }
	end
	local spawn = spawns[wildId]
	if not spawn or os.time() > spawn.ExpiresAt then
		return { success = false, message = "That slime has wandered off." }
	end

	-- State validation, never position (§5): unlock + equipped Access ability.
	local ok, why = ZoneService.CanAccess(player, spawn.ZoneId)
	if not ok then
		return { success = false, message = why }
	end

	local food = Foods[foodId]
	if not food then
		return { success = false, message = "Unknown food." }
	end
	if (data.Foods[foodId] or 0) < 1 then
		return { success = false, message = "You don't have any " .. food.Name .. "." }
	end

	local species = Species[spawn.SpeciesId]
	local favorite = species.FavoriteFood

	if SlimeService.CountOwned(data) >= RanchConfig.StorageCap then
		-- Refuse BEFORE consuming food: a full-storage attempt must cost nothing.
		return { success = false, message = "Slime storage is full — release or trade first." }
	end

	data.Foods[foodId] -= 1

	if foodId ~= favorite then
		local guessKey = player.UserId .. spawn.SpeciesId
		wrongGuesses[guessKey] = (wrongGuesses[guessKey] or 0) + 1
		local hint = nil
		if wrongGuesses[guessKey] >= WRONG_GUESSES_FOR_HINT and favorite then
			hint = Foods[favorite].Name -- discovery earned; the Index shows it too
		end
		SlimeService.PushState(player)
		return { success = true, tamed = false, interested = false, hint = hint }
	end

	local progressKey = player.UserId .. wildId
	local fed = (tameProgress[progressKey] or 0) + 1
	if fed < FoodConfig.TameCost then
		tameProgress[progressKey] = fed
		SlimeService.PushState(player)
		return { success = true, tamed = false, interested = true, fed = fed, needed = FoodConfig.TameCost }
	end

	-- Tamed. Server rolls mutation (hatch table — luck stack applies when
	-- BoostService lands) + nature; wild source is the Index/trade provenance.
	tameProgress[progressKey] = nil
	local mutation = HatchService.RollMutation(MutationConfig.Rolls.Hatch, 1)
	local nature = HatchService.RollNature()
	local slimeId, toStorage = SlimeService.Mint(player, data, spawn.SpeciesId, mutation, nature, "wild")
	data.Stats.Befriends += 1
	QuestService.Progress(player, "Befriend", 1)
	removeSpawn(wildId)
	broadcast()
	DataService.ForceSave(player) -- befriend is on the §5 force-save list
	SlimeService.PushState(player)

	return {
		success = true,
		tamed = true,
		slime = {
			SlimeId = slimeId,
			SpeciesId = spawn.SpeciesId,
			Mutation = mutation,
			Nature = nature,
			ToStorage = toStorage,
		},
	}
end

function WildSlimeService.Init()
	for zoneId in Zones do
		scheduleNext(zoneId)
	end

	-- One loop: spawn cadence + expiry sweep for every zone.
	task.spawn(function()
		while true do
			task.wait(SWEEP_SECONDS)
			local now = os.time()
			local changed = false
			for wildId, spawn in spawns do
				if now > spawn.ExpiresAt then
					removeSpawn(wildId)
					changed = true
				end
			end
			for zoneId in Zones do
				if now >= (nextSpawnAt[zoneId] or 0) then
					if countActive(zoneId) < MAX_ACTIVE_PER_ZONE then
						doSpawn(zoneId)
						changed = false -- doSpawn already broadcast
					end
					scheduleNext(zoneId)
				end
			end
			if changed then
				broadcast()
			end
		end
	end)

	Net.onInvoke(Net.Names.BefriendAttempt, onBefriendAttempt, {
		budget = 1, -- §5 anti-exploit posture: Befriend <=1/s
		window = 1,
		validator = Net.T.args(Net.T.guid, Net.T.string(40)),
	})
end

return WildSlimeService
