# Hybrid room templates — Milestone 3A

## Run and edit

Open `example_gallery.tscn` here and press **F6** to see the five selected,
instantiated authored examples. The gallery uses explicit example connection
fixtures; it is not a generated world. No procedural terrain is built.

Open any scene in `Examples/` directly to paint its normal Godot TileMapLayers:

- `Solid`: solid terrain, palette tile (0, 0).
- `Platforms`: one-way platform tiles, palette tile (1, 0).
- `Decorations`: non-colliding decoration tiles, palette tile (2, 0).
- `ObjectMarkers`: optional future object positions; no spawning logic.
- `OpeningGuides`: eight Marker2Ds showing the current side/slot convention.

`room_base.tscn` is the empty 24x24 base with the same hierarchy. Duplicate it or
an existing example in Godot's FileSystem dock, rename it, and paint its layers.
No scripts or hierarchy reconstruction are needed. Examples are ordinary,
independent scenes, not a procedural runtime representation. Tiles stay local
within [0, 23] on both axes. The registry, metadata and room root agree on a shared `tile_pixels` value.
Authored tiles default to 16 pixels (384x384-pixel rooms);
the region preview's 8-pixel debug tiles are a separate visualization scale.
The root draws room bounds only in the editor. Opening guides are references;
moving a marker does not automatically change the geometry or metadata.

The example library contains a packed horizontal tunnel, vertical tunnel,
north/east corner, open cavern with a small hand-placed platform, and a packed
transition room with a fully open west face and an east slot-0 exit. These are
architecture examples with one-cell slot apertures, not traversal-tested rooms.

## Add a room through the Inspector

1. Duplicate a scene as described above. Edit Solid / Platforms / Decorations.
   Keep the root script, layer names, local transforms, dimensions and tile size.
   Shared placeholder TileSet assets may be reused; duplicate the TileSet first
   if you want to change its collision data for only one room.
2. Duplicate the nearest metadata `.tres` from `Metadata/`, or create a new
   Resource of type `AbyssRoomTemplateMetadata`.
3. Set a unique `template_id`, display name, scene, region, room dimensions and tile scale,
   selection weight, optional compatibility tags and opening schema.
4. Expand `opening_combinations`. Each `AbyssRoomOpeningProfile` describes one
   **fixed, physically authored combination**, with a unique `variant_id`, exact
   opening IDs and `opening_tiles`. The optional scene override supplies different
   geometry for another combination; an omitted override uses metadata.scene.
   Do not list hypothetical combinations that the scene cannot physically satisfy.
5. Use the existing IDs `north:0`, `north:1`, `east:0`, `east:1`, `south:0`,
   `south:1`, `west:0`, `west:1`. With the current route configuration, N/S slots
   are tile X indices 6 and 17; E/W slots are Y indices 6 and 17. Face coordinates
   are N y=0, E x=23, S y=23 and W x=0. Examples use slot 0 only. A designer can
   author slot-1 scenes and register them without changing generation scripts.
6. For OPEN scenes, declare all four `open_sides` and no discrete holes. Keep
   the entire boundary free of solid and platform collision. Floating interior
   platforms are allowed. A transition uses region TRANSITION and declares its
   original `transition_base_region`; this never changes the noise classification.
   Packed full-open faces can only face known OPEN neighbors. Their corners stay
   capped; the open face spans interior edge tiles 1 through 22.
7. Open `example_registry.tres` (or your own `AbyssRoomTemplateRegistry`) and append
   the metadata Resource to `templates`. No route-generator changes are needed.
   Assign another registry on RegionPreview if desired.
8. Run the tests below. They report missing layers, out-of-room tiles, declared
   holes blocked by collision, undeclared boundary holes, invalid IDs and sizes.

Legacy `supported_openings` remains available as a descriptive union. It is not
permission to choose arbitrary subsets: `opening_combinations` is authoritative.
Changing route offsets or the physical opening convention requires matching
metadata/geometry and an appropriate opening-schema version. An offset/schema
mismatch returns fallback rather than silently moving holes.

## Compatibility and selection

`room_requirements.gd` snapshots the generated room dimensions, primary region,
transition/boundary data, main-route flag, logical neighbors, exact route openings,
neighbor classification masks, and opening schema/offsets. It does not write to
room or chunk data. Unknown neighbors never authorize a fully open packed face.

`room_template_selector.gd` snapshots the registry and validates its geometry at
registration. It excludes invalid definitions and duplicate stable IDs; read
`registration_errors` for diagnostics. Selection itself only compares data:

- Region and dimensions/schema must match. TRANSITION requires a boundary room
  with matching OPEN/PACKED base type; ordinary templates can also fit boundaries.
- Every discrete profile coordinate must match the current route convention.
- PACKED discrete openings must exactly equal required openings, except that
  required slots on a declared full-open face are covered by that face.
- A packed full-open face must face a known OPEN room. Extra holes into packed
  or unknown neighbors are never implicitly allowed. This conservative policy
  also rejects extra discrete slots into OPEN unless they are part of a declared
  full-open transition face.
