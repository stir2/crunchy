extends RefCounted
## Shared parchment and ink treatment, using the existing village paper artwork.
const PAPER = preload("res://Assets/Sprites/UI/Village/Untitled copy.png")
const INK := Color("392b24")
static func make_theme(factor: float = 1.0, pixel_mode: bool = false) -> Theme:
	var theme := Theme.new()
	var text_size := 16 if pixel_mode else roundi(28 * factor)
	theme.default_font_size = text_size
	for type in ["Label", "Button"]:
		theme.set_color("font_color", type, INK)
	var paper := StyleBoxTexture.new()
	paper.texture = PAPER
	var content_pad := 12.0 if pixel_mode else 32.0 * factor
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		paper.set_texture_margin(side, 14)
		paper.set_content_margin(side, content_pad)
	theme.set_stylebox("panel", "PanelContainer", paper)
	var border := 1 if pixel_mode else maxi(1, roundi(2 * factor))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.12, 0.07, 0.09) if state == "hover" else Color.TRANSPARENT
		if state == "pressed": style.bg_color = Color(0.2, 0.12, 0.07, 0.18)
		style.border_color = Color(0.25, 0.17, 0.12, 0.25)
		style.border_width_bottom = border
		if state == "focus":
			style.border_color = Color("704c31")
			style.set_border_width_all(border)
		style.content_margin_left = 8.0 if pixel_mode else 16.0 * factor
		style.content_margin_right = 8.0 if pixel_mode else 16.0 * factor
		style.content_margin_top = 4.0 if pixel_mode else 10.0 * factor
		style.content_margin_bottom = 4.0 if pixel_mode else 10.0 * factor
		theme.set_stylebox(state, "Button", style)
	for name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(name, "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color("99816b"))
	var rule := StyleBoxLine.new()
	rule.color = Color(0.25, 0.17, 0.12, 0.3)
	rule.thickness = border
	theme.set_stylebox("separator", "HSeparator", rule)
	return theme


static func make_confirmation_theme(pixel_mode: bool = false) -> Theme:
	var theme := Theme.new()
	var font_size := 16 if pixel_mode else 32
	theme.default_font_size = font_size
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("261929")
	panel.border_color = Color("76536f")
	var border := 1 if pixel_mode else 2
	panel.set_border_width_all(border)
	var pad_h := 16 if pixel_mode else 36
	var pad_v := 14 if pixel_mode else 28
	panel.content_margin_left = pad_h
	panel.content_margin_right = pad_h
	panel.content_margin_top = pad_v
	panel.content_margin_bottom = pad_v
	theme.set_stylebox("panel", "AcceptDialog", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)
	var frame := panel.duplicate() as StyleBoxFlat
	var header_h := 24 if pixel_mode else 48
	frame.expand_margin_top = header_h
	theme.set_stylebox("embedded_border", "Window", frame)
	theme.set_stylebox("embedded_unfocused_border", "Window", frame)
	theme.set_constant("title_height", "Window", header_h)
	theme.set_color("title_color", "Window", Color("fae6d6"))
	theme.set_font_size("title_font_size", "Window", font_size)
	var close_size := 10 if pixel_mode else 18
	var close_margin := (header_h - close_size) / 2
	theme.set_constant("close_h_offset", "Window", close_size + close_margin)
	theme.set_constant("close_v_offset", "Window", close_size + close_margin)
	theme.set_icon("close", "Window", _make_close_icon(close_size, Color("d8c0b4"), pixel_mode))
	theme.set_icon("close_pressed", "Window", _make_close_icon(close_size, Color("fae6d6"), pixel_mode))
	theme.set_color("font_color", "Label", Color("fae6d6"))
	theme.set_constant("buttons_separation", "AcceptDialog", 12 if pixel_mode else 24)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("452d46") if state == "normal" else Color("644360")
		style.border_color = Color("e7c7ad") if state == "focus" else Color("876480")
		style.set_border_width_all(border)
		style.draw_center = state != "focus"
		style.content_margin_left = 12 if pixel_mode else 24
		style.content_margin_right = 12 if pixel_mode else 24
		style.content_margin_top = 5 if pixel_mode else 12
		style.content_margin_bottom = 5 if pixel_mode else 12
		theme.set_stylebox(state, "Button", style)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(color_name, "Button", Color("fae6d6"))
	return theme


static func _make_close_icon(icon_size: int, color: Color, pixel_mode: bool) -> ImageTexture:
	var img := Image.create_empty(icon_size, icon_size, false, Image.FORMAT_RGBA8)
	var stroke := 1 if pixel_mode else 2
	for i in range(2, icon_size - 2):
		for dy in range(stroke):
			for dx in range(stroke):
				var ax := clampi(i + dx, 0, icon_size - 1)
				var ay := clampi(i + dy, 0, icon_size - 1)
				var bx := clampi(icon_size - 1 - i - dx, 0, icon_size - 1)
				img.set_pixel(ax, ay, color)
				img.set_pixel(bx, ay, color)
	return ImageTexture.create_from_image(img)
