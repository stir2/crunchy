extends RefCounted
## Shared portraits derived from saved names, including older saves and loss records.

const ROOT := "res://uiSprites/Portraits/"
const SIZE := Vector2i(72, 76)
const HAIR := ["hairBraid.PNG", "hairShort.PNG", "hairTied.PNG", "mikuHair.png", "portraits/guyhair.PNG", "portraits/guyHairBack.PNG"]
const SKIN := [
	["f3cbad", "ec9782", "b6877b"], ["e4b28b", "c98369", "965e50"],
	["c68f68", "a9694e", "774c3e"], ["9e684b", "804b39", "59392f"],
	["744b38", "59372c", "3d2823"], ["edc6b8", "cc9991", "a57773"],
]
const HAIR_COLOURS := [
	["422016", "5e3b30"], ["251d1b", "41342d"], ["85592f", "b58b4e"],
	["a87942", "d4b775"], ["743a29", "a45839"], ["817b72", "b7b1a1"],
	["c0b8a5", "e0d8c5"], ["403736", "665251"],
]
const CLOTHES := ["cec6a0", "78917b", "899ca3", "a47b70", "b49b69", "9689a2", "777a6b", "b3a99d"]
static var _textures: Dictionary = {}
static var _layers: Dictionary = {}


static func texture_for(villager_name: String) -> Texture2D:
	if _textures.has(villager_name):
		return _textures[villager_name]
	var random := RandomNumberGenerator.new()
	random.seed = villager_name.hash()
	var hair := random.randi_range(0, HAIR.size() - 1)
	var canvas := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	_blend(canvas, "portraits/72x76.PNG")
	_blend(canvas, "portraitBase.PNG" if hair < 4 else "portraits/portraitBase1.PNG")
	_blend(canvas, "portraits/ear.PNG")
	_blend(canvas, HAIR[hair])
	if hair >= 4:
		var facial_hair := random.randi_range(0, 2)
		if facial_hair > 0:
			_blend(canvas, "portraits/beard.PNG" if facial_hair == 1 else "portraits/stache.PNG")
	var accessory := random.randi_range(0, 4)
	if accessory == 1:
		_blend(canvas, "glasses.PNG")
	elif accessory == 2:
		_blend(canvas, "portraits/eyepatch.PNG")
	elif accessory == 3:
		_blend(canvas, "portraits/scar.PNG")
	if random.randf() < 0.3:
		_blend(canvas, "earing.PNG")
	var skin: Array = SKIN[random.randi_range(0, SKIN.size() - 1)]
	var hair_colour: Array = HAIR_COLOURS[random.randi_range(0, HAIR_COLOURS.size() - 1)]
	var palette := {
		Color("f3cbad"): Color(skin[0]), Color("ec9782"): Color(skin[1]),
		Color("b6877b"): Color(skin[2]),
		Color("422016"): Color(hair_colour[0]), Color("5e3b30"): Color(hair_colour[1]),
		Color("4f2d23"): Color(hair_colour[0]), Color("c0826b"): Color(hair_colour[1]),
		Color("cec6a0"): Color(CLOTHES[random.randi_range(0, CLOTHES.size() - 1)]),
	}
	for y in SIZE.y:
		for x in SIZE.x:
			var pixel := canvas.get_pixel(x, y)
			if palette.has(pixel):
				canvas.set_pixel(x, y, palette[pixel])
	var texture := ImageTexture.create_from_image(canvas)
	_textures[villager_name] = texture
	return texture


static func _blend(canvas: Image, path: String) -> void:
	if not _layers.has(path):
		var texture := load(ROOT + path) as Texture2D
		var layer := texture.get_image()
		layer.convert(Image.FORMAT_RGBA8)
		_layers[path] = layer
	canvas.blend_rect(_layers[path], Rect2i(Vector2i.ZERO, SIZE), Vector2i.ZERO)
