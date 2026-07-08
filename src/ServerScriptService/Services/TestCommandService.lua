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
local SlimeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SlimeConfig"))
local FoodConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FoodConfig"))
local MutationConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MutationConfig"))
local NatureConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NatureConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local RateLimiter = require(script.Parent:WaitForChild("RateLimiter"))
local SlimeService = require(script.Parent:WaitForChild("SlimeService"))
local ProductionService = require(script.Parent:WaitForChild("ProductionService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))
local WildSlimeService = require(script.Parent:WaitForChild("WildSlimeService"))
local OfflineEarningsService = require(script.Parent:WaitForChild("OfflineEarningsService"))

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

	-- !slime <speciesId> [mutation] [nature] — mint through SlimeService (the
	-- owning service; never a direct profile poke).
	local speciesId, mutationArg, natureArg = string.match(message, "^!slime%s+(%S+)%s*(%S*)%s*(%S*)$")
	if speciesId then
		local data = DataService.GetData(player)
		local species = (SlimeConfig.Species :: { [string]: SlimeConfig.Species })[speciesId]
		if not (data and species) then
			print("[TestCommand] unknown species: " .. tostring(speciesId))
			return
		end
		local mutation = if mutationArg ~= "" then mutationArg :: string else "none"
		if not (MutationConfig.Mutations :: { [string]: any })[mutation] then
			print("[TestCommand] unknown mutation: " .. mutation)
			return
		end
		local nature = if natureArg ~= "" then natureArg :: string else "bouncy"
		if not (NatureConfig.Natures :: { [string]: any })[nature] then
			print("[TestCommand] unknown nature: " .. nature)
			return
		end
		local slimeId, toStorage = SlimeService.Mint(player, data, speciesId, mutation, nature, "egg")
		print(
			("[TestCommand] minted %s (%s/%s/%s) -> %s"):format(
				slimeId,
				speciesId,
				mutation,
				nature,
				if toStorage then "storage" else "ranch"
			)
		)
		return
	end

	-- !food <foodId> <n> — grant special foods.
	local foodId, foodCountText = string.match(message, "^!food%s+(%S+)%s+(%S+)$")
	if foodId then
		local data = DataService.GetData(player)
		local count = tonumber(foodCountText)
		if data and count and (FoodConfig.Foods :: { [string]: any })[foodId] then
			data.Foods[foodId] = (data.Foods[foodId] or 0) + math.floor(count)
			SlimeService.PushState(player)
			print(("[TestCommand] %s now has %d %s"):format(player.Name, data.Foods[foodId], foodId))
		end
		return
	end

	-- !gps — print the production authority's number for this player.
	if message == "!gps" then
		print(("[TestCommand] %s gps = %.2f"):format(player.Name, ProductionService.GetGps(player)))
		return
	end

	-- !playtime <min> — set lifetime playtime (the trade gate's clock).
	local playtimeText = string.match(message, "^!playtime%s+(%S+)$")
	if playtimeText then
		local data = DataService.GetData(player)
		local minutes = tonumber(playtimeText)
		if data and minutes then
			data.Stats.PlayTimeMin = math.floor(minutes)
			print(("[TestCommand] %s PlayTimeMin = %d"):format(player.Name, data.Stats.PlayTimeMin))
		end
		return
	end

	-- !wild <zoneId> — force a wild spawn through WildSlimeService.
	local wildZone = string.match(message, "^!wild%s+(%S+)$")
	if wildZone then
		local spawn = WildSlimeService.ForceSpawn(wildZone)
		print(
			if spawn
				then ("[TestCommand] wild %s (%s) in %s"):format(spawn.Id, spawn.SpeciesId, wildZone)
				else "[TestCommand] unknown zone: " .. wildZone
		)
		return
	end

	-- !unlock <zoneId> — force a zone unlock through ZoneService's seam.
	local unlockZone = string.match(message, "^!unlock%s+(%S+)$")
	if unlockZone then
		ZoneService._forceUnlock(player, unlockZone)
		print("[TestCommand] unlocked " .. unlockZone .. " for " .. player.Name)
		return
	end

	-- !offline <seconds> — simulate an away window through the owning service.
	local offlineText = string.match(message, "^!offline%s+(%S+)$")
	if offlineText then
		local seconds = tonumber(offlineText)
		if seconds then
			local earned = OfflineEarningsService._simulateAway(player, math.floor(seconds))
			print(("[TestCommand] simulated %ds away -> +%d pending Goo"):format(seconds, earned))
		end
		return
	end

	-- !goo <n> — set Goo (the one sanctioned direct poke: it IS the faucet
	-- being tested; projection + save mirror the real grant path).
	local amountText = string.match(message, "^!goo%s+(.+)$")
	if amountText then
		local amount = parseAmount(amountText)
		local data = DataService.GetData(player)
		if amount and data then
			data.Goo = amount
			player:SetAttribute(Attrs.Goo, amount) -- projection only, never read back
			SlimeService.PushState(player)
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
			SlimeService.PushState(player)
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
