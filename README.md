# LD60

Our Ludum Dare 60 jam game, built with Godot 4.7 (2D, single-player,
web + Windows builds). The theme is "old tech": broken gadgets arrive
at a repair shop, each tool is a small microgame, and each repair earns
1 to 3 stars. The design is in `docs/design/` (start at `overview.md`).

## Getting set up (first time)

1. Install **Godot 4.7.2** (the **Standard** build, not the .NET
   one): <https://godotengine.org/download/archive/4.7.2-stable/>
2. Install **GitHub Desktop** and sign in:
   <https://desktop.github.com/>
3. In GitHub Desktop: `File > Clone repository`, pick
   `levilindsey/ld60`, and choose where to put it.
4. Open Godot, click **Import**, and select the `project.godot` file
   inside the cloned folder.
5. Press **F5** (or the Play button in the top-right) to run the
   game. You should see a parallax background, a brown floor, and a
   cyan spawn marker. That means everything works!

## Working together during the jam

- **Pull before you start** (`Fetch origin` then `Pull` in GitHub
  Desktop) so you have everyone's latest changes.
- **Commit and push small changes often.** Little commits are easy
  to untangle; giant ones are not.
- **Say in Discord which scene or file you're working on.** Two
  people editing the same `.tscn` file at once causes painful merge
  conflicts. One person per file at a time.

## Check your change

Before you commit and push, run the check script. It opens the project
without a window, runs it for a few seconds, and fails if Godot logged
any script errors. Open PowerShell (or Command Prompt) in the project
folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check.ps1
```

It takes about 15 seconds (longer the first time, while Godot imports
the art) and ends with `check: OK` when all is well. Otherwise it lists
the error lines, each followed by the file and line it points at. If the
first error says `Could not parse global class`, open the file it names:
that script has a mistake in it.

For a gameplay change, add `-Tests` to the command to also play the game
with the probes in `tests/` (about 90 seconds more).

If it says it can't find Godot, tell it where your Godot `.exe` is, once,
and then open a new PowerShell window:

```powershell
setx GODOT "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
```

To try a different Godot for a single run, add `-Godot "C:\path\to\Godot.exe"`
to the command above instead.

## Project layout

- `src/core/` - App spine: `G` autoload, main scene, game state
  machine, audio manager, settings.
- `src/scaffolder/` - Reusable utilities (timers/tweens, geometry,
  drawing, logging).
- `src/level/` - `Level` base class + the default level scene.
- `src/ui/` - HUD overlays (title/pause/credits) + debug console.
- `assets/` - Fonts, images, audio.
- `scripts/` - `check.ps1` (check your change), web export + local
  web-serve tooling.
- `tests/` - Probes that play the game without a window
  (`check.ps1 -Tests`), and the sweep that loads every script in `src/`.

## Web build

```powershell
powershell -ExecutionPolicy Bypass -File scripts/export_web.ps1
python scripts/serve_web.py    # then open http://localhost:8060
```

To publish to itch.io (our page is `levilindsey/repair-shop`), push the
build with Butler:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/deploy_itch.ps1
```

First time on a new machine: install
[Butler](https://itchio.itch.io/butler), then run `butler login` once.
One-time setup on the itch page itself (Butler can't set these): in
**Edit game**, set **Kind of project** to **HTML**, and on the `html5`
upload tick **This file will be played in the browser** with a
1280×720 viewport. Without those two, the page shows a download button
instead of a playable game.
The zip from `export_web.ps1` (`build/ld60-web.zip`) still works for a
manual upload in the itch dashboard.

## Links

- Ludum Dare: <https://ldjam.com/> (our game page will be linked here
  once the jam starts)
