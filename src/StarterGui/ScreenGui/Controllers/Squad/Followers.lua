--!strict
-- =============================================================================
-- Squad/Followers — the client follower-parade sim, for EVERY player here.
-- [Contract] Owns: reading each player's Attrs.SquadJson projection, spawning
--   local no-collision follower models, and stepping them with the pure
--   WanderSim.FollowerStep spring against the leader's replicated character
--   position. Squash animation is a looping Tween.
-- [Contract] Never: replicates any motion (this sim runs identically on every
--   client from the same data); never collides (anchored, CanCollide off);
--   never grants anything — followers are presentation of the squad roster.
-- =============================================================================
--
-- The Heartbeat step here is ACTIVE motion (chasing a live character), not
-- idle animation — the Tweens-not-Heartbeat law governs idle loops, which the
-- squash Tween carries.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Attrs = require(Shared:WaitForChild("Attrs"))
local WanderSim = require(Shared:WaitForChild("WanderSim"))
local NatureConfig = require(Shared:WaitForChild("NatureConfig"))
local GrowthConfig = require(Shared:WaitForChild("GrowthConfig"))

local Natures = NatureConfig.Natures :: { [string]: NatureConfig.Nature }

local Followers = {}

type Follower = {
	part: BasePart,
	state: WanderSim.FollowerState,
	speed: number,
	index: number,
}

-- player -> ordered follower list.
local paradeOf: { [Player]: { Follower } } = {}

local function fxFolder(): Folder
	local found = Workspace:FindFirstChild("FollowerFx")
	if found and found:IsA("Folder") then
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = "FollowerFx"
	folder.Parent = Workspace
	return folder
end

local function clearParade(player: Player)
	local parade = paradeOf[player]
	if parade then
		paradeOf[player] = nil
		for _, follower in parade do
			follower.part:Destroy()
		end
	end
end

local function makeFollowerPart(entry: { [string]: any }): BasePart
	-- Placeholder ball until SlimeAssets exist; scale reads the stage.
	local scale = GrowthConfig.Stages[(entry.St :: number?) or 1].ModelScale
	local part = Instance.new("Part")
	part.Name = "Follower"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2, 2, 2) * scale
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Studs
	part.Parent = fxFolder()
	TweenService:Create(part, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Size = part.Size * Vector3.new(1.05, 0.9, 1.05),
	}):Play()
	return part
end

local function rebuildParade(player: Player)
	clearParade(player)
	local json = player:GetAttribute(Attrs.SquadJson)
	if typeof(json) ~= "string" or #json == 0 then
		return
	end
	local ok, entries = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok or typeof(entries) ~= "table" then
		return
	end

	local parade: { Follower } = {}
	local at = if player.Character then player.Character:GetPivot().Position else Vector3.zero
	for index, entry in entries :: { { [string]: any } } do
		local nature = Natures[(entry.Nt :: string?) or ""]
		-- FollowSpeed is the ONE exploration stat a nature may move (±10%).
		local speed = if nature and nature.Exploration.Stat == "FollowSpeed" then nature.Exploration.Mult else 1
		table.insert(parade, {
			part = makeFollowerPart(entry),
			state = { X = at.X, Z = at.Z },
			speed = speed,
			index = index,
		})
	end
	paradeOf[player] = parade
end

local function watch(player: Player)
	rebuildParade(player)
	player:GetAttributeChangedSignal(Attrs.SquadJson):Connect(function()
		rebuildParade(player)
	end)
end

function Followers.Init(_ctx: { [string]: any })
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clearParade)

	RunService.Heartbeat:Connect(function(dt)
		for player, parade in paradeOf do
			local character = player.Character
			local root = if character then character.PrimaryPart else nil
			if root then
				local back = -root.CFrame.LookVector
				local right = root.CFrame.RightVector
				local floorY = root.Position.Y - 2
				for _, follower in parade do
					local backDist, side = WanderSim.FollowerSlot(follower.index)
					local target = root.Position + back * backDist + right * side
					follower.state = WanderSim.FollowerStep(follower.state, target.X, target.Z, dt, follower.speed)
					local half = follower.part.Size.Y / 2
					follower.part.CFrame = CFrame.lookAt(
						Vector3.new(follower.state.X, floorY + half, follower.state.Z),
						Vector3.new(root.Position.X, floorY + half, root.Position.Z)
					)
				end
			end
		end
	end)
end

return Followers
