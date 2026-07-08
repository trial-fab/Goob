--!strict
-- =============================================================================
-- ClientState — the client-side cache of the server's StateSync projection.
--
-- [Contract] Owns: receiving StateSync pushes (+ the one-shot GetState pull at
--   boot), caching the latest projection, and fanning change notifications out
--   to controllers. The ONE place a controller reads profile-shaped state.
-- [Contract] Never: mutates state or sends anything profile-shaped back to the
--   server (projections are one-directional, §8 W3); never required by server
--   code; never a second cache (controllers subscribe here, not to Net).
-- [Contract] Binds: DESIGN.md §5 replication cost control, §8 W3.
-- =============================================================================
--
-- Init() is called exactly once, by HudController (the first controller in
-- every screen's dependency chain). Everyone else just Get()/OnChanged().

local RunService = game:GetService("RunService")

local Net = require(script.Parent:WaitForChild("Net"))

local ClientState = {}

local current: { [string]: any } = {}
local listeners: { (state: { [string]: any }) -> () } = {}
local initialized = false

local function apply(state: { [string]: any })
	current = state
	for _, listener in listeners do
		task.spawn(listener, current)
	end
end

function ClientState.Init()
	assert(not RunService:IsServer(), "ClientState is client-only")
	if initialized then
		return
	end
	initialized = true

	Net.on(Net.Names.StateSync, function(state: { [string]: any })
		apply(state)
	end)

	-- The load-time push may have fired before this client script connected;
	-- pull once to close the gap.
	task.spawn(function()
		local result = Net.invoke(Net.Names.GetState)
		if typeof(result) == "table" and result.success and next(current) == nil then
			apply(result.state)
		end
	end)
end

-- The latest projection ({} until the first sync lands).
function ClientState.Get(): { [string]: any }
	return current
end

-- Subscribe to every sync. Fires immediately with the current state when one
-- already landed, so subscription order can't drop the initial render.
function ClientState.OnChanged(listener: (state: { [string]: any }) -> ())
	table.insert(listeners, listener)
	if next(current) ~= nil then
		task.spawn(listener, current)
	end
end

return ClientState
