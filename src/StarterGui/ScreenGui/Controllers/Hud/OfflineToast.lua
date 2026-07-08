--!strict
-- =============================================================================
-- Hud/OfflineToast — the welcome-back offline-earnings claim moment.
-- [Contract] Owns: showing the Studio-authored OfflineToast when the server
--   pushes OfflineEarningsReady, and routing the claim tap through
--   ClaimOfflineEarnings (server-validated; the toast renders the result).
-- [Contract] Never: constructs GuiObjects; never computes earnings (the
--   amount is the server's — this displays it).
-- =============================================================================
--
-- Studio hand-off: ScreenGui.OfflineToast (Frame, hidden by default) with
-- AmountLabel (TextLabel) + ClaimButton (TextButton).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local OfflineToast = {}

local TOAST_NAME = "OfflineToast" -- single-controller lookup: local literal

local claiming = false
local wiredButtons: { [Instance]: boolean } = {}

local function wire(frame: Instance)
	local button = frame:FindFirstChild("ClaimButton")
	if not (button and button:IsA("GuiButton")) or wiredButtons[button] then
		return
	end
	wiredButtons[button] = true
	button.Activated:Connect(function()
		if claiming then
			return
		end
		claiming = true
		local result = Net.invoke(Net.Names.ClaimOfflineEarnings)
		claiming = false
		if typeof(result) == "table" and result.success and frame:IsA("Frame") then
			frame.Visible = false
		end
	end)
end

function OfflineToast.Init(ctx: { [string]: any })
	local gui = ctx.gui :: ScreenGui

	Net.on(Net.Names.OfflineEarningsReady, function(payload: { [string]: any })
		local frame = gui:FindFirstChild(TOAST_NAME)
		if not (frame and frame:IsA("Frame")) then
			warn("Hud/OfflineToast: OfflineToast template not authored yet — offline claim UI pending.")
			return
		end
		wire(frame)
		local amount = frame:FindFirstChild("AmountLabel")
		if amount and amount:IsA("TextLabel") then
			amount.Text = NumberFormat.abbreviate(payload.Amount or 0)
		end
		frame.Visible = true
	end)
end

return OfflineToast
