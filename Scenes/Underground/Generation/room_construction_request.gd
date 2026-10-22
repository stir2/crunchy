class_name AbyssRoomConstructionRequest
extends RefCounted
## Construction decision only. No geometry is built by selection.
enum Method { AUTHORED, PROCEDURAL }
var global_seed: int
var room_seed: int
var method: Method = Method.PROCEDURAL
var requirements: AbyssRoomRequirements
var template_id: StringName
var variant_id: StringName
var scene: PackedScene
var reason: String = "No compatible authored template"
