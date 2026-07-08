--!strict
-- =============================================================================
-- Slime/RanchRender — drives every ranch slime through the WanderSim.
-- [Contract] Owns: watching Workspace.RanchSlimes for slime Models (server
--   spawns them with attributes), sampling Shared/WanderSim per segment, and
--   animating each slime with Tweens: one waypoint move per segment + one
--   looping squash "breathe" — never per-frame Heartbeat writes (idle
--   render-throttle rule).
-- [Contract] Never: tells the server where a slime is (the sim replicates
--   NOTHING); never a per-slime loop (ONE segment scheduler for all slimes).
-- =============================================================================
--
-- Determinism: every client seeds from the slime GUID and samples at the same
-- Workspace:GetServerTimeNow(), so all clients see the same slime in the same
-- place with zero replication. Multi-part slime meshes must weld everything to
-- PrimaryPart (Studio contract) — we tween PrimaryPart.CFrame only.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Attrs = require(Shared:WaitForChild("Attrs"))
local WanderSim = require(Shared:WaitForChild("WanderSim"))
local NatureConfig = require(Shared:WaitForChild("NatureConfig"))
local DecorConfig = require(Shared:WaitForChild("DecorConfig"))

local Natures = NatureConfig.Natures :: { [string]: NatureConfig.Nature }
local Catalog = DecorConfig.Catalog :: { [string]: DecorConfig.Decor }

local RanchRender = {}

type Entry = {
	model: Model,
	seed: number,
	wander: WanderSim.WanderParams,
	ownerUserId: number,
	squash: Tween?,
}

local entries: { [Instance]: Entry } = {}
local guiRef: ScreenGui? = nil

-- ---------------------------------------------------------------------------
-- Plot context per owner: bounds (from the plot Base) + decor affinity points.
-- ---------------------------------------------------------------------------

local function ownerBase(ownerUserId: number): BasePart?
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local index = if owner then owner:GetAttribute(Attrs.PlotIndex) else nil
	if typeof(index) ~= "number" then
		return nil
	end
	local plots = Workspace:FindFirstChild("Plots")
	local plot = if plots then plots:FindFirstChild("Plot" .. index) else nil
	local base = if plot then plot:FindFirstChild("Base") else nil
	return if base and base:IsA("BasePart") then base else nil
end

local function boundsFor(entry: Entry): (WanderSim.Bounds, number)
	local base = ownerBase(entry.ownerUserId)
	if base then
		return {
			CX = base.Position.X,
			CZ = base.Position.Z,
			HW = base.Size.X * 0.45,
			HD = base.Size.Z * 0.45,
		},
			base.Position.Y + base.Size.Y / 2
	end
	-- World not authored: wander a small ring around the spawn point.
	local pivot = entry.model:GetPivot().Position
	return { CX = pivot.X, CZ = pivot.Z, HW = 10, HD = 10 }, pivot.Y
end

-- Placed decor on the owner's plot as WanderSim affinity points (§2
-- interactive decor: the reason decor changes what a ranch looks like DOING).
local function decorPointsFor(entry: Entry): { WanderSim.DecorPoint }
	local owner = Players:GetPlayerByUserId(entry.ownerUserId)
	local index = if owner then owner:GetAttribute(Attrs.PlotIndex) else nil
	if typeof(index) ~= "number" then
		return {}
	end
	local plots = Workspace:FindFirstChild("Plots")
	local plot = if plots then plots:FindFirstChild("Plot" .. index) else nil
	if not plot then
		return {}
	end
	local points = {}
	for _, child in plot:GetChildren() do
		local decorId = child:GetAttribute("DecorId")
		if typeof(decorId) == "string" and child:IsA("Model") then
			local decor = Catalog[decorId]
			if decor and decor.Affinity then
				local at = child:GetPivot().Position
				table.insert(points, { X = at.X, Z = at.Z, Affinity = decor.Affinity :: string })
			end
		end
	end
	return points
