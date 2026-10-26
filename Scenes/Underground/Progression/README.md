# Abyss progression foundations

This pass adds placement, nonblocking placeholder objects, level-border collision,
queries, and mutable state. It adds no player, teleportation, inventory, crafting,
combat, streaming implementation, or movement/traversal guarantee.

## Inspecting the result

Run `progression_preview.tscn` with F6 for the first 100 rows of all three levels.
Cyan dots are checkpoints, gold dots fragments, red dots gates; red vertical lines
mark level borders. Press N to increment the world seed. Inspector controls are
`configuration`, `progression_configuration`, and `depth_rows`.

The existing `abyss.tscn` preview also enables progression by default. On its
RegionPreview node use `enable_progression`, `progression_configuration`, and
`show_special_rooms`. All existing terrain/route overlays remain available. The
physical view constructs placeholders and collidable borders; the logical view
shows the same special-room positions. To inspect a gate closely, find it in the
overview and set the abyss preview's chunk origin to that location. Disable
`enable_progression` to compare against the previous unbounded route layout.

## World boundaries and compatibility

`Generation/Config/progression_config.gd` defines three finite, horizontally
adjacent strips, each eight chunks wide by default. With unchanged 8-room chunks:

| Level | Room X coordinates |
| --- | --- |
| 1 | -32 through 31 |
| 2 | 32 through 95 |
| 3 | 96 through 159 |

Room Y >= 0 is progression depth. The strips extend indefinitely in Y; barriers
also continue above row zero, so going above the entrance cannot bypass a gate.
Outer world sides are sealed. Classification/noise is unchanged everywhere.

When progression is enabled, the existing macro route planner clamps its main
column to its level and uses a translated main descent for each level. Its
existing path search, branches, loops, hashes, and room slots are retained.
Cross-level chunk contracts are excluded *before* local network construction,
rather than deleting edges from completed routes. Every level keeps a connected
logical chunk network. Natural OPEN adjacency also checks level identity.
Cross-level traversal is a separate gate contract, never an ordinary route edge.

Each border-room instance owns a separate `LevelBoundaryEast/West` TileMapLayer
using the existing solid tiles and collision. Both sides enforce the border even
when their neighbor is unloaded. A gate opens three vertically aligned cells on
both layers when unlocked. Outside those cells, the border stays sealed. These
layers are indestructible through the breakable-wall API. They do not modify
source scenes, conditional groups, normal terrain, platforms, or opening metadata.
Boundary slot positions remain unchanged; north/south slots do not intersect the
vertical border layer.

Enabling boundaries changes previous cross-border routes and adds main descents
to levels 2 and 3. Existing template IDs, 24x24 room dimensions, 16px tiles, chunk
dimensions, region settings, and ordinary room-state format are unchanged. This
is a world-layout migration: changing strip origin/width, seeds, or eligibility
rules after saving requires a new world namespace or a future explicit migration.

## Placement rules

`AbyssSpecialRooms` is a random-access planner. It uses stable coordinate hashes
with independent feature domains, never a shared RNG. IDs include world namespace,
level, feature kind, and global room coordinates. Decisions do not depend on
chunk request order, template choice, collection, activation, or gate state.

* Checkpoints roll with configurable `checkpoint_probability` (default 8% candidate chance) in
  OPEN rooms only. Deterministic local-priority thinning enforces
  `checkpoint_min_spacing_rooms` (default 4 rooms between room centers, Euclidean
  distance), including across chunk, interval, and level borders. Increase the
  candidate probability for more checkpoints, or reduce spacing for denser
  placement. Final density is lower than the candidate probability. They are not guaranteed in every cavern. Construction prefers
  an editor-painted checkpoint hint, then an existing landing surface with a
  clear 2x3-tile area, then a collision-free position. It never carves terrain.
  The default spawn position is a future player's collision **center**, not feet.
  The eventual controller must validate its own shape and reachability.
