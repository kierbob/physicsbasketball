# Stupid Physics Archery

A janky first-person physics archery game made in Godot 4. You have two floppy
arms, a heavy war bow and unlimited arrows.

## Running it

1. Install [Godot 4.4 or newer](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot, click **Import**, and pick this folder's `project.godot`.
3. Press **F5** (or the ▶ button).

The project uses the Jolt physics engine that ships with Godot 4.4+.

## How to play

| Input | Action |
|---|---|
| Mouse | Look around (smoothed, full speed even while drawing) |
| WASD / Space / Shift | Move / jump / sprint |
| **Click** while looking at the bow | Your hand reaches out and grabs it |
| Q | Drop the bow |
| Hold **left click** | Grab the string and haul it back |
| Let go of left click | Shoot |
| Hold **right click** | Zoom in |
| R | Reset the range |
| Esc | Free the mouse |

- **The bow starts on the table** in front of you.
- **It's a war bow.** Arrows leave at 25–85 m/s depending on how far you drew.
  At full draw they land on the crosshair. The pink dot always shows where the
  arrow would land right now, so you can watch it rise to the crosshair as you draw.
- **The bow is heavy.** It swings after your aim with a little lag. Hold full
  draw for more than a couple of seconds and your arm starts shaking.
- **Drop the bow while drawn** and the arrow goes off wherever it's pointing.
- Arrows have a glowing trail so you can follow them downrange. They stick into
  things they hit hard and head-on; glancing hits bounce off and tumble. Hits
  shove crates and melons around far harder than real arrows would.

### Scoring (free mode)

Arrows are unlimited and the score just keeps counting. The HUD also tracks
shots and your best single shot.

- **Targets:** 10 for the bullseye down to 1 for the outer ring, multiplied by
  distance: 10 m ×1, 20 m ×2, 30 m ×3, 45 m ×4.
- **Balloons:** +15. Arrows go straight through, so you can pop two at once.
- **Melons on posts:** +10.
- **The crate pyramid** is just for fun.

## Project layout

Everything is built from code, so the only scene is an empty root:

| File | What it does |
|---|---|
| `scripts/main.gd` | Builds the range, targets and props; free-mode scoring and input map |
| `scripts/player.gd` | First-person controller, smoothed camera, floppy hands, arm IK, bow handling, aim and fatigue |
| `scripts/bow.gd` | The bow: rigid body when dropped, bending limbs, string and nocked arrow visuals |
| `scripts/arrow.gd` | Raycast-swept arrow flight with gravity, drag and a glowing trail; sticking, glancing and tumbling |
| `scripts/target.gd` | Target boss with a 10-ring face and ring scoring |
| `scripts/balloon.gd` | Drifting balloons that pop |
| `scripts/hud.gd` | Score, popups, help text, crosshair and landing dot |
| `scripts/util.gd` | Mesh, material and shader helpers, and collision layers |

Tuning constants for camera smoothing and offset, draw speed, arrow speed and
fatigue are at the top of `scripts/player.gd`. Arrow sticking and the extra shove on props are
at the top of `scripts/arrow.gd`.
