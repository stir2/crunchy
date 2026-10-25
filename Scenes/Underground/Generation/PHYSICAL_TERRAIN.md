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


Room dimensions have migrated to 24x24 tiles with 16px tiles. The five authored
scenes and their metadata use slots 6 and 17 on boundaries 0 and 23. Construction
uses request dimensions, so the existing builder needs no algorithm change.
Earlier tile counts in this document are historical samples. See Rooms/README.md
for physical save compatibility and the complete opening-coordinate table.

## Continuous cavern boundaries

The old transition removed independent 1–3-tile strips from room faces. At 24x24,
this left long straight walls, square corners, and room-local noise resets.
`transition_depth` remains a compatibility control only for standalone builds
without a world sampler; it does not shape the current world preview.

`AbyssCavernBoundaryField` samples signed distance to the nearest opposite-region
room rectangle, then compares it against broad and fine global tile-coordinate
noise. A positive bias expands caverns into surrounding rock. Distance to unions
of room rectangles rounds exterior corners; the noise introduces broad lobes,
recesses, and small surface steps. Negative displacement can push rock into the
OPEN side of the band. Room classifications and the logical graph never change.

The region halo is derived from blend width + warp amplitude + detail strength,
rounded up to rooms with an extra margin. The smoothing stencil samples a global
3x3 halo, never a clamped room/chunk image. Noise uses terrain-specific seeds
from the existing global seed and no room/global RNG consumption. The sampler
caches masks and tile samples only for its finite preview lifetime; regeneration
discards it. Chunk-local rendering and integer global tile positions are unchanged.

Routing wins over deformation: packed-to-packed faces stay sealed except at
required slots, open-to-open faces stay open, and the existing tunnel carving runs
after boundary construction. OPEN route corridors are cleared after any rock
intrusion. Authored scenes bypass the field entirely. A smooth procedural collar over the transition blend width
samples the neighboring authored scene's actual Solid cells, preserving edited
geometry rather than approximating its openings. Only the boundary cell is pinned;
there is no copied two-tile strip. Exact tunnel ports are cleared
afterward. Authoring and hard interface contracts can still leave straight edges;
the field does not rewrite these constraints to hide them.

Select RegionPreview > Terrain Configuration > Cavern Boundaries:

| Control | Default | Suggested tuning |
| --- | --- | --- |
| Boundary Warp Amplitude | 8 tiles | 4–8 subtle; 12–20 strong lobes |
| Boundary Warp Frequency | 0.035 | 0.015–0.035 broad; 0.05–0.08 tighter shapes |
| Transition Blend Width | 10 tiles | 6–16; half the width is baseline erosion |
| Boundary Detail Strength | 1.5 tiles | 0–1 smooth; 2–4 craggy |
| Boundary Smoothing | enabled | Global one-pass 3x3 majority cleanup |

For smoother caverns, lower detail and frequency and keep smoothing enabled.
For rougher edges, raise detail/frequency or disable smoothing. For heavily eroded
caverns, raise blend width and amplitude together. High amplitude without enough
blend width also creates inward rock lobes. Route seals and authored collars can
limit displacement at individual interfaces. Restart after Inspector edits or call
`regenerate()` to compare the same seed. B toggles original region edges (cyan),
F toggles final physical edges (green), G toggles room grid; the Inspector also
exposes the chunk grid. R toggles route overlays; T switches logical/terrain view.

World callers should share one field for a bounded build:

    var field := AbyssCavernBoundaryField.new(route_generator, selector, terrain_config)
    var room := AbyssRoomTerrainBuilder.build(request, terrain_config, field)

Omitting the optional field retains conservative local-only construction for old
callers with no neighboring world context. Authored requests remain identical in
both modes. The preview uses the field for every generated procedural room.

`Tests/abyss_cavern_boundaries_test.gd` exercises 30 rooms across the x=0 chunk
seam and negative coordinates, compares independent samplers in reverse build
order, validates packed seals/open-open faces/required ports and authored tile
bytes, and checks connected packed passages. It compares amplitude 0 vs 20 with
the same seed: 535 changed field tiles, 253 well inside room interiors, 2,016
interface checks, 29 required ports, 9 authored rooms, zero isolated procedural
solid tiles. It also checks high-warp port clearance. The test writes a field-mask
comparison to `/tmp/abyss-boundary-comparison.png` (flat left, high warp right).
The seven previous regression suites and the new boundary suite pass on Godot
4.7.2. Both debug edge overlays and the abyss scene pass headless smoke checks.
Physical layouts change; region and route generation and room dimensions do not.


Corner follow-up: the signed-distance mask now receives a global Gaussian stencil
with radius half the transition blend width before noise is applied. This rounds
concave rectangular mask corners at a meaningful scale; the separate optional
3x3 binary cleanup remains available. Authored collars now blend signed values
with smooth falloff instead of copying a constant two-tile strip and abruptly
switching to the noise field. Smoothing stencils read actual authored cells.
The mask halo includes the wider rounding stencil. All samples remain global and
cached independently of construction order. No new Inspector parameters are needed:
Transition Blend Width also controls corner rounding and authored blend reach.
The boundary suite includes a zero-noise concave-corner regression fixture.

Packed-seal fin follow-up: forcing the outermost tile of both adjacent PACKED
rooms solid left a two-tile-wide fin when the surrounding field eroded. It could
look like a chunk-rendering seam, but it was a post-field room-boundary seal.
The field now includes rounded capsule-shaped support around these seals before
cleanup, with exposed endpoints inset by their radius to round the tip. The same
global segment is computed on both sides, including negative chunk coordinates.
Support survives authored-side blending; authored scene contents remain unchanged.
Tunnel carving still runs last. The radius uses half Transition Blend Width
(clamped to 2 tiles through one third of the room size); no new knob is added.
A required seal can still form a rounded rock projection, but not a long bare
pair of boundary rows. Tests cover vertical pillars and horizontal ledges at
chunk seams -192, 0, and 192, with both procedural and authored OPEN neighbors.
