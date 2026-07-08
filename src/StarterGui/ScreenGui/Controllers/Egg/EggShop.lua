--!strict
-- =============================================================================
-- Egg/EggShop — the egg shop modal (bottom-shell pattern, ADAPTed).
-- [Contract] Owns: rendering purchasable eggs as cloned EggCard rows (live
--   cost from EggConfig.Cost × the player's EggCounts), the Hatch button ->
--   BuyEgg round trip, and handing results to HatchReveal / odds requests to
--   OddsPopup.
-- [Contract] Never: constructs GuiObjects (clones the Studio EggCard template
--   only); never rolls or prices anything locally beyond displaying
--   EggConfig.Cost (the same function the server charges — §8 W6).
-- =============================================================================
--
-- Studio hand-off: ScreenGui.EggShop (Frame, hidden) with:
--   Cards        ScrollingFrame
--     EggCard    Frame template (Visible = false): NameLabel, CostLabel,
--                HatchButton, OddsButton
--   Close        button (GuiNames.Close)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GuiNames = require(Shared:WaitForChild("GuiNames"))
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Eggs = EggConfig.Eggs :: { [string]: EggConfig.Egg }

local EggShop = {}

local cards: { [string]: Frame } = {} -- eggId -> cloned card
local buying = false
local warned = false

-- Purchasable eggs in ladder order (cheapest line first).
local function shopEggIds(): { string }
	local ids = {}
	for id, egg in Eggs do
		if egg.Purchasable then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		return Eggs[a].BaseCost < Eggs[b].BaseCost
	end)
	return ids
end

local function refreshCosts(state: { [string]: any })
	local counts = (state.EggCounts or {}) :: { [string]: number }
	for eggId, card in cards do
		local cost = card:FindFirstChild("CostLabel")
		if cost and cost:IsA("TextLabel") then
			cost.Text = NumberFormat.abbreviate(EggConfig.Cost(eggId, counts[eggId] or 0))
		end
	end
end

function EggShop.Init(ctx: { [string]: any })
	local gui = ctx.gui :: ScreenGui

	local function frame(): Frame?
		local found = gui:FindFirstChild(GuiNames.EggShop)
		return if found and found:IsA("Frame") then found else nil
	end

	local function setVisible(visible: boolean)
		local shop = frame()
		if shop then
			shop.Visible = visible
		end
	end

	local slot = ctx.modals.register("EggShop", function()
		setVisible(false)
	end, function()
		setVisible(true)
	end)

	local function build(shop: Frame)
		local list = shop:FindFirstChild("Cards")
		local template = if list then list:FindFirstChild("EggCard") else nil
		if not (list and template and template:IsA("Frame")) then
			if not warned then
				warned = true
				warn("Egg/EggShop: EggShop.Cards.EggCard template not authored yet — shop pending Studio UI.")
			end
			return
		end
		local close = shop:FindFirstChild(GuiNames.Close, true)
		if close and close:IsA("GuiButton") then
			close.Activated:Connect(function()
				setVisible(false)
				slot.close()
			end)
		end

		for order, eggId in shopEggIds() do
			local egg = Eggs[eggId]
			local card = template:Clone()
			card.Name = "EggCard_" .. eggId
			card.LayoutOrder = order
			card.Visible = true
			local name = card:FindFirstChild("NameLabel")
			if name and name:IsA("TextLabel") then
				name.Text = egg.Name
			end
			local hatch = card:FindFirstChild("HatchButton")
			if hatch and hatch:IsA("GuiButton") then
				hatch.Activated:Connect(function()
					if buying then
						return
					end
					buying = true
					local result = Net.invoke(Net.Names.BuyEgg, eggId)
					buying = false
					if typeof(result) == "table" and result.success then
						ctx.hatchReveal.Show(result.slime)
					elseif typeof(result) == "table" and result.message then
						ctx.hatchReveal.ShowMessage(result.message)
					end
				end)
			end
			local odds = card:FindFirstChild("OddsButton")
			if odds and odds:IsA("GuiButton") then
				odds.Activated:Connect(function()
					ctx.oddsPopup.Show(eggId)
				end)
			end
			card.Parent = list
			cards[eggId] = card
		end
		refreshCosts(ctx.state.Get())
	end

	local existing = frame()
	if existing then
		build(existing)
	end
	gui.ChildAdded:Connect(function(child)
		if child.Name == GuiNames.EggShop and child:IsA("Frame") and next(cards) == nil then
			task.defer(build, child)
		end
	end)

	ctx.state.OnChanged(refreshCosts)
end

return EggShop
