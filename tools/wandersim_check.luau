--!strict
-- =============================================================================
-- wandersim_check — off-Roblox determinism/behavior checks for WanderSim:
--   ~/.local/bin/luau tools/wandersim_check.luau      (from the project root)
--
-- [Contract] Owns: asserting the properties the zero-replication wander sim
--   depends on — seed/waypoint/sample determinism (any two clients agree),
--   bounds containment, nature-driven behavior rates, decor-affinity capture,
--   segment continuity, and follower-spring purity/convergence.
-- [Contract] Never: rendering or timing (client concerns); never a second
--   copy of sim math (it requires the REAL Shared/WanderSim, §8 W6).
-- [Contract] Binds: DESIGN.md §5 ranch wander sim + follower sim.
-- =============================================================================
local WanderSim = require("../src/ReplicatedStorage/Shared/WanderSim")
local NatureConfig = require("../src/ReplicatedStorage/Shared/NatureConfig")

local fails = 0
local function check(ok, label)
	print((ok and "  PASS  " or "  FAIL  ") .. label)
	if not ok then
		fails += 1
	end
end

local guid = "9bb44f4c-1d2f-4bbe-a9e5-08e6ad9ee582"
local seed = WanderSim.Seed(guid)
check(seed == WanderSim.Seed(guid), "Seed is deterministic")
check(seed ~= WanderSim.Seed("9bb44f4c-1d2f-4bbe-a9e5-08e6ad9ee583"), "different GUIDs, different seeds")

local bounds = { CX = 0, CZ = 0, HW = 20, HD = 20 }
local natures = NatureConfig.Natures

-- Determinism: same inputs -> identical waypoints/samples across "clients"
local sleepy = natures.sleepy.Wander
local w1 = WanderSim.WaypointAt(seed, 123, bounds, sleepy)
local w2 = WanderSim.WaypointAt(seed, 123, bounds, sleepy)
check(w1.X == w2.X and w1.Z == w2.Z and w1.Behavior == w2.Behavior, "WaypointAt deterministic")

local s1 = WanderSim.Sample(seed, 493.7, bounds, sleepy)
local s2 = WanderSim.Sample(seed, 493.7, bounds, sleepy)
check(s1.X == s2.X and s1.Z == s2.Z, "Sample deterministic")

-- Bounds: 10k waypoints stay inside the rect
local inBounds = true
for seg = 1, 10000 do
	local w = WanderSim.WaypointAt(seed, seg, bounds, natures.zippy.Wander)
	if math.abs(w.X) > bounds.HW + 1e-9 or math.abs(w.Z) > bounds.HD + 1e-9 then
		inBounds = false
		break
	end
end
check(inBounds, "10k waypoints stay in bounds (no decor)")

-- Nature personality: sleepy naps far more than zippy
local function napRate(wander)
	local naps = 0
	for seg = 1, 5000 do
		if WanderSim.WaypointAt(seed, seg, bounds, wander).Behavior == "nap" then
			naps += 1
		end
	end
	return naps / 5000
end
local sleepyNaps, zippyNaps = napRate(natures.sleepy.Wander), napRate(natures.zippy.Wander)
print(("        sleepy naps %.1f%%, zippy naps %.1f%%"):format(sleepyNaps * 100, zippyNaps * 100))
check(sleepyNaps > 0.25 and zippyNaps < 0.05, "NapBias drives nap behavior")

-- Decor affinity: a Nap decor point captures sleepy nap targets exactly
local decor = { { X = 5, Z = 5, Affinity = "Nap" } }
local captured = true
for seg = 1, 2000 do
	local w = WanderSim.WaypointAt(seed, seg, bounds, sleepy, decor)
	if w.Behavior == "nap" and not (w.X == 5 and w.Z == 5) then
		captured = false
		break
	end
end
check(captured, "nap waypoints land on Nap-affinity decor")

-- Sample continuity: position at segment end == that segment's waypoint
local seg = 777
local w = WanderSim.WaypointAt(seed, seg, bounds, sleepy)
local atEnd = WanderSim.Sample(seed, (seg + 1) * WanderSim.SEGMENT_SECONDS - 0.001, bounds, sleepy)
check(math.abs(atEnd.X - w.X) < 0.01 and math.abs(atEnd.Z - w.Z) < 0.01, "Sample converges to the waypoint")

-- Follower spring: converges toward target, pure (state untouched)
local state = { X = 0, Z = 0 }
local before = state
for _ = 1, 120 do
	state = WanderSim.FollowerStep(state, 10, -4, 1 / 30, 1)
end
check(
	before.X == 0 and math.abs(state.X - 10) < 0.5 and math.abs(state.Z + 4) < 0.5,
	"FollowerStep converges, never mutates"
)

local b1, s1a = WanderSim.FollowerSlot(1)
local b2 = WanderSim.FollowerSlot(2)
local b3 = WanderSim.FollowerSlot(3)
check(b1 == b2 and b3 > b1 and s1a < 0, "FollowerSlot staggers a two-column parade")

if fails > 0 then
	error(fails .. " failure(s)")
end
print("wandersim_test: ALL PASS")
