--!strict
-- =============================================================================
-- Slime/Interact — Feed/Pet prompts on the local player's ranch slimes.
-- [Contract] Owns: ProximityPrompts on OWN slime models (Feed with live cost
--   from GrowthConfig.FeedCost — the same function the server charges; Pet as
--   a local heart/squish response), and the FeedSlime round trip.
-- [Contract] Never: attaches economy prompts to other players' slimes; never
--   charges or advances anything locally (renders the server result).
-- =============================================================================
--
-- ProximityPrompts are interaction Instances (not GuiObjects) and attach to
-- the client-simulated position by parenting to the model — exactly the §5
-- "prompts attach to the client-simulated position" note.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local SlimeConfig = require(Shared:WaitForChild("SlimeConfig"))
local GrowthConfig = require(Shared:WaitForChild("GrowthConfig"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }
local MAX_STAGE = #GrowthConfig.Stages

local Interact = {}

local feeding = false

local function feedActionText(model: Model): string
	local speciesId = model:GetAttribute(Attrs.SpeciesId)
	local stage = model:GetAttribute(Attrs.Stage)
	if typeof(speciesId) ~= "string" or typeof(stage) ~= "number" or stage >= MAX_STAGE then
		return "Fully grown"
	end
	local species = Species[speciesId]
	if not species then
		return "Feed"
	end
	return "Feed (" .. NumberFormat.abbreviate(GrowthConfig.FeedCost(species.Base, stage)) .. ")"
end

local function petResponse(model: Model)
	-- Local-only flourish: a quick squash. Nature-flavored hearts ride the
	-- Studio VFX pass (PetsForHeart lives in NatureConfig for it).
	local primary = model.PrimaryPart
	if primary then
		TweenService:Create(primary, TweenInfo.new(0.15, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out, 0, true), {
			Size = primary.Size * Vector3.new(1.15, 0.8, 1.15),
		}):Play()
	end
end

local function attach(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local slimeId = model:GetAttribute(Attrs.SlimeId)
	local ownerUserId = model:GetAttribute(Attrs.OwnerUserId)
	if typeof(slimeId) ~= "string" or ownerUserId ~= Players.LocalPlayer.UserId then
		return
	end
	local primary = model.PrimaryPart
	if not primary then
		return
	end

	local feed = Instance.new("ProximityPrompt")
	feed.Name = "FeedPrompt"
	feed.ActionText = feedActionText(model)
	feed.ObjectText = "Slime"
	feed.KeyboardKeyCode = Enum.KeyCode.E
	feed.RequiresLineOfSight = false
	feed.MaxActivationDistance = 12
	feed.Parent = primary

	local pet = Instance.new("ProximityPrompt")
	pet.Name = "PetPrompt"
	pet.ActionText = "Pet"
	pet.UIOffset = Vector2.new(0, 40)
	pet.KeyboardKeyCode = Enum.KeyCode.F
	pet.RequiresLineOfSight = false
	pet.MaxActivationDistance = 12
	pet.Parent = primary

	feed.Triggered:Connect(function()
		if feeding then
			return
		end
		feeding = true
		local result = Net.invoke(Net.Names.FeedSlime, slimeId)
		feeding = false
		if typeof(result) == "table" and result.success then
			feed.ActionText = feedActionText(model)
			if result.stageUp then
				petResponse(model) -- size pop lands via the server's ScaleTo
			end
		elseif typeof(result) == "table" and result.message then
			feed.ActionText = result.message
			task.delay(2, function()
				feed.ActionText = feedActionText(model)
			end)
		end
	end)

	pet.Triggered:Connect(function()
		petResponse(model)
	end)

	-- Stage attribute changes re-price the prompt (server refreshes attrs).
	model:GetAttributeChangedSignal(Attrs.Stage):Connect(function()
		feed.ActionText = feedActionText(model)
	end)
end

function Interact.Init(_ctx: { [string]: any })
	task.spawn(function()
		local folder = Workspace:WaitForChild("RanchSlimes", 60)
		if not folder then
			return
		end
		for _, child in folder:GetChildren() do
			attach(child)
		end
		folder.ChildAdded:Connect(function(child)
			-- Attributes land with the server clone; defer one step in case.
			task.defer(attach, child)
		end)
	end)
end

return Interact
