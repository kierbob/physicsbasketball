# Stupid Physics Archery

A janky first-person physics archery game made in Godot 4, in the spirit of
Half Sword: while you're holding something, the mouse moves your hands, not the
camera. You have two floppy arms, a bow you have to physically hold onto and
ten arrows.

## Running it

1. Install [Godot 4.4 or newer](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot, click **Import**, and pick this folder's `project.godot`.
3. Press **F5** (or the ▶ button).

The project uses the Jolt physics engine that ships with Godot 4.4+.

## How to play

| Input | Action |
|---|---|
| Mouse | Look around (when your hands are empty) |
| WASD / Space / Shift | Move / jump / sprint |
| Hold **right click** | Grab the bow. **Keep holding**: let go and you drop it |
| Mouse while holding the bow | Move your bow arm. Push past the edge of your reach to turn |
| Hold **left click** | Grab the string and haul it back to your cheek |
| Let go of left click | Shoot |
| Left click with no bow | Flail your hand around and slap things |
| R | Restart the range |
| Esc | Free the mouse |

- **The bow starts on the table** in front of you. Look at it and hold right
  click to pick it up.
- **Aiming is physical.** The arrow flies along the line from your string hand
  through your bow hand. The red dot shows where the bow is pointing, but
  arrows drop over distance, so aim high on far targets.
- **Your arm gets tired.** Hold full draw for more than a second and a half
  and your bow arm starts shaking, sagging and letting the string creep forward.
- **Drop the bow while drawn** and the arrow goes off wherever it's pointing.
- Arrows stick into things they hit hard and head-on. Glancing hits bounce off
  and tumble. Hits shove crates and melons around, far harder than real arrows
  would.

### Scoring

You get ten arrows per round.

- **Targets:** 10 for the bullseye down to 1 for the outer ring, multiplied by
  distance: 10 m ×1, 20 m ×2, 30 m ×3, 45 m ×4.
- **Balloons:** +15. Arrows go straight through, so you can pop two at once.
- **Melons on posts:** +10.
- **The crate pyramid** is just for fun.

Your best score is saved.

## Project layout

Everything is built from code, so the only scene is an empty root:

| File | What it does |
|---|---|
| `scripts/main.gd` | Builds the range, targets and props; scoring and input map |
| `scripts/player.gd` | First-person controller, mouse-driven floppy hands, arm IK, bow handling and fatigue |
| `scripts/bow.gd` | The bow: rigid body when dropped, bending limbs, string and nocked arrow visuals |
| `scripts/arrow.gd` | Raycast-swept arrow flight with gravity and drag, sticking, glancing and tumbling |
| `scripts/target.gd` | Target boss with a 10-ring face and ring scoring |
| `scripts/balloon.gd` | Drifting balloons that pop |
| `scripts/hud.gd` | Score, popups, help text, crosshair and bow sight dot |
| `scripts/util.gd` | Mesh, material and shader helpers, and collision layers |

Tuning constants for hand movement, draw speed, arrow speed and fatigue are at
the top of `scripts/player.gd`. Arrow sticking and the extra shove on props are
at the top of `scripts/arrow.gd`.
