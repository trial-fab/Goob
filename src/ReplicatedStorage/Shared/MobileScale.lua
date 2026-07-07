--!strict
-- =============================================================================
-- MobileScale — the shared responsive-UI scaler every screen uses.
--
-- [Contract] Owns: the one tuned continuous design-resolution scale standard
--   (min(vp/1920, vp/1080), damped + clamped), modal fit/centering in the safe
--   band, the touch-device predicate, and keeping a frame's single UIScale in
--   sync with the viewport.
-- [Contract] Never: authors GuiObjects (the UIScale instances it creates are
--   logic-owned scaling proxies, per the ClickGame precedent); never a second
--   UIScale on a frame that animates its own — those consumers FOLD targetScale
--   into their animation instead (use targetScale/onViewportChanged).
-- [Contract] Binds: DESIGN.md §6 reuse map (PORT-AS-IS), §7 (all screens use
--   MobileScale); WORKFLOW.md.
-- =============================================================================
--
-- Entry points:
--   computeScale(viewportSize, opts) -- pure: the factor for a given Vector2
--                                       viewport, no global reads (testable).
--   targetScale(gui, opts)           -- computeScale for the gui's live viewport;
--   + onViewportChanged(cb)             for frames that drive their own UIScale.
--   apply(gui, opts)                 -- frames with no animation UIScale: ensures
--                                       a single UIScale and keeps it in sync.
--   applyResolved(gui, opts)         -- modal resize-to-fit + center (no pop).
--   resolveModal(gui, designSize, o) -- layout a modal; returns its resting scale.
--   fitScale / mobileFactor / applyMobileScale / shiftLeftOnMobile -- see below.
--
-- `opts` (all entry points): { multiplier, min, max, sensitivity, mobileScale }.

local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local DESIGN_RESOLUTION = Vector2.new(1920, 1080)
local MIN_SCALE = 0.5
local MAX_SCALE = 1.25

-- How sensitive desktop scaling is to window size. The raw design-res factor
-- shrinks UI fast as the window drops below 1080p; this damps that toward 1.0 so
-- modals stay large when there's still room. 1 = raw, 0 = never scale. At 0.5 a
-- 1280x720 window gives ~0.83 instead of ~0.67. 1080p is always exactly 1.
local DESKTOP_SENSITIVITY = 0.5

-- Safe-area margins for fitScale/resolveModal. The top comes from
-- GuiService:GetGuiInset() (the Roblox topbar); the bottom is a fixed reserve for
-- the game's own bottom bar, which is not part of the GUI inset. Retune
-- SAFE_BOTTOM_RESERVE when the SlimeGame bottom bar is authored (session 3).
local SAFE_SIDE_MARGIN = 12
local SAFE_TOP_MARGIN = 12
local SAFE_BOTTOM_RESERVE = 96
local FIT_FLOOR = 0.2 -- never scale a fitted modal below this

-- Hybrid mobile scale: on a phone the modal's box resizes to fit AND this gentle
-- UIScale shrinks elements a bit so more content fits per screen. Closer to 1 =
-- bigger/more readable but fewer rows.
local MOBILE_SCALE = 0.6

-- Touch-device predicate threshold — the single source of that threshold for
-- consumers that want a hard mobile branch on top of the continuous scale.
local MOBILE_VIEWPORT_MAX_SHORT_SIDE = 600

export type ScaleOpts = {
	multiplier: number?,
	min: number?,
	max: number?,
	sensitivity: number?,
	mobileScale: number?,
}

local MobileScale = {}

MobileScale.DESIGN_RESOLUTION = DESIGN_RESOLUTION
MobileScale.MOBILE_VIEWPORT_MAX_SHORT_SIDE = MOBILE_VIEWPORT_MAX_SHORT_SIDE

local function clamp(value: number, lower: number, upper: number): number
	if value < lower then
		return lower
	elseif value > upper then
		return upper
	end
	return value
end

