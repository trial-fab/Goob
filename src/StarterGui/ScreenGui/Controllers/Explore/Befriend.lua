--!strict
-- =============================================================================
-- Explore/Befriend — wild-slime prompts + the food-offer picker.
-- [Contract] Owns: attaching Befriend prompts to server-spawned wild slime
--   models, the FoodOfferPicker (owned special foods; favorite unknown until
--   discovered), and the BefriendAttempt round trip + result hints.
-- [Contract] Never: constructs GuiObjects (clones the FoodRow template);
--   never decides taming (renders the server verdict: interested / hint /
--   tamed fanfare via the Egg HatchReveal-style card is M2 polish).
-- =============================================================================
--
-- Studio hand-off: ScreenGui.FoodOfferPicker (Frame, hidden) with:
--   TitleLabel  TextLabel
--   Rows        Frame
--     FoodRow   Frame template (Visible = false): NameLabel, CountLabel,
--               OfferButton
--   HintLabel   TextLabel (server hints: "not interested" / favorite reveal)
--   Close       button (GuiNames.Close)

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GuiNames = require(Shared:WaitForChild("GuiNames"))
local FoodConfig = require(Shared:WaitForChild("FoodConfig"))
local SlimeConfig = require(Shared:WaitForChild("SlimeConfig"))

local Foods = FoodConfig.Foods :: { [string]: FoodConfig.Food }
local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }

local PICKER_NAME = "FoodOfferPicker" -- single-controller lookup

local Befriend = {}

local ctxRef: { [string]: any } = {}
local currentWildId: string? = nil
local offering = false

local function picker(): Frame?
	local gui = ctxRef.gui :: ScreenGui
	local found = gui:FindFirstChild(PICKER_NAME)
	return if found and found:IsA("Frame") then found else nil
end

local function setHint(text: string)
	local frame = picker()
	local hint = if frame then frame:FindFirstChild("HintLabel") else nil
	if hint and hint:IsA("TextLabel") then
		hint.Text = text
	end
end

local function renderPicker()
	local frame = picker()
	if not (frame and currentWildId) then
		return
	end
	local rows = frame:FindFirstChild("Rows")
	local template = if rows then rows:FindFirstChild("FoodRow") else nil
	if not (rows and template and template:IsA("Frame")) then
		warn("Explore/Befriend: FoodOfferPicker.Rows.FoodRow template not authored yet.")
		return
	end
	for _, child in rows:GetChildren() do
		if child ~= template and child.Name:sub(1, 8) == "FoodRow_" then
			child:Destroy()
		end
	end

	local owned = (ctxRef.state.Get().Foods or {}) :: { [string]: number }
	local order = 0
	for foodId, food in Foods do
		local count = owned[foodId] or 0
		if count > 0 then
			order += 1
			local row = template:Clone()
			row.Name = "FoodRow_" .. foodId
			row.LayoutOrder = order
			row.Visible = true
			local name = row:FindFirstChild("NameLabel")
			if name and name:IsA("TextLabel") then
				name.Text = food.Name
			end
			local countLabel = row:FindFirstChild("CountLabel")
			if countLabel and countLabel:IsA("TextLabel") then
				countLabel.Text = "×" .. count
			end
			local offer = row:FindFirstChild("OfferButton")
			if offer and offer:IsA("GuiButton") then
				offer.Activated:Connect(function()
					if offering or not currentWildId then
						return
					end
					offering = true
					local result = Net.invoke(Net.Names.BefriendAttempt, currentWildId, foodId)
					offering = false
					if typeof(result) ~= "table" then
						return
					end
					if result.success and result.tamed then
						setHint("Befriended! It joins your ranch.")
						currentWildId = nil
						task.delay(1.5, function()
							local f = picker()
							if f then
								f.Visible = false
							end
						end)
					elseif result.success and result.interested then
						setHint(("It loves that! %d/%d"):format(result.fed or 0, result.needed or 0))
						renderPicker() -- food counts changed
					elseif result.success then
						setHint(if result.hint then "Not interested... it wants " .. result.hint else "Not interested.")
						renderPicker()
					else
						setHint(result.message or "Try again.")
					end
				end)
			end
			row.Parent = rows
		end
	end
	if order == 0 then
		setHint("You have no special foods — gather some at the nodes.")
	end
end

local function openPicker(wildId: string, speciesId: string?)
	currentWildId = wildId
	local frame = picker()
	if not frame then
		warn("Explore/Befriend: FoodOfferPicker template not authored yet — befriend UI pending.")
		return
	end
	local title = frame:FindFirstChild("TitleLabel")
	if title and title:IsA("TextLabel") then
		local species = if speciesId then Species[speciesId] else nil
		title.Text = "Offer food to " .. (if species then species.Name else "the wild slime")
	end
	setHint("Pick a food to offer. Its favorite tames it.")
	renderPicker()
	local close = frame:FindFirstChild(GuiNames.Close, true)
	if close and close:IsA("GuiButton") and not close:GetAttribute("BefriendWired") then
		close:SetAttribute("BefriendWired", true)
		close.Activated:Connect(function()
			frame.Visible = false
			currentWildId = nil
		end)
	end
	frame.Visible = true
end

local function attachPrompt(model: Instance)
	if not model:IsA("Model") or model.Name ~= "WildSlime" then
		return
	end
	local wildId = model:GetAttribute("WildId")
	local speciesId = model:GetAttribute("SpeciesId")
	local primary = model.PrimaryPart
	if typeof(wildId) ~= "string" or not primary then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BefriendPrompt"
	prompt.ActionText = "Offer food"
	prompt.ObjectText = "Wild slime"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 14
	prompt.Parent = primary
	prompt.Triggered:Connect(function()
		openPicker(wildId, if typeof(speciesId) == "string" then speciesId else nil)
	end)
end

function Befriend.Init(ctx: { [string]: any })
	ctxRef = ctx

	-- Wild models live under Workspace.Zones.<zoneId> (server spawns them at
	-- Studio spawn points); watch the whole Zones tree.
	task.spawn(function()
		local zones = Workspace:WaitForChild("Zones", 60)
		if not zones then
			return
		end
		for _, descendant in zones:GetDescendants() do
			attachPrompt(descendant)
		end
		zones.DescendantAdded:Connect(function(descendant)
			task.defer(attachPrompt, descendant)
		end)
	end)

	-- A despawn/steal while the picker is open: drop the stale target.
	Net.on(Net.Names.WildSpawnChanged, function(list: { { [string]: any } })
		if not currentWildId or typeof(list) ~= "table" then
			return
		end
		for _, spawn in list do
			if spawn.Id == currentWildId then
				return
			end
		end
		currentWildId = nil
		setHint("It wandered off...")
	end)
end

return Befriend
