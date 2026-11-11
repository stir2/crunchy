extends RefCounted
## Shared parchment and ink treatment for menus, notices, and dialogs.
const PAPER = preload("res://uiSprites/paper.png")
const INK := Color("392b24")
const CREAM := Color("f3d8ae")

static var _clean_paper: ImageTexture

static func paper_texture() -> Texture2D:
	if _clean_paper == null:
		var image := PAPER.get_image()
		image.convert(Image.FORMAT_RGBA8)
		var data := image.get_data()
		# The source has a low-opacity wash outside the torn right edge.
		for index in range(3, data.size(), 4):
			if data[index] < 64:
				data[index] = 0
		image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)
		_clean_paper = ImageTexture.create_from_image(image)
	return _clean_paper

static func paper_style(pad_h: float, pad_v: float, tint := Color(1.12, 1.18, 1.24)) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = paper_texture()
	style.modulate_color = tint
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 26 if side in [SIDE_LEFT, SIDE_RIGHT] else 16)
		style.set_content_margin(side, pad_h + 7.0 if side == SIDE_LEFT else pad_h + 3.0 if side == SIDE_RIGHT else pad_v)
	return style

static func apply_buttons(theme: Theme, pad_h: float, pad_v: float, border: int) -> void:
	var fills := {
		"normal": Color("594139"),
		"hover": Color("704c3e"),
		"pressed": Color("47332f"),
		"disabled": Color("80664f"),
	}
	for state: String in fills:
		var style := StyleBoxFlat.new()
		style.bg_color = fills[state]
		style.border_color = Color("392823")
		style.set_border_width_all(border)
		style.border_width_bottom = border + 1
		style.content_margin_left = pad_h
		style.content_margin_right = pad_h
		style.content_margin_top = pad_v
		style.content_margin_bottom = pad_v
		theme.set_stylebox(state, "Button", style)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color("edca92")
	focus.set_border_width_all(border)
	theme.set_stylebox("focus", "Button", focus)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(key, "Button", CREAM)
	theme.set_color("font_disabled_color", "Button", Color("d0b69a"))

static func make_theme(factor: float = 1.0, pixel_mode: bool = false) -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16 if pixel_mode else roundi(28 * factor)
	theme.set_color("font_color", "Label", INK)
	var pad := 12.0 if pixel_mode else 32.0 * factor
	theme.set_stylebox("panel", "PanelContainer", paper_style(pad, pad))
	var border := 1 if pixel_mode else maxi(1, roundi(2 * factor))
	apply_buttons(theme, 8.0 if pixel_mode else 16.0 * factor, 4.0 if pixel_mode else 8.0 * factor, border)
	var rule := StyleBoxLine.new()
	rule.color = Color(0.25, 0.17, 0.12, 0.3)
	rule.thickness = border
	theme.set_stylebox("separator", "HSeparator", rule)
	return theme

static func make_confirmation_theme(pixel_mode: bool = false) -> Theme:
	var theme := make_theme(1.0, pixel_mode)
	var font_size := 16 if pixel_mode else 32
	theme.default_font_size = font_size
	var pad_h := 16 if pixel_mode else 36
	var pad_v := 14 if pixel_mode else 28
	var panel := paper_style(pad_h, pad_v)
	theme.set_stylebox("panel", "AcceptDialog", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)
	var header_h := 24 if pixel_mode else 48
	var frame := StyleBoxTexture.new()
	var header := AtlasTexture.new()
	header.atlas = paper_texture()
	header.region = Rect2(0, 0, PAPER.get_width(), header_h)
	frame.texture = header
	frame.modulate_color = panel.modulate_color
	frame.draw_center = false
	frame.set_texture_margin(SIDE_TOP, header_h)
	frame.set_texture_margin(SIDE_LEFT, 26)
	frame.set_texture_margin(SIDE_RIGHT, 26)
	frame.set_expand_margin(SIDE_TOP, header_h)
	theme.set_stylebox("embedded_border", "Window", frame)
	theme.set_stylebox("embedded_unfocused_border", "Window", frame)
	theme.set_constant("title_height", "Window", header_h)
	theme.set_color("title_color", "Window", INK)
	theme.set_font_size("title_font_size", "Window", font_size)
	var close_size := 10 if pixel_mode else 18
	var close_margin := (header_h - close_size) / 2
	theme.set_constant("close_h_offset", "Window", close_size + close_margin)
	theme.set_constant("close_v_offset", "Window", close_size + close_margin)
	theme.set_icon("close", "Window", _make_close_icon(close_size, INK, pixel_mode))
	theme.set_icon("close_pressed", "Window", _make_close_icon(close_size, Color("80573d"), pixel_mode))
	theme.set_constant("buttons_separation", "AcceptDialog", 12 if pixel_mode else 24)
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