- OPEN profiles keep every face open, independent of required graph edges. A
  neighboring packed room still controls its own wall and deliberate openings.

Opposite packed endpoints use the route graph's existing side/slot positions;
selection neither rerolls those slots nor changes the route. Exact matching
prevents one endpoint from selecting a scene with a different aperture.

Candidates are sorted by stable template and variant ID before a coordinate/seed
hash makes a weighted choice. A template's weight is divided among its compatible
variants, avoiding increased overall weight just from listing more combinations.
Registry order, chunk request order and exploration history do not influence
selection. Weight zero disables a template. Adding/removing templates can change
choices, so future saved worlds should record library/algorithm versions.

## Generator integration and procedural fallback

```gdscript
var selector := AbyssRoomTemplateSelector.new(registry, region_config.global_seed)
var request := selector.select_room(route_generator, global_room_coords)
if request.method == AbyssRoomConstructionRequest.Method.AUTHORED:
	var room_scene := AbyssRoomSceneInstantiator.instantiate_authored(request)
	if room_scene != null:
		world_rooms.add_child(room_scene)
else:
	# Milestone 3B: build procedural geometry from request.requirements/room_seed.
	pass
```

The instantiator is explicit and separate from selection. It places authored
geometry at global room coordinates using its tile size. The example gallery
overrides that position only to arrange demonstration cards.

Every request carries the immutable-by-convention requirements snapshot, global
seed, stable per-room seed, method, reason, selected stable IDs and PackedScene
when authored. A PROCEDURAL request has no scene and instantiates nothing.
Milestone 3B should consume exactly the same dimensions, neighbor masks and
required apertures; it must not modify the route graph to suit construction.
Generated layout, selection results, scene geometry and future persistent
pickups/discovery/gameplay state remain separate. Persistent state should be
keyed by world identity plus the existing global room ID, not scene instances.

In `abyss.tscn`, enable **RegionPreview > Show Template Selection** to see green
A (authored request) and amber F (fallback request) markers over the existing
region/route preview. It uses real generated room data and the assigned registry.
The toggle defaults off. It does not construct room geometry in the abyss scene.
Restart after Inspector changes, or call `regenerate()` at runtime.

## Verification

```sh
godot --headless --path . --script Tests/abyss_room_templates_test.gd
godot --headless --path . --script Tests/abyss_regions_test.gd
godot --headless --path . --script Tests/abyss_routes_test.gd
godot --headless --path . --script Tests/abyss_route_complexity_test.gd
godot --headless --path . --script Tests/abyss_main_wander_test.gd
godot --headless --path . Scenes/Underground/Rooms/example_gallery.tscn --quit-after 3
```

New tests validate all five scenes and the base hierarchy; successful selection
and instantiation; wrong regions/combinations/dimensions/schema/coordinates;
unsafe extra openings and unknown neighbors; multiple scene-backed combinations;
registration and request-order independence; duplicate IDs; metadata/physical
boundary mismatches; weighted seed variation; stable fallback seeds; and selection
against actual generated rooms without changing their data. A 3:1 weighted trial
selected the heavier template 773/1000 times, with 363 changes between seeds.
A real generated chunk gave 5 authored / 59 fallback requests (the library is
intentionally small). The gallery and abyss run headlessly without script errors.

The region test's statistical fixture is now pinned to its original seed 12345,
frequency 0.035, threshold 0.27, radius 1 and two iterations: 29.97% OPEN across
65,536 rooms. The current live radius-5 tuning measured 22.42% OPEN; it was left
unchanged. Scene integration still exercises the live configuration. Other route
regression tests retain their existing settings and assertions.

## Milestone 3B remaining work

Implement procedural construction from fallback requests, library expansion,
aperture widths, room-interior traversability and physical upward backtracking.
The structural validator checks tile-boundary collision presence, not exact
collision-polygon coverage, movement physics, path clearance, or interior route
reachability. It trusts metadata about region intent and does not simulate
physics. Normal scene scripts may run when a scene is instantiated for validation;
keep templates free of autonomous spawning in this milestone. No player,
streaming, gates, enemies, hazards, map UI or mutable persistence is added.


## 24x24 dimension migration

The world default is `AbyssRegionConfig.DEFAULT_ROOM_SIZE` (24x24); the world
configuration's `room_size` remains configurable. A world uses one size for all
rooms. The five authored examples pin that size in both metadata and scene roots.
A different world size requires compatible authored assets and route offsets;
otherwise selection produces procedural construction requests with the world size.
The validator already checks root/metadata agreement, local tile bounds, boundary
collision, and opening geometry; the selector checks the world dimensions and
exact offsets before selecting a template. No mixed-size room placement is added.

The migrated assets retain their template IDs, variant IDs, and opening combinations.
`abyss_slots_v1` still means the same side/slot convention; dimensions and explicit
opening coordinates are separately checked. Default slot indices are now 6 and 17:

