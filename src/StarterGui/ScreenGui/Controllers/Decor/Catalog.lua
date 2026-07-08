--!strict
-- =============================================================================
-- Decor/Catalog — the decor catalog drawer + owned-pieces list.
-- [Contract] Owns: rendering DecorConfig's catalog (DecorCard clones with
--   Goo/Gem price + Buy), the owned-but-unplaced list ("Place" starts a
--   Placement session; "Recall" pulls a placed piece), and the BuyDecor
--   round trip.
-- [Contract] Never: constructs GuiObjects (clones DecorCard/OwnedRow); never
--   prices anything (DecorConfig is the display AND the server's charge).
-- =============================================================================
--
-- Studio hand-off: ScreenGui.DecorCatalog (Frame, hidden) with:
--   Cards       ScrollingFrame
--     DecorCard Frame template (Visible = false): NameLabel, CostLabel,
--               BuyButton
--   Owned       Frame/ScrollingFrame
--     OwnedRow  Frame template (Visible = false): NameLabel, PlaceButton,
--               RecallButton
--   Close       button (GuiNames.Close)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GuiNames = require(Shared:WaitForChild("GuiNames"))
local DecorConfig = require(Shared:WaitForChild("DecorConfig"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local DecorCatalog = DecorConfig.Catalog :: { [string]: DecorConfig.Decor }

local Catalog = {}

local ctxRef: { [string]: any } = {}
local visible = false
local built = false
local buying = false
local warned = false

local function frame(): Frame?
	local gui = ctxRef.gui :: ScreenGui
	local found = gui:FindFirstChild(GuiNames.DecorCatalog)
	return if found and found:IsA("Frame") then found else nil
end

local function buildCards(panel: Frame)
	if built then
		return
	end
	local list = panel:FindFirstChild("Cards")
	local template = if list then list:FindFirstChild("DecorCard") else nil
	if not (list and template and template:IsA("Frame")) then
		if not warned then
			warned = true
			warn("Decor/Catalog: DecorCatalog.Cards.DecorCard template not authored yet.")
		end
		return
	end
	built = true

	local ids = {}
	for id in DecorCatalog do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local costA = DecorCatalog[a].CostGoo or ((DecorCatalog[a].CostGems or 0) * 1e15)
		local costB = DecorCatalog[b].CostGoo or ((DecorCatalog[b].CostGems or 0) * 1e15)
		return costA < costB
	end)

	for order, decorId in ids do
		local decor = DecorCatalog[decorId]
		local card = template:Clone()
		card.Name = "DecorCard_" .. decorId
		card.LayoutOrder = order
		card.Visible = true
		local name = card:FindFirstChild("NameLabel")
		if name and name:IsA("TextLabel") then
			name.Text = decor.Name
		end
		local cost = card:FindFirstChild("CostLabel")
		if cost and cost:IsA("TextLabel") then
			cost.Text = if decor.CostGoo
				then NumberFormat.abbreviate(decor.CostGoo)
				else NumberFormat.abbreviate(decor.CostGems or 0) .. " Gems"
		end
		local buy = card:FindFirstChild("BuyButton")
		if buy and buy:IsA("GuiButton") then
			buy.Activated:Connect(function()
				if buying then
					return
				end
				buying = true
				Net.invoke(Net.Names.BuyDecor, decorId)
				buying = false
				-- StateSync refreshes the owned list.
			end)
		end
		card.Parent = list
	end
end

local function renderOwned()
	local panel = frame()
	if not (visible and panel) then
		return
	end
	local list = panel:FindFirstChild("Owned")
	local template = if list then list:FindFirstChild("OwnedRow") else nil
	if not (list and template and template:IsA("Frame")) then
		return
	end
	for _, child in list:GetChildren() do
		if child ~= template and child.Name:sub(1, 9) == "OwnedRow_" then
			child:Destroy()
		end
	end

	local owned = (ctxRef.state.Get().Decor or {}) :: { [string]: any }
	local order = 0
	for instanceId, record in owned do
		local decor = DecorCatalog[record.Id]
		if decor then
			order += 1
			local row = template:Clone()
			row.Name = "OwnedRow_" .. instanceId
			row.LayoutOrder = order
			row.Visible = true
			local name = row:FindFirstChild("NameLabel")
			if name and name:IsA("TextLabel") then
				name.Text = decor.Name .. (if record.P then " (placed)" else "")
			end
			local place = row:FindFirstChild("PlaceButton")
			if place and place:IsA("GuiButton") then
				place.Activated:Connect(function()
					ctxRef.modals.closeAll() -- placement owns the screen now
					ctxRef.placement.Begin(instanceId, record.Id)
				end)
			end
			local recall = row:FindFirstChild("RecallButton")
			if recall and recall:IsA("GuiButton") then
				recall.Visible = record.P == true
				recall.Activated:Connect(function()
					ctxRef.placement.Recall(instanceId)
				end)
			end
			row.Parent = list
		end
	end
end

function Catalog.Init(ctx: { [string]: any })
	ctxRef = ctx
	local gui = ctx.gui :: ScreenGui

	local slot = ctx.modals.register("Decor", function()
		visible = false
		local panel = frame()
		if panel then
			panel.Visible = false
		end
	end, function()
		visible = true
		local panel = frame()
		if panel then
			buildCards(panel)
			panel.Visible = true
		end
		renderOwned()
	end)

	local function wireClose(panel: Frame)
		local close = panel:FindFirstChild(GuiNames.Close, true)
		if close and close:IsA("GuiButton") and not close:GetAttribute("DecorWired") then
			close:SetAttribute("DecorWired", true)
			close.Activated:Connect(function()
				visible = false
				panel.Visible = false
				slot.close()
			end)
		end
	end
	local existing = frame()
	if existing then
		wireClose(existing)
	end
	gui.ChildAdded:Connect(function(child)
		if child.Name == GuiNames.DecorCatalog and child:IsA("Frame") then
			task.defer(wireClose, child)
		end
	end)

	ctx.state.OnChanged(function()
		renderOwned()
	end)
end

return Catalog
