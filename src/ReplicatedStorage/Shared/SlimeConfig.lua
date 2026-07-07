--!strict
-- =============================================================================
-- SlimeConfig — STUB (scaffold session 1; values from the session-2 economy sim).
--
-- [Contract] Owns: the species catalog — id, display name, line (Meadow/Cave/
--   Ocean/Volcano), rarity tier (Common..Legendary), base Goo production,
--   ability family, and hatchable vs wild-exclusive.
-- [Contract] Never: balance numbers before the economy spreadsheet signs them
--   off (§9 M0 — retuning after players hold inventory is 10x harder); never
--   logic — data + pure lookups only. Replicated: clients read it for UI.
-- [Contract] Binds: DESIGN.md §2 slimes & collection, §3, §5 tree.
-- =============================================================================

local SlimeConfig = {}

return SlimeConfig
