--!strict
-- =============================================================================
-- CollectService — goo-blob claim validation.
--
-- [Contract] Owns: validating goo-blob claims — client says "collect blob id";
--   server checks the blob record exists, the plot is the claimant's, and the
--   claim rate; then grants the server-known value and retires the record.
-- [Contract] Never: grants from client-supplied amounts (the blob record is the
--   value authority); never trusts position.
-- [Contract] Binds: DESIGN.md §5 server authority (goo-blob collection), §5
--   Anti-exploit posture (Collect <=10/s).
-- =============================================================================
--
-- Plot ownership is implicit: ProductionService keys blob records by player,
-- so TakeBlob can only ever return a value for the claimant's own records —
-- someone else's blob id is indistinguishable from a bogus one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Attrs = require(Shared:WaitForChild("Attrs"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local ProductionService = require(script.Parent:WaitForChild("ProductionService"))
local QuestService = require(script.Parent:WaitForChild("QuestService"))

local CollectService = {}

function CollectService.Init()
	Net.onInvoke(Net.Names.CollectBlob, function(player: Player, blobId: string)
		local data = DataService.GetData(player)
		if not data then
			return { success = false, message = "Loading..." }
		end
		local value = ProductionService.TakeBlob(player, blobId)
		if not value then
			return { success = false, message = "That blob is gone." }
		end
		data.Goo += value
		data.Stats.GooEarned += value
		player:SetAttribute(Attrs.Goo, data.Goo)
		QuestService.Progress(player, "CollectBlobs", 1)
		return { success = true, value = value, goo = data.Goo }
	end, {
		budget = 10, -- §5 anti-exploit posture: Collect <=10/s
		window = 1,
		validator = Net.T.args(Net.T.guid),
	})
end

return CollectService
