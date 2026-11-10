extends RefCounted
## Shared parchment and ink treatment, using the existing village paper artwork.
const PAPER = preload("res://Assets/Sprites/UI/Village/Untitled copy.png")
const INK := Color("392b24")
static func make_theme(factor: float = 1.0) -> Theme:
	var theme := Theme.new()
	theme.default_font_size = roundi(18 * factor)
	for type in ["Label", "Button"]:
		theme.set_color("font_color", type, INK)
	var paper := StyleBoxTexture.new()
	paper.texture = PAPER
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		paper.set_texture_margin(side, 14)
		paper.set_content_margin(side, 24 * factor)
	theme.set_stylebox("panel", "PanelContainer", paper)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.12, 0.07, 0.09) if state == "hover" else Color.TRANSPARENT
		if state == "pressed": style.bg_color = Color(0.2, 0.12, 0.07, 0.18)
		style.border_color = Color(0.25, 0.17, 0.12, 0.25)
		style.border_width_bottom = 1
		if state == "focus":
			style.border_color = Color("704c31")
			style.set_border_width_all(1)
		style.content_margin_left = 12 * factor
		style.content_margin_right = 12 * factor
		style.content_margin_top = 9 * factor
		style.content_margin_bottom = 9 * factor
		theme.set_stylebox(state, "Button", style)
	for name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(name, "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color("99816b"))
	var rule := StyleBoxLine.new()
	rule.color = Color(0.25, 0.17, 0.12, 0.3)
	rule.thickness = 1
	theme.set_stylebox("separator", "HSeparator", rule)
	return theme
