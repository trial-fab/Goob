--!strict
-- =============================================================================
-- Inventory/InventoryGrid — the slime-card grid + per-slime actions.
-- [Contract] Owns: rendering the owned-slime grid from ClientState (SlimeCard
--   clones; rarity/stage/mutation/nature chips) and wiring the five actions —
--   Ranch/Store toggle, Equip toggle, Release, Lock, Rename — each a
--   server-validated RemoteFunction round trip.
-- [Contract] Never: constructs GuiObjects (clones the SlimeCard template);
--   never mutates state locally (renders the next StateSync instead).
-- =============================================================================
--
-- Studio hand-off: ScreenGui.Inventory (Frame, hidden) with:
--   HeaderLabel  TextLabel ("Slimes 12/200 · Ranch 8/8")
--   Cards        ScrollingFrame
--     SlimeCard  Frame template (Visible = false): NameLabel, StageLabel,
--                MutationLabel, NatureLabel, RanchButton, EquipButton,
--                LockButton, ReleaseButton, RenameBox (TextBox)
--   Close        button (GuiNames.Close)
--
-- Equip is a TOGGLE against the current squad list: tap adds (if a slot is
-- free) or removes, then sends the FULL desired squad (EquipSquad's shape).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GuiNames = require(Shared:WaitForChild("GuiNames"))
local SlimeConfig = require(Shared:WaitForChild("SlimeConfig"))
local GrowthConfig = require(Shared:WaitForChild("GrowthConfig"))
local MutationConfig = require(Shared:WaitForChild("MutationConfig"))
local NatureConfig = require(Shared:WaitForChild("NatureConfig"))

local Species = SlimeConfig.Species :: { [string]: SlimeConfig.Species }
local Mutations = MutationConfig.Mutations :: { [string]: MutationConfig.Mutation }
local Natures = NatureConfig.Natures :: { [string]: NatureConfig.Nature }

local InventoryGrid = {}

local visible = false
local warned = false

local function setLabel(card: Frame, name: string, text: string)
	local label = card:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function wireButton(card: Frame, name: string, onTap: () -> ())
	local button = card:FindFirstChild(name)
	if button and button:IsA("GuiButton") then
		button.Activated:Connect(onTap)
	end
end

function InventoryGrid.Init(ctx: { [string]: any })
	local gui = ctx.gui :: ScreenGui

	local function frame(): Frame?
		local found = gui:FindFirstChild(GuiNames.Inventory)
		return if found and found:IsA("Frame") then found else nil
	end

	local function render()
		local inv = frame()
		if not (visible and inv) then
			return
		end
		local state = ctx.state.Get()
		local slimes = (state.Slimes or {}) :: { [string]: any }
		local roster = (state.Roster or {}) :: { string }
		local squad = (state.Squad or {}) :: { string }

		local header = inv:FindFirstChild("HeaderLabel")
		if header and header:IsA("TextLabel") then
			local owned = 0
			for _ in slimes do
				owned += 1
			end
			header.Text = ("Slimes %d · Ranch %d/%d · Squad %d/%d"):format(
				owned,
				#roster,
				state.Slots or 8,
				#squad,
				state.SquadSlots or 2
			)
		end

		local list = inv:FindFirstChild("Cards")
		local template = if list then list:FindFirstChild("SlimeCard") else nil
		if not (list and template and template:IsA("Frame")) then
			if not warned then
				warned = true
				warn("Inventory/InventoryGrid: Inventory.Cards.SlimeCard template not authored yet.")
			end
			return
		end

		-- Rebuild-on-sync: ≤200 cards, and syncs arrive on user actions — the
		-- simple render beats diffing until profiling says otherwise.
		for _, child in list:GetChildren() do
			if child ~= template and child.Name:sub(1, 10) == "SlimeCard_" then
				child:Destroy()
			end
		end

		-- Stable sort: ranch first, then newest hatch first.
		local ids = {}
		for slimeId in slimes do
			table.insert(ids, slimeId)
		end
		table.sort(ids, function(a, b)
			local aRanch = table.find(roster, a) ~= nil
			local bRanch = table.find(roster, b) ~= nil
			if aRanch ~= bRanch then
				return aRanch
			end
			return (slimes[a].T or 0) > (slimes[b].T or 0)
		end)

		for order, slimeId in ids do
			local record = slimes[slimeId]
			local species = Species[record.Sp]
			local card = template:Clone()
			card.Name = "SlimeCard_" .. slimeId
			card.LayoutOrder = order
			card.Visible = true

			local onRanch = table.find(roster, slimeId) ~= nil
			local equipped = table.find(squad, slimeId) ~= nil
			local mutation = Mutations[record.Mu]
			local nature = Natures[record.Nt]
			setLabel(card, "NameLabel", record.Nm or (if species then species.Name else record.Sp))
			setLabel(card, "StageLabel", GrowthConfig.Stages[record.St].Name)
			setLabel(card, "MutationLabel", if mutation and mutation.Tier > 0 then mutation.Name else "")
			setLabel(card, "NatureLabel", if nature then nature.Name else "")

			local ranchButton = card:FindFirstChild("RanchButton")
			if ranchButton and ranchButton:IsA("TextButton") then
				ranchButton.Text = if onRanch then "Store" else "Ranch"
			end
			wireButton(card, "RanchButton", function()
				Net.invoke(Net.Names.SetRanchState, slimeId, if onRanch then "storage" else "ranch")
			end)

			local equipButton = card:FindFirstChild("EquipButton")
			if equipButton and equipButton:IsA("TextButton") then
				equipButton.Text = if equipped then "Unequip" else "Equip"
			end
			wireButton(card, "EquipButton", function()
				local desired = table.clone(squad)
				local at = table.find(desired, slimeId)
				if at then
					table.remove(desired, at)
				else
					table.insert(desired, slimeId)
				end
				Net.invoke(Net.Names.EquipSquad, desired)
			end)

			local lockButton = card:FindFirstChild("LockButton")
			if lockButton and lockButton:IsA("TextButton") then
				lockButton.Text = if record.Lk then "Unlock" else "Lock"
			end
			wireButton(card, "LockButton", function()
				Net.invoke(Net.Names.SetSlimeLocked, slimeId, not record.Lk)
			end)

			wireButton(card, "ReleaseButton", function()
				Net.invoke(Net.Names.ReleaseSlime, slimeId)
			end)

			local renameBox = card:FindFirstChild("RenameBox")
			if renameBox and renameBox:IsA("TextBox") then
				renameBox.FocusLost:Connect(function(enterPressed)
					if enterPressed and #renameBox.Text > 0 then
						Net.invoke(Net.Names.RenameSlime, slimeId, renameBox.Text)
					end
				end)
			end

			card.Parent = list
		end
	end

	local slot = ctx.modals.register("Inventory", function()
		visible = false
		local inv = frame()
		if inv then
			inv.Visible = false
		end
	end, function()
		visible = true
		local inv = frame()
		if inv then
			inv.Visible = true
		end
		render()
	end)

	local function wireClose(inv: Frame)
		local close = inv:FindFirstChild(GuiNames.Close, true)
		if close and close:IsA("GuiButton") and not close:GetAttribute("InvWired") then
			close:SetAttribute("InvWired", true)
			close.Activated:Connect(function()
				visible = false
				inv.Visible = false
				slot.close()
			end)
		end
	end

	local existing = frame()
	if existing then
		wireClose(existing)
	end
	gui.ChildAdded:Connect(function(child)
		if child.Name == GuiNames.Inventory and child:IsA("Frame") then
			task.defer(wireClose, child)
		end
	end)

	ctx.state.OnChanged(function()
		render()
	end)
end

return InventoryGrid
