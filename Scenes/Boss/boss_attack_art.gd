extends Node2D
## JV's exported layers share a 640x360 canvas. Preserve that alignment when cropping.
enum Layer { BODY, LEFT, RIGHT, HEAD }
const ROOT := "res://BossSprites/%s Attack/%s Frames/%s/%s%04d.png"
# The exports include held duplicates. These are the source indices where each layer changes.
const CLIPS := {
	&"Sweep": [
		["body sweep", "bodySweep", [0, 7, 10, 14, 19, 22, 25, 27, 29, 53, 55, 57, 59, 70, 74, 76, 78]],
		["main arm sweep", "mainArmSweep", [0, 4, 7, 10, 14, 19, 22, 24, 25, 26, 27, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 68, 70, 74, 76, 78]],
		["claw arm sweep", "clawArmSweep", [0, 4, 7, 10, 14, 19, 24, 53, 55, 57, 68, 76, 78]],
		["head sweep", "headSweep", [0, 4, 7, 22, 24, 25, 27, 53, 55, 57, 68, 74, 76, 78]],
	],
	&"Strike": [
		["body strike", "bodyStrike", [0, 17, 26, 31, 41, 43, 45, 47, 59, 63, 66, 69, 71]],
		["main arm strike", "handStrike", [0, 11, 17, 26, 29, 31, 41, 43, 59, 63, 66, 69, 71]],
		["claw arm strike", "clawStrike", [0, 11, 17, 22, 26, 29, 31, 41, 43, 59, 63, 66, 69, 71, 73]],
		["head strike", "headStrike", [0, 11, 17, 22, 26, 29, 31, 41, 43, 45, 47, 63, 66, 69, 71]],
	],
}

const ANCHOR_BLEND := 1.0

var _frames: Dictionary = {}
var _layers: Array[Sprite2D] = []

func _ready() -> void:
	for layer in Layer.size():
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.z_index = -1 if layer in [Layer.LEFT, Layer.RIGHT] else 0
		sprite.hide()
		add_child(sprite)
		_layers.append(sprite)
	for clip: StringName in CLIPS:
		var layers: Array = []
		for spec: Array in CLIPS[clip]:
			var frames: Array = []
			for index: int in spec[2]:
				var texture := ResourceLoader.load(ROOT % [clip, clip, spec[0], spec[1], index]) as Texture2D
				if texture == null:
					frames.append([])
					continue
				var image := texture.get_image()
				var bounds := image.get_used_rect()
				frames.append([ImageTexture.create_from_image(image.get_region(bounds)), Vector2(bounds.position), Rect2(bounds).get_center()])
			layers.append(frames)
		_frames[clip] = layers

func paint(layer: Layer, clip: StringName, frame: float, opacity: float,
		art_scale := Vector2.ONE, art_offset := Vector2.ZERO) -> float:
	var sprite := _layers[layer]
	sprite.visible = opacity > 0.001
	if not sprite.visible:
		return 0.0
	var keys: Array = CLIPS[clip][layer][2]
	var key := keys.bsearch(roundi(frame), false) - 1
	var drawings: Array = _frames[clip][layer]
	var drawing: Array = drawings[key]
	if drawing.is_empty():
		sprite.hide()
		return 0.0
	sprite.texture = drawing[0]
	var origin: Vector2 = drawing[1]
	# Keep the center moving through held frames without blending two silhouettes.
	# The strike smear still lands on its original frame.
	if layer in [Layer.BODY, Layer.HEAD] and not (clip == &"Strike" and frame >= 39.0 and frame <= 44.0):
		origin += _smoothed_anchor(keys, drawings, key, frame) - Vector2(drawing[2])
	sprite.position = origin * art_scale + art_offset
	sprite.scale = art_scale
	sprite.modulate.a = opacity
	return opacity

func _smoothed_anchor(keys: Array, drawings: Array, key: int, frame: float) -> Vector2:
	var center: Vector2 = drawings[key][2]
	if key > 0 and frame < keys[key] - 0.5 + ANCHOR_BLEND and not drawings[key - 1].is_empty():
		var blend := smoothstep(keys[key] - 0.5 - ANCHOR_BLEND, keys[key] - 0.5 + ANCHOR_BLEND, frame)
		return Vector2(drawings[key - 1][2]).lerp(center, blend)
	if key + 1 < keys.size() and frame > keys[key + 1] - 0.5 - ANCHOR_BLEND and not drawings[key + 1].is_empty():
		var blend := smoothstep(keys[key + 1] - 0.5 - ANCHOR_BLEND, keys[key + 1] - 0.5 + ANCHOR_BLEND, frame)
		return center.lerp(drawings[key + 1][2], blend)
	return center
