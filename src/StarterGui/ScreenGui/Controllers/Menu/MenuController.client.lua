--!strict
-- =============================================================================
-- MenuController — bottom bar + menu pill wiring.
-- [Contract] Owns: the top-right menu pill (Settings/Profile/Quests buttons —
--   ClickGame MenuPill pattern ADAPTed) and the bottom bar buttons that open
--   the Shop/Inventory/Index/Trade/Explore modals (DESIGN.md §7.1). Buttons
--   route through ModalCoordinator.request — Menu opens nothing itself.
--
-- [Contract] Pattern (all client domains): a thin orchestrator (this file) +
--   focused ctx-based ModuleScripts it coordinates. Call modules through their
--   ctx.<module> handle — NEVER re-alias them as top-level locals (the
--   200-local-cap lesson, WORKFLOW.md).
-- [Contract] Never: constructs GuiObjects — ALL UI instances are authored by
--   the user in Studio; code owns logic only (WORKFLOW.md). New UI needs a
--   default-color Studio template handed off for styling.
-- =============================================================================
--
-- Studio hand-off: ScreenGui.BottomBar with buttons named GuiNames.ShopButton/
-- InventoryButton/IndexButton/TradeButton/ExploreButton; ScreenGui.MenuPill
-- with SettingsButton/ProfileButton/QuestsButton.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GuiNames = require(Shared:WaitForChild("GuiNames"))
local Modals = require(script.Parent.Parent:WaitForChild("Modals"):WaitForChild("ModalCoordinator"))

local gui = script:FindFirstAncestorOfClass("ScreenGui") :: ScreenGui

-- button name -> the modal name it requests (modal names are the register()
-- keys their owning controllers use).
local BUTTON_TO_MODAL: { [string]: string } = {
	[GuiNames.ShopButton] = "EggShop",
	[GuiNames.InventoryButton] = "Inventory",
	[GuiNames.IndexButton] = "Index", -- M2 domain; request is a harmless no-op until it registers
	[GuiNames.TradeButton] = "Trade", -- M2 domain
	[GuiNames.ExploreButton] = "Explore",
	[GuiNames.SettingsButton] = "Settings",
	[GuiNames.ProfileButton] = "Profile",
	[GuiNames.QuestsButton] = "Quests",
	[GuiNames.DecorButton] = "Decor",
}

local wired: { [Instance]: boolean } = {}

local function wireButtons(container: Instance)
	for _, descendant in container:GetDescendants() do
		local modalName = BUTTON_TO_MODAL[descendant.Name]
		if modalName and descendant:IsA("GuiButton") and not wired[descendant] then
			wired[descendant] = true
			descendant.Activated:Connect(function()
				if Modals.current() == modalName then
					Modals.closeAll() -- same button toggles its modal shut
				else
					Modals.request(modalName)
				end
			end)
		end
	end
end

local function wireContainer(name: string)
	local container = gui:FindFirstChild(name)
	if container then
		wireButtons(container)
	end
end

wireContainer(GuiNames.BottomBar)
wireContainer(GuiNames.MenuPill)
if not gui:FindFirstChild(GuiNames.BottomBar) then
	warn("MenuController: BottomBar not authored yet — modal buttons pending Studio UI.")
end

-- The user authors UI live in Studio: wire late-arriving containers too.
gui.ChildAdded:Connect(function(child)
	if child.Name == GuiNames.BottomBar or child.Name == GuiNames.MenuPill then
		task.defer(wireButtons, child)
	end
end)
