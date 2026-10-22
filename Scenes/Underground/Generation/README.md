# Abyss regions — Milestone 1

Open `Scenes/Underground/abyss.tscn` and run the current scene (F6).
Select `RegionPreview`: expand `Configuration` to edit the seed, room/chunk
sizes, noise frequency, OPEN threshold, and smoothing radius/iterations.
Preview origin accepts negative chunk coordinates. Width/height are in chunks.
Restart the scene after Inspector edits; this is a runtime preview, not an
editor tool. `regenerate()` also rebuilds the preview from its current settings.
Cyan means OPEN; slate means PACKED. Grid toggles are on the preview node.
The preview fits to the viewport beside the existing HUD.

Lower frequency produces larger blobs. Lower threshold produces more OPEN.
The default threshold 0.27 gives approximately 30% OPEN with simplex-smooth
noise, no fractal, frequency 0.035, and two radius-one majority iterations.
The percentage is statistical, not enforced per chunk or guaranteed for every
seed/configuration. Larger smoothing radii/iteration counts remove small
features and can shift the distribution.

`AbyssRegionConfig` contains layout inputs; a generator snapshots it on creation.
Create a new generator when changing settings:

```gdscript
var generator := AbyssRegionGenerator.new(settings)
var chunk := generator.get_chunk(Vector2i(-1, 2))
var room := generator.get_room(Vector2i(-1, 16))
```

Chunks are cached by coordinate. Room arrays are row-major, with global and
chunk coordinates, original noise, final enum classification, and four cardinal
boundary bits (north/east/south/west). `is_transition()` identifies rooms next
to the other classification. `get_room()` on chunks takes local coordinates;
on the generator it takes global coordinates. Negative coordinates use floor
division. Treat returned generated data and config as read-only. Keep future
mutable discovery/pickup/gameplay state separate and keyed by global room.

Each smoothing pass is synchronous majority voting over a square neighborhood,
including the center. Chunk sampling includes radius * iterations plus one
room of halo, then shrinks after each pass, so edge classifications and boundary
bits are independent of generation order, chunk size, and preview dimensions.
No shared RNG is used. Raw noise always samples global room coordinates.

`region_preview.gd` alone owns rendering. It builds a two-color TileSet with
8-pixel tiles, no physics layers, and disabled TileMapLayer collision. Each
room fills exactly `room_size` tile cells (12 by 12 by default). These tiles
are classification markers, not terrain.

Run verification from the project directory:

```sh
godot --headless --path . --script Tests/abyss_regions_test.gd
```

The test checks reconstruction/order, negative coordinates, boundary metadata,
repartitioned chunk seams, a 65,536-room distribution, isolated rooms, different
seeds, scene initialization, collision absence, tile footprints, and preview
resizing. On Godot 4.7.2 the current sample was 29.97% OPEN, zero isolated OPEN
rooms; 518 of 1,600 compared rooms changed with the next seed.

Limitations: no streaming or cache eviction; callers choose a finite set of
chunks. Large previews fill many tile cells and may be expensive. Generation
uses floating-point FastNoiseLite: persist the seed, all configuration, and an
algorithm/engine version before promising compatibility across future engine
or generator changes. Smoothing only removes small local artifacts; it does
not guarantee connectivity or traversability. Milestone 2 can use the boundary
metadata for routes but must not assume OPEN blobs form a connected network.

## Milestone 2: logical routes

`AbyssRouteGenerator.new(region_settings, route_settings)` owns a fresh instance
of the existing region generator. Use its `get_chunk()` / `get_room()` for
route-enriched data. Its `regions` property remains the unchanged pass-1 API;
requesting a region chunk alone does not run the route pass. No physical
construction or template selection occurs. Required edges are undirected;
`logical_neighbors()` supports future map queries and upward backtracking.
Room IDs are signed global `x:y` strings, scoped to a world seed/configuration.

The previous generator forced a horizontal access highway through every chunk
row, plus a three-segment main route. Those lines were real graph edges, not a
rendering error. Its branch walks stopped on their first invalid choice. Route
layout version 3 replaces that structure with five stages:

