--!strict
-- =============================================================================
-- Net — the single client<->server remote façade.
--
-- [Contract] Owns: RemoteEvent/RemoteFunction creation, naming, caching, and
--   access; the server-side middleware on every registered handler — per-player
--   per-remote token-bucket rate limiting and declarative argument validation
--   (Net.T combinators) — plus pcall isolation so a bad handler or bad client
--   input can never error into game code.
-- [Contract] Never: contains game logic; never grants value from client-supplied
--   amounts (handlers receive intent + ids only — validators enforce shapes);
--   never bypassed — no other script may touch Remote* instances directly.
-- [Contract] Binds: DESIGN.md §5 Networking, §5 Anti-exploit posture, §8 W1.
-- =============================================================================
--
-- Ported from ClickGame (get-or-create remotes, Net.Names registry, pcall-
-- isolated multi-subscriber events, result-table RemoteFunctions) and upgraded
-- with the two middleware layers ClickGame lacked:
--
--   1. RATE LIMITING — every server-side registration gets a token bucket per
--      player per remote (default 10 calls burst, refilled 10/s). Exceeding the
--      budget drops the call and records a strike; egregious abuse kicks (the
--      strike ledger and kick policy live in Services/RateLimiter, installed at
--      boot via Net.useRateLimiter — Server.server.lua inits RateLimiter first).
--      Tighter budgets are declared at the handler site, e.g. economy remotes:
--        Net.onInvoke(Net.Names.BuyEgg, handler, { budget = 3, window = 1, ... })
--      The first registration for a remote fixes its budget; later subscribers
--      share the same bucket.
--
--   2. ARGUMENT VALIDATION — handlers declare a validator that runs before the
--      handler; invalid args are dropped (events) or answered with
--      { success = false } (functions), and never error into game code:
--        { validator = Net.T.args(Net.T.guid, Net.T.integer(1, 100)) }
--      Combinators: T.number/T.integer(min?, max?), T.string(maxLen?),
--      T.boolean, T.enum{...}, T.guid, T.optional(check), T.any, T.none.
--
-- Design notes kept from ClickGame:
--   * Named per-feature remotes (not multiplexed) so channels stay independent.
--   * Net.event/Net.fn are get-or-create on the server, WaitForChild on the
--     client; a typo'd Names key resolves to nil and errors loudly here.
--   * RemoteFunctions are the standard for economy request/response ("always
--     return a result table"); fire-and-forget events are for non-economic
--     signals only (DESIGN.md §5).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}
Net.Names = require(script.Parent:WaitForChild("RemoteNames"))

local IS_SERVER = RunService:IsServer()
local REMOTES_FOLDER_NAME = "Remotes"

-- Middleware defaults: the ceiling for remotes that don't declare a budget.
-- UI-driven actions should never legitimately exceed this; economy remotes
-- declare tighter budgets at their registration site (DESIGN.md §5 examples:
-- BuyEgg <=3/s, Collect <=10/s, Feed <=5/s, Gather <=3/s, Befriend <=1/s).
local DEFAULT_BUDGET = 10
local DEFAULT_WINDOW = 1

type Check = (value: any) -> (boolean, string?)
type Validator = (...any) -> (boolean, string?)

export type NetOpts = {
	budget: number?, -- max calls per window (token-bucket capacity); default 10
	window: number?, -- refill window in seconds; default 1
	validator: Validator?, -- Net.T.args(...) or any (...any) -> (ok, why?)
}

type BucketLike = { allow: (self: BucketLike, player: Player) -> boolean }
export type RateLimiterLike = {
	bucket: (scope: string, budget: number, window: number) -> BucketLike,
	strike: (player: Player, scope: string) -> (),
}

local eventCache: { [string]: RemoteEvent } = {}
local fnCache: { [string]: RemoteFunction } = {}
local remotesFolder: Folder? = nil

-- Installed by RateLimiter.Init() (first service in the boot order). Server-side
-- registrations hard-require it: rate limiting is fail-closed, not optional.
local rateLimiter: RateLimiterLike? = nil

function Net.useRateLimiter(limiter: RateLimiterLike)
	assert(IS_SERVER, "Net.useRateLimiter is server-only")
	rateLimiter = limiter
end

local function requireRateLimiter(context: string): RateLimiterLike
	local limiter = rateLimiter
	if not limiter then
		error(
			("Net.%s: no rate limiter installed. Server.server.lua must Init RateLimiter (which calls Net.useRateLimiter) before any service registers remotes."):format(
				context
			),
			3
		)
	end
	return limiter
end

local function validateName(name: any)
	if typeof(name) ~= "string" then
		error(
			("Net: remote name must be a string, got %s. Use Net.Names.<Key> "):format(typeof(name))
				.. "(a misspelled key resolves to nil).",
			3
		)
	end
end

local function getRemotesFolder(): Folder
	if remotesFolder then
		return remotesFolder
	end
	local folder: Folder
	if IS_SERVER then
		local found = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
		if found and found:IsA("Folder") then
			folder = found
		else
			folder = Instance.new("Folder")
			folder.Name = REMOTES_FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
	else
		-- Remotes are created lazily at service init, so a client that boots
		-- first must wait rather than assume existence.
		folder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME) :: Folder
	end
	remotesFolder = folder
	return folder
