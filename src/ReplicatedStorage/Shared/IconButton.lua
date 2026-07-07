--!strict
-- =============================================================================
-- IconButton — reusable icon-button hover/press/active logic.
--
-- [Contract] Owns: resolving the interactive GuiButton inside a Studio-authored
--   container, the invisible padding-aware Hitbox overlay, and the
--   hover/press/active image-state machine (persisted via *Image attributes).
-- [Contract] Never: authors layout/visual GuiObjects — the one instance it
--   creates (the Hitbox) is a deliberately invisible input proxy. Never game
--   logic; callers own what a click means.
-- [Contract] Binds: DESIGN.md §6 reuse map (PORT-AS-IS from ClickGame, B2);
--   WORKFLOW.md (code owns UI logic only).
-- =============================================================================

local Attrs = require(script.Parent:WaitForChild("Attrs"))

local IconButton = {}

export type IconButtonHandle = {
	container: Instance?,
	button: GuiButton?,
	set: (active: boolean, text: string?) -> (),
	toggled: ((selected: boolean) -> ())?,
}

export type ResolveOpts = {
	className: string?, -- "GuiButton" (default) or "ImageButton"
	containerFirst: boolean?, -- test the container itself before its descendants
}

-- Find the interactive instance inside `container`. Returns (button, owner)
-- where owner is the container that was searched; button is nil if none.
function IconButton.resolveButton(container: Instance?, opts: ResolveOpts?): (GuiObject?, Instance?)
	if not container then
		return nil, nil
	end

	local o: ResolveOpts = opts or {}
	local className = o.className or "GuiButton"

	if o.containerFirst and container:IsA(className) then
		return container :: GuiObject, container
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA(className) then
			return descendant :: GuiObject, container
		end
	end

	if container:IsA(className) then
		return container :: GuiObject, container
	end

	return nil, container
end

-- Write the Active attribute onto a button + its container: set Active on the
-- container (or button), also on the button when distinct, and — for a
-- non-IconOnly TextButton — set its label text. `text` is optional.
function IconButton.setActive(button: GuiObject?, container: Instance?, active: boolean, text: string?)
	local target: Instance? = container or button
	if target then
		target:SetAttribute(Attrs.Active, active)
	end
	if button and button ~= target then
		button:SetAttribute(Attrs.Active, active)
	end

	if button and button:IsA("TextButton") and not button:GetAttribute(Attrs.IconOnly) and text ~= nil then
		button.Text = text
	end
end

-- Create (or reuse) an invisible, padding-aware TextButton sized to fully cover
-- `container`, so a framed icon gets a single reliable click/hover target.
-- If the pairing isn't applicable (no real container frame, or visual isn't an
-- ImageButton), returns `visualButton` unchanged.
function IconButton.createHitbox(container: Instance?, visualButton: GuiButton?): GuiButton?
	if not container or not container:IsA("GuiObject") or container:IsA("GuiButton") then
		return visualButton
	end
	if not visualButton or not visualButton:IsA("ImageButton") then
		return visualButton
	end

	local existing = container:FindFirstChild("Hitbox")
	local hitbox: TextButton
	if existing and existing:IsA("TextButton") then
		hitbox = existing
	else
		if existing then
			existing:Destroy()
		end
		hitbox = Instance.new("TextButton")
		hitbox.Name = "Hitbox"
		hitbox.Parent = container
	end

	hitbox.BackgroundTransparency = 1
	hitbox.BorderSizePixel = 0
	hitbox.Text = ""
	hitbox.TextTransparency = 1
	hitbox.AutoButtonColor = false
	hitbox.Selectable = false
	hitbox:SetAttribute(Attrs.IconOnly, true)
	hitbox.ZIndex = math.max(container.ZIndex, visualButton.ZIndex) + 10

	local padding = container:FindFirstChildWhichIsA("UIPadding")
	if padding then
		hitbox.Position = UDim2.new(
			-padding.PaddingLeft.Scale,
			-padding.PaddingLeft.Offset,
			-padding.PaddingTop.Scale,
			-padding.PaddingTop.Offset
		)
		hitbox.Size = UDim2.new(
			1 + padding.PaddingLeft.Scale + padding.PaddingRight.Scale,
			padding.PaddingLeft.Offset + padding.PaddingRight.Offset,
			1 + padding.PaddingTop.Scale + padding.PaddingBottom.Scale,
			padding.PaddingTop.Offset + padding.PaddingBottom.Offset
		)
	else
		hitbox.Position = UDim2.fromScale(0, 0)
		hitbox.Size = UDim2.fromScale(1, 1)
	end

	return hitbox
