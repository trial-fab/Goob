--!strict
-- =============================================================================
-- DataService — session-locked player persistence on ProfileStore.
--
-- [Contract] Owns: the versioned profile schema (PROFILE_TEMPLATE +
--   SchemaVersion + MIGRATIONS), ProfileStore session lifecycle (start on join,
--   EndSession on leave, BindToClose sweep), the in-profile receipt buffer, and
--   force-saves after economy-critical actions. The profile table is the SINGLE
--   truth for player state.
-- [Contract] Never: reads Values/attributes back at save time (they are write-
--   through UI projections only — §8 W3); never grants anything (services
--   mutate Data, DataService persists it); never hands profiles to a player
--   whose session isn't locked by THIS server (ProfileStore guarantee — the
--   prerequisite for trading, §5); never a second DataStore for receipts
--   (§8 W2: receipts live in the profile so grant + record is one atomic save).
-- [Contract] Binds: DESIGN.md §5 Persistence & saves, §8 W2/W3/W4.
-- =============================================================================
--
-- Vendored ProfileStore (MadStudio) lives in ServerScriptService/Vendor — never
-- edit it; update by re-vendoring (see WORKFLOW.md).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local ProfileStore = require(script.Parent.Parent:WaitForChild("Vendor"):WaitForChild("ProfileStore")) :: any

local STORE_NAME = "PlayerData_v1"
local KEY_PREFIX = "Player_"
local MAX_RECEIPTS = 50 -- FIFO cap on buffered purchase ids (oldest evicted)

-- ---------------------------------------------------------------------------
-- Schema (DESIGN.md §5 profile shape). Compact slime records use short keys —
-- 200 slimes ≈ 25KB, far under the 4MB value limit.
-- ---------------------------------------------------------------------------

local CURRENT_SCHEMA_VERSION = 1

local PROFILE_TEMPLATE = {
	SchemaVersion = CURRENT_SCHEMA_VERSION,
	Goo = 0,
	Gems = 0,
	Molts = 0,
	-- [slimeId (GUID)] = { Sp = speciesId, Mu = mutation, Nt = nature, St = stage,
	--                      Fed = food progress, T = hatch tick, Lk = locked,
	--                      Src = "egg"|"wild" }
	Slimes = {} :: { [string]: any },
	Ranch = {
		Roster = {} :: { string }, -- slimeIds producing on the plot (cap = Slots)
		Slots = 8,
		-- [decorInstanceId (GUID)] = { Id = decorId, X = 0, Z = 0, RY = 0 }
		Decor = {} :: { [string]: any },
		Likes = 0,
	},
	Squad = {} :: { string }, -- equipped slimeIds (<= SquadSlots; slots NEVER sold)
	SquadSlots = 2,
	Foods = {} :: { [string]: number }, -- special foods are items, not a currency
	Zones = {
		Unlocked = { MeadowWilds = true } :: { [string]: boolean },
		ShrineCooldowns = {} :: { [string]: number },
	},
	Index = {} :: { [string]: boolean }, -- ["speciesId:mutation"] = discovered
	Cosmetics = {
		Owned = {} :: { [string]: boolean },
		Equipped = {} :: { [string]: any },
	},
	Streak = {} :: { [string]: any }, -- DailyRewardService (session 3)
	Quests = {} :: { [string]: any }, -- QuestService (session 3)
	Receipts = {} :: { string }, -- purchase ids, buffered IN-profile (§8 W2)
	Stats = { GooEarned = 0, Hatches = 0, Befriends = 0, PlayTimeMin = 0 },
	LastSeen = 0,
	TradeHistory = {} :: { string }, -- last 20 tradeIds (idempotency + support ledger)
}

export type ProfileData = typeof(PROFILE_TEMPLATE)

-- Migrations run oldest-first on load, each raising SchemaVersion by one:
--   MIGRATIONS[n] upgrades a version-n profile to version n+1.
-- Rules (bump CURRENT_SCHEMA_VERSION only with a migration to match):
--   * Purely additive changes need NO migration — Reconcile fills new template
--     keys on every load. Migrate only to rename/move/transform existing data.
--   * A profile with a version NEWER than this server (a rollback mid-update)
--     is never touched: the player is kicked rather than risk corrupting it.
local MIGRATIONS: { [number]: (data: any) -> () } = {
	-- [1] = function(data) ... end, -- 1 -> 2 (none yet)
}

local function migrate(data: any): (boolean, string?)
	local version = tonumber(data.SchemaVersion) or 1
	if version > CURRENT_SCHEMA_VERSION then
		return false, ("profile is schema v%d but this server only knows v%d"):format(version, CURRENT_SCHEMA_VERSION)
	end
	while version < CURRENT_SCHEMA_VERSION do
		local step = MIGRATIONS[version]
		if not step then
			return false, ("no migration from schema v%d"):format(version)
		end
		step(data)
		version += 1
		data.SchemaVersion = version
	end
	return true, nil
end

-- ---------------------------------------------------------------------------

local DataService = {}

local playerStore: any = nil
local profiles: { [Player]: any } = {}
local loadedCallbacks: { (player: Player, data: ProfileData) -> () } = {}

