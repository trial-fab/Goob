--!strict
-- =============================================================================
-- GuiNames — single source of truth for cross-controller GUI instance names.
--
-- [Contract] Owns: the canonical spelling of Studio-authored GUI instances that
--   2+ controllers resolve by string. Reference one as `GuiNames.MenuPill`; a
--   typo'd key is nil — a loud error at the call site, never a silent wrong
--   FindFirstChild match.
-- [Contract] Never: names for deep single-file structural lookups (those stay
--   local literals); never GuiObject construction — ALL UI instances are
--   authored by the user in Studio (WORKFLOW.md).
-- [Contract] Binds: DESIGN.md §7 UI plan; WORKFLOW.md authoring contract.
-- =============================================================================
--
-- Placeholder starter set: the real tree is authored in Studio during session 3
-- UI work; every name here must match the Studio instance exactly. Add a name
-- ONLY when a second controller needs it.

return table.freeze({
	-- top-right menu pill + its buttons (ClickGame pattern)
	MenuPill = "MenuPill",
	Settings = "Settings",
	SettingsButton = "SettingsButton",
	Profile = "Profile",
	ProfileButton = "ProfileButton",
	Close = "Close",

	-- bottom bar (DESIGN.md §7: Shop · Inventory · Index · Trade · Explore)
	BottomBar = "BottomBar",
	ShopButton = "ShopButton",
	InventoryButton = "InventoryButton",
	IndexButton = "IndexButton",
	TradeButton = "TradeButton",
	ExploreButton = "ExploreButton",
	QuestsButton = "QuestsButton", -- menu pill (Menu opens, Quests renders)
	DecorButton = "DecorButton", -- build-mode entry (Menu opens, Decor renders)

	-- HUD (Hud binds counters; Egg/Inventory flows re-anchor toasts around it)
	HudFrame = "HudFrame",
	GooLabel = "GooLabel",
	GemsLabel = "GemsLabel",
	GpsLabel = "GpsLabel",

	-- modal shells opened by Menu, owned by their domain controllers
	EggShop = "EggShop",
	Inventory = "Inventory",
	ExplorePanel = "ExplorePanel",
	QuestsModal = "QuestsModal",
	StreakModal = "StreakModal",
	DecorCatalog = "DecorCatalog",
})
