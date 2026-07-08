--!strict
-- =============================================================================
-- SlimeService — slime instance lifecycle, roster state, projections.
--
-- [Contract] Owns: slime instance lifecycle — minting slime GUIDs (server-side,
--   at hatch/befriend, NEVER reused), spawning/despawning slime Models with the
--   replicated attributes (SlimeId/SpeciesId/Mutation/Stage/Nature/OwnerUserId),
--   the ranch/storage roster state machine (+ release/rename/lock remotes),
--   the Index discovery ledger, the shared busy registry (trade/shrine holds),
--   and the StateSync UI projection push.
-- [Contract] Never: Humanoid rigs (one anchored mesh; clients animate with
--   Tweens); never paths/moves ranch slimes (wander is a deterministic client
--   sim — the server owns rosters only and replicates no motion); never trusts
--   a client-supplied slimeId without an ownership check.
-- [Contract] Binds: DESIGN.md §5 topology/perf budget + ranch wander sim, §2.
-- =============================================================================
--
-- Slime meshes are Studio-authored (docs/studio-handoff.md):
--   ReplicatedStorage.SlimeAssets.<speciesId>   Model (PrimaryPart set; base
--                                               scale = Blob; ≤1 mesh + 2
--                                               accessories, §8 W7)
-- Until they exist, a clearly-named placeholder ball spawns instead so the
-- whole loop is playable/verifiable; the user replaces assets, not code.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local SlimeConfig = require(Shared:WaitForChild("SlimeConfig"))
local GrowthConfig = require(Shared:WaitForChild("GrowthConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }

local MAX_NAME_LENGTH = 24

local SlimeService = {}

export type SlimeRecord = {
	Sp: string,
	Mu: string,
	Nt: string,
	St: number,
	Fed: number,
	T: number,
	StT: number,
	Lk: boolean,
	Src: string,
	Nm: string?,
}

-- slimeId -> true while a system (trade escrow, shrine roll) holds the slime.
-- GUIDs are globally unique, so one server-wide set suffices.
local busy: { [string]: boolean } = {}

-- slimeId -> spawned ranch Model.
local models: { [string]: Model } = {}

-- Subscribers told whenever a player's collection/roster/squad changed shape
-- (mint, remove, roster toggle). ZoneService re-evaluates unlocks, SquadService
-- re-projects the parade — without SlimeService requiring either (init tiers).
local collectionChanged: { (player: Player) -> () } = {}

-- ---------------------------------------------------------------------------
-- Projections (write-through only; never read back — §8 W3).
-- ---------------------------------------------------------------------------

local function projectCurrencies(player: Player, data: DataService.ProfileData)
	player:SetAttribute(Attrs.Goo, data.Goo)
	player:SetAttribute(Attrs.Gems, data.Gems)
end

-- The batched UI projection every client screen renders (StateSync).
local function buildState(data: DataService.ProfileData): { [string]: any }
	return {
		Goo = data.Goo,
		Gems = data.Gems,
		Molts = data.Molts,
		Slimes = data.Slimes,
		Roster = data.Ranch.Roster,
		Slots = data.Ranch.Slots,
		Decor = data.Ranch.Decor,
		Likes = data.Ranch.Likes,
		Squad = data.Squad,
		SquadSlots = data.SquadSlots,
		Foods = data.Foods,
		EggCounts = data.EggCounts,
		Zones = data.Zones,
		Index = data.Index,
		Quests = data.Quests,
		Streak = data.Streak,
		Stats = data.Stats,
	}
end

function SlimeService.PushState(player: Player)
	local data = DataService.GetData(player)
	if data then
		projectCurrencies(player, data)
		Net.fireClient(Net.Names.StateSync, player, buildState(data))
	end
end

function SlimeService.OnCollectionChanged(callback: (player: Player) -> ())
	table.insert(collectionChanged, callback)
end

local function notifyCollectionChanged(player: Player)
	for _, callback in collectionChanged do
		task.spawn(callback, player)
	end
end

-- ---------------------------------------------------------------------------
-- Ranch Models. One anchored mesh per producing slime; all motion is the
-- client wander sim. Server sets attributes + an initial resting position.
-- ---------------------------------------------------------------------------

local warnedNoAssets: { [string]: boolean } = {}

local function slimeFolder(): Folder
	local folder = Workspace:FindFirstChild("RanchSlimes")
	if folder and folder:IsA("Folder") then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "RanchSlimes"
	created.Parent = Workspace
	return created
end

local function makeModel(speciesId: string): Model
	local assets = ReplicatedStorage:FindFirstChild("SlimeAssets")
	local template = if assets then assets:FindFirstChild(speciesId) else nil
	if template and template:IsA("Model") and template.PrimaryPart then
		return template:Clone()
	end
	if not warnedNoAssets[speciesId] then
		warnedNoAssets[speciesId] = true
		warn(("SlimeService: no ReplicatedStorage.SlimeAssets.%s — spawning placeholder."):format(speciesId))
	end
	-- Placeholder until the user authors the mesh (docs/studio-handoff.md).
	local model = Instance.new("Model")
	model.Name = "PlaceholderSlime"
	local part = Instance.new("Part")
	part.Name = "Body"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2, 2, 2)
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Studs -- classic studded style (project law)
	part.BottomSurface = Enum.SurfaceType.Studs
	part.Parent = model
	model.PrimaryPart = part
	return model
end

local function applyAttributes(model: Model, player: Player, slimeId: string, record: SlimeRecord)
	model:SetAttribute(Attrs.SlimeId, slimeId)
	model:SetAttribute(Attrs.SpeciesId, record.Sp)
	model:SetAttribute(Attrs.Mutation, record.Mu)
	model:SetAttribute(Attrs.Stage, record.St)
	model:SetAttribute(Attrs.Nature, record.Nt)
	model:SetAttribute(Attrs.OwnerUserId, player.UserId)
end

local function despawnModel(slimeId: string)
	local model = models[slimeId]
	if model then
		models[slimeId] = nil
		model:Destroy()
	end
end

local function spawnModel(player: Player, slimeId: string, record: SlimeRecord)
	despawnModel(slimeId)
	local model = makeModel(record.Sp)
	applyAttributes(model, player, slimeId, record)
	local scale = GrowthConfig.Stages[record.St].ModelScale
	pcall(function()
		model:ScaleTo(scale)
	end)
	-- Initial resting spot only — the wander sim owns every position after
	-- this. Without plot geometry the model still spawns (at the world origin
	-- area) so the loop stays testable pre-world.
	local base = PlotService.GetBase(player)
	local at = if base then base.CFrame * CFrame.new(0, base.Size.Y / 2 + scale, 0) else CFrame.new(0, 3, 0)
	model:PivotTo(at)
	model.Parent = slimeFolder()
	models[slimeId] = model
end

-- Re-project a record's attributes/scale after stage/mutation/rename changes.
function SlimeService.RefreshModel(player: Player, slimeId: string)
	local data = DataService.GetData(player)
	local record = if data then data.Slimes[slimeId] :: SlimeRecord? else nil
	local model = models[slimeId]
	if not (data and record and model) then
		return
	end
	applyAttributes(model, player, slimeId, record)
	pcall(function()
		model:ScaleTo(GrowthConfig.Stages[record.St].ModelScale)
	end)
end

-- ---------------------------------------------------------------------------
-- Collection queries + busy registry (TradeService/ShrineService coordinate
-- through these instead of poking each other).
-- ---------------------------------------------------------------------------

function SlimeService.GetRecord(player: Player, slimeId: string): SlimeRecord?
	local data = DataService.GetData(player)
	return if data then data.Slimes[slimeId] :: SlimeRecord? else nil
end

function SlimeService.CountOwned(data: DataService.ProfileData): number
	local count = 0
	for _ in data.Slimes do
		count += 1
	end
	return count
end

function SlimeService.IsEquipped(data: DataService.ProfileData, slimeId: string): boolean
	return table.find(data.Squad, slimeId) ~= nil
end

function SlimeService.SetBusy(slimeId: string, isBusy: boolean)
	if isBusy then
		busy[slimeId] = true
	else
		busy[slimeId] = nil
	end
end

function SlimeService.IsBusy(slimeId: string): boolean
	return busy[slimeId] == true
end

-- Whether a slime may be offered/consumed/released right now. One rule, every
-- caller (release, trade offer, shrine, equip) — divergence here is a dupe.
function SlimeService.IsHeld(data: DataService.ProfileData, slimeId: string): boolean
	local record = data.Slimes[slimeId] :: SlimeRecord?
	if not record then
		return true
	end
	return record.Lk or SlimeService.IsEquipped(data, slimeId) or SlimeService.IsBusy(slimeId)
end

function SlimeService.Discover(data: DataService.ProfileData, speciesId: string, mutation: string)
	data.Index[speciesId .. ":" .. mutation] = true
end

-- ---------------------------------------------------------------------------
-- Mint / remove / transfer.
-- ---------------------------------------------------------------------------

-- Mint a NEW slime (hatch/befriend — the only GUID sources, §5). Joins the
-- ranch roster when there is space, otherwise storage. Returns (id, toStorage).
function SlimeService.Mint(
	player: Player,
	data: DataService.ProfileData,
	speciesId: string,
	mutation: string,
	nature: string,
	source: string
): (string, boolean)
	assert(Species[speciesId] ~= nil, "Mint: unknown species " .. speciesId)
	local slimeId = HttpService:GenerateGUID(false)
	local now = os.time()
	local record: SlimeRecord = {
		Sp = speciesId,
		Mu = mutation,
		Nt = nature,
		St = 1,
		Fed = 0,
		T = now,
		StT = now,
		Lk = false,
		Src = source,
	}
	data.Slimes[slimeId] = record
	SlimeService.Discover(data, speciesId, mutation)

	local toStorage = #data.Ranch.Roster >= data.Ranch.Slots
	if not toStorage then
		table.insert(data.Ranch.Roster, slimeId)
		spawnModel(player, slimeId, record)
	end
	SlimeService.PushState(player)
	notifyCollectionChanged(player)
	return slimeId, toStorage
end

-- Remove a slime record everywhere it can be referenced (record, roster,
-- squad, model). Used by release and by the trade commit's giving side —
-- deliberately NO refund logic here.
function SlimeService.Remove(player: Player, data: DataService.ProfileData, slimeId: string)
	data.Slimes[slimeId] = nil
	local rosterAt = table.find(data.Ranch.Roster, slimeId)
	if rosterAt then
		table.remove(data.Ranch.Roster, rosterAt)
	end
	local squadAt = table.find(data.Squad, slimeId)
	if squadAt then
		table.remove(data.Squad, squadAt)
	end
	busy[slimeId] = nil
	despawnModel(slimeId)
	SlimeService.PushState(player)
	notifyCollectionChanged(player)
end

-- Attach an EXISTING record under its original GUID (trade commit's receiving
-- side — the GUID must survive the move; a re-mint would be a fresh identity
-- and would break the tradeId ledger's audit trail).
function SlimeService.AddExisting(player: Player, data: DataService.ProfileData, slimeId: string, record: SlimeRecord)
	data.Slimes[slimeId] = record
	SlimeService.Discover(data, record.Sp, record.Mu)
	if #data.Ranch.Roster < data.Ranch.Slots then
		table.insert(data.Ranch.Roster, slimeId)
		spawnModel(player, slimeId, record)
	end
	SlimeService.PushState(player)
	notifyCollectionChanged(player)
end

-- ---------------------------------------------------------------------------
-- Remotes.
-- ---------------------------------------------------------------------------

local function onSetRanchState(player: Player, slimeId: string, state: string): { [string]: any }
	local data = DataService.GetData(player)
	local record = if data then data.Slimes[slimeId] :: SlimeRecord? else nil
	if not (data and record) then
		return { success = false, message = "Unknown slime." }
	end
	if SlimeService.IsBusy(slimeId) then
		return { success = false, message = "That slime is busy." }
	end
	local rosterAt = table.find(data.Ranch.Roster, slimeId)
	if state == "ranch" then
		if rosterAt then
			return { success = true }
		end
		if SlimeService.IsEquipped(data, slimeId) then
			return { success = false, message = "Unequip it from your squad first." }
		end
		if #data.Ranch.Roster >= data.Ranch.Slots then
			return { success = false, message = "Your ranch is full." }
		end
		table.insert(data.Ranch.Roster, slimeId)
		spawnModel(player, slimeId, record)
	else
		if not rosterAt then
			return { success = true }
		end
		table.remove(data.Ranch.Roster, rosterAt)
		despawnModel(slimeId)
	end
	SlimeService.PushState(player)
	notifyCollectionChanged(player)
	return { success = true }
end

local function onReleaseSlime(player: Player, slimeId: string): { [string]: any }
	local data = DataService.GetData(player)
	local record = if data then data.Slimes[slimeId] :: SlimeRecord? else nil
	if not (data and record) then
		return { success = false, message = "Unknown slime." }
	end
	if SlimeService.IsHeld(data, slimeId) then
		return { success = false, message = "That slime is locked, equipped, or busy." }
	end
	local species = Species[record.Sp]
	local gooRefund = 0
	local foodRefund: { [string]: number } = {}
	if species.Hatchable then
		-- Rarity-fraction refund × stage RefundMult — always a token vs the
		-- expected cost of obtaining it (§3 risk 3; config_check asserts).
		gooRefund = math.floor(species.RefundGoo * GrowthConfig.Stages[record.St].RefundMult)
		data.Goo += gooRefund
		data.Stats.GooEarned += gooRefund
	elseif species.RefundFood then
		-- Wild-exclusives refund FOOD, never Goo (no befriend->release printer).
		for foodId, count in species.RefundFood :: { [string]: number } do
			data.Foods[foodId] = (data.Foods[foodId] or 0) + count
			foodRefund[foodId] = count
		end
	end
	SlimeService.Remove(player, data, slimeId) -- pushes state
	return { success = true, gooRefund = gooRefund, foodRefund = foodRefund }
end

local function onRenameSlime(player: Player, slimeId: string, name: string): { [string]: any }
	local data = DataService.GetData(player)
	local record = if data then data.Slimes[slimeId] :: SlimeRecord? else nil
	if not (data and record) then
		return { success = false, message = "Unknown slime." }
	end
	local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
	if #trimmed == 0 or #trimmed > MAX_NAME_LENGTH then
		return { success = false, message = "Names must be 1-" .. MAX_NAME_LENGTH .. " characters." }
	end
	-- Young audience: every player-authored string is filtered (§2 naming).
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(trimmed, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return { success = false, message = "Couldn't check that name. Try again." }
	end
	record.Nm = filtered
	SlimeService.RefreshModel(player, slimeId)
	SlimeService.PushState(player)
	return { success = true, name = filtered }
end

local function onSetSlimeLocked(player: Player, slimeId: string, locked: boolean): { [string]: any }
	local data = DataService.GetData(player)
	local record = if data then data.Slimes[slimeId] :: SlimeRecord? else nil
	if not (data and record) then
		return { success = false, message = "Unknown slime." }
	end
	if SlimeService.IsBusy(slimeId) then
		return { success = false, message = "That slime is busy." }
	end
	record.Lk = locked
	SlimeService.PushState(player)
	return { success = true, locked = locked }
end

function SlimeService.Init()
	DataService.OnProfileLoaded(function(player, data)
		-- Respawn the persisted roster and hand the client its first state.
		for _, slimeId in data.Ranch.Roster do
			local record = data.Slimes[slimeId] :: SlimeRecord?
			if record then
				spawnModel(player, slimeId, record)
			end
		end
		SlimeService.PushState(player)
		notifyCollectionChanged(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local data = DataService.GetData(player)
		if data then
			for _, slimeId in data.Ranch.Roster do
				despawnModel(slimeId)
			end
		end
	end)

	Net.onInvoke(Net.Names.GetState, function(player: Player)
		local data = DataService.GetData(player)
		if not data then
			return { success = false, message = "Loading..." }
		end
		return { success = true, state = buildState(data) }
	end, { budget = 3, window = 5, validator = Net.T.none })

	Net.onInvoke(Net.Names.SetRanchState, onSetRanchState, {
		budget = 5,
		window = 1,
		validator = Net.T.args(Net.T.guid, Net.T.enum({ "ranch", "storage" })),
	})
	Net.onInvoke(Net.Names.ReleaseSlime, onReleaseSlime, {
		budget = 3,
		window = 1,
		validator = Net.T.args(Net.T.guid),
	})
	Net.onInvoke(Net.Names.RenameSlime, onRenameSlime, {
		budget = 2,
		window = 5,
		validator = Net.T.args(Net.T.guid, Net.T.string(50)),
	})
	Net.onInvoke(Net.Names.SetSlimeLocked, onSetSlimeLocked, {
		budget = 5,
		window = 1,
		validator = Net.T.args(Net.T.guid, Net.T.boolean),
	})
end

return SlimeService
