# Authored room features

Open `feature_demo.tscn` and press F6. This is an isolated room laboratory, not a
player controller. The existing player prototype was reverted; no movement,
combat, enemy AI, inventory, hazard gameplay or traversal validator is introduced.

- Arrows move a free probe; right click places it. Green means climbable, red
  means outside. The status reports entering/exiting the ladder/vine shaft.
- Left click the cracked alcove wall three times to destroy its entire group.
  A short flash demonstrates the destruction signal hook.
- N changes world seed; R rebuilds the same room while retaining mutations.
- L records selected loot as collected; I records an interaction as activated.
- F5 saves the demo store to `user://room_feature_state.json`; F9 restores it.
  K clears the demo's mutations. The demo store is independent of campaign state.
- The panel lists wall/platform decisions, group health, marker types, spawn
  decisions and persistent status. Markers are visible here only for debugging.

The sample has two independent conditional platform groups, two conditional wall
groups, a connected shaft alternating two climbable visuals, a breakable entrance
to an optional alcove, two enemies, loot, a hazard, a transition, an interaction,
and a decoration marker. None of those object requests instantiate gameplay yet.

`Examples/feature_room.tscn` and `Metadata/feature_room.tres` are deliberately not
added to the default registry: existing template selection stays unchanged. Add
its metadata to a registry's Templates array in the Inspector to use it in the
abyss. Registering additional templates can change which compatible rooms win.

## Painting layers

All existing examples and `room_base.tscn` retain their previous layers and now
also have the following normal editable TileMapLayers. Coordinates are 0–23 on
both axes; tiles remain 16px. Keep layer transforms at identity.

| Layer | Palette atlas coordinate | Behavior |
| --- | --- | --- |
| Solid | (0,0) | Existing permanent solid rock |
| Platforms | (1,0) | Existing permanent one-way platforms |
| Decorations | (2,0) | Existing non-colliding decoration |
| ConditionalWalls | (0,0) | Existing 50% four-connected wall groups, unchanged rolls |
| Climbables | (3,0), (4,0) | Blue ladder / green vine, same `climbable` custom data |
| ConditionalPlatforms | (1,0) | One independent one-way platform decision per group |
| BreakableWalls | (5,0) | Cracked solid rock; shared health per connected structure |

Climbable placeholders have no collision. The Climbables layer itself permits
collision so a future climbable tile variant can also supply its own collision
polygons. Colliding variants cannot cover protected boundaries/routes.

Leave a tile gap between independent groups; diagonal contact does not merge
components. Groups never span room instances. Do not overlap solid/platform layers
or paint conditional/breakable cells on outer boundaries. The validator reports
wrong tile collision types, bounds, overlaps, reserved areas and invalid metadata.

In metadata, Room Features exposes **Conditional Platform Probability** (0.5 by
default) and **Breakable Health** (3 by default). Conditional wall probability and
its original hash/decisions remain unchanged. New randomness uses separate feature
domains and does not consume a shared RNG.

On the room root, Reserved Route Rects protects clear navigation corridors.
**Required Support Rects** declares support tiles necessary for guaranteed routes;
paint those supports on permanent Platforms. Conditional platforms intersecting
these rectangles are rejected, not forced to appear. Runtime also rejects whole
conditional platform groups touching required ports or the structural reserved
path. Breakables touching those paths are omitted. Paint optional features away
from those areas. This does not infer jump reach or determine whether a platform
is essential for upward traversal: authors must declare required supports until
Milestone 3C performs movement-aware validation.

## Shared groups and identities

`AbyssTileGroups` owns the existing four-direction flood fill, extracted without
changing its ordering. During construction each relevant layer is grouped once.
`room.tile_groups[layer_name]` holds read-only-by-convention group descriptions:
`id`, `canonical`, `cells`, `bounds`, `tile_type`, and `tiles` (source, atlas and
alternative indices). Runtime behavior-specific state is kept separately.

