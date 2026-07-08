--!strict
-- =============================================================================
-- Decor/BuildCamera — the Build View placement camera (ClickGame ADAPT).
-- [Contract] Owns: entering/leaving the decor build-mode camera — a pitched
--   3/4 view framing the player's plot (framing math ported from ClickGame's
--   BuildViewCamera), scroll dolly, and restoring the normal camera on exit.
--   Owns the ScreenGui PlacementActive attribute.
-- [Contract] Never: places anything (Placement owns the ghost + remote);
--   never fights the default camera outside build mode.
-- =============================================================================
--
-- Port note (DESIGN §6): ClickGame's free-fly glide/momentum controller is
-- 1200+ lines; M1 decor needs frame + dolly, so this ports the pure framing
-- math (framePose/lookDirection) and keeps the input surface minimal. The
-- full glide can be lifted later without touching Placement.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Attrs = require(Shared:WaitForChild("Attrs"))

local PITCH = math.rad(55) -- ClickGame's comfortable 3/4 "creative" view
local FOV = 60
local FRAME_AIR = 1.1 -- breathing room multiplier around the plot
local MARGIN_STUDS = 9
local MIN_DISTANCE = 16
local MAX_DISTANCE = 400
local DOLLY_STEP = 6

local BuildCamera = {}

local ctxRef: { [string]: any } = {}
local active = false
local savedType: Enum.CameraType? = nil
local distance = 60
local scrollConnection: RBXScriptConnection? = nil

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

-- Ported lookDirection: plot-aligned horizontal forward pitched down.
local function lookDirection(base: BasePart): Vector3
	local forward = base.CFrame.LookVector
	forward = Vector3.new(forward.X, 0, forward.Z)
	if forward.Magnitude < 1e-4 then
		forward = Vector3.new(0, 0, 1)
	end
	forward = forward.Unit
	return (forward * math.cos(PITCH) + Vector3.new(0, -1, 0) * math.sin(PITCH)).Unit
end

-- Ported framePose: dolly distance from the plot's bounding radius vs FOV.
local function frameDistance(base: BasePart): number
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local aspect = math.max(viewport.X / math.max(viewport.Y, 1), 0.1)
	local halfX = base.Size.X / 2 + MARGIN_STUDS
	local halfZ = base.Size.Z / 2 + MARGIN_STUDS
	local boundingRadius = math.sqrt(halfX * halfX + halfZ * halfZ)
	local vertHalf = math.rad(FOV / 2)
	local horizHalf = math.atan(math.tan(vertHalf) * aspect)
	local limitingHalf = math.min(vertHalf, horizHalf)
	return math.clamp((boundingRadius / math.tan(limitingHalf)) * FRAME_AIR, MIN_DISTANCE, MAX_DISTANCE)
end

local function apply(base: BasePart)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local look = lookDirection(base)
	local center = base.Position + Vector3.new(0, base.Size.Y / 2, 0)
	local position = center - look * distance
	camera.CFrame = CFrame.lookAt(position, position + look, Vector3.new(0, 1, 0))
end

function BuildCamera.IsActive(): boolean
	return active
end

function BuildCamera.Enter(): boolean
	if active then
		return true
	end
	local base = myBase()
	local camera = Workspace.CurrentCamera
	if not (base and camera) then
		warn("Decor/BuildCamera: no plot Base part yet — build view needs the Studio world.")
		return false
	end
	active = true
	savedType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	distance = frameDistance(base)
	apply(base)
	local gui = ctxRef.gui :: ScreenGui
	gui:SetAttribute(Attrs.PlacementActive, true)

	scrollConnection = UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if processed or not active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			distance = math.clamp(distance - input.Position.Z * DOLLY_STEP, MIN_DISTANCE, MAX_DISTANCE)
			local liveBase = myBase()
			if liveBase then
				apply(liveBase)
			end
		end
	end)
	return true
end

function BuildCamera.Exit()
	if not active then
		return
	end
	active = false
	if scrollConnection then
		scrollConnection:Disconnect()
		scrollConnection = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = savedType or Enum.CameraType.Custom
	end
	local gui = ctxRef.gui :: ScreenGui
	gui:SetAttribute(Attrs.PlacementActive, false)
end

function BuildCamera.Init(ctx: { [string]: any })
	ctxRef = ctx
	local gui = ctx.gui :: ScreenGui
	gui:SetAttribute(Attrs.PlacementActive, false)
end

return BuildCamera
