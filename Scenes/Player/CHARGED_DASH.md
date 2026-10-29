# Jump grace and charged dash

Run **Scenes/Player/player_test.tscn** with F6. Move with the existing A/D or arrow
bindings, Jump with Space, and Dash with the **Action** Input Map action (currently Shift). Dashing uses the existing `Action` mapping; its configured binding is preserved. It reacts to a press,
not a repeated hold trigger. **Hold Shift to build charge; release to launch.**
Full charge launches automatically. Change its binding under Project Settings > Input Map > Action.

Your current normal movement tuning is retained: run speed 170 px/s, acceleration
1400, ground friction 1500, air acceleration 900, jump velocity -390, gravity
multiplier 1, and jump-release multiplier 0.5. The feet-centered body stays
30x36 at (0,-18); the hurtbox stays 24x32 at the same center. Collision masks,
climb detector, and inactive/unassigned melee hitbox are unchanged. Dash has no
separate collision shape, damage, stamina, attack, climbing, or invulnerability.

## One small state machine

`player.gd` owns all movement and frame counters:

```
NORMAL -> DASH_CHARGING -> DASHING -> RECOVERY -> NORMAL
```

The physics loop captures jump input, tries a new dash, calculates velocity for
**one** state, calls `move_and_slide()` **once**, resolves floor transitions and
landing buffers, then advances counters. New phases move on the next physics
tick. No normal steering/gravity function runs during a charge or dash.

- **NORMAL:** existing horizontal acceleration/friction, gravity, facing, and
  variable-height jump behavior, with coyote/buffer support.
- **DASH_CHARGING:** direction starts at current facing. Holding left/right
  changes the pending dash direction and visual facing while charging; releasing
  direction keeps the last choice. Charge strength and timing are preserved.
  Velocity becomes (0,0) every tick. There is no gravity, steering, jumping, or
  jump buffering. An airborne charge stays at its current position, subject to
  collision resolution (for example a moving platform pushing the body).
- **DASHING:** velocity is (locked direction * chosen dash speed, 0). Gravity,
  steering, and airborne jump buffering remain suspended. A fresh Jump press
  while physically touching a floor cancels the dash and jumps immediately. CharacterBody2D swept movement
  handles collision; a wall ends the dash early. Direction is locked at launch and does not follow new input while dashing.
- **RECOVERY:** the full horizontal dash momentum carries into recovery, then
  decelerates toward zero using the configurable recovery braking. There is no
  snap back to normal run speed. Gravity resumes from zero vertical velocity, without
  replaying pre-charge jump/fall momentum. Steering and Dash remain locked;
  grounded/buffered jumps may execute. Normal control returns at the end.

Dash takes priority over Jump if both are pressed in the same tick. Starting a
dash cancels coyote time, stored jump input, and jump-release eligibility. Jump
presses during charging or an airborne dash are discarded; holding one through
the end does not create a deferred jump. A fresh grounded press during DASHING
instead cancels into a jump. New jump input during recovery is treated normally.

`player_dash_visuals.gd` lives on Visuals and listens to `movement_state_changed`.
It tints charging yellow and dashing cyan, then restores the original modulation
at recovery/normal. Charging also shakes Visuals by about 1 pixel; both position
and modulation reset immediately at launch, recovery, or respawn. Select Visuals
to tune `charge_shake_pixels` (0 disables it) and `charge_shake_frequency` (24 Hz
by default). Offsets are rounded to pixel steps. It never modifies body/hurtbox
transforms. Replace this small
feedback script later without changing movement logic.

## Frame counters and Inspector tuning