-- Pure: the continuous design-resolution factor for a given viewport. No global
-- reads so it can be asserted directly (computeScale(Vector2.new(1920,1080)) == 1).
local function computeScale(viewportSize: Vector2?, opts: ScaleOpts?): number
	local o: ScaleOpts = opts or {}
	if not viewportSize or viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return clamp(o.multiplier or 1, o.min or MIN_SCALE, o.max or MAX_SCALE)
	end

	local ratio = math.min(viewportSize.X / DESIGN_RESOLUTION.X, viewportSize.Y / DESIGN_RESOLUTION.Y)
	-- Damp how far the scale moves away from 1.0; 1080p (ratio 1) is unaffected.
	local sensitivity = o.sensitivity or DESKTOP_SENSITIVITY
	local damped = (1 + (ratio - 1) * sensitivity) * (o.multiplier or 1)

	return clamp(damped, o.min or MIN_SCALE, o.max or MAX_SCALE)
end
MobileScale.computeScale = computeScale

local function getViewportSize(gui: Instance?): Vector2
	local camera = Workspace.CurrentCamera
	if camera and camera.ViewportSize.X > 0 and camera.ViewportSize.Y > 0 then
		return camera.ViewportSize
	end

	local parent = gui and gui.Parent
	if parent and parent:IsA("GuiObject") and parent.AbsoluteSize.X > 0 and parent.AbsoluteSize.Y > 0 then
		return parent.AbsoluteSize
	end

	return Vector2.zero
end
MobileScale.getViewportSize = getViewportSize

local function shouldUseMobile(gui: Instance?): boolean
	if not UserInputService.TouchEnabled then
		return false
	end

	local viewportSize = getViewportSize(gui)
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return false
	end

	return math.min(viewportSize.X, viewportSize.Y) <= MOBILE_VIEWPORT_MAX_SHORT_SIDE
end
MobileScale.shouldUseMobile = shouldUseMobile

-- The continuous responsive scale for the gui's live viewport.
function MobileScale.targetScale(gui: Instance?, opts: ScaleOpts?): number
	return computeScale(getViewportSize(gui), opts)
end

-- Returns `position` shifted left by `px` pixels of X-offset on a mobile
-- viewport, otherwise unchanged (dodges rounded screen corners for right-edge
-- HUD). Pair with onViewportChanged to re-apply on orientation changes.
function MobileScale.shiftLeftOnMobile(position: UDim2, px: number, gui: Instance?): UDim2
	local shift = shouldUseMobile(gui) and px or 0
	return UDim2.new(position.X.Scale, position.X.Offset - shift, position.Y.Scale, position.Y.Offset)
end

-- Run `callback` once now and again whenever the viewport size or current
-- camera changes.
function MobileScale.onViewportChanged(callback: () -> ())
	callback()

	local function bindCamera(camera: Camera?)
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(callback)
		end
	end

	bindCamera(Workspace.CurrentCamera)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera(Workspace.CurrentCamera)
		callback()
	end)
end

-- The usable vertical band on screen: [topEdge, bottomEdge] in raw screen
-- pixels, clear of the Roblox topbar (GUI inset) and the bottom bar reserve. The
-- ScreenGui has IgnoreGuiInset on, so coordinate 0 is the true screen top and we
-- must dodge the topbar ourselves.
local function usableBand(gui: Instance?): (Vector2, number, number)
	local vp = getViewportSize(gui)
	local insetTopLeft = GuiService:GetGuiInset()
	local topEdge = insetTopLeft.Y + SAFE_TOP_MARGIN
	local bottomEdge = vp.Y - SAFE_BOTTOM_RESERVE
	return vp, topEdge, bottomEdge
end

-- Like targetScale, but for an OFFSET-sized modal: also clamps the scale so the
-- modal's rendered box (offset * scale) fits inside the safe area. Falls back to
-- the plain design-res scale for non-offset frames.
function MobileScale.fitScale(gui: Instance?, opts: ScaleOpts?): number
	local design = MobileScale.targetScale(gui, opts)
	if not (gui and gui:IsA("GuiObject")) then
		return design
	end

	local baseW, baseH = gui.Size.X.Offset, gui.Size.Y.Offset
	local vp, topEdge, bottomEdge = usableBand(gui)
	if baseW <= 0 or baseH <= 0 or vp.X <= 0 or vp.Y <= 0 then
		return design -- not an offset-sized frame: nothing to fit to
	end

	local availW = vp.X - 2 * SAFE_SIDE_MARGIN
	local availH = bottomEdge - topEdge
	local fit = math.min(design, availW / baseW, availH / baseH)
	return math.max(fit, FIT_FLOOR)
end

