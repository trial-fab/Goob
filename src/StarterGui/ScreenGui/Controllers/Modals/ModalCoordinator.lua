--!strict
-- =============================================================================
-- ModalCoordinator — single-open coordination for every modal.
--
-- [Contract] Owns: the ONE open-modal slot, backed by the ScreenGui `OpenModal`
--   attribute (the attribute is the source of truth; this module is the one
--   place that reads/writes/watches it). Every modal (Egg shop, Inventory,
--   Index, Trade, Settings, Profile, ...) registers here.
-- [Contract] Never: opens/closes modal UI itself (each controller owns its own
--   show/hide); never a second coordination mechanism — controllers must not
--   touch OpenModal directly.
-- [Contract] Binds: DESIGN.md §6 reuse map (PORT-AS-IS from ClickGame, B3),
--   §7 (all modals register with ModalCoordinator).
-- =============================================================================
--
-- Usage (per modal controller):
--   local Modals = require(script.Parent:WaitForChild("ModalCoordinator"))
--   local slot = Modals.register("EggShop", function()
--       -- another modal claimed the slot — close myself
--       if eggShopVisible then setEggShopVisible(false) end
--   end, function()
--       -- (optional) someone requested me open (Menu bottom bar) — show myself
--       setEggShopVisible(true)
--   end)
--   -- on open:  slot.open()      -- claim the slot for "EggShop"
--   -- on close: slot.close()     -- release the slot iff "EggShop" still holds it
--
-- `slot.close()` is safe to call unconditionally from a close path: it only
-- clears the attribute when this modal currently owns it, so the foreign-close
-- callback can route through it without re-claiming or fighting the new owner.
--
-- Session-3 addition (SlimeGame): `ModalCoordinator.request(name)` lets a
-- non-owner (the Menu bottom bar) open a modal by name; the owner's
-- onOpenRequested callback fires via the same shared observer. This file
-- remains the ONLY place that touches the OpenModal attribute.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attrs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attrs"))

local ModalCoordinator = {}

local screenGui = script:FindFirstAncestorOfClass("ScreenGui")
assert(screenGui, "ModalCoordinator must live under the ScreenGui (Controllers/Modals)")

local NONE = ""

export type ModalSlot = {
	open: () -> (),
	close: () -> (),
}

type Entry = {
	onForeignOpen: () -> (),
	onOpenRequested: (() -> ())?,
}

-- name -> callbacks (foreign-open always; open-requested optional).
local registry: { [string]: Entry } = {}

local function current(): string
	local value = screenGui:GetAttribute(Attrs.OpenModal)
	return if typeof(value) == "string" then value else NONE
end

-- One shared observer drives every registered modal. When the slot changes,
-- every registered modal that is NOT the current owner is told to close
-- itself, and the new owner (if it asked for the signal) is told to open.
-- Each callback self-guards on its own open state, so this is a no-op for
-- modals already in the right state.
screenGui:GetAttributeChangedSignal(Attrs.OpenModal):Connect(function()
	local owner = current()
	for name, entry in pairs(registry) do
		if name ~= owner then
			entry.onForeignOpen()
		elseif entry.onOpenRequested then
			entry.onOpenRequested()
		end
	end
end)

-- Register a modal under `name`. `onForeignOpen` is called whenever another
-- modal claims the single open slot (i.e. this modal should close itself);
-- `onOpenRequested` (optional) whenever someone requests THIS modal open.
function ModalCoordinator.register(name: string, onForeignOpen: () -> (), onOpenRequested: (() -> ())?): ModalSlot
	assert(type(name) == "string" and name ~= NONE, "ModalCoordinator.register: name must be a non-empty string")
	assert(type(onForeignOpen) == "function", "ModalCoordinator.register: onForeignOpen must be a function")
	registry[name] = { onForeignOpen = onForeignOpen, onOpenRequested = onOpenRequested }

	return {
		-- Claim the single slot for this modal. Sibling modals are closed via
		-- the shared observer above.
		open = function()
			screenGui:SetAttribute(Attrs.OpenModal, name)
		end,
		-- Release the slot, but only if this modal still owns it. Safe to call
		-- from any close path: when a sibling already took the slot this is a
		-- no-op.
		close = function()
			if current() == name then
				screenGui:SetAttribute(Attrs.OpenModal, NONE)
			end
		end,
	}
end

-- Open a modal BY NAME from outside its owner (Menu bottom bar). Routes
-- through the same attribute + observer as slot.open().
function ModalCoordinator.request(name: string)
	screenGui:SetAttribute(Attrs.OpenModal, name)
end

-- Close whatever is open (Menu close-all, Decor build-mode entry).
function ModalCoordinator.closeAll()
	screenGui:SetAttribute(Attrs.OpenModal, NONE)
end

-- Name of the modal that currently holds the open slot ("" if none).
function ModalCoordinator.current(): string
	return current()
end

-- True while any registered modal holds the open slot.
function ModalCoordinator.isOpen(): boolean
	return current() ~= NONE
end

return ModalCoordinator
