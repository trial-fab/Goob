--!strict
-- =============================================================================
-- TradeService — the escrowed trade state machine + tradeId ledger.
--
-- [Contract] Owns: the escrowed trade state machine (Invited -> Negotiating ->
--   BothConfirmed(3s lock) -> BothAccepted -> Committing -> Done/Aborted), the
--   commit protocol (validate ownership/locks/squad/shrine, write tradeId +
--   payload to BOTH TradeHistories AND move slime records in one in-memory
--   mutation, force-save both), trade rate limits (1 active, 20/day), and the
--   ~30-min-playtime trust gate.
-- [Contract] Never: cross-server trades (both profiles session-locked by THIS
--   server — the constraint that removes the dupe surface); never currency in
--   trades at MVP (the #1 scam/dupe vector); never commits without both
--   sessions active (DataService.IsSessionActive); tradeIds make commits
--   idempotent and are NEVER reused.
-- [Contract] Binds: DESIGN.md §5 Trading integrity — re-read it before ANY
--   change here; §2 trust rails; §9 M2 exit-gate dupe tests.
-- =============================================================================
--
-- Why this is safe (§5, condensed): both profiles are session-locked by THIS
-- server, so the commit is a plain in-memory swap on one machine — no
-- cross-server two-phase commit exists to get wrong. Escrow = offered slimes
-- are marked busy in SlimeService for the whole trade, so release/feed/equip/
-- shrine/second-trade can't touch them mid-flight. The tradeId written into
-- both TradeHistories in the SAME mutation as the record move makes a re-sent
-- commit a no-op and gives support a ledger.
--
-- Any offer edit regresses BothConfirmed -> Negotiating, clears both confirms,
-- and starts a 3s input lockout (anti-switch-scam, §2 trust rails). Leave or
-- disconnect in any state before Committing aborts cleanly.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local RanchConfig = require(Shared:WaitForChild("RanchConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local SlimeService = require(script.Parent:WaitForChild("SlimeService"))

local MAX_OFFER = 4 -- §7 trade window: 4 slots per side
local EDIT_LOCK_SECONDS = 3
local TRADES_PER_DAY = 20 -- scam-farm throttle (§5)
local PLAYTIME_GATE_MIN = 30 -- §2 trust rails
local TRADE_HISTORY_KEEP = 20
local INVITE_TTL_SECONDS = 60

local TradeService = {}

type TradeState = "Invited" | "Negotiating" | "BothConfirmed" | "Committing" | "Done" | "Aborted"

type Trade = {
	Id: string,
	A: Player, -- inviter
	B: Player, -- invitee
	State: TradeState,
	Offers: { [Player]: { string } },
	Confirmed: { [Player]: boolean },
	Accepted: { [Player]: boolean },
	LockUntil: number, -- os.clock(); confirms/accepts refused before this
	CreatedAt: number,
}

local trades: { [string]: Trade } = {}
local activeTradeOf: { [Player]: string } = {}
-- Completed-trades/day throttle, in-memory: [userId] = { day, count }.
local completedToday: { [number]: { day: number, count: number } } = {}

-- ---------------------------------------------------------------------------
-- Escrow helpers.
-- ---------------------------------------------------------------------------

local function setOfferBusy(offer: { string }, busyState: boolean)
	for _, slimeId in offer do
		SlimeService.SetBusy(slimeId, busyState)
	end
end

local function otherParty(trade: Trade, player: Player): Player
	return if player == trade.A then trade.B else trade.A
end

local function isParty(trade: Trade, player: Player): boolean
	return player == trade.A or player == trade.B
end

-- One view per recipient (their side is "You"). Sent on every transition —
-- the client renders state, it never decides it.
local function broadcast(trade: Trade)
	for _, player in { trade.A, trade.B } do
		local partner = otherParty(trade, player)
		Net.fireClient(Net.Names.TradeStateChanged, player, {
			TradeId = trade.Id,
			State = trade.State,
			PartnerName = partner.DisplayName,
			PartnerUserId = partner.UserId,
			YourOffer = trade.Offers[player],
			TheirOffer = trade.Offers[partner],
			YouConfirmed = trade.Confirmed[player],
			TheyConfirmed = trade.Confirmed[partner],
			LockRemaining = math.max(0, trade.LockUntil - os.clock()),
		})
	end
end

local function finish(trade: Trade, state: TradeState)
	trade.State = state
	setOfferBusy(trade.Offers[trade.A], false)
	setOfferBusy(trade.Offers[trade.B], false)
	activeTradeOf[trade.A] = nil
	activeTradeOf[trade.B] = nil
	trades[trade.Id] = nil
	broadcast(trade)
end

local function abort(trade: Trade)
	if trade.State ~= "Done" and trade.State ~= "Aborted" then
		finish(trade, "Aborted")
	end
end

local function tradesCompletedToday(player: Player): number
	local today = math.floor(os.time() / 86400)
	local entry = completedToday[player.UserId]
	return if entry and entry.day == today then entry.count else 0
end

local function recordCompleted(player: Player)
	local today = math.floor(os.time() / 86400)
	local entry = completedToday[player.UserId]
	if not entry or entry.day ~= today then
		completedToday[player.UserId] = { day = today, count = 1 }
	else
		entry.count += 1
	end
end

-- ---------------------------------------------------------------------------
-- Commit protocol (§5 — the part that must be right the first time).
-- ---------------------------------------------------------------------------

-- Re-validate one side's offer at commit time. Everything can have changed
-- since Negotiating (that is the point of re-checking inside Committing).
local function validateSide(giver: Player, offer: { string }): (boolean, string?)
	local data = DataService.GetData(giver)
	if not data or not DataService.IsSessionActive(giver) then
		return false, "session lost"
	end
	for _, slimeId in offer do
		local record = data.Slimes[slimeId]
		if not record then
			return false, "slime no longer owned"
		end
		if record.Lk then
			return false, "slime is locked"
		end
		if SlimeService.IsEquipped(data, slimeId) then
			return false, "slime is equipped"
		end
		-- NOT IsBusy: the trade's own escrow marks these busy. Any OTHER
		-- system's hold was refused at offer time and can't start now (busy).
	end
	return true, nil
end

local function commit(trade: Trade): (boolean, string?)
	local dataA = DataService.GetData(trade.A)
	local dataB = DataService.GetData(trade.B)
	if not (dataA and dataB) then
		return false, "session lost"
	end

	-- Idempotency: a re-entered commit (retry, duplicate accept) is a no-op
	-- success — the ledger says it already happened.
	if table.find(dataA.TradeHistory, trade.Id) or table.find(dataB.TradeHistory, trade.Id) then
		return true, nil
	end

	local okA, whyA = validateSide(trade.A, trade.Offers[trade.A])
	if not okA then
		return false, "your offer: " .. (whyA or "?")
	end
	local okB, whyB = validateSide(trade.B, trade.Offers[trade.B])
	if not okB then
		return false, "their offer: " .. (whyB or "?")
	end

	-- Storage caps for the RECEIVING side (net of what each gives away).
	local ownedA = SlimeService.CountOwned(dataA) - #trade.Offers[trade.A] + #trade.Offers[trade.B]
	local ownedB = SlimeService.CountOwned(dataB) - #trade.Offers[trade.B] + #trade.Offers[trade.A]
	if ownedA > RanchConfig.StorageCap or ownedB > RanchConfig.StorageCap then
		return false, "a storage cap would be exceeded"
	end

	-- THE atomic mutation: capture records, move them, and write the ledger —
	-- all before any yield. ProfileStore's session locks guarantee no other
	-- server writes a conflicting view even if the save lands later (§5).
	local movedToB: { [string]: SlimeService.SlimeRecord } = {}
	local movedToA: { [string]: SlimeService.SlimeRecord } = {}
	for _, slimeId in trade.Offers[trade.A] do
		movedToB[slimeId] = dataA.Slimes[slimeId] :: SlimeService.SlimeRecord
	end
	for _, slimeId in trade.Offers[trade.B] do
		movedToA[slimeId] = dataB.Slimes[slimeId] :: SlimeService.SlimeRecord
	end
	for slimeId in movedToB do
		SlimeService.Remove(trade.A, dataA, slimeId)
	end
	for slimeId in movedToA do
		SlimeService.Remove(trade.B, dataB, slimeId)
	end
	for slimeId, record in movedToB do
		SlimeService.AddExisting(trade.B, dataB, slimeId, record)
	end
	for slimeId, record in movedToA do
		SlimeService.AddExisting(trade.A, dataA, slimeId, record)
	end

	for _, data in { dataA, dataB } do
		table.insert(data.TradeHistory, trade.Id)
		while #data.TradeHistory > TRADE_HISTORY_KEEP do
			table.remove(data.TradeHistory, 1)
		end
	end

	DataService.ForceSave(trade.A)
	DataService.ForceSave(trade.B)
	recordCompleted(trade.A)
	recordCompleted(trade.B)
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Remote handlers.
-- ---------------------------------------------------------------------------

local function gateCheck(player: Player): (boolean, string?)
	local data = DataService.GetData(player)
	if not data or not DataService.IsSessionActive(player) then
		return false, "Loading..."
	end
	if data.Stats.PlayTimeMin < PLAYTIME_GATE_MIN then
		return false, ("Trading unlocks after %d minutes of playtime."):format(PLAYTIME_GATE_MIN)
	end
	if tradesCompletedToday(player) >= TRADES_PER_DAY then
		return false, "You've hit today's trade limit."
	end
	if activeTradeOf[player] then
		return false, "You're already in a trade."
	end
	return true, nil
end

local function onTradeInvite(player: Player, targetUserId: number): { [string]: any }
	local ok, why = gateCheck(player)
	if not ok then
		return { success = false, message = why }
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return { success = false, message = "Player not found." }
	end
	local targetOk, targetWhy = gateCheck(target)
	if not targetOk then
		return { success = false, message = "They can't trade right now (" .. (targetWhy or "?") .. ")" }
	end

	local trade: Trade = {
		Id = HttpService:GenerateGUID(false),
		A = player,
		B = target,
		State = "Invited",
		Offers = { [player] = {}, [target] = {} },
		Confirmed = { [player] = false, [target] = false },
		Accepted = { [player] = false, [target] = false },
		LockUntil = 0,
		CreatedAt = os.clock(),
	}
	trades[trade.Id] = trade
	activeTradeOf[player] = trade.Id
	activeTradeOf[target] = trade.Id
	broadcast(trade)

	-- Unanswered invites decay so neither side is stuck "in a trade".
	task.delay(INVITE_TTL_SECONDS, function()
		local live = trades[trade.Id]
		if live and live.State == "Invited" then
			abort(live)
		end
	end)
	return { success = true, tradeId = trade.Id }
end

local function onTradeRespond(player: Player, tradeId: string, accept: boolean): { [string]: any }
	local trade = trades[tradeId]
	if not trade or player ~= trade.B or trade.State ~= "Invited" then
		return { success = false, message = "No pending invite." }
	end
	if not accept then
		abort(trade)
		return { success = true }
	end
	trade.State = "Negotiating"
	broadcast(trade)
	return { success = true }
end

local function onTradeSetOffer(player: Player, tradeId: string, slimeIds: { string }): { [string]: any }
	local trade = trades[tradeId]
	if not trade or not isParty(trade, player) then
		return { success = false, message = "No such trade." }
	end
	if trade.State ~= "Negotiating" and trade.State ~= "BothConfirmed" then
		return { success = false, message = "The trade can't be edited now." }
	end
	if #slimeIds > MAX_OFFER then
		return { success = false, message = ("Offers hold %d slimes."):format(MAX_OFFER) }
	end

	local data = DataService.GetData(player)
	if not data then
		return { success = false, message = "Loading..." }
	end
	-- Release the old escrow FIRST so re-offering the same slime validates.
	setOfferBusy(trade.Offers[player], false)

	local seen: { [string]: boolean } = {}
	for _, slimeId in slimeIds do
		if seen[slimeId] or not data.Slimes[slimeId] or SlimeService.IsHeld(data, slimeId) then
			setOfferBusy(trade.Offers[player], true) -- restore the old escrow
			return { success = false, message = "A slime in that offer isn't available." }
		end
		seen[slimeId] = true
	end

	trade.Offers[player] = table.clone(slimeIds)
	setOfferBusy(trade.Offers[player], true)

	-- Any edit regresses the machine + arms the anti-switch-scam lockout (§2).
	trade.State = "Negotiating"
	trade.Confirmed[trade.A] = false
	trade.Confirmed[trade.B] = false
	trade.Accepted[trade.A] = false
	trade.Accepted[trade.B] = false
	trade.LockUntil = os.clock() + EDIT_LOCK_SECONDS
	broadcast(trade)
	return { success = true }
end

local function onTradeConfirm(player: Player, tradeId: string): { [string]: any }
	local trade = trades[tradeId]
	if not trade or not isParty(trade, player) or trade.State ~= "Negotiating" then
		return { success = false, message = "Nothing to confirm." }
	end
	if os.clock() < trade.LockUntil then
		return { success = false, message = "The offer just changed — wait a moment." }
	end
	trade.Confirmed[player] = true
	if trade.Confirmed[trade.A] and trade.Confirmed[trade.B] then
		trade.State = "BothConfirmed"
		trade.LockUntil = os.clock() + EDIT_LOCK_SECONDS -- accept gate: 3s of stillness
	end
	broadcast(trade)
	return { success = true }
end

local function onTradeAccept(player: Player, tradeId: string): { [string]: any }
	local trade = trades[tradeId]
	if not trade or not isParty(trade, player) then
		-- The trade may have JUST committed and been retired: answer a re-sent
		-- accept from the ledger so the client sees success, not a mystery.
		local data = DataService.GetData(player)
		if data and table.find(data.TradeHistory, tradeId) then
			return { success = true, done = true }
		end
		return { success = false, message = "Nothing to accept." }
	end
	if trade.State ~= "BothConfirmed" then
		return { success = false, message = "Confirm first." }
	end
	if os.clock() < trade.LockUntil then
		return { success = false, message = "Hold on — the confirm lock is still counting." }
	end

	trade.Accepted[player] = true
	if not (trade.Accepted[trade.A] and trade.Accepted[trade.B]) then
		broadcast(trade)
		return { success = true, waiting = true }
	end

	trade.State = "Committing"
	broadcast(trade)
	local ok, why = commit(trade)
	if ok then
		finish(trade, "Done")
		return { success = true, done = true }
	end
	abort(trade)
	return { success = false, message = "Trade failed: " .. (why or "?") }
end

local function onTradeCancel(player: Player, tradeId: string): { [string]: any }
	local trade = trades[tradeId]
	if not trade or not isParty(trade, player) then
		return { success = false, message = "No such trade." }
	end
	if trade.State == "Committing" or trade.State == "Done" then
		return { success = false, message = "Too late to cancel." }
	end
	abort(trade)
	return { success = true }
end

function TradeService.Init()
	-- Leave/disconnect before Committing = clean abort (§5 state machine).
	Players.PlayerRemoving:Connect(function(player)
		local tradeId = activeTradeOf[player]
		local trade = if tradeId then trades[tradeId] else nil
		if trade and trade.State ~= "Committing" then
			abort(trade)
		end
		completedToday[player.UserId] = nil
	end)

	Net.onInvoke(Net.Names.TradeInvite, onTradeInvite, {
		budget = 2,
		window = 5,
		validator = Net.T.args(Net.T.integer(1)),
	})
	Net.onInvoke(Net.Names.TradeRespond, onTradeRespond, {
		budget = 3,
		window = 5,
		validator = Net.T.args(Net.T.guid, Net.T.boolean),
	})
	Net.onInvoke(Net.Names.TradeSetOffer, onTradeSetOffer, {
		budget = 5,
		window = 1,
		validator = Net.T.args(Net.T.guid, Net.T.arrayOf(Net.T.guid, MAX_OFFER)),
	})
	Net.onInvoke(Net.Names.TradeConfirm, onTradeConfirm, {
		budget = 3,
		window = 1,
		validator = Net.T.args(Net.T.guid),
	})
	Net.onInvoke(Net.Names.TradeAccept, onTradeAccept, {
		budget = 3,
		window = 1,
		validator = Net.T.args(Net.T.guid),
	})
	Net.onInvoke(Net.Names.TradeCancel, onTradeCancel, {
		budget = 3,
		window = 1,
		validator = Net.T.args(Net.T.guid),
	})
end

return TradeService