end

-- Resolve/persist a cosmetic image triple onto the visual button, returning
-- (default, hover, pressed). These per-button attrs stay string literals by
-- design (Attrs.lua keeps cosmetic *Image pairs out of the shared table);
-- `prefix` namespaces them per call site.
local function resolveImageStates(visual: ImageButton, prefix: string): (string, string, string)
	local default = visual:GetAttribute(prefix .. "DefaultImage")
	if typeof(default) ~= "string" or default == "" then
		default = visual.Image
		visual:SetAttribute(prefix .. "DefaultImage", default)
	end

	local hover = visual:GetAttribute(prefix .. "HoverImage")
	if typeof(hover) ~= "string" or hover == "" then
		hover = if visual.HoverImage ~= "" then visual.HoverImage else default
		visual:SetAttribute(prefix .. "HoverImage", hover)
	end

	local pressed = visual:GetAttribute(prefix .. "ActiveImage")
	if typeof(pressed) ~= "string" or pressed == "" then
		pressed = if visual.PressedImage ~= "" then visual.PressedImage else hover
		visual:SetAttribute(prefix .. "ActiveImage", pressed)
	end

	return default :: string, hover :: string, pressed :: string
end

export type NewConfig = {
	imageAttrPrefix: string?, -- namespace for the persisted image attrs (default "Icon")
}

-- Build a full icon button over `container` + `visualButton`. Returns a handle:
--   .container  -- the container that was wired
--   .button     -- the interactive instance (the Hitbox if created, else visualButton)
--   .set(active [, text]) -- write the Active attribute (drives the active image)
--   .toggled    -- assignable callback; when set, clicking flips Active and calls
--                  it(newActive). Leave nil to drive .set yourself.
-- When no hitbox is applicable (e.g. the container is itself the button), the
-- image-state machine is skipped.
function IconButton.new(container: Instance?, visualButton: GuiButton?, config: NewConfig?): IconButtonHandle
	local cfg: NewConfig = config or {}
	local prefix = cfg.imageAttrPrefix or "Icon"

	local hitbox = IconButton.createHitbox(container, visualButton)
	local hasHitbox = hitbox ~= visualButton

	local function isActive(): boolean
		return (container ~= nil and container:GetAttribute(Attrs.Active) == true)
			or (hitbox ~= nil and hitbox:GetAttribute(Attrs.Active) == true)
	end

	local updateVisual: () -> () = function() end

	if hasHitbox and hitbox and visualButton and visualButton:IsA("ImageButton") and container then
		local visual = visualButton :: ImageButton
		local defaultImage, hoverImage, pressedImage = resolveImageStates(visual, prefix)

		-- The component owns the visual states; clear the built-in swaps so they
		-- can't fight us.
		visual.AutoButtonColor = false
		visual.HoverImage = ""
		visual.PressedImage = ""

		local hovering = false
		local pressing = false

		updateVisual = function()
			if isActive() or pressing then
				visual.Image = pressedImage
			elseif hovering then
				visual.Image = hoverImage
			else
				visual.Image = defaultImage
			end
		end

		hitbox.MouseEnter:Connect(function()
			hovering = true
			updateVisual()
		end)
		hitbox.MouseLeave:Connect(function()
			hovering = false
			updateVisual()
		end)
		hitbox.MouseButton1Down:Connect(function()
			pressing = true
			updateVisual()
		end)
		hitbox.MouseButton1Up:Connect(function()
			pressing = false
			updateVisual()
		end)
		hitbox:GetAttributeChangedSignal(Attrs.Active):Connect(updateVisual)
		container:GetAttributeChangedSignal(Attrs.Active):Connect(updateVisual)
	end

	local handle: IconButtonHandle = {
		container = container,
		button = hitbox,
		set = function(active: boolean, text: string?)
			IconButton.setActive(hitbox, container, active, text)
			updateVisual()
		end,
		toggled = nil,
	}

	if hitbox then
		hitbox.MouseButton1Click:Connect(function()
			if handle.toggled then
				local selected = not isActive()
				handle.set(selected)
				local toggled = handle.toggled :: (boolean) -> ()
				toggled(selected)
			end
		end)
	end

	updateVisual()
	return handle
end

return IconButton
