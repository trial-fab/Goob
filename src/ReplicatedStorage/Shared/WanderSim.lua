--!strict
-- =============================================================================
-- WanderSim — the deterministic ranch wander + follower simulation.
--
-- [Contract] Owns: the deterministic ranch wander simulation — pure functions
--   from (slime GUID seed, synchronized epoch, nature params, plot bounds,
--   decor affinity tags) -> position/pose over time. Client-run on every
--   client; server-checkable because it is deterministic. Also the pure
--   follower-formation/step helpers the squad parade sim uses.
-- [Contract] Never: replication (motion costs ZERO network — the server owns
--   rosters only); never per-frame Heartbeat writes for idle motion (looping
--   Tweens — idle render-throttle rule); never non-deterministic inputs
--   (os.clock, math.random without the GUID seed).
-- [Contract] Binds: DESIGN.md §5 ranch wander sim + follower sim, §1 (M0 perf
--   spike validates the rig budget BEFORE caps are final).
-- =============================================================================
--
-- Requires nothing and touches no Roblox APIs: every function is a pure map of
-- its arguments, so any two clients (or a server spot-check, or a CLI test)
-- that agree on (guid, time) agree on the slime's waypoint exactly.
--
-- Model: time is cut into fixed SEGMENT_SECONDS windows. Each segment picks —
-- purely from hash(seed, segment) — a behavior (weighted by the slime's
-- NatureConfig Wander params) and a target point (weighted toward decor whose
-- Affinity matches the behavior; the §2 "interactive decor" hook). A slime
-- hops from its previous segment's target to the current one over the first
-- MoveFraction of the segment, then idles/naps/plays in place. Clients render
-- a waypoint as one position Tween + a looping squash/hop Tween — never
-- per-frame writes. `Sample` reconstructs the exact in-segment position for
-- late joiners and camera checks.
--
-- The synchronized epoch is Workspace:GetServerTimeNow() at the CALL SITE
-- (identical across clients); it is passed in as `time`, never read here.

local WanderSim = {}

WanderSim.SEGMENT_SECONDS = 4

export type Bounds = {
	CX: number, -- plot-space rect center X
	CZ: number,
	HW: number, -- half width (X extent)
	HD: number, -- half depth (Z extent)
}

export type WanderParams = {
	HopPower: number,
	Pace: number,
	NapBias: number,
	SocialBias: number,
	BlobBias: number,
	PetsForHeart: number,
}

export type DecorPoint = {
	X: number,
	Z: number,
	Affinity: string, -- DecorConfig Affinity tag ("Bounce"|"Swim"|"Nap"|"Play"|"Perch")
}