| Inspector setting | Default | Meaning |
| --- | --- | --- |
| Coyote Frames | 6 | Airborne jump opportunities after walking off a ledge |
| Jump Buffer Frames | 6 | Inclusive pending-input window |
| Dash Charge Frames | 12 | Maximum held charge ticks before automatic launch |
| Dash Duration Frames | 9 | Fully charged horizontal movement ticks |
| Dash Min Duration Frames | 4 | Minimum horizontal movement ticks |
| Dash Recovery Frames | 8 | Braking/gravity ticks with Dash locked |
| Dash Speed | 650 px/s | Fully charged burst speed |
| Dash Min Speed | 350 px/s | Minimum burst speed |
| Dash Recovery Deceleration | 1800 px/s² | Horizontal braking during recovery |

All grace/phase timers are integer **physics frames**, independent of rendering
FPS. At 60 physics ticks per second, 6 frames is 0.1 seconds, 12 is 0.2 seconds,
9 is 0.15 seconds, and 8 is about 0.133 seconds. Debug seconds use
`Engine.physics_ticks_per_second`; no 60 Hz assumption is baked into movement.
Changing the physics tick rate intentionally changes the real-time duration of
frame-based windows. At 60 Hz, a collision-free default dash travels 97.5 px
(650 * 9 / 60), excluding the brief recovery drift.

Exact counting rules:

- Walking off with no vertical launch seeds N coyote opportunities **after** the
  ledge-departure tick. The next N physics ticks may jump. The counter is consumed
  immediately on jumping. Passing upward through a one-way platform does **not**
  grant coyote time or restore the aerial dash. Zero disables ledge grace.
- A buffered input's press tick is tick 1. For a buffer of 3, landing during that
  tick or either of the next 2 ticks consumes it. Landing at the end of the last
  valid tick still sets jump velocity; upward movement begins on the next tick,
  without a second collision update. Zero buffers only immediate legal jumps.
- Releasing Jump before takeoff is remembered, including buffered taps, and
  launches the shorter jump once the fixed takeoff delay finishes. Releasing
  during ascent reduces upward velocity once. Holding allows full jump height.
  Jump Charge Frames is a delay only; it never scales jump strength.
- Each physics tick with Shift held adds one charge frame. Releasing launches
  with the accumulated charge; the release tick does not add charge. The maximum
  is `dash_charge_frames` (12 by default), after which launch is automatic.
- Speed interpolates from `dash_min_speed` (350) to `dash_speed` (650). Duration
  interpolates from `dash_min_duration_frames` (4) to `dash_duration_frames` (9),
  rounded to whole physics frames. Both increase with charge. The chosen values
  are locked at launch and shown by the controller's `active_dash_speed` and
  `active_dash_duration_frames`. The controller exposes charge percentage as `dash_charge_ratio`.
- With defaults, holding 6 frames gives 50% charge: 500 px/s and 7 dash frames.
  Holding all 12 gives 650 px/s and 9 frames. A quick tap gives a short, slower
  dash. Minimums are clamped to their maximums if Inspector settings conflict.
- The release/maximum-charge tick still performs frozen charging movement;
  dash displacement starts next physics tick. Recovery timing is unchanged.
- Zero charge disables charging and immediately launches at full strength.
  Zero recovery returns directly to NORMAL. Dash duration is at least 1 tick.

## Availability, landing, and reset

`dash_available` is independent of the phase counter. Starting Dash consumes it.
A real floor collision landing restores it; coyote time and jump buffering do
not. Recovery still blocks reactivation even if landing has restored the budget.
Completing recovery while physically supported by a floor also rearms the next
airtime. Grounded Dash presses may start again after recovery. Airborne presses
cannot repeat until another landing. Holding Dash never auto-restarts a phase.

`reset_movement()` clears velocity, all temporary counters, jump-release state,
floor history, and the active phase, restores dash availability, and restores
normal visual feedback. It preserves facing. Held Jump/Dash input must be released
before being accepted again. Test respawn and F-key debug repositioning call it;
future spawn/teleport code should do the same after setting the feet position.

`cancel_jump_grace()` is also available for future external launches: call it
before assigning knockback/launch velocity so that no old ground/buffer allowance
survives. Ordinary nonzero vertical launches do not seed new coyote time.

## Debug lab

