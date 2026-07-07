--!strict
-- =============================================================================
-- TestCommandService — Studio/creator-gated debug commands + Net test harness.
--
-- [Contract] Owns: chat commands for development (grant Goo/Gems, force-save,
--   dump profile summaries) and the DebugEcho/DebugPing remotes used to exercise
--   the Net middleware from execute_luau. Every entry point is gated to Studio
--   or the place creator — twice: at the chat/remote boundary AND inside each
--   handler.
-- [Contract] Never: reachable by ordinary players in production; never a
--   gameplay surface (session 3 rebuilds the command set: grant slime, force
--   event, unlock zone, force wild spawn — always through the owning service,
--   never by poking profile internals those services own).
-- [Contract] Binds: DESIGN.md §6 reuse map (TestCommandService ADAPT), §5
--   Anti-exploit posture.
-- =============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Attrs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attrs"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local RateLimiter = require(script.Parent:WaitForChild("RateLimiter"))

local TestCommandService = {}

local function isAllowed(player: Player): boolean
	return RunService:IsStudio() or player.UserId == game.CreatorId
end

-- "1k" / "2.5m" / "3b" style amounts, matching the ClickGame command grammar.
local function parseAmount(text: string): number?
	local amountText, suffix = string.match(string.lower(text), "^%s*(%-?[%d%.]+)%s*([kmb]?)%s*$")
	local amount = tonumber(amountText)
	if not amount then
		return nil
	end

	if suffix == "k" then
		amount *= 1000
	elseif suffix == "m" then
		amount *= 1000000
	elseif suffix == "b" then
		amount *= 1000000000
	end

	return math.floor(amount)
end

local function handleCommand(player: Player, message: string)
	if not isAllowed(player) then
		return
	end

	-- !goo <n> — set Goo. Direct profile pokes are acceptable ONLY here and only
	-- until ProductionService/HatchService own these fields (session 3 replaces
	-- these with service-routed grants).
	local amountText = string.match(message, "^!goo%s+(.+)$")
	if amountText then
		local amount = parseAmount(amountText)
		local data = DataService.GetData(player)
		if amount and data then
			data.Goo = amount
			player:SetAttribute(Attrs.Goo, amount) -- projection only, never read back
			DataService.ForceSave(player)
			print(("[TestCommand] set Goo for %s to %d"):format(player.Name, amount))
		end
		return
	end

	-- !gems <n> — set Gems.
	amountText = string.match(message, "^!gems%s+(.+)$")
	if amountText then
		local amount = parseAmount(amountText)
		local data = DataService.GetData(player)
		if amount and data then
			data.Gems = amount
			player:SetAttribute(Attrs.Gems, amount)
			DataService.ForceSave(player)
			print(("[TestCommand] set Gems for %s to %d"):format(player.Name, amount))
		end
		return
	end

	-- !save — force-save now.
	if message == "!save" then
		DataService.ForceSave(player)
		print(("[TestCommand] force-saved %s"):format(player.Name))
		return
	end

	-- !data — print a one-line profile summary to the server log.
	if message == "!data" then
		local data = DataService.GetData(player)
		if data then
			local slimeCount = 0
			for _ in pairs(data.Slimes) do
				slimeCount += 1
			end
			print(
				("[TestCommand] %s: schema v%d, Goo=%d, Gems=%d, Molts=%d, slimes=%d, roster=%d/%d, squad=%d/%d, strikes=%d"):format(
					player.Name,
					data.SchemaVersion,
					data.Goo,
					data.Gems,
					data.Molts,
					slimeCount,
					#data.Ranch.Roster,
					data.Ranch.Slots,
					#data.Squad,
					data.SquadSlots,
					RateLimiter.strikeCount(player)
				)
			)
		else
			print(("[TestCommand] %s: no profile loaded"):format(player.Name))
		end
		return
	end
end

function TestCommandService.Init()
	local function hookPlayer(player: Player)
		player.Chatted:Connect(function(message)
			handleCommand(player, message)
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)

	-- Net middleware test harness (also the reference registration style).
	-- DebugEcho: request/response round trip through validation.
	Net.onInvoke(Net.Names.DebugEcho, function(player: Player, text: string)
		if not isAllowed(player) then
			return { success = false, message = "Not allowed." }
		end
		return { success = true, echo = text }
	end, {
		budget = 5,
		window = 1,
		validator = Net.T.args(Net.T.string(100)),
	})

	-- DebugPing: deliberately tight budget (3 per 5s) so the rate limiter is
	-- trivially trippable from a test; each accepted ping bumps a player
	-- attribute a test can read back.
	Net.on(Net.Names.DebugPing, function(player: Player)
		if not isAllowed(player) then
			return
		end
		local count = player:GetAttribute(Attrs.DebugPingCount)
		player:SetAttribute(Attrs.DebugPingCount, (if typeof(count) == "number" then count else 0) + 1)
	end, {
		budget = 3,
		window = 5,
		validator = Net.T.none,
	})
end

return TestCommandService
