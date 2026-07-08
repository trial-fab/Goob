--!strict
-- =============================================================================
-- PlotService — plot assignment for the 12 radial wedges.
--
-- [Contract] Owns: assignment/release of the 12 radial wedge plots around the
--   hub, plot bounds queries, and plot ownership lookups (userId <-> plot).
-- [Contract] Never: slime placement (slimes free-roam — there is no placement,
--   §2 Ranch); never authors plot geometry (Studio-authored world, WORKFLOW.md).
-- [Contract] Binds: DESIGN.md §2 Ranch & world, §5 (radial wedges, SheetService
--   descendant), §6 reuse map.
-- =============================================================================
--
-- Studio build contract (world authored by the user; see docs/studio-handoff.md):
--   Workspace.Plots            Folder
--     Plot1 .. Plot12          Model, one per wedge
--       Base                   BasePart — the buildable/wanderable footprint;
--                              its CFrame/Size are the bounds every consumer
--                              (wander sim, decor grid, blob spawns) derives from.
-- Until that world exists this service still assigns plot INDICES (all state
-- validation is index/data-based, never geometry-based), and geometry lookups
-- return nil — consumers must treat a nil Base as "world not authored yet".

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attrs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attrs"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local PLOT_COUNT = 12

local PlotService = {}

local plotOwner: { [number]: Player? } = {} -- index -> player
local playerPlot: { [Player]: number } = {} -- player -> index
local warnedNoWorld = false

local function plotModel(index: number): Model?
	local plots = Workspace:FindFirstChild("Plots")
	if not plots then
		if not warnedNoWorld then
			warnedNoWorld = true
			warn("PlotService: Workspace.Plots not authored yet — running data-only (no plot geometry).")
		end
		return nil
	end
	local model = plots:FindFirstChild("Plot" .. index)
	return if model and model:IsA("Model") then model else nil
end

local function assign(player: Player)
	if playerPlot[player] then
		return
	end
	for index = 1, PLOT_COUNT do
		if plotOwner[index] == nil then
			plotOwner[index] = player
			playerPlot[player] = index
			player:SetAttribute(Attrs.PlotIndex, index)
			local model = plotModel(index)
			if model then
				model:SetAttribute(Attrs.OwnerUserId, player.UserId)
			end
			return
		end
	end
	-- MaxPlayers is 12 with 12 plots (§5 topology); reaching here means the
	-- place settings drifted from the design.
	warn(("PlotService: no free plot for %s — check MaxPlayers vs PLOT_COUNT."):format(player.Name))
end

local function release(player: Player)
	local index = playerPlot[player]
	if not index then
		return
	end
	playerPlot[player] = nil
	plotOwner[index] = nil
	local model = plotModel(index)
	if model then
		model:SetAttribute(Attrs.OwnerUserId, nil)
	end
end

function PlotService.Init()
	-- Assign only once the profile is locked: a player whose data never loads
	-- is kicked by DataService and must not hold a wedge meanwhile.
	DataService.OnProfileLoaded(function(player)
		assign(player)
	end)
	Players.PlayerRemoving:Connect(release)
end

function PlotService.GetPlotIndex(player: Player): number?
	return playerPlot[player]
end

function PlotService.GetOwner(index: number): Player?
	return plotOwner[index]
end

function PlotService.GetModel(player: Player): Model?
	local index = playerPlot[player]
	return if index then plotModel(index) else nil
end

-- The plot's Base part (bounds authority for wander/decor/blobs), nil until
-- the Studio world exists.
function PlotService.GetBase(player: Player): BasePart?
	local model = PlotService.GetModel(player)
	if not model then
		return nil
	end
	local base = model:FindFirstChild("Base")
	return if base and base:IsA("BasePart") then base else nil
end

return PlotService
