--!strict
-- =============================================================================
-- Egg/OddsPopup — the policy-required odds disclosure.
-- [Contract] Owns: rendering an egg's FULL outcome list with exact percentages
--   (straight from EggConfig — the SAME table the server rolls from), the
--   uniform nature disclosure, and active luck modifiers (numerically, when
--   BoostService lands).
-- [Contract] Never: constructs GuiObjects (clones the OddsRow template);
--   never rounds/derives its own numbers — a rendered percent that differs
--   from the rolled percent is a policy violation, not a bug (§4).
-- =============================================================================
--
-- Studio hand-off: ScreenGui.OddsPopup (Frame, hidden) with:
--   TitleLabel   TextLabel
--   Rows         Frame/ScrollingFrame
--     OddsRow    Frame template (Visible = false): NameLabel, PercentLabel
--   NatureLabel  TextLabel (renders NatureConfig.RollDisclosure)
--   LuckLabel    TextLabel (modifier line)
--   Close        button (GuiNames.Close)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GuiNames = require(Shared:WaitForChild("GuiNames"))
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local SlimeConfig = require(Shared:WaitForChild("SlimeConfig"))
local NatureConfig = require(Shared:WaitForChild("NatureConfig"))

local Eggs = EggConfig.Eggs :: { [string]: EggConfig.Egg }
local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }

local POPUP_NAME = "OddsPopup" -- single-controller lookup

local OddsPopup = {}

local ctxRef: { [string]: any } = {}

local function popup(): Frame?
	local gui = ctxRef.gui :: ScreenGui
	local found = gui:FindFirstChild(POPUP_NAME)
	return if found and found:IsA("Frame") then found else nil
end

function OddsPopup.Hide()
	local frame = popup()
	if frame then
		frame.Visible = false
	end
end

-- Render the odds table for one egg, verbatim from EggConfig. Percentages are
-- printed with just enough precision to be exact on the 0.25 grid.
function OddsPopup.Show(eggId: string)
	local egg = Eggs[eggId]
	local frame = popup()
	if not egg then
		return
	end
	if not frame then
		warn("Egg/OddsPopup: OddsPopup template not authored yet — odds UI pending Studio UI.")
		return
	end

	local title = frame:FindFirstChild("TitleLabel")
	if title and title:IsA("TextLabel") then
		title.Text = egg.Name .. " — odds"
	end

	local rows = frame:FindFirstChild("Rows")
	local template = if rows then rows:FindFirstChild("OddsRow") else nil
	if rows and template and template:IsA("Frame") then
		for _, child in rows:GetChildren() do
			if child ~= template and child.Name:sub(1, 8) == "OddsRow_" then
				child:Destroy()
			end
		end
		-- Highest odds first, ties by name — the §4 "full outcome list".
		local speciesIds = {}
		for speciesId in egg.Odds do
			table.insert(speciesIds, speciesId)
		end
		table.sort(speciesIds, function(a, b)
			if egg.Odds[a] ~= egg.Odds[b] then
				return egg.Odds[a] > egg.Odds[b]
			end
			return a < b
		end)
		for order, speciesId in speciesIds do
			local row = template:Clone()
			row.Name = "OddsRow_" .. speciesId
			row.LayoutOrder = order
			row.Visible = true
			local name = row:FindFirstChild("NameLabel")
			if name and name:IsA("TextLabel") then
				local species = Species[speciesId]
				name.Text = ("%s (%s)"):format(species.Name, species.Rarity)
			end
			local percent = row:FindFirstChild("PercentLabel")
			if percent and percent:IsA("TextLabel") then
				-- %g keeps 0.25-grid values exact ("14.5", never "14.50000").
				percent.Text = ("%g%%"):format(egg.Odds[speciesId])
			end
			row.Parent = rows
		end
	end

	local nature = frame:FindFirstChild("NatureLabel")
	if nature and nature:IsA("TextLabel") then
		nature.Text = NatureConfig.RollDisclosure
	end
	local luck = frame:FindFirstChild("LuckLabel")
	if luck and luck:IsA("TextLabel") then
		-- BoostService (session 4) swaps this for the numeric modifier line.
		luck.Text = "No luck modifiers active."
	end

	local close = frame:FindFirstChild(GuiNames.Close, true)
	if close and close:IsA("GuiButton") and not close:GetAttribute("OddsWired") then
		close:SetAttribute("OddsWired", true)
		close.Activated:Connect(OddsPopup.Hide)
	end

	frame.Visible = true
end

function OddsPopup.Init(ctx: { [string]: any })
	ctxRef = ctx
end

return OddsPopup