| Side | Slot 0 | Slot 1 |
| --- | --- | --- |
| North | (6, 0) | (17, 0) |
| East | (23, 6) | (23, 17) |
| South | (6, 23) | (17, 23) |
| West | (0, 6) | (0, 17) |

At 16 pixels per tile, a room is 384x384 pixels. Its world origin is
`global_room_coords * room_size * tile_pixels`. The 8x8-room chunk is now
192x192 tiles (3072x3072 pixels). Noise still samples room coordinates: seed,
noise settings, classifications, graph edges and slot IDs are unchanged.

Existing tile layouts were expanded into real cells, without scaling the room
or TileMapLayer nodes: solid formations expanded in both axes, platforms expanded
horizontally and were repositioned vertically, decorations were repositioned,
and marker guides were moved. Boundary apertures were restored to one cell at
the declared slots. Local edits in the corner and transition examples were used
as migration inputs. The gallery displays scenes at native tile size.

This changes physical world positions, room extents, and tile layouts. Existing
12x12 tile-coordinate or pixel-coordinate save data must be versioned/regenerated
or explicitly migrated; do not load it unchanged into the 24x24 world. Stable room
coordinate IDs and the logical graph retain their meanings. Tunnel interiors are
larger, but the one-cell boundary aperture clearance limitation remains.

This checkout already includes Milestone 3B physical construction. The dimension
migration adds no construction features and leaves that builder unchanged. The
older 3A-only descriptions above describe the original architecture stage; the
abyss preview currently constructs terrain and T toggles its logical view.

Verify migration invariance with:

    godot --headless --path . --script Tests/abyss_room_dimensions_test.gd

That test compares old 12x12 / (3,8) contracts against the new contracts for 1,728
rooms over three seeds, including negative coordinates and neighboring chunks.

## Conditional wall groups

All five example scenes and `room_base.tscn` now contain an editable
`ConditionalWalls` TileMapLayer sharing the placeholder TileSet. Paint the solid
rock tile (atlas 0,0) on this layer. Four-directionally connected cells form one
group. Leave at least one empty tile between groups; diagonal contact does not
connect them. Keep tiles strictly inside the room, without overlapping Solid or
Platforms. Boundary walls still belong on Solid, preserving opening contracts.

Open the room's metadata `.tres` and expand **Conditional Walls**:

- **Conditional Wall Probability** defaults to 0.5 per eligible group. 0 disables
  every group; 1 includes every safe group.
- **Debug Conditional Walls** prints room coordinates, canonical group coordinate,
  tile count, roll, inclusion result, and rejection reason during construction.

No node script needs to be attached to a painted group. Its stable identifier is
its minimum (X, then Y) tile coordinate. Hashing combines that identifier, the world
seed, room coordinates, and template ID. Decisions do not consume a shared RNG;
adding an unrelated group or changing chunk construction order does not reroll
existing groups. Moving a group's minimum coordinate or joining two groups changes
its identity. Groups never merge across room instances.

Construction changes only the instantiated ConditionalWalls layer: included groups
retain their edited solid tiles and collision; omitted groups erase every cell.
The source PackedScene, Solid, Platforms, Decorations, and object markers remain
unchanged. Old registered scenes without ConditionalWalls remain compatible.

To reserve navigation space explicitly, select the room root and edit
**Reserved Route Rects**. Rectangles use local tile coordinates and appear as cyan
editor guides. The instantiator additionally protects each required port and its
entry throat, a deterministic tree of existing empty paths joining required ports,
and an interior approach for dead ends. These are structural tile-clearance guards,
not movement-aware traversal validation. Any group touching protected space is
omitted as a whole, even if its probability roll succeeds. Static boundary,
permanent-layer overlap, non-solid tile, and reserved-rectangle authoring errors
are reported by template validation. No openings or logical route edges are changed.

`Examples/open_cavern.tscn` contains four separated, three-tile L-shaped sample
clusters and two reserved central rectangles. Open `example_gallery.tscn` and press
F6 to view constructed results. Orange rocks are conditional; the room label shows
included/total groups. Press **N** for the next preview seed, or set Preview Seed
on the gallery root. For the real abyss use its existing seed controls. Physical
preview statistics now include `conditional_tiles`, and final-edge overlays and
neighbor boundary sampling include selected conditional terrain.

Run `godot --headless --path . --script Tests/abyss_conditional_walls_test.gd`.
The test exercises all 16 combinations across 256 seeds, all-or-nothing groups,
negative room coordinates, order independence, group-ID stability when adding a
component, forced probability endpoints, actual PhysicsServer collision queries,
protected openings/corridors/dead ends, metadata errors, and source-scene byte
preservation. Existing terrain snapshots also include the new layer.

See [ROOM_FEATURES.md](ROOM_FEATURES.md) for climbables, conditional platforms,
breakable group health/persistence, six extensible placement marker types, the
standalone feature laboratory, save interfaces, and the changed-file manifest.
