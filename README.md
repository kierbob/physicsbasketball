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
| Hold **left click** | Reach out and grab whatever you're looking at. Keep holding to carry the ball |
| **Whip the mouse and let go** of left click | Hurl the ball |
| Q | Drop the ball |
| R | Re-rack all balls and restart the round |
| Esc | Free the mouse |

- **Throws come from your arms.** The ball rides between two floppy, springy
  hands, so whipping the mouse whips the ball. Let go during or just after the
  whip and it flies with that speed. Flick up for a jump-shot arc, sideways for
  a hook, or down for a bounce pass.
- **Hidden assist:** throws that were already heading close to the hoop get
  nudged toward it. Wild throws stay wild.
- Everything is physical. Your hands bump into things, your running and jumping
  speed carries into the throw, and rim rattles are real.

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
| `scripts/player.gd` | First-person controller, floppy physics hands, arm IK, throwing and the assist |
| `scripts/ball.gd` | Basketball physics settings and make detection |
| `scripts/hoop.gd` | FIBA-sized rim (a ring of capsules), backboard, net drag and support |
| `scripts/hud.gd` | Score, clock, shot popups and crosshair |
| `scripts/util.gd` | Mesh, material and shader helpers, and collision layers |

Tuning constants for the arms and the throw (spring stiffness, throw boost,
assist radius and strength) are at the top of `scripts/player.gd`.
