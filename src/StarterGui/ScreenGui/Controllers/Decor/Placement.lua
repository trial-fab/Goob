--!strict
-- =============================================================================
-- Decor/Placement — the grid ghost preview + place/recall round trips.
-- [Contract] Owns: the placement session (one owned decor instance at a time),
--   the mouse->plot-grid solve (the SAME cell model DecorService validates:
--   4-stud cells, origin at the Base -X/-Z corner, RY ∈ {0,90,180,270}), the
--   semi-transparent ghost, and the PlaceDecor/RecallDecor invokes.
-- [Contract] Never: trusts its own solve (the server re-validates bounds +
--   overlap); the ghost is a client FX part, not world authoring.
-- =============================================================================
--
-- Input: mouse move drags the ghost, R rotates, click/tap places, Q or
-- build-mode exit cancels. GridPlacement's snap-to-cell idea is ADAPTed to
-- integer cell coords because the server's record stores cells, not studs.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local DecorConfig = require(Shared:WaitForChild("DecorConfig"))

local Catalog = DecorConfig.Catalog :: { [string]: DecorConfig.Decor }

local CELL_STUDS = 4 -- MUST match DecorService's grid model

local Placement = {}

local ctxRef: { [string]: any } = {}
local session: { instanceId: string, decorId: string, ry: number }? = nil
local ghost: Part? = nil
local connections: { RBXScriptConnection } = {}

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

local function footprint(decor: DecorConfig.Decor, ry: number): (number, number)
	if ry == 90 or ry == 270 then
		return decor.Footprint.D, decor.Footprint.W
	end
	return decor.Footprint.W, decor.Footprint.D
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
end

local function ensureGhost(decor: DecorConfig.Decor, ry: number): Part
	local w, d = footprint(decor, ry)
	if not ghost then
		local part = Instance.new("Part")
		part.Name = "DecorGhost"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 0.5
		part.Parent = Workspace
		ghost = part
	end
	local live = ghost :: Part
	live.Size = Vector3.new(w * CELL_STUDS, 2, d * CELL_STUDS)
	return live
end

-- Mouse ray -> integer cell coords on my Base (nil while off-plot). The same
-- corner-origin cell model DecorService validates.
local function solveCell(base: BasePart, decor: DecorConfig.Decor, ry: number): (number?, number?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil, nil
	end
	local mouse = UserInputService:GetMouseLocation()
	-- GetMouseLocation includes the top inset even with IgnoreGuiInset=true:
	-- subtract it or every placement skews ~58px in Play (ClickGame lesson).
	local inset = game:GetService("GuiService"):GetGuiInset()
	local ray = camera:ViewportPointToRay(mouse.X - inset.X, mouse.Y - inset.Y)
	local planeY = base.Position.Y + base.Size.Y / 2
	if math.abs(ray.Direction.Y) < 1e-6 then
		return nil, nil
	end
	local t = (planeY - ray.Origin.Y) / ray.Direction.Y
	if t <= 0 then
		return nil, nil
	end
	local hit = ray.Origin + ray.Direction * t
	local localHit = base.CFrame:PointToObjectSpace(hit)
	local w, d = footprint(decor, ry)
	local gridW = math.floor(base.Size.X / CELL_STUDS)
	local gridD = math.floor(base.Size.Z / CELL_STUDS)
	-- Corner origin: cell 0 starts at local -X/-Z. Snap the footprint CENTER
	-- to the hovered cell, clamped fully on-plot (preview slides along edges).
	local x = math.floor((localHit.X + base.Size.X / 2) / CELL_STUDS - w / 2 + 0.5)
	local z = math.floor((localHit.Z + base.Size.Z / 2) / CELL_STUDS - d / 2 + 0.5)
	x = math.clamp(x, 0, math.max(0, gridW - w))
	z = math.clamp(z, 0, math.max(0, gridD - d))
	return x, z
end

local function ghostCFrame(base: BasePart, decor: DecorConfig.Decor, ry: number, x: number, z: number): CFrame
	local w, d = footprint(decor, ry)
	local originX = -base.Size.X / 2 + (x + w / 2) * CELL_STUDS
	local originZ = -base.Size.Z / 2 + (z + d / 2) * CELL_STUDS
	return base.CFrame * CFrame.new(originX, base.Size.Y / 2 + 1, originZ) * CFrame.Angles(0, math.rad(ry), 0)
end

local function updateGhost()
	local live = session
	local base = myBase()
	if not (live and base) then
		return
	end
	local decor = Catalog[live.decorId]
	if not decor then
		return
	end
	local x, z = solveCell(base, decor, live.ry)
	if x == nil or z == nil then
		return
	end
	ensureGhost(decor, live.ry).CFrame = ghostCFrame(base, decor, live.ry, x :: number, z :: number)
end

local function endSession()
	session = nil
	clearGhost()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	ctxRef.buildCamera.Exit()
end

local function tryPlace()
	local live = session
	local base = myBase()
	if not (live and base) then
		return
	end
	local decor = Catalog[live.decorId]
	local x, z = solveCell(base, decor, live.ry)
	if x == nil or z == nil then
		return
	end
	task.spawn(function()
		local result = Net.invoke(Net.Names.PlaceDecor, live.instanceId, x, z, live.ry)
		if typeof(result) == "table" and result.success then
			endSession()
		end
		-- Refusals ("Something is already there.") keep the session alive so
		-- the player just moves the ghost and clicks again.
	end)
end

-- Start placing an owned decor instance (Catalog's "Place" button).
function Placement.Begin(instanceId: string, decorId: string)
	if not Catalog[decorId] then
		return
	end
	if session then
		endSession()
	end
	if not ctxRef.buildCamera.Enter() then
		return
	end
	session = { instanceId = instanceId, decorId = decorId, ry = 0 }
	updateGhost()

	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input, _processed)
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				updateGhost()
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				tryPlace()
			elseif input.KeyCode == Enum.KeyCode.R then
				local live = session
				if live then
					live.ry = (live.ry + 90) % 360
					updateGhost()
				end
			elseif input.KeyCode == Enum.KeyCode.Q then
				endSession()
			end
		end)
	)
end

function Placement.Recall(instanceId: string)
	task.spawn(function()
		Net.invoke(Net.Names.RecallDecor, instanceId)
	end)
end

function Placement.Init(ctx: { [string]: any })
	ctxRef = ctx
end

return Placement