-- "wander" | "nap" | "social" | "seek" (plain string: the literal union trips
-- luau-lsp's return-widening on pickBehavior; the sim treats it as a tag).
export type Behavior = string

export type Waypoint = {
	X: number,
	Z: number,
	Behavior: Behavior,
	-- Fraction of the segment spent traveling to (X, Z); the rest is spent
	-- idling there in the behavior's pose.
	MoveFraction: number,
}

export type Sample = {
	X: number,
	Z: number,
	Behavior: Behavior,
	Moving: boolean,
	FacingX: number, -- unit travel direction while moving (0,0 when idle)
	FacingZ: number,
}

-- ---------------------------------------------------------------------------
-- Deterministic hashing. FNV-1a over the GUID string gives the per-slime seed;
-- an integer mix (splitmix-style) turns (seed, segment, salt) into uniform
-- [0, 1) draws. All in doubles-safe 32-bit space.
-- ---------------------------------------------------------------------------

function WanderSim.Seed(guid: string): number
	local hash = 2166136261
	for i = 1, #guid do
		hash = bit32.bxor(hash, string.byte(guid, i))
		hash = bit32.band(hash * 16777619, 0xFFFFFFFF)
	end
	return hash
end

local SALTS: { [string]: number } = {
	behavior = 0x9E3779B9,
	pointX = 0x85EBCA6B,
	pointZ = 0xC2B2AE35,
	decor = 0x27D4EB2F,
}

-- Uniform [0, 1) from (seed, segment, salt). Two rounds of xorshift-multiply
-- mixing — enough to decorrelate consecutive segments for a cosmetic sim.
local function draw(seed: number, segment: number, salt: string): number
	local h = bit32.band(seed + segment * 0x9E3779B9 + (SALTS[salt] or 0), 0xFFFFFFFF)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = bit32.band(h * 0x21F0AAAD, 0xFFFFFFFF)
	h = bit32.bxor(h, bit32.rshift(h, 15))
	h = bit32.band(h * 0x735A2D97, 0xFFFFFFFF)
	h = bit32.bxor(h, bit32.rshift(h, 15))
	return h / 4294967296
end

function WanderSim.SegmentIndex(time: number): number
	return math.floor(time / WanderSim.SEGMENT_SECONDS)
end

-- ---------------------------------------------------------------------------
-- Behavior + target selection.
-- ---------------------------------------------------------------------------

-- Behavior -> decor Affinity tags it seeks (nil = no decor pull).
local BEHAVIOR_AFFINITIES: { [string]: { [string]: boolean } } = {
	nap = { Nap = true },
	seek = { Bounce = true, Swim = true, Play = true, Perch = true },
}

local function pickBehavior(seed: number, segment: number, wander: WanderParams): Behavior
	-- Baseline wander weight 1; nature biases stack against it. SocialBias
	-- drives the "social" pose (face the nearest visitor — presentation the
	-- client layers on; the sim only needs the behavior tag).
	local wWander = 1
	local wNap = wander.NapBias * 2
	local wSocial = wander.SocialBias * 0.75
	local wSeek = wander.BlobBias * 1.25
	local total = wWander + wNap + wSocial + wSeek
	local r = draw(seed, segment, "behavior") * total
	if r < wNap then
		return "nap"
	end
	r -= wNap
	if r < wSocial then
		return "social"
	end
	r -= wSocial
	if r < wSeek then
		return "seek"
	end
	return "wander"
end

local function randomPoint(seed: number, segment: number, bounds: Bounds): (number, number)
	local x = bounds.CX + (draw(seed, segment, "pointX") * 2 - 1) * bounds.HW
	local z = bounds.CZ + (draw(seed, segment, "pointZ") * 2 - 1) * bounds.HD
	return x, z
end

-- Deterministic pick among decor matching the behavior. Nap targets are keyed
-- to a 4-segment window so a sleepy slime settles at ONE lamp instead of
-- shuffling between naps every segment.
local function decorPoint(seed: number, segment: number, behavior: Behavior, decor: { DecorPoint }): (number?, number?)
	local wanted = BEHAVIOR_AFFINITIES[behavior]
	if not wanted or #decor == 0 then
		return nil, nil
	end
	local matches: { DecorPoint } = {}
	for _, point in decor do
		if wanted[point.Affinity] then
			table.insert(matches, point)
		end
	end
	if #matches == 0 then
		return nil, nil
	end
	local key = if behavior == "nap" then segment - segment % 4 else segment
	local pick = matches[1 + math.floor(draw(seed, key, "decor") * #matches)]
	return pick.X, pick.Z
end

-- The waypoint for `segment`. Pure in (seed, segment, bounds, wander, decor):
-- every client computes the identical point.
function WanderSim.WaypointAt(
	seed: number,
	segment: number,
	bounds: Bounds,
	wander: WanderParams,
	decor: { DecorPoint }?
): Waypoint
	local behavior = pickBehavior(seed, segment, wander)
	local x, z = decorPoint(seed, segment, behavior, decor or {})
	if x == nil or z == nil then
		x, z = randomPoint(seed, segment, bounds)
	end
	-- Faster natures cross the segment quicker; nappers scurry to the spot and
	-- rest. Clamped so there is always visible travel AND visible idle.
	local moveFraction = if behavior == "nap" then 0.25 else math.clamp(0.55 / math.max(wander.Pace, 0.1), 0.2, 0.9)
	return {
		X = x :: number,
		Z = z :: number,
		Behavior = behavior,
		MoveFraction = moveFraction,
	}
end

-- Exact position/pose at `time` — for late joiners, LOD re-entry, and server
-- spot-checks. Interpolates from the previous segment's waypoint with the
-- ease-out the client Tweens use (quadratic).
function WanderSim.Sample(
	seed: number,
	time: number,
	bounds: Bounds,
	wander: WanderParams,
	decor: { DecorPoint }?
): Sample
	local segment = WanderSim.SegmentIndex(time)
	local from = WanderSim.WaypointAt(seed, segment - 1, bounds, wander, decor)
	local to = WanderSim.WaypointAt(seed, segment, bounds, wander, decor)
	local elapsed = time - segment * WanderSim.SEGMENT_SECONDS
	local alpha = math.clamp(elapsed / (WanderSim.SEGMENT_SECONDS * to.MoveFraction), 0, 1)
	local eased = 1 - (1 - alpha) * (1 - alpha)
	local dx, dz = to.X - from.X, to.Z - from.Z
	local dist = math.sqrt(dx * dx + dz * dz)
	local moving = alpha < 1 and dist > 0.01
	return {
		X = from.X + dx * eased,
		Z = from.Z + dz * eased,
		Behavior = to.Behavior,
		Moving = moving,
		FacingX = if moving then dx / dist else 0,
		FacingZ = if moving then dz / dist else 0,
	}
end

-- Hop cadence for the travel Tween: how many hops the client plays across a
-- waypoint move, and how high, from nature + distance. Pure so every client
-- animates the same slime the same way.
function WanderSim.HopsFor(wander: WanderParams, distance: number): (number, number)
	local hops = math.max(1, math.floor(distance / (3 * math.max(wander.Pace, 0.1))))
	local height = 1.5 * wander.HopPower
	return hops, height
end

-- ---------------------------------------------------------------------------
-- Follower sim (equipped-squad parade). The squad list replicates as data
-- (Attrs.SquadJson); every client runs this same math against the leader's
-- replicated character position — follower motion itself replicates nothing.
-- ---------------------------------------------------------------------------

export type FollowerState = {
	X: number,
	Z: number,
}

-- Parade slot offsets in the leader's local space: a staggered two-column
-- trail behind the character (slot 1 = closest).
function WanderSim.FollowerSlot(index: number): (number, number)
	local row = math.floor((index - 1) / 2)
	local side = if index % 2 == 1 then -1 else 1
	local back = 4 + row * 3.5
	return back, side * 2.25
end

-- One smoothing step toward the slot target. Exponential chase: pure in
-- (state, target, dt); FollowSpeed natures and Mobility ability scale `speed`.
-- Returns a NEW state (never mutates — purity is the contract).
function WanderSim.FollowerStep(
	state: FollowerState,
	targetX: number,
	targetZ: number,
	dt: number,
	speed: number
): FollowerState
	local k = math.clamp(dt * 5 * speed, 0, 1)
	return {
		X = state.X + (targetX - state.X) * k,
		Z = state.Z + (targetZ - state.Z) * k,
	}
end

return table.freeze(WanderSim)
