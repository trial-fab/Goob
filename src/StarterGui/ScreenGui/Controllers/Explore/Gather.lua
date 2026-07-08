--!strict
-- =============================================================================
-- Explore/Gather — prompts on gathering nodes.
-- [Contract] Owns: attaching Gather prompts to Studio-authored node parts
--   (NodeId attribute) and the GatherNode round trip, rendering yields and
--   cooldowns in the prompt text.
-- [Contract] Never: times respawns locally (the server cooldown is the truth;
--   the prompt just displays the refusal); never derives yields.
-- =============================================================================
--
-- Studio hand-off (docs/studio-handoff.md): node parts anywhere under
-- Workspace.Zones.<zoneId> with a string attribute NodeId =
-- "<zoneId>/<nodeConfigId>/<n>" (n = 1..Node.Count from ZoneConfig).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Gather = {}

local gathering = false

local function attach(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local nodeId = part:GetAttribute("NodeId")
	if typeof(nodeId) ~= "string" then
		return
	end
	if part:FindFirstChild("GatherPrompt") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GatherPrompt"
	prompt.ActionText = "Gather"
	prompt.ObjectText = "Node"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.Parent = part

	prompt.Triggered:Connect(function()
		if gathering then
			return
		end
		gathering = true
		local result = Net.invoke(Net.Names.GatherNode, nodeId)
		gathering = false
		if typeof(result) ~= "table" then
			return
		end
		if result.success then
			if result.kind == "Goo" then
				prompt.ActionText = "+" .. NumberFormat.abbreviate(result.value or 0) .. " Goo"
			else
				prompt.ActionText = ("+%d %s"):format(result.count or 1, result.foodName or "food")
			end
			task.delay(2, function()
				prompt.ActionText = "Gather"
			end)
		else
			prompt.ActionText = result.message or "Not ready"
			task.delay(2, function()
				prompt.ActionText = "Gather"
			end)
		end
	end)
end

function Gather.Init(_ctx: { [string]: any })
	task.spawn(function()
		local zones = Workspace:WaitForChild("Zones", 60)
		if not zones then
			warn("Explore/Gather: Workspace.Zones not authored yet — node prompts pending world.")
			return
		end
		for _, descendant in zones:GetDescendants() do
			attach(descendant)
		end
		zones.DescendantAdded:Connect(function(descendant)
			task.defer(attach, descendant)
		end)
	end)
end

return Gather