-- Lay out a modal for the current device regime and return the resting UIScale
-- its pop should target. `designSize` is the authored offset box (capture it
-- ONCE before the first call, since this rewrites gui.Size on mobile).
--
--   Desktop: the authored offset box, design-res scaled, centered in the band.
--   Mobile: the box is RESIZED to fit the safe area and UIScale stays gentle, so
--     the shrink happens on the Size and TEXT keeps its authored readable size
--     (fixed-size text, container reflows — the documented best practice).
function MobileScale.resolveModal(gui: Instance?, designSize: Vector2, opts: ScaleOpts?): number
	local o: ScaleOpts = opts or {}
	if not (gui and gui:IsA("GuiObject")) then
		return 1
	end

	local vp, topEdge, bottomEdge = usableBand(gui)
	local centerY = (topEdge + bottomEdge) / 2
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.new(0.5, 0, 0, math.floor(centerY + 0.5))

	if shouldUseMobile(gui) and vp.X > 0 and vp.Y > 0 then
		-- Hybrid: split the shrink between the box and a gentle UIScale. Size the
		-- box so the SCALED box fills the safe area, capped at the design size.
		local s = o.mobileScale or MOBILE_SCALE
		local availW = vp.X - 2 * SAFE_SIDE_MARGIN
		local availH = bottomEdge - topEdge
		local width = math.min(designSize.X, availW / s)
		local height = math.min(designSize.Y, availH / s)
		gui.Size = UDim2.fromOffset(math.floor(width + 0.5), math.floor(height + 0.5))
		return s
	end

	-- Desktop: restore the authored offset box and design-res scale it to fit.
	gui.Size = UDim2.fromOffset(designSize.X, designSize.Y)
	return MobileScale.fitScale(gui, opts)
end

local function ensureScale(gui: GuiObject): UIScale
	local existing = gui:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "MobileScale"
	scale.Parent = gui
	return scale
end

-- For a frame whose only UIScale is the responsive scale: reuse an existing
-- UIScale or create one, and keep it in sync with the viewport.
function MobileScale.apply(gui: Instance?, opts: ScaleOpts?): UIScale?
	if not (gui and gui:IsA("GuiObject")) then
		return nil
	end

	local scale = ensureScale(gui)

	MobileScale.onViewportChanged(function()
		-- opts.mobileScale: a fixed gentle scale on touch/small viewports instead
		-- of the continuous design-res shrink (which can get aggressively small).
		if opts and opts.mobileScale and shouldUseMobile(gui) then
			scale.Scale = opts.mobileScale :: number
		else
			scale.Scale = MobileScale.targetScale(gui, opts)
		end
	end)

	return scale
end

-- Like apply, but runs resolveModal (resize-to-fit + center, native text on
-- mobile) for a modal with no pop animation of its own. `designSize` is captured
-- here from the authored box before the first resolve rewrites it.
function MobileScale.applyResolved(gui: Instance?, opts: ScaleOpts?): UIScale?
	if not (gui and gui:IsA("GuiObject")) then
		return nil
	end

	local designSize = Vector2.new(gui.Size.X.Offset, gui.Size.Y.Offset)
	local scale = ensureScale(gui)

	MobileScale.onViewportChanged(function()
		scale.Scale = MobileScale.resolveModal(gui, designSize, opts)
	end)

	return scale
end

-- The flat mobile-only shrink factor: the fixed MOBILE_SCALE (or
-- opts.mobileScale) on a touch phone, and exactly 1 everywhere else — for
-- HUD/overlay elements that should scale down on phones but never on PC.
function MobileScale.mobileFactor(gui: Instance?, opts: ScaleOpts?): number
	if shouldUseMobile(gui) then
		return (opts and opts.mobileScale) or MOBILE_SCALE
	end
	return 1
end

-- Scale an element down on phones only, leaving PC untouched. Drives ONLY a
-- UIScale by mobileFactor — a single uniform zoom, safe for laid-out frames with
-- mixed scale/offset children (resizing Size instead double-shrinks scale-sized
-- children vs offset-sized ones; that overlap bug is why this is UIScale-only).
function MobileScale.applyMobileScale(gui: Instance?, opts: ScaleOpts?): UIScale?
	if not (gui and gui:IsA("GuiObject")) then
		return nil
	end

	local scale = ensureScale(gui)

	MobileScale.onViewportChanged(function()
		scale.Scale = MobileScale.mobileFactor(gui, opts)
	end)

	return scale
end

return MobileScale