1. **Boundary contracts and random-access global planning.** Hashed horizontal
   waypoints are spaced `main_route_wander_scale` chunk rows apart. Waypoint zero
   is fixed at the entrance column. Other waypoint displacements are seeded,
   smoothly interpolated, rounded to chunk columns, and clamped to the configured
   main-route envelope. `main_column(y)` evaluates two waypoint hashes, without
   generating any shallower chunks. Within chunk row y, the main sequence visits
   adjacent columns from `main_column(y)` to `main_column(y+1)`, then descends.
   Shared ports connect the visits; no teleports or horizontal full-width lines
   are constructed. `main_chunks_for_band()` returns the ordered chunk visits,
   and `is_main_chunk()` supports preview/map queries. Negative rows use floor
   division and the same interpolation.

   A side chunk approaches a fixed hub row/column within its attachment band.
   The hub column is sampled from the wandering main route at the hub row.
   Either absolute X-distance to this fixed hub decreases, or Y-distance to its
   row decreases. This lexicographic potential strictly decreases until a main
   chunk is reached. Main chunk parents follow their ordered horizontal visits
   and then descend, never pointing back to side chunks. The chunk parent
   hierarchy is acyclic even though optional graph connections create loops.
2. **Winding main route.** A coordinate-seeded private RNG runs a bounded,
   self-avoiding randomized DFS between its incoming and outgoing MAIN ports. These can be on top/bottom
   or lateral chunk faces, preserving the same local organic path search. Weighted
   directions favor downward movement; turning/persistence weights and a
   straight-run cap shape the route. Preferred stretch encourages detours,
   including upward steps. A bounded number of retries and a finite direct
   fallback guarantee completion even with tiny or restrictive configurations.
   A shorter found path is allowed when the stretch preference is infeasible.
3. **Connected access and branches.** Other ports attach to the local network
   with randomized winding paths, rather than mandatory horizontal lines.
   Roots are shuffled deterministically. Branches choose a preferred length
   in the configured range and try valid unoccupied directions. Branch points
   may grow secondary branches. A room-density budget limits optional growth;
   necessary main/access routes take priority over that budget. Total depth
   from the initial network is bounded by the maximum branch budget. Dead ends
   remain intentional. Branches may be shorter when blocked or density-limited.
4. **Loops.** Selected unused edges between already connected occupied rooms
   become reconnection edges. Optional shared contracts allow inter-chunk loops.
   Attachment paths stop at their first contact with the existing network;
   cycles are introduced only in the reconnection stage or by optional shared
   loop contracts. A reconnection edge is not a promise of a physically
   traversable loop until construction is validated in Milestone 3.
5. **Validation.** A finite BFS checks each chunk's interior network. Global
   connectivity follows from the parent rule, connected interiors, and matching
   reciprocal contracts; it does not depend on generation order or loaded data.

`entrance_room()` and `entrance_for_band()` preserve their public interfaces.
Negative bands extend the same system upward for previews; no surface cap is
constructed. A cropped preview can cut a valid path which exits and returns.
Tests follow the deterministic parent closure and necessary main-column bands
when checking global reachability instead of requiring horizontal highways.
With wandering, the closure includes every main chunk between the sampled bands,
not a fixed central column.

Contracts are computed from coordinates alone. Building a chunk never calls
`get_chunk()` on a neighbor. Both endpoints derive contract existence, port,
kind and opening slot independently from the same canonical inputs. Optional
inter-chunk contracts are enabled by their own probability when branches and
reconnections are enabled. No exploration-order RNG or frontier state exists.

A canonical global edge identifier and deterministic slot hash supply identical
opening slots at both endpoints. Connections expose side (N/E/S/W = 0/1/2/3),
slot (0/1), stable `side:slot` ID, local tile index, neighbor, and edge kind.
Packed endpoints list their required openings; OPEN endpoints do not imply
walls or physical doors. The same tangential tile index is used on opposing
edges. Tile positions represent one-cell markers, not aperture width/geometry.
Changing offsets changes the physical contract; version `opening_schema` with
that change and match it in future templates.

`allows_open_adjacency()` reports adjacent OPEN rooms regardless of route edges.
Absence of a required edge must never imply a wall between OPEN rooms. Unrouted
rooms are classification data only, not promised exploration areas.

Run the scene with F6. On RegionPreview, expand Route Configuration:

