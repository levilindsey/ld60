# LD60

Our Ludum Dare 60 jam game, built with Godot 4.7 (2D, single-player,
web + Windows builds). Right now this repo holds pre-jam starter
scaffolding; the actual game arrives once the theme is announced.

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

## Project layout

- `src/core/` - App spine: `G` autoload, main scene, game state
  machine, audio manager, settings.
- `src/scaffolder/` - Reusable utilities (timers/tweens, geometry,
  drawing, logging).
- `src/level/` - `Level` base class + the default level scene.
- `src/ui/` - HUD overlays (title/pause/credits) + debug console.
- `assets/` - Fonts, images, audio.
- `scripts/` - Web export + local web-serve tooling.

## Web build

```powershell
powershell -ExecutionPolicy Bypass -File scripts/export_web.ps1
python scripts/serve_web.py    # then open http://localhost:8060
```

The zip it produces (`build/ld60-web.zip`) is what gets uploaded to
itch.io.

## Links

- Ludum Dare: <https://ldjam.com/> (our game page will be linked here
  once the jam starts)