The existing movement/collision obstacles remain. The lab adds a separate runway
on the right with a one-way perch, a 64 px gap, and a tall solid dash wall.
The far landing is one tile lower so a horizontal grounded dash clears its lip.
Horizontal movement now has `edge_correction_pixels` (default 2) of vertical
corner assistance. It can lift the player over a ledge or lower them under an
underside when the complete body and travel path fit. Larger corners still block;
use the lowered runway to inspect dash distance independently.

Optional lab-only keys:

- **F1:** reset near the original ledge for late/coyote jumps.
- **F2:** reset onto the dash runway.
- **F3:** reset above a floor to practice buffering just before landing.

All instructional labels, obstacle labels, and the debug HUD have been removed
from the test scene. `enable_debug_shortcuts` on PlayerTest controls the F-key
shortcuts independently. The reusable player has no debug text, window settings,
or F-key logic. Camera zoom remains editable; presentation settings are unchanged.

## Checks and extension points

**Do not run automated tests unless the user explicitly asks to resume them.**
Tests were not executed for the hold-to-charge update. Existing suite expectations
were adjusted to remove the deleted one-way jump bonus and hold Dash for full
charge. Movement testing was later explicitly authorized for the jump-anticipation
fix; see the verification results below.

Keep ordinary horizontal/jump behavior in its existing helpers. Modify
`try_start_dash`, `update_dash_charge`, `update_dashing`, `finish_dash`, and
`update_dash_recovery` for dash tuning. `update_floor_transitions` owns real landing
and ledge departure, so future abilities should not independently reset budgets.
`set_movement_state` publishes feedback; `advance_dash_phase` owns phase timing.

Playtest charge length, burst distance, recovery braking, buffered-tap full jump
height, and the decision to allow grounded jumps during recovery. There is no
terminal-velocity cap, moving-platform test coverage, traversal validation,
production death/respawn, or final animation system. No abyss-generation code,
room templates, or checkpoint logic changed.

## Files changed by this task

Modified: `Scenes/Player/player.gd`, `player.tscn`, `player_test.gd`,
`player_test.tscn`, `README.md`, `Tests/player_movement_test.gd`, and
`project.godot` (only the new Dash action, on top of existing local edits).

Created: `Scenes/Player/player_dash_visuals.gd`, this guide,
`Tests/player_dash_test.gd`, and their generated script UID sidecars.


Current follow-up removes `player_one_way_jump.gd` and its UID, along with all
upward one-way grace queries. It updates `player.gd`, the lab HUD/instructions,
existing dash-suite expectations, and this guide for variable charge strength.
Dash momentum is retained on finish; recovery braking and the small visual-only
charge shake remain. No tests or Godot test runs were performed for this update.


## Ledge corner assistance

On Player, **Collision Assistance > Edge Correction Pixels** defaults to **2**.
When a mostly vertical wall blocks horizontal movement, the controller tries the
smallest upward/downward whole-pixel offset that clears it, up to this limit.
Upward wins equal-distance ties. Zero disables the feature. It applies to normal
movement, recovery momentum, and dashing, but never to frozen dash charging.

The vertical adjustment is swept for collision, its destination is checked with
the real body shape, and the horizontal/combined travel is checked before moving.
A blocked ceiling, floor, or full-height wall prevents the adjustment. This does
not resize the body/hurtbox, change jump velocity, restore the dash in midair, or
modify terrain. Actual collision/floor handling still uses one move_and_slide()
per tick after the small positional correction. No tests were run, per request.


## Grounded dash jump-cancel

Press Jump while DASHING and physically touching a floor (including a one-way
platform) to cancel the dash into a normal jump. A press on a landing tick also
works. The jump keeps horizontal dash momentum, clears the dash phase timer,
restores normal control without recovery, and begins a new airtime with Dash
available. Airborne/coyote-only presses cannot cancel, and charging still blocks
jumping. Jump is consumed once and keeps the normal release-height behavior.