local function canAccessDataStores(): boolean
	if not RunService:IsStudio() then
		return true
	end
	local ok = pcall(function()
		-- Throws immediately in Studio when API access is disabled.
		DataStoreService:GetDataStore("__ProbeAccess"):GetAsync("__probe")
	end)
	return ok
end

local function onPlayerAdded(player: Player)
	local profile = playerStore:StartSessionAsync(KEY_PREFIX .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- Another server holds the session lock and won't yield it (or the store
		-- is erroring). Never proceed without a locked profile.
		player:Kick("Your data couldn't be loaded safely. Please rejoin in a moment.")
		return
	end

	profile:AddUserId(player.UserId) -- GDPR erasure discoverability
	profile:Reconcile() -- deep-fill missing template keys (additive schema growth)

	local ok, why = migrate(profile.Data)
	if not ok then
		warn(("DataService: %s profile rejected: %s"):format(player.Name, why or "?"))
		profile:EndSession()
		player:Kick("Your save data is from a newer version of the game. Please rejoin later.")
		return
	end

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		-- Lock lost or released elsewhere (e.g. crash-expiry reclaim): the profile
		-- can no longer be written, so the player must not keep playing on it.
		player:Kick("Your data session ended. Please rejoin.")
	end)

	if player.Parent ~= Players then
		profile:EndSession() -- left while the session was starting
		return
	end

	profiles[player] = profile
	for _, callback in ipairs(loadedCallbacks) do
		task.spawn(callback, player, profile.Data)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile.Data.LastSeen = os.time() -- offline-earnings anchor (session 3)
		profile:EndSession() -- final save happens inside ProfileStore
	end
end

function DataService.Init()
	playerStore = ProfileStore.New(STORE_NAME, PROFILE_TEMPLATE)
	if RunService:IsStudio() and not canAccessDataStores() then
		-- No DataStore API access in this Studio session: use ProfileStore's
		-- in-memory mock so play-testing never needs real keys.
		warn("DataService: Studio without DataStore access — using ProfileStore.Mock (nothing persists).")
		playerStore = playerStore.Mock
	end

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player) -- players who joined before Init
	end
	Players.PlayerAdded:Connect(function(player)
		onPlayerAdded(player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- ProfileStore's own BindToClose blocks shutdown until active sessions
	-- finish saving; this sweep just makes the end explicit for any player
	-- PlayerRemoving hasn't reached yet.
	game:BindToClose(function()
		for player, profile in pairs(profiles) do
			profiles[player] = nil
			profile.Data.LastSeen = os.time()
			pcall(function()
				profile:EndSession()
			end)
		end
	end)
end

-- The live profile Data table (the single truth) — nil until loaded / after leave.
function DataService.GetData(player: Player): ProfileData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

-- Yields until the player's profile is loaded (or they leave / timeout).
function DataService.WaitForData(player: Player, timeout: number?): ProfileData?
	local deadline = os.clock() + (timeout or 30)
	while os.clock() < deadline do
		local data = DataService.GetData(player)
		if data then
			return data
		end
		if player.Parent ~= Players then
			return nil
		end
		task.wait(0.1)
	end
	return nil
end

-- Register for profile loads. Fires immediately for already-loaded players, so
-- init order between services and joins can't drop anyone.
function DataService.OnProfileLoaded(callback: (player: Player, data: ProfileData) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in pairs(profiles) do
		task.spawn(callback, player, profile.Data)
	end
end

-- Queue an immediate save. Call after every economy-critical mutation: hatch,
-- befriend, trade commit, shrine roll, Robux purchase (DESIGN.md §5).
function DataService.ForceSave(player: Player)
	local profile = profiles[player]
	if profile then
		profile:Save()
	end
end

-- ---------------------------------------------------------------------------
-- Receipts (§8 W2): purchase ids buffered inside the session-locked profile so
-- grant + record commit in one atomic save. MonetizationService's ProcessReceipt
-- flow: HasReceipt? -> already granted, ack. Otherwise mutate grant into Data,
-- RecordReceipt (force-saves), THEN ack.
-- ---------------------------------------------------------------------------

function DataService.HasReceipt(player: Player, purchaseId: string): boolean
	local data = DataService.GetData(player)
	if not data then
		return false
	end
	return table.find(data.Receipts, purchaseId) ~= nil
end

function DataService.RecordReceipt(player: Player, purchaseId: string)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	if table.find(data.Receipts, purchaseId) then
		return
	end
	table.insert(data.Receipts, purchaseId)
	while #data.Receipts > MAX_RECEIPTS do
		table.remove(data.Receipts, 1)
	end
	DataService.ForceSave(player)
end

-- Whether a profile is loaded and session-locked for this player right now.
-- TradeService must check BOTH parties before opening a trade (§5).
function DataService.IsSessionActive(player: Player): boolean
	return profiles[player] ~= nil
end

-- Test seams (Studio verification only — NOT public API). migrate() is pure
-- over a data table, so execute_luau tests can exercise version upgrades and
-- the newer-than-server rejection without a live profile.
DataService._migrate = migrate
DataService._template = PROFILE_TEMPLATE

return DataService
