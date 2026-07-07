--!strict
-- =============================================================================
-- RateLimiter — token buckets + the abuse-strike ledger behind Net's middleware.
--
-- [Contract] Owns: per-scope token buckets keyed by player (get-or-create; the
--   first creation of a scope fixes its budget/window), the per-player strike
--   ledger, throttled abuse logging, the kick-on-egregious policy, and cleanup
--   of per-player state on leave. Installs itself into Net at Init.
-- [Contract] Never: decides WHAT to limit (budgets are declared at each remote's
--   registration site); never kicks in Studio (dev/test friction); never used to
--   authorize anything — allowing a call is not validating it.
-- [Contract] Binds: DESIGN.md §5 Networking (rate limiting middleware), §5
--   Anti-exploit posture, §8 W1.
-- =============================================================================
--
-- Also usable directly by services for non-remote throttles (e.g. TradeService's
-- completed-trades/day cap can layer on its own bucket scope).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

-- Kick policy: an ordinary player tripping a budget occasionally accumulates a
-- handful of strikes; exploit tooling hammering remotes accumulates hundreds per
-- minute. Kick when the rolling window count crosses the threshold.
local STRIKE_WINDOW = 60 -- seconds; rolling window for the strike count
local KICK_STRIKES = 120 -- strikes within the window that trigger a kick
local WARN_INTERVAL = 1 -- seconds; per-player log throttle

export type Bucket = {
	allow: (self: Bucket, player: Player) -> boolean,
}

type StrikeLedger = { count: number, windowStart: number }
type TokenState = { tokens: number, last: number }
type BucketInternal = {
	budget: number,
	window: number,
	state: { [Player]: TokenState },
}

local RateLimiter = {}

local buckets: { [string]: BucketInternal } = {}
local bucketHandles: { [string]: Bucket } = {}
local strikes: { [Player]: StrikeLedger } = {}
local lastWarn: { [Player]: number } = {}

-- Get-or-create the token bucket for `scope` ("Net:<RemoteName>" for remotes).
-- The first creation fixes budget/window; later calls with different numbers
-- warn and keep the original (subscribers to one remote share one bucket).
function RateLimiter.bucket(scope: string, budget: number, window: number): Bucket
	assert(budget >= 1 and window > 0, "RateLimiter.bucket: budget must be >= 1 and window > 0")

	local existing = buckets[scope]
	if existing then
		if existing.budget ~= budget or existing.window ~= window then
			warn(
				("RateLimiter.bucket(%q): already created with budget=%d window=%.2f; keeping the original."):format(
					scope,
					existing.budget,
					existing.window
				)
			)
		end
		return bucketHandles[scope] :: Bucket
	end

	local internal: BucketInternal = { budget = budget, window = window, state = {} }
	buckets[scope] = internal

	local bucket = {} :: Bucket
	bucket.allow = function(_self: Bucket, player: Player): boolean
		local now = os.clock()
		local s = internal.state[player]
		if not s then
			s = { tokens = internal.budget, last = now }
			internal.state[player] = s
		end
		local refill = (now - s.last) * (internal.budget / internal.window)
		s.tokens = math.min(internal.budget, s.tokens + refill)
		s.last = now
		if s.tokens >= 1 then
			s.tokens -= 1
			return true
		end
		return false
	end

	bucketHandles[scope] = bucket
	return bucket
end

-- Record one over-budget / invalid-args hit for `player`. Logs (throttled) and
-- kicks when the rolling-window count crosses KICK_STRIKES — except in Studio,
-- where abuse is our own testing and a kick would just be friction.
function RateLimiter.strike(player: Player, scope: string)
	local now = os.clock()
	local existing = strikes[player]
	local ledger: StrikeLedger
	if existing == nil or now - existing.windowStart > STRIKE_WINDOW then
		ledger = { count = 0, windowStart = now }
		strikes[player] = ledger
	else
		ledger = existing
	end
	ledger.count += 1

	local last = lastWarn[player]
	if not last or now - last >= WARN_INTERVAL then
		lastWarn[player] = now
		warn(
			("RateLimiter: %s struck on %s (%d strikes in the last %ds)"):format(
				player.Name,
				scope,
				ledger.count,
				STRIKE_WINDOW
			)
		)
	end

	if ledger.count >= KICK_STRIKES and not RunService:IsStudio() then
		strikes[player] = nil
		warn(
			("RateLimiter: kicking %s for remote abuse (%d strikes in %ds)"):format(
				player.Name,
				ledger.count,
				STRIKE_WINDOW
			)
		)
		player:Kick("Disconnected for sending too many requests.")
	end
end

-- Current rolling-window strike count (analytics / TestCommandService).
function RateLimiter.strikeCount(player: Player): number
	local ledger = strikes[player]
	if not ledger or os.clock() - ledger.windowStart > STRIKE_WINDOW then
		return 0
	end
	return ledger.count
end

local function forget(player: Player)
	for _, internal in pairs(buckets) do
		internal.state[player] = nil
	end
	strikes[player] = nil
	lastWarn[player] = nil
end

function RateLimiter.Init()
	-- Net's server middleware is fail-closed: it refuses registrations until a
	-- limiter is installed, which is why RateLimiter is first in the boot order.
	Net.useRateLimiter(RateLimiter)
	Players.PlayerRemoving:Connect(forget)
end

return RateLimiter
