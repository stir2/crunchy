extends Control
## The loss stays visible through its sound, then fades back to black.
signal finished
const PORTRAITS = preload("res://Scenes/Village/villager_portraits.gd")
var losses: Array[Dictionary] = []
var _content: VBoxContainer


func _ready() -> void:
	name = "VillagerLossNotice"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var content := VBoxContainer.new()
	_content = content
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


func fade_out() -> void:
	var fade := create_tween()
	fade.tween_property(_content, "modulate:a", 0.0, 0.55)
	await fade.finished
	finished.emit()