end

-- Returns the RemoteEvent for `name`, creating it on the server and waiting for
-- it on the client. Cached per name.
function Net.event(name: string): RemoteEvent
	validateName(name)
	local cached = eventCache[name]
	if cached then
		return cached
	end

	local folder = getRemotesFolder()
	local remote: RemoteEvent
	if IS_SERVER then
		local found = folder:FindFirstChild(name)
		if found and found:IsA("RemoteEvent") then
			remote = found
		else
			if found then
				warn(
					("Net.event(%q): found a %s under that name; replacing it with a RemoteEvent."):format(
						name,
						found.ClassName
					)
				)
				found:Destroy()
			end
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	else
		remote = folder:WaitForChild(name) :: RemoteEvent
	end

	eventCache[name] = remote
	return remote
end

-- Returns the RemoteFunction for `name`, creating it on the server and waiting
-- for it on the client. Cached per name. A name is either an event or a function
-- for its whole lifetime; the server replaces a stale wrong-class instance left
-- in a long-lived Studio DataModel so a type flip can't hand back the wrong class.
function Net.fn(name: string): RemoteFunction
	validateName(name)
	local cached = fnCache[name]
	if cached then
		return cached
	end

	local folder = getRemotesFolder()
	local remote: RemoteFunction
	if IS_SERVER then
		local found = folder:FindFirstChild(name)
		if found and found:IsA("RemoteFunction") then
			remote = found
		else
			if found then
				warn(
					("Net.fn(%q): found a %s under that name; replacing it with a RemoteFunction."):format(
						name,
						found.ClassName
					)
				)
				found:Destroy()
			end
			remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	else
		remote = folder:WaitForChild(name) :: RemoteFunction
	end

	fnCache[name] = remote
	return remote
end