Normal movement now uses the chief walk animation. Run begins at 125% of the
normal movement speed, so it reflects fast dashes and momentum after a dash,
including in the air. Weak dashes can still use walk. Tune Run Threshold Ratio on
Visuals/AnimatedSprite2D. No tests were run for this change.


## Variable jump height and takeoff delay

Jump Release Multiplier is now **0.5**: a short tap produces a lower jump, while
holding Jump allows the full jump. Jump Velocity remains unchanged. A new
**Jump Charge Frames** setting defaults to **6** physics ticks (100 ms at 60 Hz).
This is a fixed takeoff delay, not a power charge: waiting never increases jump
speed, and holding longer than the delay does not add jump strength. Set it to 0
for immediate takeoff.

Movement, steering, gravity, and friction pause during the delay. Incoming
horizontal speed is saved before any braking and restored exactly at takeoff;
normal movement resumes on the following tick. A valid
floor/coyote/buffer jump reserves its allowance immediately and launches once
when the delay ends, even if the original grace window then expires. Repeated
presses do not restart or stack it. Releasing before takeoff is remembered and
produces the short jump; releasing during ascent still cuts the jump normally.
A released buffered tap now also produces the short jump rather than full height.
Starting a dash, resetting the player, or canceling jump grace clears any pending
jump. Grounded dash-jump cancellation remains immediate, but its takeoff uses the
same short delay. Collider sizes and walking/running animation rules are unchanged.
No tests or Godot runs were performed, per request.


## Jump anticipation verification

The previous physical delay was active for only 3 ticks (50 ms) without a visible
charge pose. The default is now 6 ticks (100 ms). During that interval the chief
holds a crouched pose from run frame 4 and uses a warm tint; signal-driven feedback
appears immediately when the jump is reserved and clears at takeoff/cancellation.
Select AnimatedSprite2D > Jump Charge Pose Frame to adjust the placeholder pose.
Only artwork changes: collider/hurtbox size and horizontal movement stay intact.

`Tests/player_jump_charge_test.gd` checks exact delay counts for 0/1/3/6 ticks,
visible feedback, equal full-jump height across delays, early-release taps,
single reservation, frozen momentum during the wait, dash-jump cancellation, ability
interruptions, and respawn cleanup. Existing movement/dash assertions now account
for delayed launch rather than requiring upward velocity on the input tick.
The user explicitly authorized movement testing for this fix; no generation tests
are needed or run for it.


Latest verification: the movement suite passes (75.0 px held jump, 19.6 px short
jump), all 279 dash/grace assertions pass, and all 55 anticipation assertions pass
at both 60 and 120 rendering FPS with 60 physics ticks/s. The test scene smoke
run has no script errors. No tests run region/route generation for this fix.


Jump-charge momentum follow-up: the body now freezes during anticipation, including
coyote jumps in midair. It saves the horizontal speed before normal/recovery
braking and restores that exact speed on the takeoff tick; vertical speed becomes
the usual jump impulse. Steering, friction, gravity, corner assistance, and
recovery timing do not run during the freeze. Normal movement/braking resumes
from the next tick. Dash interruption or respawn discards the saved momentum.
Only physical collision resolution (such as a moving platform) may adjust the
frozen body's position. Test expectations were updated but not executed for this
follow-up, per the user's testing preference.


## Jump momentum boost

`Jump Horizontal Boost` defaults to **30 px/s**, added once at takeoff only when
left/right input matches the saved horizontal momentum. Eligibility is checked
at takeoff, so releasing or reversing input during jump charge removes the boost.
Stationary jumps and no-input jumps receive no boost. Existing momentum is still
preserved; input cannot reverse it during jump charge. Set the boost to 0 to
disable it. Charge duration and vertical jump strength are unchanged. No tests
were run for this change.


## Airborne animation

