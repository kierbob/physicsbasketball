# Physics Basketball

A silly first-person physics basketball game made in Godot 4. You have two
physics-driven arms, a pile of basketballs and one minute to win the
three-point contest.

## Running it

1. Install [Godot 4.4 or newer](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot, click **Import**, and pick this folder's `project.godot`.
3. Press **F5** (or the ▶ button).

The project uses the Jolt physics engine that ships with Godot 4.4+.

## How to play

| Input | Action |
|---|---|
| Mouse | Look around |
| WASD / Space / Shift | Move / jump / sprint |
| Hold **left click** | Reach out and grab whatever you're looking at |
| Hold **right click** | Bring the ball up into shooting form |
| While in form: **pull the mouse back** (down) | Load the shot. The meter by the crosshair shows power |
| Then **flick the mouse forward** (up) | Shoot |
| Q | Drop the ball |
| R | Re-rack all balls and restart the round |
| Esc | Free the mouse |

- **Power** comes from how far you pulled back. Easing the mouse up slowly takes
  power off, and a quick flick fires. A three is roughly 45% on the meter.
- **Direction** is wherever the crosshair is pointing.
- **Arc** comes from how high you're looking: look higher for a loftier shot.
- Everything is physical. The ball follows your hands, your hands bump into
  things, spinning around too fast can fumble the ball, and your running and
  jumping speed carry into the shot.

### Three-point contest

There are five racks around the arc, each with four regular balls (1 point) and
one money ball (red/blue, 2 points). The 60-second clock starts when you grab
your first ball, and each ball only counts on its first shot. The most you can
score is 30. Your best score is saved.

## Project layout

Everything is built from code, so the only scene is an empty root:

| File | What it does |
|---|---|
| `scripts/main.gd` | Builds the court, fence and racks; runs the contest and input map |
| `scripts/player.gd` | First-person controller, physics hands, arm IK and the shooting mechanic |
| `scripts/ball.gd` | Basketball physics settings and make detection |
| `scripts/hoop.gd` | FIBA-sized rim (a ring of capsules), backboard, net drag and support |
| `scripts/hud.gd` | Score, clock, shot popups, crosshair and power meter |
| `scripts/util.gd` | Mesh, material and shader helpers, and collision layers |

Tuning constants for the shot (power range, pull distance, flick sensitivity,
arc, backspin) are at the top of `scripts/player.gd`.