-- Registers a handler for `name`.
--   Server: connects to OnServerEvent; handler(player, ...). Rate-limited +
--           validated + pcall-isolated; multi-subscriber (subscribers share the
--           remote's bucket; the first registration fixes its budget).
--   Client: connects to OnClientEvent; handler(...). `opts` is server-side
--           middleware config and is ignored on the client.
-- Returns the RBXScriptConnection.
function Net.on(name: string, handler: (...any) -> (), opts: NetOpts?): RBXScriptConnection
	local remote = Net.event(name)
	if not IS_SERVER then
		return remote.OnClientEvent:Connect(handler)
	end

	local limiter = requireRateLimiter("on")
	local scope = "Net:" .. name
	local bucket =
		limiter.bucket(scope, (opts and opts.budget) or DEFAULT_BUDGET, (opts and opts.window) or DEFAULT_WINDOW)
	local validator = opts and opts.validator

	return remote.OnServerEvent:Connect(function(player: Player, ...: any)
		if not bucket:allow(player) then
			limiter.strike(player, scope)
			return
		end
		if validator then
			local ok, why = validator(...)
			if not ok then
				limiter.strike(player, scope)
				warn(("Net.on(%q): rejected args from %s: %s"):format(name, player.Name, why or "invalid"))
				return
			end
		end
		local ok, err = pcall(handler :: (...any) -> ...any, player, ...)
		if not ok then
			warn(("Net.on(%q) handler error: %s"):format(name, tostring(err)))
		end
	end)
end

-- Server -> one client.
function Net.fireClient(name: string, player: Player, ...: any)
	assert(IS_SERVER, "Net.fireClient is server-only")
	Net.event(name):FireClient(player, ...)
end

-- Server -> all clients.
function Net.fireAll(name: string, ...: any)
	assert(IS_SERVER, "Net.fireAll is server-only")
	Net.event(name):FireAllClients(...)
end

-- Client -> server.
function Net.fireServer(name: string, ...: any)
	assert(not IS_SERVER, "Net.fireServer is client-only")
	Net.event(name):FireServer(...)
end

-- Server: registers the single OnServerInvoke handler for `name`. Rate-limited +
-- validated + pcall-isolated. Every path returns a result table ("always send a
-- result, even on failure"): middleware rejections return { success = false } so
-- a blocked/invalid client sees a clean refusal, never a hang or an error.
function Net.onInvoke(name: string, handler: (...any) -> any, opts: NetOpts?)
	assert(IS_SERVER, "Net.onInvoke is server-only")
	local limiter = requireRateLimiter("onInvoke")
	local scope = "Net:" .. name
	local bucket =
		limiter.bucket(scope, (opts and opts.budget) or DEFAULT_BUDGET, (opts and opts.window) or DEFAULT_WINDOW)
	local validator = opts and opts.validator

	Net.fn(name).OnServerInvoke = function(player: Player, ...: any)
		if not bucket:allow(player) then
			limiter.strike(player, scope)
			return { success = false, message = "Too many requests." }
		end
		if validator then
			local ok, why = validator(...)
			if not ok then
				limiter.strike(player, scope)
				warn(("Net.onInvoke(%q): rejected args from %s: %s"):format(name, player.Name, why or "invalid"))
				return { success = false, message = "Invalid request." }
			end
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn(("Net.onInvoke(%q) handler error: %s"):format(name, tostring(result)))
			return { success = false, message = "Something went wrong." }
		end
		return result
	end
end

-- Client -> server request/response. Blocks the calling thread until the server
-- replies; call sites that must stay responsive should wrap this in task.spawn.
function Net.invoke(name: string, ...: any): any
	assert(not IS_SERVER, "Net.invoke is client-only")
	return Net.fn(name):InvokeServer(...)
end

-- ============================================================================
-- Net.T — declarative argument validators.
--
-- A Check validates one argument: (value) -> (ok, why?). T.args(...) composes
-- Checks into a whole-remote Validator that also rejects EXTRA arguments (a
-- padded-args exploit signal). Checks must stay pure and total: any input,
-- including nil / NaN / wrong types / absurd sizes, returns (false, why) —
-- never errors.
-- ============================================================================

local T = {}

-- Composes per-argument Checks into a Validator for the whole call.
function T.args(...: Check): Validator
	local checks = table.pack(...)
	return function(...: any): (boolean, string?)
		local n = select("#", ...)
		if n > checks.n then
			return false, ("too many arguments (%d > %d)"):format(n, checks.n)
		end
		for i = 1, checks.n do
			local check = checks[i] :: Check
			-- Parenthesized select(i, ...) truncates to exactly the i-th argument.
			local ok, why = check((select(i, ...)))
			if not ok then
				return false, ("arg #%d: %s"):format(i, why or "invalid")
			end
		end
		return true, nil
	end
end

-- No arguments at all (fire-and-forget signals that carry no payload).
T.none = T.args()

function T.number(min: number?, max: number?): Check
	return function(value: any): (boolean, string?)
		if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return false, "expected a finite number"
		end
		if min ~= nil and value < min then
			return false, ("number below min %s"):format(tostring(min))
		end
		if max ~= nil and value > max then
			return false, ("number above max %s"):format(tostring(max))
		end
		return true, nil
	end
end

function T.integer(min: number?, max: number?): Check
	local numberCheck = T.number(min, max)
	return function(value: any): (boolean, string?)
		local ok, why = numberCheck(value)
		if not ok then
			return false, why
		end
		if math.floor(value) ~= value then
			return false, "expected an integer"
		end
		return true, nil
	end
end

function T.string(maxLength: number?): Check
	local limit = maxLength or 200
	return function(value: any): (boolean, string?)
		if typeof(value) ~= "string" then
			return false, "expected a string"
		end
		if #value > limit then
			return false, ("string longer than %d"):format(limit)
		end
		return true, nil
	end
end

T.boolean = function(value: any): (boolean, string?)
	if typeof(value) ~= "boolean" then
		return false, "expected a boolean"
	end
	return true, nil
end :: Check

-- Membership in a fixed string set, e.g. T.enum({ "ranch", "storage" }).
function T.enum(values: { string }): Check
	local set: { [string]: boolean } = {}
	for _, v in values do
		set[v] = true
	end
	return function(value: any): (boolean, string?)
		if typeof(value) ~= "string" or not set[value] then
			return false, "not a member of the allowed set"
		end
		return true, nil
	end
end

-- A server-minted GUID (HttpService:GenerateGUID(false) shape). Slime ids,
-- decor instance ids, and trade ids all travel as these.
T.guid = function(value: any): (boolean, string?)
	if typeof(value) ~= "string" then
		return false, "expected a GUID string"
	end
	if not value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
		return false, "not a GUID"
	end
	return true, nil
end :: Check

-- A dense array of at most maxLength elements, each passing `inner`. Rejects
-- dictionary keys / holes (mixed tables are an exploit smell, same posture as
-- T.args rejecting padded arguments). E.g. TradeSetOffer's slimeId list:
--   T.arrayOf(T.guid, 4)
function T.arrayOf(inner: Check, maxLength: number): Check
	return function(value: any): (boolean, string?)
		if typeof(value) ~= "table" then
			return false, "expected an array"
		end
		local n = 0
		for _ in value do
			n += 1
		end
		if n ~= #value then
			return false, "array has non-sequential keys"
		end
		if n > maxLength then
			return false, ("array longer than %d"):format(maxLength)
		end
		for i = 1, n do
			local ok, why = inner(value[i])
			if not ok then
				return false, ("element #%d: %s"):format(i, why or "invalid")
			end
		end
		return true, nil
	end
end

-- Argument may be nil OR pass the inner check (trailing optional params).
function T.optional(inner: Check): Check
	return function(value: any): (boolean, string?)
		if value == nil then
			return true, nil
		end
		return inner(value)
	end
end

-- Escape hatch for payloads validated in the handler itself. Prefer real checks.
T.any = function(_value: any): (boolean, string?)
	return true, nil
end :: Check

Net.T = T

return Net