* Every level independently searches each interval [50n, 50n+49], choosing the
  lowest deterministic rank among PACKED rooms on the existing logical network.
  This guarantees one fragment in each eligible interval, even when its first
  chunk was never requested. Eligible packed rooms also roll independently with
  probability 1/200 for an extra fragment; the guarantee and extra roll never
  create two fragments in the same room.
* Each internal border gets at most one gate per 50-row interval. A candidate
  requires OPEN rooms on **both** sides. If none exist, that interval has no gate;
  the wall stays closed. The planner never changes PACKED rooms into OPEN rooms.
* A pathological configuration with no eligible packed rooms in an entire
  level/interval is impossible to satisfy without changing classifications. The
  planner emits an explicit error, rather than silently placing an invalid
  fragment or rewriting the region generator. The shipped settings pass.

Interval searches inspect a bounded level-width x 50 region, cache the result,
and only construct logical routes for fragment candidates whose ranks can win.
No feature needs per-frame scans. Future streaming may evict planner/route caches;
retain the mutation store independently.

## Editor workflow

Reusable editor-visible scenes under `Rooms/Markers/`:

* `checkpoint_marker.tscn` / `CheckpointMarker`
* `fragment_marker.tscn` / `KeyFragmentMarker`
* `gate_marker.tscn` / `LevelGateMarker`

Place these under an authored room's ObjectMarkers and give them unique local
marker IDs. They are placement **hints**, not extra probability rolls: the planner
authorizes the room, feature, and stable identity. Checkpoint and gate hints require
OPEN metadata; fragment hints require PACKED metadata. The validator reports
incompatible room types. The marker framework discovers these subclasses through
its existing RoomMarker base. A hint without a progression planner produces an
unselected typed request with an explanatory reason.

`Rooms/Examples/checkpoint_room.tscn` inherits the editable open cavern and adds a
checkpoint hint. It is intentionally not in the default registry, so adding the
example does not alter template selection. To select it, register compatible
metadata just like any other OPEN template. The standalone fragment marker is the
editable fragment placeholder; place it in any compatible packed template.
Gate hints cannot force gates off a level border. The physical gate placeholder
is placed at the actual boundary aperture. Checkpoints replace the abandoned
surface-teleport-station concept; the feature lab's old station example is now a
generic switch, preserving its interaction-marker demonstration.

Placeholder scenes in this folder expose an `AbyssSpecialSpawnRequest` on their
`request` property. They have no blocking collision. Only the separate level
boundary layers block movement. Creating a special does not automatically discover,
activate, collect, or unlock it.

## Construction and future gameplay APIs

```gdscript
var settings := AbyssProgressionConfig.new()
var routes := AbyssRouteGenerator.new(region_config, route_config, settings)
var specials := AbyssSpecialRooms.new(
    routes, settings, GameController.abyss_progression_state)
var request := selector.select_room(routes, room_coords)
var room := AbyssRoomTerrainBuilder.build(
    request, terrain_config, boundary_field, GameController.abyss_room_state, specials)
```

Pass the *same* service/state when constructing different chunks. The existing
preview already does this. Old callers that omit settings/service retain legacy
unbounded generation. Use the boundary-aware route generator with the existing
`AbyssCavernBoundaryField`; the independent border layer remains authoritative
over cavern noise and authored geometry.

`AbyssSpecialRooms`:

* `definitions_at(room_coords)` — deterministic special definitions.
* `interval_definitions(level, interval)` — guaranteed fragment and gate (if any).
* `level_at(room_coords)`, `level_key(level)` — world-aware level identity.
* `gate_status(border_room)`, `can_cross(a, b)`, `unlock_gate(definition)` — gate
  graph access. Gate unlocking verifies the deterministic gate and source level.
  `can_cross` reports **level-boundary permission**, not physical route validity.
* `activated_checkpoints()` — current world's activated definitions, sorted by ID.
* `checkpoint_destination(id)` — activated destination's world, level, room,
  chunk, and saved player spawn position. Rejects other worlds/inactive IDs.