The conditional wall helper delegates only component detection to the common
helper and reads its cached cells. Its roll function and all-or-nothing policy are
preserved. Conditional platforms use their own hash domain. Included tiles are
retained as authored, so atlas alternatives, flips and collision data survive.
Omission/destruction erases only the affected group's cells. No per-tile nodes or
per-frame group scans are created. The demo alone has a per-frame probe.

Automatically derived IDs combine template identity, layer and canonical minimum
(X, then Y) cell. Joining, splitting or moving a group can change that identity.
For breakable persistence across intentional revisions, set root **Breakable Group
Ids**: canonical Vector2i -> explicit string. If a group's canonical cell changes,
move the dictionary key but retain the explicit string. Duplicate/stale overrides
are validation errors. If a structure's meaning changes, version its ID/template
or world namespace so old destruction records do not target unrelated terrain.

To add another tile-group behavior, add a layer, describe it once through
`AbyssTileGroups.describe`, add one construction handler and collision/protection
checks in `AbyssRoomFeatureValidator`, and choose its own random/state domain.
Keep behavior state out of group definitions. A registry of per-tile behaviors is
unnecessary for the current jam.

## Climbing interface and future traversal checks

`AbyssClimbableTiles.sample(layers, world_position)` returns a detection result
including layer/cell/world location. `vertical_path(layers, start, end)` checks a
continuous vertical painted span; it detects gaps and accepts layers from multiple
rooms. Both functions accept ordinary TileMapLayers, including future procedural
climbables. `room.climbable_layers()`, `climbable_cells`, and `climbable_regions`
expose the instantiated room's geometry to the future validator.

A future CharacterBody2D controller should sample at its hands/body, enter climb
mode while an up/down input is held in a climbable region, apply vertical climb
velocity instead of gravity, and leave when detection ends or the player jumps.
`sample` is a geometry query, not a replacement controller or a physics guarantee.
Climbable caches describe construction-time geometry; direct layer edits should
refresh caches if a consumer needs them, while `sample` always reads current tiles.

## Breakable API and persistence

    room.damage_breakable_at(world_position, amount)
    room.destroy_breakable_group(group_id)
    room.breakables.groups()

An isolated painted tile is a singleton group. Connected tiles share one health
pool. Calls reject non-positive/non-finite damage and already destroyed/protected
groups. `breakable_damaged(id, remaining_health, world_position)` and
`breakable_destroyed(id, cells, world_position)` are room signals for combat,
particles and sound. `terrain_changed` invalidates optional terrain overlays.
Signals, cells and world positions refer to the constructed instance, including
room/chunk transforms. No combat framework has been created.

`AbyssRoomState` holds mutable group health and marker statuses. Keys include a
world namespace (request.world_id, or the world seed by default), room coordinates,
template identity and stable group/marker ID. No per-tile destruction save entries
are used. Partial damage persists as well as destruction. Different world namespaces
cannot consume each other's records.

`GameController.abyss_room_state` owns the live store across abyss scene exits and
later descents. RegionPreview retains it when regenerating chunks. Other chunk
builders pass their retained store to:

    AbyssRoomSceneInstantiator.instantiate_authored(request, state)
    AbyssRoomTerrainBuilder.build(request, terrain_config, boundary_field, state)

Omitting state creates an isolated room store, useful for galleries and tests.
A full game save can save `GameController.abyss_room_state.serialize()` and load
with `restore(json)`. Restore checks schema/version before replacing live state.
Disk save orchestration is deferred; the demo provides a manual round trip. A new
campaign should replace/clear the store. Keep one live instance per logical room.
Generation/metadata are never mutated by damage or collected/activated objects.
The boundary field remains generation-only; runtime validators should query actual
layers and group health, rather than assume its cached original terrain is mutable.

## Placement markers

Drag a reusable scene from `Markers/*_marker.tscn` under ObjectMarkers and position
it in the 2D editor. Set a nonempty room-unique Marker Id. Common Inspector fields
are Spawn Probability, Tags, Configuration Resource, and Persistence (persistent
or respawn). Distinct colored editor gizmos identify categories. Ordinary gameplay
hides their debug visuals unless Show Debug is enabled.

