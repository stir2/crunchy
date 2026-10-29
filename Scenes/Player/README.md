# Player movement, collision, and hit detection

Run `player_test.tscn` with **F6**. A/D or Left/Right moves; Space jumps; releasing
Space early shortens the jump. **Hold Action (currently Shift)** to charge a horizontal dash; release to launch. More charge
means more speed and duration, with automatic launch at full charge.
Falling resets to Spawn. Your current movement tuning is preserved.
See [charged dash and jump grace](CHARGED_DASH.md) for state/timing details.

## Scene hierarchy and exact dimensions

```
Player (CharacterBody2D, player.gd; origin at feet)
├── Visuals (0, -18)
│   └── AnimatedSprite2D (player_animation.gd)
├── CollisionShape2D — RectangleShape2D 30x36, position (0, -18)
├── Hurtbox (Area2D, player_hurtbox.gd; position (0, -18))
│   └── CollisionShape2D — RectangleShape2D 24x32, position (0, 0)
├── AttackPivot (0, -18)
│   └── AttackHitbox (Area2D, inactive)
│       └── CollisionShape2D — disabled, no assigned shape
└── ClimbDetector (Area2D, inactive; position (0, -18))
    └── CollisionShape2D — disabled reserved extent
```

The physical body spans X -15..15, Y -36..0 relative to the feet. The hurtbox
spans X -12..12, Y -34..-2: **3 px inset on each side, 2 px top and bottom**.
Both rectangles are set directly on Shape resources. No collider/body scaling is
used, and movement/jumping/facing never resizes or flips either rectangle. Shapes
are local to each scene instance. Visuals and AttackPivot alone flip horizontally.

Select the root `CollisionShape2D` in Godot's 2D editor to inspect the physical
rectangle. Expand **Shape > Size** and **Transform > Position** in the Inspector.
Select `Hurtbox/CollisionShape2D` separately to inspect its 24x32 rectangle; its
local position is zero, while the parent Hurtbox is at (0,-18). Hide Visuals with
the editor eye if needed. **Debug > Visible Collision Shapes** displays both when
running the scene. The empty disabled attack shape may have an expected editor
configuration warning; it has no runtime collision or attack behavior.

## Layers and hurtbox hooks

Project Settings > Layer Names > 2D Physics now labels these existing/free bits:

| GUI layer | Bit mask | Purpose |
| --- | --- | --- |
| 1 | 1 | Terrain |
| 2 | 2 | Player Body |
| 3 | 4 | Player Hurtbox |
| 4 | 8 | Damage Areas |

The CharacterBody2D is on layer 2, mask 1: it physically collides with the existing
solid and one-way terrain tiles. Hurtbox is on layer 3, mask 4 (numeric values
**4 and 8**), monitoring and monitorable enabled. It detects incoming **Area2D**
shapes on Damage Areas, not terrain, bodies, or arbitrary areas. Incoming areas
must be monitorable and have an enabled Shape2D. Their own mask can be zero when
the hurtbox is responsible for detection.

`PlayerHurtbox` forwards two typed signals:

```gdscript
$Player/Hurtbox.damage_area_entered.connect(_on_damage_area_entered)
$Player/Hurtbox.damage_area_exited.connect(_on_damage_area_exited)

func _on_damage_area_entered(area: Area2D) -> void:
    # Future gameplay can inspect the source area/configuration here.
    pass
```

These are overlap events, not health changes or automatic per-frame damage. No
health, immunity, knockback, damage numbers, death, or combat framework is added.
Areas do not physically block movement. AttackHitbox stays separate, unassigned,
disabled, and on zero layers/masks; no attacks or dash shapes are implemented.
ClimbDetector remains an inactive future hook. Noncolliding climbable tiles will
need the existing `AbyssClimbableTiles` query interface rather than Area2D overlap.

## Visuals and presentation

The player uses the existing `chiefIdle`, `chiefWalk`, and `chiefRun` sheets in
`Assets/Sprites/Player/`, all at **100x100 frame size and 24 FPS**. The editable
`chief_sprite_frames.tres` contains 14 idle, 21 walk, and 15 run frames, all looping.
AnimatedSprite2D uses scale (1,1) and nearest filtering; it does not resize either
collision shape. The source art faces left, so Flip H starts enabled and the
existing Visuals facing flip supplies left/right direction.