* `request_checkpoint_chunk(id)` — validates the destination then emits
  `chunk_load_requested(chunk_coords, destination)`. Future chunk loaders listen;
  no chunk loading or teleportation happens in this pass.

Typed room requests:

* `discover()` and `activate()` for checkpoints.
* `collect()` for fragments, idempotent; collected fragments have
  `should_spawn() == false` on reconstruction.
* `unlock()` for gates, using their verified source-level key.

Future gameplay should remove/hide a collected placeholder after `collect()`;
reconstruction already omits it. No automatic pickup loop or player detector is
provided. A saved checkpoint destination uses absolute room-grid world pixels,
not the preview's scaled debug canvas.

## Mutable state

`GameController.abyss_progression_state` survives chunk and scene reconstruction
and later descents. `reset_run()` starts a fresh progression store. It is separate
from `abyss_room_state` (breakables and ordinary markers) and from deterministic
definitions. Neither store writes to source `.tscn` or metadata resources.

`AbyssProgressionState.serialize()` / `restore(json)` handle versioned JSON.
Checkpoint records include discovery, activation, level, coordinates, stable ID,
and saved spawn center. Fragment collection is stored per stable fragment ID;
unlocked gates per gate ID; assembled keys per world/level. Invalid restores leave
state unchanged. Full save-game wiring remains future work.

`collected_count(world_level_id)` and `can_assemble_key(world_level_id)` expose the
three-fragment requirement without implementing crafting. The future blacksmith
calls `record_assembled_key(world_level_id)` **after** a successful craft; this is a
trusted gameplay-state API, not a crafting transaction. Gates require that recorded
key. Keys currently authorize all gates on that level's outgoing border; they are
not consumed. Inventory, crafting costs, and key-use policy remain future work.

## Validation and limitations

`Tests/abyss_progression_test.gd` covers request-order and seed determinism,
per-level 50-row guarantees, PACKED/OPEN constraints, reconstruction/JSON state,
checkpoint destinations, three-fragment eligibility, border route enforcement,
locked/unlocked tile collision, and source preservation. Existing region, route,
conditional-wall, template, terrain, and feature tests remain applicable.

Logical network membership is not a promise of physical platforming reachability.
Gate interiors, checkpoint spawn shapes, return routes, and fragment access still
need the future player controller and traversal validator. Some intervals have no
valid OPEN border pair and intentionally no gate. No gate carving or automatic
route repair is performed.

## File manifest

Created:

* `Generation/Config/progression_config.gd` (+ Godot UID)
* `Progression/progression_state.gd`, `special_rooms.gd`,
  `special_spawn_request.gd`, `special_room_construction.gd`,
  `level_boundary.gd`, `special_placeholder.gd`, `progression_preview.gd`
  (+ their Godot UIDs)
* `Progression/checkpoint.tscn`, `fragment.tscn`, `gate.tscn`,
  `progression_preview.tscn`, and this README
* `Rooms/Markers/checkpoint_marker.gd`, `fragment_marker.gd`, `gate_marker.gd`
  (+ matching `.tscn` and `.gd.uid` files)
* `Rooms/Examples/checkpoint_room.tscn`
* `Tests/abyss_progression_test.gd` (+ Godot UID)

Modified:

* `Autoload/game_controller.gd` — retained progression state and new-run reset.
* `Generation/route_generator.gd` — optional strip-aware macro columns/contracts.
* `Generation/room_data.gd` — level-aware natural open adjacency.
* `Generation/room_terrain_builder.gd` — optional post-construction integration.
* `Generation/room_content.gd` — defer special marker hints to the planner.
* `Generation/room_feature_validator.gd` — marker-region validation.
* `Generation/region_preview.gd` — progression construction and position overlays.
* `Rooms/Markers/room_marker.gd` — special marker gizmo colors.
* `Rooms/Examples/feature_room.tscn` — switch replaces obsolete station example.
* `Generation/README.md` — link to this guide.