| Scene/type | Additional Inspector fields | Typed request |
| --- | --- | --- |
| enemy_marker / EnemySpawnMarker | type/pool, difficulty/depth ranges, encounter group | EnemySpawnRequest |
| loot_marker / LootSpawnMarker | type/table, quantity range, rarity, collection ID | LootSpawnRequest |
| hazard_marker / HazardSpawnMarker | type/scene, orientation, clearance radius | HazardSpawnRequest |
| transition_marker / TransitionMarker | destination, logical gate ID | TransitionSpawnRequest |
| interaction_marker / InteractionMarker | interaction type/scene | InteractionSpawnRequest |
| decoration_marker / DecorationMarker | decoration pool, variation range | DecorationSpawnRequest |

Depth restrictions currently use nonnegative room Y, and difficulty comes from
request.difficulty (default 1). Configuration Resources are read-only spawn
configuration, not mutable state. Hazard requests overlapping protected corridors
are ineligible and carry a reason. Their radius is a conservative tile footprint;
final hazard geometry will need a future placement/traversal check.

`room.spawn_requests` contains every supported marker's typed definition and stable
roll, even when omitted. `selected` is deterministic; `should_spawn()` additionally
checks restrictions and persistent status. `world_position` follows room/chunk
reparenting and transforms. Local positions also work for nested marker containers.
A future spawn consumer can instantiate referenced scenes or interpret pools and
Resources. Calling `request.record_status("collected")` / `("activated")` updates
only the mutable store. Respawn-policy requests ignore persistent records.

To add a new type, subclass `RoomMarker` with `@tool`, expose only relevant fields,
and override `kind()` plus `make_request()` returning a `RoomSpawnRequest` subclass.
Alternatively register a factory with `RoomMarkerHandlers.register(kind, callable)`.
The pipeline discovers the common base recursively: no selector/route changes are
needed. Unsupported types produce a warning and `room.content_warnings` entry,
then are skipped without blocking generation. Factories must create request data,
not spawn gameplay as a side effect.

## Verification and files

Run `Tests/abyss_room_features_test.gd` headlessly for climb placement/variants,
platform grouping and one-way data, independent domains across 128 seeds, marker
order determinism, real collision removal, group-only damage, partial/destroyed
state round trips, explicit-ID revisions, probability endpoints, protected routes,
registered and unknown custom markers, and source byte preservation.
The existing conditional-wall suite still produces all 16 combinations over 256
seeds with inclusion counts [113,132,123,113]. The complete regression suite also
covers regions, routes, complexity, wander, room dimensions, templates, terrain,
and cavern seams. Demo, gallery and abyss have headless smoke checks.

Created (alongside Godot-generated .gd.uid files):

- Generation/tile_groups.gd, room_random.gd, room_state.gd, room_content.gd,
  room_feature_validator.gd.
- Features/climbable_tiles.gd, breakable_terrain.gd.
- Markers/room_marker.gd, room_spawn_request.gd, marker_handlers.gd.
- Markers/{enemy,loot,hazard,transition,interaction,decoration}_marker.gd,
  matching _marker.tscn scenes, and matching _spawn_request.gd scripts.
- Examples/feature_room.tscn, Metadata/feature_room.tres,
  feature_demo.gd, feature_demo.tscn, ROOM_FEATURES.md.
- Tests/abyss_room_features_test.gd.

Modified:

- Assets/Tiles/room_placeholders.svg and .tres (existing tile indices preserved).
- authored_room.gd, room_base.tscn, all five existing Examples scenes (empty layers).
- Generation/conditional_wall_groups.gd (shared detection/cache + climbable collision),
  room_construction_request.gd, room_template_metadata.gd, room_template_selector.gd,
  room_scene_instantiator.gd, room_terrain_builder.gd, room_template_validator.gd,
  region_preview.gd, cavern_boundary_field.gd.
- Autoload/game_controller.gd (retained state store only), Rooms/README.md.

No classification, routing, conditional-wall probability algorithm, room dimensions,
world seed, AI, combat, inventory or final hazard logic has been changed.