`player_animation.gd` chooses idle while stopped, walk during ordinary horizontal movement,
and run only above 125% of normal run speed (including retained dash momentum).
A weak dash below that threshold also uses walk. Keyboard and analog input both
use walk at normal movement speeds. No new walk/run input or movement-speed change is added.
Jumping and falling always play the run loop, including stationary vertical
jumps. Below the high-speed threshold it plays at half speed (12 FPS), adjustable
with Airborne Run Speed Scale; high-speed movement stays at 24 FPS. Grounded movement still walks unless it has high horizontal momentum.
Dash charging pauses the current pose until release.
The existing charge tint/shake continues on the parent Visuals node.

Select Visuals/AnimatedSprite2D to tune idle threshold, run threshold ratio, or
per-animation offsets. Idle/walk use offset (0,-4), run uses (0,3), accounting for
different foot padding while the Visuals base stays (0,-18). Slight frame-to-frame
foot motion is retained from the artwork. Replace/tune art offsets independently
of physics; sprites are not stretched to fit the body. Jump wind-up now holds a
crouched chief pose with a warm tint before takeoff.

The project deliberately uses a **1920x1080, canvas_items/expand** presentation for
its village UI: `Scenes/Village/House/house.tscn` has an explicit 1920x1080 minimum
canvas and large fixed-size panels. A global switch to 640x360 would clip that UI.
Those project display settings are preserved, as allowed by the existing-rendering
exception in this task. The existing display settings are unchanged; `Dash` is added to the Input Map.

**The movement lab** uses the requested pixel-art presentation while it runs:

- Base viewport **640x360 (16:9)**.
- Stretch **viewport**, aspect **keep**, scale mode **integer**.
- Desktop test window **1280x720** by default (2x).
- **1920x1080** gives 3x with the same world-pixel collision dimensions.
- Default viewport texture filter **nearest**, plus explicit nearest on the player
  AnimatedSprite2D and terrain layers.

`player_test.gd` sets these Window properties, saves the previous host settings,
and restores them on scene exit. The PlayerTest root exports `base_viewport_size`
and `test_window_size`; change the latter to (1920,1080) to test 3x. Non-16:9
windows preserve aspect; integer scaling may add borders. No village layout or
other gameplay systems were rewritten.

The Camera2D is on the player instance in **player_test.tscn**, not in the reusable
player. Its zoom is configurable in the Inspector and defaults to **(1,1)** for
this smaller base viewport. Keep integer zoom when evaluating pixel art; arbitrary
fractional camera zoom or subpixel movement can still affect visual crispness.
World collision sizes do not change with viewport, window size, or camera zoom.

## Editable collision lab

Solid and Platforms are painted TileMapLayers using the existing placeholder
TileSet. Atlas (0,0) is solid; (1,0) has one-way collision. The lab includes a floor,
96 px jump gap, solid steps at 64 px height increments, wall, ceiling passages,
and a one-way platform 64 px above the floor.

- **64 px-high** passage: comfortable walking, with a ceiling low enough to hit
  during a jump.
- **48 px-high** passage: 12 px headroom for the 36 px body.
- **16 px-high** passage: deliberately blocked.
- **32 px-wide shaft** above the blocked-passage roof: only **1 px clearance per
  side** for the 30 px body; a precision drop test.
- **48 px-wide shaft**: a more comfortable vertical clearance test.

The shaft/roof fixtures are also editable tiles. Spawn and Player initial
positions represent **feet**, not body centers. Move both to change the starting
point; the `fall_reset_y` export controls the test-only fall reset. Respawn is not
a death, damage, or checkpoint mechanic.

## Movement extension points

The single movement controller uses NORMAL, DASH_CHARGING, DASHING, and RECOVERY states, with
one authoritative `move_and_slide()` per physics tick. Normal movement uses:

1. `handle_horizontal_movement(delta)` — horizontal acceleration/friction only.
2. `apply_gravity(delta)` — project/area gravity while airborne.
3. `handle_jump()` — grounded jumping and upward release reduction.
4. `update_facing_direction()` — visual/attack-pivot facing, never collider scale.