end

-- ---------------------------------------------------------------------------
-- Animation. One waypoint tween per slime per segment; a looping squash tween
-- carries all idle life (the Tweens-not-Heartbeat law).
-- ---------------------------------------------------------------------------

local function animationsEnabled(): boolean
	local gui = guiRef
	return gui == nil or gui:GetAttribute(Attrs.AnimationsEnabled) ~= false
end

local function ensureSquash(entry: Entry)
	local primary = entry.model.PrimaryPart
	if entry.squash or not primary or not animationsEnabled() then
		return
	end
	local hop = entry.wander.HopPower
	local tween = TweenService:Create(
		primary,
		TweenInfo.new(0.6 / math.max(hop, 0.5), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = primary.Size * Vector3.new(1.06, 0.92, 1.06) }
	)
	tween:Play()
	entry.squash = tween
end

local function stepEntry(entry: Entry, segment: number)
	local primary = entry.model.PrimaryPart
	if not primary then
		return
	end
	local bounds, floorY = boundsFor(entry)
	local decor = decorPointsFor(entry)
	local waypoint = WanderSim.WaypointAt(entry.seed, segment, bounds, entry.wander, decor)
	local scale = primary.Size.Y / 2
	local target = Vector3.new(waypoint.X, floorY + scale, waypoint.Z)
	local from = primary.Position
	local flat = Vector3.new(target.X, from.Y, target.Z)
	local look: CFrame
	if (flat - from).Magnitude > 0.05 then
		look = CFrame.lookAt(target, target + (flat - from).Unit)
	else
		look = primary.CFrame.Rotation + target -- idle: keep facing, settle in place
	end

	if not animationsEnabled() then
		primary.CFrame = look
		return
	end
	local duration = WanderSim.SEGMENT_SECONDS * waypoint.MoveFraction
	TweenService:Create(primary, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = look,
	}):Play()
	ensureSquash(entry)
end

-- ---------------------------------------------------------------------------

local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local slimeId = model:GetAttribute(Attrs.SlimeId)
	local natureId = model:GetAttribute(Attrs.Nature)
	local ownerUserId = model:GetAttribute(Attrs.OwnerUserId)
	if typeof(slimeId) ~= "string" or typeof(ownerUserId) ~= "number" then
		return
	end
	local nature = if typeof(natureId) == "string" then Natures[natureId] else nil
	entries[model] = {
		model = model,
		seed = WanderSim.Seed(slimeId),
		wander = if nature then nature.Wander else Natures.bouncy.Wander,
		ownerUserId = ownerUserId,
		squash = nil,
	}
end

local function untrack(model: Instance)
	local entry = entries[model]
	if entry then
		entries[model] = nil
		if entry.squash then
			entry.squash:Cancel()
		end
	end
end

function RanchRender.Init(ctx: { [string]: any })
	guiRef = ctx.gui :: ScreenGui

	task.spawn(function()
		local folder = Workspace:WaitForChild("RanchSlimes", 60)
		if not folder then
			warn("Slime/RanchRender: Workspace.RanchSlimes never appeared — no ranch slimes to render.")
			return
		end
		for _, child in folder:GetChildren() do
			track(child)
		end
		folder.ChildAdded:Connect(track)
		folder.ChildRemoved:Connect(untrack)

		-- ONE segment scheduler for every slime on the server: wake at each
		-- WanderSim segment boundary, hand out one tween each, sleep again.
		while true do
			local now = Workspace:GetServerTimeNow()
			local segment = WanderSim.SegmentIndex(now)
			for _, entry in entries do
				stepEntry(entry, segment)
			end
			local nextBoundary = (segment + 1) * WanderSim.SEGMENT_SECONDS
			task.wait(math.max(0.1, nextBoundary - Workspace:GetServerTimeNow()))
		end
	end)
end

return RanchRender
