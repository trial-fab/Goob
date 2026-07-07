--!strict
-- =============================================================================
-- RemoteNames — single source of truth for every client<->server remote name.
--
-- [Contract] Owns: the canonical spelling of every remote. Reference one as
--   `Net.Names.BuyEgg` — a typo'd key resolves to nil and Net errors loudly at
--   the call site instead of a client hanging forever on WaitForChild.
-- [Contract] Never: carries values, budgets, or handler logic (budgets/validators
--   are declared where the handler registers, in the owning service); never a
--   remote outside this table.
-- [Contract] Binds: DESIGN.md §5 Networking.
-- =============================================================================
--
-- Grows with sessions 2–3 as services land. Conventions:
--   * Economy/purchase-like actions are RemoteFunctions (Net.fn/onInvoke) that
--     always return a result table — never fire-and-forget.
--   * Fire-and-forget RemoteEvents are for non-economic signals only.
--   * Remotes carry intent + ids, never amounts (server derives all values).

return table.freeze({
	-- client -> server request/response (RemoteFunction; result table returned)
	BuyEgg = "BuyEgg", -- (eggId) -> hatch result(s); server rolls species/mutation/nature
	FeedSlime = "FeedSlime", -- (slimeId, foodId?)
	CollectBlob = "CollectBlob", -- (blobId) validated against server-known blob records
	ReleaseSlime = "ReleaseSlime", -- (slimeId) refund is server-derived
	RenameSlime = "RenameSlime", -- (slimeId, name) name filtered server-side
	SetSlimeLocked = "SetSlimeLocked", -- (slimeId, locked)
	SetRanchState = "SetRanchState", -- (slimeId, state) ranch <-> storage roster toggle
	EquipSquad = "EquipSquad", -- (slimeIds) full desired squad; server validates slots
	BefriendAttempt = "BefriendAttempt", -- (wildId, foodId)
	GatherNode = "GatherNode", -- (nodeId)
	ShrineRoll = "ShrineRoll", -- (shrineId, slimeId, offering foodIds)
	BuyDecor = "BuyDecor", -- (decorId)
	PlaceDecor = "PlaceDecor", -- (decorInstanceId, gridX, gridZ, rotY)
	RecallDecor = "RecallDecor", -- (decorInstanceId)
	LikeRanch = "LikeRanch", -- (plotOwnerUserId)
	ClaimDailyReward = "ClaimDailyReward",
	ClaimOfflineEarnings = "ClaimOfflineEarnings",
	ClaimQuest = "ClaimQuest", -- (questId)

	-- trade state machine (DESIGN.md §5 Trading integrity; all RemoteFunctions)
	TradeInvite = "TradeInvite", -- (targetUserId)
	TradeRespond = "TradeRespond", -- (tradeId, accept)
	TradeSetOffer = "TradeSetOffer", -- (tradeId, slimeIds) regresses state + 3s lockout
	TradeConfirm = "TradeConfirm", -- (tradeId)
	TradeAccept = "TradeAccept", -- (tradeId)
	TradeCancel = "TradeCancel", -- (tradeId)

	-- server -> client pushes (RemoteEvent)
	ProductionEarnings = "ProductionEarnings", -- ONE batched per-player tick (§8 W5)
	BlobSpawned = "BlobSpawned",
	BlobRemoved = "BlobRemoved",
	WildSpawnChanged = "WildSpawnChanged",
	TradeStateChanged = "TradeStateChanged",
	EventStateChanged = "EventStateChanged", -- Slime Rain / Lucky Hour-let / Wild Surge
	QuestProgress = "QuestProgress",
	OfflineEarningsReady = "OfflineEarningsReady", -- claim modal payload on join

	-- debug / test harness only (server handlers are gated to Studio or the
	-- place creator; also used to exercise the Net middleware from execute_luau)
	DebugEcho = "DebugEcho", -- RemoteFunction: echoes args back in a result table
	DebugPing = "DebugPing", -- RemoteEvent: tight budget, increments an attribute
})
