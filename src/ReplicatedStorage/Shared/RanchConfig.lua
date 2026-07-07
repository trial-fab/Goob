--!strict
-- =============================================================================
-- RanchConfig — ranch capacity & expansion (NEW in session 2; additive to the
-- DESIGN §5 tree — the §2 "Goo-purchased ranch upgrades" sink needed a data
-- home and fits no existing config's contract).
--
-- [Contract] Owns: producing-slime capacity (base 8 -> max 16 via Goo
--   upgrades), per-slot upgrade costs, and the storage cap (200).
-- [Contract] Never: the gamepass +4 slots (MonetizationConfig, session 3);
--   never slot GRANTS — PlotService/SlimeService own roster state. Squad slots
--   are NOT ranch slots and are progression-only, never sold (§4).
-- [Contract] Binds: DESIGN.md §2 ranch capacity, §3 currency map (sink).
-- =============================================================================
--
-- Requires nothing (the off-Roblox sim loads this exact file).
--
-- Slot costs are the mid-game's paced sink: each one is "hold this much Goo
-- without spending it on eggs" — slot 12 lands late week 1 (§3 beat), 16 is a
-- week 3-4 project. Molt resets Slots to SlotsBase (§2 Molt) but NOT these
-- prices — they are lifetime, like egg ladders, so each Molt run re-earns its
-- capacity faster via the Molt multiplier instead of inflating past the sink.

local RanchConfig = {}

RanchConfig.SlotsBase = 8 -- producing slimes at first join / after Molt
RanchConfig.SlotsMax = 16 -- Goo-purchasable ceiling (gamepass +4 on top, session 3)
RanchConfig.StorageCap = 200 -- total owned slimes; overflow blocks hatching (§2)

-- Goo cost to unlock slot N (index = the slot number being bought).
RanchConfig.SlotCosts = table.freeze({
	[9] = 25000, -- a day-1-evening buy: session 1 ends at 8 producing (§3)
	[10] = 500000,
	[11] = 4000000,
	[12] = 20000000, -- the "ranch -> 12 slots" week-1 beat (§3, lands day 6-7)
	[13] = 150000000,
	[14] = 1000000000,
	[15] = 8000000000,
	[16] = 40000000000, -- the week-3-4 capacity project
})

return table.freeze(RanchConfig)
