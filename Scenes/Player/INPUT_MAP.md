# Input Map controls

Edit bindings under **Project > Project Settings > Input Map**. Runtime code uses
action names, not specific keys/buttons, so rebindings apply to both polling and
event-based controls. The existing `Action` binding is reused for all dash input:
start, charging hold/release, and held-input suppression after respawn. Its current
Shift binding is unchanged. The legacy `Dash` entry is retained as user data but
is no longer used by any script.

| Action | Default | Context |
| --- | --- | --- |
| Move Left / Right / Up / Down | Existing bindings | Player / feature probe |
| Jump | Existing binding | Player jumping |
| Attack | Existing binding | Reserved player attack |
| Action | Existing Shift binding | Player dash |
| Interact | Left mouse | Hovered/picked village hotspot |
| Debug Menu | = | Global developer menu |
| Player Test Ledge / Dash / Drop | F1 / F2 / F3 | Movement lab shortcuts |
| Preview Next Seed | N | Room gallery / feature lab / progression overview |
| Preview Regenerate | R | Feature lab reconstruction |
| Preview Clear State | K | Feature lab mutable-state reset |
| Preview Collect Loot | L | Feature lab placeholder collection |
| Preview Activate Interaction | I | Feature lab interaction state |
| Preview Save State / Load State | F5 / F9 | Feature lab JSON state |
| Preview Damage | Left mouse | Feature lab breakable API |
| Preview Place Probe | Right mouse | Feature lab detection probe |
| Preview Original Boundaries | B | Abyss overlay |
| Preview Final Boundaries | F | Abyss overlay |
| Preview Toggle Terrain | T | Abyss physical/logical view |
| Preview Room Grid | G | Abyss overlay |
| Preview Openings | O | Abyss overlay |
| Preview Routes | R | Abyss route overlays |
| Preview Templates | A | Abyss template-selection overlay |
| Preview Zoom In / Out | Wheel up / down | Abyss preview zoom |
| Preview Pan | Middle mouse hold | Abyss preview pan |
| Cutscene Skip | Mouse buttons / wheel | Toll cutscene, alongside ui_accept/ui_cancel |

Actions sharing default bindings are used in separate scene contexts. Event
handlers use `is_action_pressed()` (without key repeat); held movement uses
`get_axis()` and pan uses `is_action_pressed()`. Physical cursor coordinates and
mouse-motion deltas remain event data. Native Godot Control button/focus handling
and cursor display settings are unchanged. A keyboard/controller Interact binding
activates the currently hovered house hotspot too.

Existing automated tests now inject named actions, and no longer require Dash to
be bound to a particular physical Shift key. Tests were not executed for this
input-only migration.
