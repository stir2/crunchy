class_name AbyssRouteConnection
extends RefCounted
## An undirected required connection, exposed from either endpoint.
enum Kind { MAIN, ACCESS, BRANCH, RECONNECTION }
var edge_id: String
var neighbor: Vector2i
var kind: Kind
var side: int
var slot: int
var opening_id: StringName
var opening_tile: Vector2i
