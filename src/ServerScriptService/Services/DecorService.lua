--!strict
-- =============================================================================
-- DecorService — decor purchase, grid placement validation, likes.
--
-- [Contract] Owns: decor purchase (Goo/Gem tiers), grid placement validation
--   (plot-relative snap, bounds, overlap) for Profile.Ranch.Decor, recall, and
--   ranch likes (one per visitor per plot).
-- [Contract] Never: production effects of ANY kind (decor is cosmetic-only —
--   the hard rule that makes it the economy's open-ended sink, §3); never
--   authors decor geometry (Studio-authored; behavior-affinity tags live in
--   DecorConfig for the client wander sim).
-- [Contract] Binds: DESIGN.md §2 decor build mode, §3 inflation mitigation.
-- =============================================================================
--
-- Grid model (shared with the client Build View, which PREVIEWS what this
-- validates): 4-stud cells over the plot Base, origin at the Base's -X/-Z
-- corner, integer cell coords, RY ∈ {0, 90, 180, 270} (90/270 swap the
-- footprint). Owned-but-unplaced pieces live in Ranch.Decor with P = false.
--
-- Record shape: Ranch.Decor[instanceId] = { Id, X, Z, RY, P }.
--
-- Physical models clone from ReplicatedStorage.DecorAssets.<decorId>
-- (Studio-authored, ≤20 parts each — §8 W7); a placeholder box stands in
-- until assets exist. Placed decor replicates to everyone (visits/wander sim).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local DecorConfig = require(Shared:WaitForChild("DecorConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local SlimeService = require(script.Parent:WaitForChild("SlimeService"))

local Catalog = DecorConfig.Catalog :: { [string]: DecorConfig.Decor }

local CELL_STUDS = 4
-- Grid dimensions when the plot world isn't authored yet (data-only mode).
local FALLBACK_CELLS = 24

local DecorService = {}

-- RY must be one of the four grid rotations (a plain Check — Net.T composes it).
local function ryCheck(value: any): (boolean, string?)
	if value ~= 0 and value ~= 90 and value ~= 180 and value ~= 270 then
		return false, "rotation must be 0/90/180/270"
	end
	return true, nil
end

local decorModels: { [string]: Model } = {} -- instanceId -> placed model
-- likes given this server session: [visitorUserId] = { [ownerUserId] = true }.
local likedThisSession: { [number]: { [number]: boolean } } = {}

-- ---------------------------------------------------------------------------
-- Grid math (server-side truth; the client ghost preview mirrors it).
-- ---------------------------------------------------------------------------

local function gridSize(player: Player): (number, number)
	local base = PlotService.GetBase(player)
	if not base then
		return FALLBACK_CELLS, FALLBACK_CELLS
	end
	return math.floor(base.Size.X / CELL_STUDS), math.floor(base.Size.Z / CELL_STUDS)
end

local function footprint(decor: DecorConfig.Decor, ry: number): (number, number)
	if ry == 90 or ry == 270 then
		return decor.Footprint.D, decor.Footprint.W
	end
	return decor.Footprint.W, decor.Footprint.D
end

local function overlaps(
	ax: number,
	az: number,
	aw: number,
	ad: number,
	bx: number,
	bz: number,
	bw: number,
	bd: number
): boolean
	return ax < bx + bw and bx < ax + aw and az < bz + bd and bz < az + ad
end

-- ---------------------------------------------------------------------------
-- Physical models (presentation of validated state).
-- ---------------------------------------------------------------------------

local function despawn(instanceId: string)
	local model = decorModels[instanceId]
	if model then
		decorModels[instanceId] = nil
		model:Destroy()
	end
end

local function spawnPlaced(player: Player, instanceId: string, record: { [string]: any })
	despawn(instanceId)
	local base = PlotService.GetBase(player)
	if not base then
		return -- data-only until the world exists
	end
	local decor = Catalog[record.Id]
	if not decor then
		return
	end

	local assets = ReplicatedStorage:FindFirstChild("DecorAssets")
	local template = if assets then assets:FindFirstChild(record.Id) else nil
	local model: Model
	if template and template:IsA("Model") and template.PrimaryPart then
		model = template:Clone()
	else
		local w, d = footprint(decor, record.RY)
		model = Instance.new("Model")
		model.Name = "PlaceholderDecor_" .. record.Id
		local part = Instance.new("Part")
		part.Name = "Body"
		part.Size = Vector3.new(w * CELL_STUDS, 2, d * CELL_STUDS)
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Studs
		part.BottomSurface = Enum.SurfaceType.Studs
		part.Parent = model
		model.PrimaryPart = part
	end

	local w, d = footprint(decor, record.RY)
	local originX = -base.Size.X / 2 + (record.X + w / 2) * CELL_STUDS
	local originZ = -base.Size.Z / 2 + (record.Z + d / 2) * CELL_STUDS
	model:SetAttribute("DecorId", record.Id)
	model:SetAttribute("DecorInstanceId", instanceId)
	model:SetAttribute(Attrs.OwnerUserId, player.UserId)
	model:PivotTo(
		base.CFrame * CFrame.new(originX, base.Size.Y / 2 + 1, originZ) * CFrame.Angles(0, math.rad(record.RY), 0)
	)
	local plotModel = PlotService.GetModel(player)
	model.Parent = plotModel or Workspace
	decorModels[instanceId] = model
end

-- ---------------------------------------------------------------------------
-- Remotes.
-- ---------------------------------------------------------------------------

local function onBuyDecor(player: Player, decorId: string): { [string]: any }
	local data = DataService.GetData(player)
	if not data then
		return { success = false, message = "Loading..." }
	end
	local decor = Catalog[decorId]
	if not decor then
		return { success = false, message = "Unknown decor." }
	end

	if decor.CostGoo then
		if data.Goo < decor.CostGoo then
			return { success = false, message = "Not enough Goo." }
		end
		data.Goo -= decor.CostGoo
		player:SetAttribute(Attrs.Goo, data.Goo)
	elseif decor.CostGems then
		if data.Gems < decor.CostGems then
			return { success = false, message = "Not enough Gems." }
		end
		data.Gems -= decor.CostGems
		player:SetAttribute(Attrs.Gems, data.Gems)
	else
		return { success = false, message = "That piece isn't for sale." }
	end

	local instanceId = HttpService:GenerateGUID(false)
	data.Ranch.Decor[instanceId] = { Id = decorId, X = 0, Z = 0, RY = 0, P = false }
	DataService.ForceSave(player) -- Gems purchases especially must not vanish
	SlimeService.PushState(player)
	return { success = true, instanceId = instanceId, goo = data.Goo, gems = data.Gems }
end

local function onPlaceDecor(player: Player, instanceId: string, x: number, z: number, ry: number): { [string]: any }
	local data = DataService.GetData(player)
	local record = if data then data.Ranch.Decor[instanceId] :: { [string]: any }? else nil
	if not (data and record) then
		return { success = false, message = "You don't own that piece." }
	end
	local decor = Catalog[record.Id]
	if not decor then
		return { success = false, message = "Unknown decor." }
	end

	local w, d = footprint(decor, ry)
	local gridW, gridD = gridSize(player)
	if x < 0 or z < 0 or x + w > gridW or z + d > gridD then
		return { success = false, message = "Out of bounds." }
	end
	for otherId, other in data.Ranch.Decor :: { [string]: any } do
		if otherId ~= instanceId and other.P then
			local otherDecor = Catalog[other.Id]
			if otherDecor then
				local ow, od = footprint(otherDecor, other.RY)
				if overlaps(x, z, w, d, other.X, other.Z, ow, od) then
					return { success = false, message = "Something is already there." }
				end
			end
		end
	end

	record.X = x
	record.Z = z
	record.RY = ry
	record.P = true
	spawnPlaced(player, instanceId, record)
	SlimeService.PushState(player)
	return { success = true }
end

local function onRecallDecor(player: Player, instanceId: string): { [string]: any }
	local data = DataService.GetData(player)
	local record = if data then data.Ranch.Decor[instanceId] :: { [string]: any }? else nil
	if not (data and record) then
		return { success = false, message = "You don't own that piece." }
	end
	record.P = false
	despawn(instanceId)
	SlimeService.PushState(player)
	return { success = true }
end

local function onLikeRanch(player: Player, ownerUserId: number): { [string]: any }
	if ownerUserId == player.UserId then
		return { success = false, message = "Nice try." }
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local ownerData = if owner then DataService.GetData(owner) else nil
	if not (owner and ownerData) then
		return { success = false, message = "That rancher isn't here." }
	end
	local given = likedThisSession[player.UserId]
	if not given then
		given = {}
		likedThisSession[player.UserId] = given
	end
	if given[ownerUserId] then
		return { success = false, message = "Already liked this visit." }
	end
	given[ownerUserId] = true
	ownerData.Ranch.Likes += 1
	SlimeService.PushState(owner :: Player)
	return { success = true, likes = ownerData.Ranch.Likes }
end

function DecorService.Init()
	DataService.OnProfileLoaded(function(player, data)
		for instanceId, record in data.Ranch.Decor :: { [string]: any } do
			if record.P then
				spawnPlaced(player, instanceId, record)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local data = DataService.GetData(player)
		if data then
			for instanceId in data.Ranch.Decor :: { [string]: any } do
				despawn(instanceId)
			end
		end
		likedThisSession[player.UserId] = nil
	end)

	Net.onInvoke(Net.Names.BuyDecor, onBuyDecor, {
		budget = 3,
		window = 1,
		validator = Net.T.args(Net.T.string(40)),
	})
	Net.onInvoke(Net.Names.PlaceDecor, onPlaceDecor, {
		budget = 5,
		window = 1,
		validator = Net.T.args(Net.T.guid, Net.T.integer(0, 200), Net.T.integer(0, 200), ryCheck),
	})
	Net.onInvoke(Net.Names.RecallDecor, onRecallDecor, {
		budget = 5,
		window = 1,
		validator = Net.T.args(Net.T.guid),
	})
	Net.onInvoke(Net.Names.LikeRanch, onLikeRanch, {
		budget = 2,
		window = 1,
		validator = Net.T.args(Net.T.integer(1)),
	})
end

return DecorService
