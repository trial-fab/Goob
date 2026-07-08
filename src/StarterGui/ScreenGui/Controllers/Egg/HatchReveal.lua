--!strict
-- =============================================================================
-- Egg/HatchReveal — the hatch reveal overlay.
-- [Contract] Owns: showing the server's hatch RESULT (species/mutation/nature,
--   rarity flavor, to-storage toast) on the Studio HatchReveal overlay. Pure
--   presentation of a completed server roll — the slime already exists.
-- [Contract] Never: constructs GuiObjects; never anticipates a roll (nothing
--   shows until the BuyEgg result table arrives).
-- =============================================================================
--
-- Studio hand-off: ScreenGui.HatchReveal (Frame, hidden; full-screen) with
-- SpeciesLabel, MutationLabel, NatureLabel, NoteLabel, ContinueButton.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SlimeConfig = require(Shared:WaitForChild("SlimeConfig"))
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))
local NatureConfig = require(Shared:WaitForChild("NatureConfig"))

local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }
local Mutations = MutationConfig.Mutations :: { [string]: MutationConfig.Mutation }
local Natures = NatureConfig.Natures :: { [string]: NatureConfig.Nature }

local REVEAL_NAME = "HatchReveal" -- single-controller lookup

local HatchReveal = {}

local ctxRef: { [string]: any } = {}

local function overlay(): Frame?
	local gui = ctxRef.gui :: ScreenGui
	local found = gui:FindFirstChild(REVEAL_NAME)
	return if found and found:IsA("Frame") then found else nil
end

local function setLabel(frame: Frame, name: string, text: string)
	local label = frame:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function wireContinue(frame: Frame)
	local continueButton = frame:FindFirstChild("ContinueButton")
	if continueButton and continueButton:IsA("GuiButton") and not continueButton:GetAttribute("RevealWired") then
		continueButton:SetAttribute("RevealWired", true)
		continueButton.Activated:Connect(function()
			frame.Visible = false
		end)
	end
end

-- Show a hatch result table ({ SpeciesId, Mutation, Nature, ToStorage }).
function HatchReveal.Show(slime: { [string]: any }?)
	local frame = overlay()
	if not (frame and slime) then
		return
	end
	local species = Species[slime.SpeciesId]
	local mutation = Mutations[slime.Mutation]
	local nature = Natures[slime.Nature]
	setLabel(frame, "SpeciesLabel", if species then ("%s (%s)"):format(species.Name, species.Rarity) else "?")
	setLabel(frame, "MutationLabel", if mutation and mutation.Tier > 0 then mutation.Name else "")
	setLabel(frame, "NatureLabel", if nature then nature.Name .. " — " .. nature.Blurb else "")
	setLabel(
		frame,
		"NoteLabel",
		if slime.ToStorage then "Your ranch is full — sent to storage." else "It hops onto your ranch!"
	)
	wireContinue(frame)
	frame.Visible = true
end

-- Failure toast path (e.g. "Not enough Goo") using the same overlay.
function HatchReveal.ShowMessage(message: string)
	local frame = overlay()
	if not frame then
		return
	end
	setLabel(frame, "SpeciesLabel", "")
	setLabel(frame, "MutationLabel", "")
	setLabel(frame, "NatureLabel", "")
	setLabel(frame, "NoteLabel", message)
	wireContinue(frame)
	frame.Visible = true
end

function HatchReveal.Init(ctx: { [string]: any })
	ctxRef = ctx
end

return HatchReveal