| Parameter | Default | Purpose |
| --- | --- | --- |
| main_route_horizontal_wander | 4.0 | Waypoint displacement amplitude, in chunk columns |
| main_route_wander_scale | 8 | Chunk rows per interpolated waypoint interval |
| main_route_max_horizontal_drift | 6 | Hard displacement cap from entrance column |
| downward_preference | 0.65 | Main-path down weight before turn/validity weighting |
| directional_persistence | 0.25 | Weight for continuing in the same direction |
| turning_weight | 1.2 | Relative weight for changing direction |
| max_straight_run | 3 | Search run cap; degenerate grids/fallback can exceed it |
| main_path_stretch | 1.5 | Preferred length relative to endpoint distance |
| branching_probability | 0.45 | Chance to start a branch at a candidate root |
| branch_min_length / branch_max_length | 3 / 10 | Preferred branch lengths |
| secondary_branch_probability | 0.35 | Multiplier for branch-from-branch roots |
| room_density | 0.50 | Optional occupied-room budget, after necessary routes |
| reconnection_probability | 0.09 | Chance of closing an eligible local loop |
| inter_chunk_loop_probability | 0.08 | Chance of an additional shared boundary contract |
| attachment_band_height | 4 | Side-chunk parent planning scale, in chunk rows |

`branch_length` remains a stored API alias for `branch_max_length`, including old
Resource properties. Opening offsets/schema and entrance column are unchanged.
These are the current project values; all existing tuning parameters were
preserved when adding wandering. Set wander to zero for a narrow descent. Larger
amplitude increases its span; larger scale makes migration more gradual. Amplitude bounds the interpolated
waypoints; integer rounding selects columns, and the maximum drift remains a
hard bound on every visited main-route chunk.
A drift cap of zero also disables wandering. No history or accumulated RNG state
is needed, even for distant or negative rows.

The envelope is a planning bound, not a level or gate system. For future levels,
place it inside the permitted horizontal domain (or provide asymmetric domain
bounds to the pure planner). All side/access/optional contracts will also need
to honor that domain when levels are implemented; the main-route cap alone does
not restrict the whole world or create walls. Region Configuration still
controls the seed, room/chunk size, and noise.

Independent toggles control classifications, main/access routes, main-chunk
highlighting, branches,
reconnections, packed openings, room boundaries, chunk boundaries, actual
crossings and boundary contracts. Region opacity defaults to 0.25; disable
classifications for a plain graph. Yellow = main, purple = access, orange =
branches, pink = reconnects. Gray dashed lines are only the chunk grid. White
dots mark actual required crossing edges. Cyan outlined boxes mark shared
boundary contracts. Red dots show required packed opening tile centers. Optional yellow translucent chunk fills highlight
main-route participants without adding route-like boundary lines. The
contract/actual-crossing markers and packed openings start hidden to reduce
clutter. Every colored solid line corresponds to a required graph edge, never
to the chunk grid or a speculative route. Half edges at the preview perimeter
indicate graph connections continuing outside the crop.

For a wider view, try origin (-4, 0), width 9 chunks and height 12 chunks; a
small crop can lose sight of the main route as it migrates. Horizontal main
crossings use the same yellow route lines as vertical crossings. Disable chunk
grid and region colors to follow the natural graph alone.

Restart after Inspector changes, or call `regenerate()` at runtime. The preview
is not an editor tool. `debug_layout(chunk_coords)` returns read-only diagnostic
main/branch polylines, contracts and edges without scene dependencies.
`validate_chunk_layout(chunk_coords)` checks an already generated layout.

### Hand-authored templates in Milestone 3

`AbyssRoomTemplateMetadata` is an Inspector-editable Resource with stable template
ID, PackedScene reference, region, dimensions, opening schema, supported stable
opening IDs, and compatibility tags. A future selector can filter on region,
12x12 dimensions, schema, and coverage of every required opening, then sort
compatible templates by stable ID and select via a room-ID/seed-derived value.
If no compatible template exists, pass the same room requirements to procedural
construction. Normal `.tscn` templates can own separate terrain/platform/decor
TileMapLayers; the route generator knows neither their structure nor construction
scripts. Selection, scene instantiation, template libraries, and fallback terrain
construction are intentionally deferred. Extra physical connectivity is allowed.

### Route validation and metrics

```sh
godot --headless --path . --script Tests/abyss_routes_test.gd
godot --headless --path . --script Tests/abyss_route_complexity_test.gd
godot --headless --path . --script Tests/abyss_main_wander_test.gd
godot --headless --path . --script Tests/abyss_regions_test.gd
godot --headless --path . Scenes/Underground/abyss.tscn --quit-after 3
```

