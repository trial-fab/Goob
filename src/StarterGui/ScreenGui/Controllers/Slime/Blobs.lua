--!strict
-- =============================================================================
-- Slime/Blobs — goo-blob FX + tap-to-collect.
-- [Contract] Owns: rendering the local player's blob records (BlobSpawned
--   pushes) as clickable world FX on their plot, and the CollectBlob round
--   trip. FX only — the blob's VALUE lives in the server record.
-- [Contract] Never: grants or displays amounts the server didn't send; never
--   renders blobs for other plots (owner-only pushes at M1).
-- =============================================================================
--
-- Blob visuals are client-side FX parts (all FX client-side — §5/W5), not
-- world authoring: they exist only on this client, for this player.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))

local Blobs = {}

local parts: { [string]: BasePart } = {} -- blobId -> FX part

local function myBase(): BasePart?
	local index = Players.LocalPlayer:GetAttribute(Attrs.PlotIndex)
	if typeof(index) ~= "number" then
		return nil
	end
	local plots = Workspace:FindFirstChild("Plots")
	local plot = if plots then plots:FindFirstChild("Plot" .. index) else nil
	local base = if plot then plot:FindFirstChild("Base") else nil
	return if base and base:IsA("BasePart") then base else nil
end

local function fxFolder(): Folder
	local found = Workspace:FindFirstChild("BlobFx")
	if found and found:IsA("Folder") then
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = "BlobFx"
	folder.Parent = Workspace
	return folder
end

local function collect(blobId: string)
	local part = parts[blobId]
	if not part then
		return
	end
	parts[blobId] = nil
	part:Destroy()
	task.spawn(function()
		Net.invoke(Net.Names.CollectBlob, blobId)
	end)
end

local function spawnFx(blob: { [string]: any })
	local base = myBase()
	local at = if base
		then base.CFrame * CFrame.new(blob.X or 0, base.Size.Y / 2 + 1, blob.Z or 0)
		else CFrame.new(blob.X or 0, 2, blob.Z or 0)

	local part = Instance.new("Part")
	part.Name = "GooBlob"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.4, 1.4, 1.4)
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Studs
	part.CFrame = at

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 60
	click.Parent = part
	local blobId = blob.Id :: string
	click.MouseClick:Connect(function()
		collect(blobId)
	end)

	part.Parent = fxFolder()
	parts[blobId] = part
end

function Blobs.Init(_ctx: { [string]: any })
	Net.on(Net.Names.BlobSpawned, function(blob: { [string]: any }, grew: boolean?)
		if typeof(blob) ~= "table" or typeof(blob.Id) ~= "string" then
			return
		end
		if grew then
			-- Merged into an existing record at the cap: pulse the part a bit
			-- bigger so "blobs grow" reads without a new instance.
			local part = parts[blob.Id]
			if part then
				part.Size = Vector3.new(
					math.min(part.Size.X + 0.2, 3),
					math.min(part.Size.Y + 0.2, 3),
					math.min(part.Size.Z + 0.2, 3)
				)
			end
			return
		end
		if not parts[blob.Id] then
			spawnFx(blob)
		end
	end)
end

return Blobs
