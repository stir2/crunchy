extends Control
## The loss stays visible through its sound, then fades back to black.
signal finished
const PORTRAITS = preload("res://Scenes/Village/villager_portraits.gd")
var losses: Array[Dictionary] = []
var _content: VBoxContainer
var _veil: ColorRect


func _ready() -> void:
	name = "VillagerLossNotice"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	_veil = black
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var content := VBoxContainer.new()
	_content = content
	content.modulate.a = 0.0
	content.custom_minimum_size.x = 480
	content.add_theme_constant_override("separation", 24)
	center.add_child(content)
	var title := Label.new()
	title.text = "A villager has died" if losses.size() == 1 else "Villagers have died"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	content.add_child(title)
	var grayscale := Shader.new()
	grayscale.code = """shader_type canvas_item;
void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	float grey = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(grey * 0.65), pixel.a * COLOR.a);
}
"""
	var portrait_material := ShaderMaterial.new()
	portrait_material.shader = grayscale
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48)
	content.add_child(row)
	for loss in losses:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 20)
		row.add_child(card)
		var portrait := TextureRect.new()
		portrait.texture = PORTRAITS.texture_for(String(loss.get("name", "")))
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.material = portrait_material
		portrait.custom_minimum_size = Vector2(288, 304)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.add_child(portrait)
		var caption := Label.new()
		caption.text = String(loss.get("name", ""))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size", 32)
		card.add_child(caption)
		var cause := Label.new()
		match String(loss.get("cause", "")):
			"taken": cause.text = "Taken by the monster"
			"sacrificed": cause.text = "Sacrificed"
			"starved": cause.text = "Died of starvation"
			_: cause.text = "Died"
		cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cause.add_theme_font_size_override("font_size", 24)
		card.add_child(cause)

	var reveal := create_tween().set_parallel(true)
	reveal.tween_property(_veil, "color:a", 0.65, 0.65)
	reveal.tween_property(_content, "modulate:a", 1.0, 0.65).set_trans(Tween.TRANS_SINE)


func fade_out() -> void:
	var fade := create_tween().set_parallel(true)
	fade.tween_property(_content, "modulate:a", 0.0, 0.75)
	fade.tween_property(_veil, "color:a", 0.0, 0.75)
	await fade.finished
	finished.emit()