The original route suite retains determinism, reverse request order, reciprocal
openings, negative coordinates, unchanged region data, main continuation,
branch-depth bounds, zero probabilities, custom slots, OPEN adjacency and extent
independence checks: 5,241 rooms across three seeds and 8x8 / 5x3 / 1x1 chunks.
Its global BFS now includes parent chains outside the crop, since a finite
rectangle need not contain every connecting path. The previous rectangular
connectivity assumption depended on the removed horizontal highways.

The original route and complexity suites now explicitly use zero wander to
retain their fixed-column regression assumptions. The same 320-chunk complexity
sample is unchanged from immediately before this revision: main stretch 2.33x,
straight runs average 1.67 / max 3, 573 branches averaging 4.18 rooms, 53 secondary
branch starts, 1,224 junctions, 493 interior dead ends, 328 independent cycles,
and zero full-width highways. No prior connectivity/opening checks were removed.

The new wandering suite checks default 64-row descents for seeds 12, 12345, -71,
and 91. It also covers zero wander, an offset entrance with a tighter bound,
negative rows, fast multi-column migration, million-row random access, shuffled
chunk request order, parent-cycle absence, reciprocal graph/opening contracts,
MAIN-only room-level connectivity and degree two, side-network reachability,
continued downward exits, and absence of full-width horizontal highways.

| Seed | Distinct columns | Max displacement | Average shift per row | Main length / vertical | Horizontal crossings |
| --- | --- | --- | --- | --- | --- |
| 12 | 6 | 4 | 0.250 | 2.88x | 16 |
| 12345 | 4 | 3 | 0.172 | 2.77x | 11 |
| -71 | 8 | 4 | 0.422 | 3.60x | 27 |
| 91 | 7 | 4 | 0.203 | 2.90x | 13 |

Displacement and row shift are in chunk columns. Length includes every internal
main edge and one departure edge per visited chunk, including lateral crossings.
The 64-row samples collectively check a single bidirectional main chain, not
just connectivity of the chunk plan. Broad/fast controls still guarantee a
vertical departure each row, but increase route length substantially.

An apples-to-apples comparison in the same 320-chunk crop, preserving all other
parameters, gives 573 branches averaging 4.18 rooms and 334 unique reconnection
edges in zero-wander mode, versus 564 branches averaging 4.14 rooms and 353
unique reconnection edges with wandering. Reconnection-edge counts include
boundary contracts; they differ from the finite induced graph's independent
cycle count. Branch algorithm and tuning values are unchanged.

All four suites pass on Godot 4.7.2; the wandering suite checks over 112,000
connection endpoints. Pass 1 remains 29.97% OPEN across 65,536 rooms at the
current seed/frequency. The abyss scene runs headlessly without script errors.
These tests establish logical connectivity, not physical climbability.

### Remaining limitations

Wandering is bounded by a symmetric envelope around the entrance, so it does
not drift arbitrarily far sideways. Integer columns produce plateaus during
slow interpolation; random waypoint targets avoid a fixed oscillation pattern.
Chunk-row planning remains monotonic downward at the macro scale, with upward
detours inside rooms/chunks. At aggressive amplitude/scale settings it can cross
multiple columns in a row; defaults keep those transitions gradual. A finite
preview may clip the connected main path or side attachments.

Tiny chunks cannot support organic detours or long branches. Bounded searches
may fall back to shorter or straight connections for pathological settings.
Mandatory connections can exceed optional room-density budgets. Level domains,
gates and all geometry/physics remain future work. The same opening schema and
room/template interfaces apply to every lateral and vertical transition.

Route version 3 intentionally changes existing seed layouts. Persist the route
algorithm version alongside seed/configuration for future saved worlds. Same
engine/configuration reproduces layouts; no compatibility across future RNG or
algorithm changes is promised. No terrain, streaming, template selection,
physics validation or mutable game-state storage is implemented.

## Milestone 3A: hybrid room construction definitions

The metadata/selection system is implemented separately from route generation.
See [Rooms/README.md](../Rooms/README.md) for the editable base, five example
scenes, exact opening combinations, registry registration, weighted deterministic
selection, procedural fallback contract, gallery and tests. The route graph and
region algorithm are unchanged. RegionPreview has an optional authored/fallback
selection overlay; it does not build geometry into the generated abyss yet.