Jumping/falling continuously plays the chief run animation rather than holding
the takeoff frame. Below the high-speed threshold it plays at **half speed**
(12 FPS); high-speed movement and grounded animations use the normal 24 FPS.
Tune `airborne_run_speed_scale` on Visuals/AnimatedSprite2D (default 0.5).
Dash charge and jump anticipation still hold their respective charge poses.

Jump-charge direction redirection has been removed. The player's saved momentum
stays unchanged throughout the freeze, regardless of directional input. The
existing one-time boost keeps the direction captured when the jump was committed.
No tests were run for these changes.


## Wall momentum grace

Collision Assistance now exposes **Wall Momentum Frames** (12 by default, 0.2 s
at 60 physics ticks/s) and **Wall Momentum Retention** (0.75). On a fresh wall
impact, the controller remembers the horizontal speed before collision stopped
it. If the forward body path becomes clear within that window, it restores 75%
of that speed once. For example, a 500 px/s dash can recover 375 px/s after the
player jumps above the ledge. Normal braking/control then applies afterward.

The wall still blocks physical movement; this does not teleport through walls,
restart a stopped dash, or restore dash availability. A continuous wall contact
does not refresh the window, including during frozen jump anticipation. The
window counts physics ticks even during charge. Opposite-direction input,
turning away, expiry, a new dash, or respawn discards the saved speed. Restoration
waits through jump/dash charging and is checked after corner correction. It never
reduces a speed that is already higher. No tests were run for this change.


Dash-charge redirection: left/right input can now change direction at any point
in DASH_CHARGING, including the release tick. The body stays frozen, and charge
speed/duration progress is not reset. Once DASHING starts, direction stays locked.
Jump-charge momentum redirection remains disabled. No tests were run.


## Jump-charge buffering reverted

Midair charge banking has been removed. Ordinary jump input buffering still
expires after Jump Buffer Frames, even while holding the button. Once the jump
becomes eligible, its full Jump Charge Frames wind-up begins and freezes movement
while preserving horizontal momentum. Coyote jumps follow that same behavior.
Waiting in midair no longer reduces the charge duration. No tests were run.


## Dash end cooldown

**Dash Cooldown Frames** defaults to **12 physics ticks** (0.2 seconds at 60 Hz).
It begins whenever a dash ends normally, hits a wall, or is canceled by a grounded
jump. It is independent of the recovery phase and the aerial-dash budget.

The ending tick starts the full counter; the following N ticks all reject a new
Dash press. Countdown continues during jump anticipation, so jump-canceling cannot
skip it or repeatedly interrupt the wind-up to dash along the floor. Landing
restores aerial availability but never clears the cooldown. Recovery can still
block a dash after the cooldown if that phase has not ended. A rejected Dash press
is not queued: release and press again after the lockout. Respawn resets cooldown;
setting it to 0 explicitly disables this protection.

The user authorized movement tests for this fix. All four movement-related suites
pass, including the new `Tests/player_dash_cooldown_test.gd` (40 assertions),
279 dash/grace assertions, 61 jump-anticipation assertions, and the existing
movement/collision suite. The latter suites now respect current scene tuning,
charge redirection, and the complete landing time rather than old constants.
The new tests reproduce the dash-jump-dash exploit and cover repeated attempts,
exact expiry, wall endings, zero recovery, landing, air budget, held input, and
reset. Current movement/dash/jump settings and abyss generation are unchanged.


## Input Map migration

Dashing now reads **Action** for press, hold, release, and respawn suppression.
Player movement/Jump keep their existing mapped identifiers. The old Dash mapping
is no longer referenced by scripts; the user's existing Input Map entries were
not deleted or rebound.

All manually detected keyboard/button controls in project scripts now use named
Input Map actions, including debug shortcuts, room previews, mouse zoom/pan,
cutscene skipping, and house interactions. Their prior default controls are
preserved. Cursor positions, mouse motion deltas, and hover notifications still
use Godot events because they are positional data rather than button bindings.
See [Input Map controls](INPUT_MAP.md). No tests were run for this migration.
