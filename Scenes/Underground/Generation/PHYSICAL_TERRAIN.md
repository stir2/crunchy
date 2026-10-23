# Milestone 3B physical terrain

Run `Scenes/Underground/abyss.tscn` directly. It starts in terrain mode.
T switches terrain/logical classification; G toggles room boundaries; O toggles
required packed ports; A labels authored (A) and fallback (F) rooms; R toggles
route lines. Mouse wheel zooms around the cursor; middle-drag pans. All original
route debugging Inspector options remain available. Resizing or regenerating
fits the full preview again.

Select RegionPreview in the Inspector. Existing configuration, route configuration,
preview origin and chunk width/height control the same finite region as before.
Expand Terrain Configuration for tunnel width, shape variation, internal openness,
platform probability/count, and transition erosion depth. Change Inspector values
before running, or call regenerate() after runtime changes.

`room_terrain_builder.gd` consumes the existing construction request. Authored
requests go through the existing instantiator, without rewriting tiles, metadata,
markers, decorations or collisions. Procedural requests use only room_seed in a
private RNG. PACKED starts full, then carves bounded brush paths from each exact
port to a shared varied hub. Sorted port IDs make dictionary iteration irrelevant.
The brush never alters the outer ring. Only declared ports and known OPEN faces
can remove boundary terrain. OPEN starts empty and optionally receives short
interior one-way platforms. No collision is added along its perimeter.

Packed faces adjoining OPEN are eroded in shallow uneven strips, producing
recessed rock edges and ledges without placing a wall in the open room. Required
ports are carved first and erosion only removes terrain. A final bounded flood
fill removes rock islands unanchored to closed room faces. Neighbors need no shared
random state: packed owns its rock face, open owns its empty face. No tiles cross
room bounds. The lower bound logical graph remains untouched.

PhysicalChunks owns disposable chunk containers; each contains bounded room-local
Solid, Platforms and Decorations TileMapLayers. Authored scenes retain their entire
hierarchy. Chunk and room origins use integer room/tile coordinates times the
registry tile size. Only the physical preview container is scaled to match the
existing 8px debug visualization; physical tiles remain 16px. Freeing a chunk frees
all its layers and markers. This is a finite preview, not runtime streaming.

The shared placeholder TileSet provides full solid collision on atlas (0,0),
one-way collision on (1,0), and decorative (2,0). Decorations disable collision.
Authored layer settings are preserved. No changes were made to template metadata.

Validation commands (Godot 4.7):

	godot --headless --path . --script Tests/abyss_terrain_test.gd
	godot --headless --path . --script Tests/abyss_regions_test.gd
	godot --headless --path . --script Tests/abyss_routes_test.gd
	godot --headless --path . --script Tests/abyss_route_complexity_test.gd
	godot --headless --path . --script Tests/abyss_main_wander_test.gd
	godot --headless --path . --script Tests/abyss_room_templates_test.gd
	godot --headless --path . Scenes/Underground/abyss.tscn --quit-after 3

Terrain test sample: four neighboring chunks spanning negative coordinates and
horizontal/vertical chunk seams, 256 rooms, 118 authored / 138 procedural,
17,135 solid tiles, 428 platform tiles. Default preview: 768 rooms,
141 authored / 627 procedural, 77,554 solid tiles, 436 platform tiles.
Counts depend on seed and region smoothing configuration.

Milestone 3C must resolve collision-shape clearance at the existing one-tile
boundary slots (16px). Interiors are wider, but widening authored boundaries here
would violate the v1 opening contract. No eventual player dimensions were supplied.
Flood-fill tests prove tile connectivity, not movement feasibility. Jump reach,
upward travel, one-way platform accessibility, dead-end usefulness, and transition
landing suitability still need movement-aware validation. No route repair is done.


Small-cavern region preset: noise_frequency 0.16, open_threshold 0.32,
smoothing_radius 1, smoothing_iterations 1. With seed 65746575646678777,
a 128x128-room sample centered on the origin measures 20.84% OPEN, 222
connected open components, median component size 13 rooms (largest 88;
components clipped by the sample boundary). The initial 32x24-room preview is
19.40% OPEN. Coverage varies by seed and sample window. Earlier construction
counts above describe the original milestone preset.

Frequency sets feature scale in room coordinates; threshold controls coverage.
Tune both with smoothing held fixed. Radius 5 means an 11x11-room majority
filter, and three passes remove smaller features. Use radius 1 and one pass
for this preset. Saved resource overrides in the Inspector take precedence over
script defaults; reset those four properties to use these defaults if needed.