| Inspector parameter | Default | Effect |
| --- | --- | --- |
| Run Speed | 170 px/s | Maximum horizontal speed |
| Ground Acceleration | 1400 px/s² | Approach input speed on ground |
| Ground Friction | 1500 px/s² | Ground stopping speed |
| Air Acceleration | 900 px/s² | Air steering and no-input drift reduction |
| Jump Velocity | -390 px/s | Initial upward speed |
| Gravity Multiplier | 1.0 | Project gravity scaling |
| Jump Release Multiplier | 0.5 | Early-release upward speed reduction |
| Jump Horizontal Boost | 30 px/s | Takeoff boost only while holding the momentum direction |
| Jump Charge Frames | 6 | Visible 100 ms takeoff wind-up at 60 physics ticks/s |

Actual Input Map names remain `Move Left`, `Move Right`, `Move Up`, `Move Down`,
`Jump`, and `Attack`, plus `Action` for dashing (currently Shift). Up/Down and Attack
remain reserved. Jump buffering, coyote time, and the charged dash use integer
physics-frame counters. Future mechanics should explicitly own velocity without
adding another `move_and_slide()` call. No combat, stamina, climbing, or animation
state machine is implemented.

## Abyss compatibility and future integration

The abyss is still 24x24 rooms of 16 px tiles; its generation and checkpoint code
are unchanged. A single-tile opening cannot fit either body dimension. Two tiles
(32 px) fit the **30 px width** with only 1 px margin on each side, but a **32 px
ceiling is too low for the 36 px height**. Standing horizontal corridors need at
least three tiles (48 px) of height on the current tile grid. Room edges, turns,
landing surfaces, and climb exits need additional margins and movement-aware
validation. The current approximately 81 px jump rise plus the 36 px body needs
roughly **128 px (eight tiles)** floor-to-ceiling clearance for an unobstructed
full jump. This is a starting estimate, not a traversal guarantee.

Future spawn integration must use feet positions or convert stored body-center
positions before placing this root. The player is not yet inserted into the
procedural abyss.

## Validation and file manifest

The user explicitly authorized movement tests for the jump-anticipation fix.
Movement, dash/grace, and jump-charge suites pass. Unrequested automatic test
runs remain paused.

The automated checks cover exact dimensions/offsets, fixed collider transforms,
independent resources, compatible/incompatible damage areas and overlap signals,
nonblocking areas, movement, variable-height/grounded-only jumping, floor/wall/
ceiling collision, one-way platforms, jump gap, narrow passages/shafts, facing,
respawn, reserved inputs, and 640x360 presentation transforms at 1280x720 (2x)
and 1920x1080 (3x). Headless checks validate settings/transforms and physics, not
a subjective visual-art review. The lab also has a script-error smoke check.

The core files are `player.gd`, `player.tscn`, `player_hurtbox.gd`, the placeholder
sprite, the editable test scene/script, and the automated movement tests. All
collider, hurtbox, terrain-layer, and presentation details above still apply.
Existing movement formulas and tuning are preserved alongside jump grace and
the charged-dash phases. Generation scripts, room templates, village display
settings, and checkpoint logic are unchanged.

The charged-dash task additionally updates `player.gd`, `player.tscn`,
`player_test.gd`, `player_test.tscn`, `Tests/player_movement_test.gd`, and
`project.godot` (Dash input only). It creates `player_dash_visuals.gd`,
`Tests/player_dash_test.gd` (plus Godot UIDs), and `CHARGED_DASH.md`. See that guide
for exact frame semantics, test commands, and the new debug runway.


Dash now also has **Dash Cooldown Frames** (default 12, or 0.2 s at 60 Hz).
Every dash ending, including grounded jump cancellation, starts this independent
lockout. Landing and jump wind-up cannot bypass it. See CHARGED_DASH.md for timing
and the new cooldown regression suite. Movement tests were explicitly requested
and run for this fix; other automatic testing remains subject to the user's
preference.


All manual button/key handling now uses the Input Map, including debug tools.
See [Input Map controls](INPUT_MAP.md) for the mapped action names and defaults.
Existing Action bindings are preserved; no tests were run for this migration.
