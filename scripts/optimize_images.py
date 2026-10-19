#!/usr/bin/env python3
"""Halve the project's oversized PNG art and rewrite every
texture-pixel reference so the game draws exactly as before.

The art was drawn on 3508x2480 canvases and is displayed a few
hundred pixels across, so half resolution is still several
times the display size. Every reference to texture pixels
halves with the image, and every sprite drawing a halved
texture doubles its node scale, which leaves all world-space
sizes, positions, and alignment unchanged:

- `region_rect` / AtlasTexture `region` values halve.
- Sprite2D / AnimatedSprite2D node `scale` doubles when its
  texture (or any SpriteFrames frame / atlas) halved; its
  `offset` (in texture pixels) halves.
- Handfuls of texture-pixel constants in code (Part._ART,
  the exterior sign rects, the screw roll geometry) halve.

Run from the repo root:

    python scripts/optimize_images.py [--dry-run]

Only PNGs at least MIN_WIDTH wide are touched. The script
aborts if it meets a region it cannot attribute to a halved
texture, rather than guessing.
"""

import re
import sys
from pathlib import Path

from PIL import Image

MIN_WIDTH = 1500
FACTOR = 0.5

ROOT = Path(__file__).resolve().parent.parent

NUMBER = r"-?\d+(?:\.\d+)?"
RECT2_RE = re.compile(
    r"Rect2\(\s*(%s)\s*,\s*(%s)\s*,\s*(%s)\s*,\s*(%s)\s*\)"
    % (NUMBER, NUMBER, NUMBER, NUMBER)
)
VECTOR2_RE = re.compile(
    r"Vector2\(\s*(%s)\s*,\s*(%s)\s*\)" % (NUMBER, NUMBER)
)
EXT_RESOURCE_RE = re.compile(
    r'\[ext_resource[^\]]*?path="(?P<path>res://[^"]+)"[^\]]*?'
    r'id="(?P<id>[^"]+)"[^\]]*?\]'
    r'|\[ext_resource[^\]]*?id="(?P<id2>[^"]+)"[^\]]*?'
    r'path="(?P<path2>res://[^"]+)"[^\]]*?\]'
)


def fmt(value: float) -> str:
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return ("%.6f" % value).rstrip("0").rstrip(".")


def halve_rect(match: re.Match) -> str:
    values = [float(match.group(i)) * FACTOR for i in range(1, 5)]
    return "Rect2(%s)" % ", ".join(fmt(v) for v in values)


def scaled_vector(match: re.Match, factor: float) -> str:
    values = [float(match.group(i)) * factor for i in range(1, 3)]
    return "Vector2(%s)" % ", ".join(fmt(v) for v in values)


def halved_images() -> dict:
    """res:// path -> (width, height) for each PNG being halved."""
    found = {}
    for png in sorted((ROOT / "assets").rglob("*.png")):
        with Image.open(png) as image:
            if image.width >= MIN_WIDTH:
                rel = png.relative_to(ROOT).as_posix()
                found["res://" + rel] = image.size
    return found


def split_sections(text: str) -> list:
    """Split a .tscn/.tres into (header, body) chunks, keeping
    the exact original text so untouched files stay identical."""
    parts = re.split(r"(?m)^(\[[^\n]*\])$", text)
    # parts: [prefix, header1, body1, header2, body2, ...]
    sections = [(None, parts[0])]
    for index in range(1, len(parts), 2):
        sections.append((parts[index], parts[index + 1]))
    return sections


def join_sections(sections: list) -> str:
    out = []
    for header, body in sections:
        if header is not None:
            out.append(header)
        out.append(body)
    return "".join(out)


class SceneEdit:
    def __init__(self, path: Path, halved: dict, dry_run: bool):
        self.path = path
        self.halved = halved
        self.dry_run = dry_run
        self.changes = []
        self.problems = []

    def ext_map(self, sections) -> dict:
        mapping = {}
        for header, _ in sections:
            if header and header.startswith("[ext_resource"):
                match = EXT_RESOURCE_RE.match(header)
                if match:
                    res_id = match.group("id") or match.group("id2")
                    res_path = match.group("path") or match.group("path2")
                    mapping[res_id] = res_path
        return mapping

    def run(self) -> bool:
        text = self.path.read_text(encoding="utf-8")
        sections = split_sections(text)
        ext = self.ext_map(sections)

        def is_halved(res_id):
            return ext.get(res_id) in self.halved

        # Sub-resources: which AtlasTextures / SpriteFrames draw
        # on halved textures.
        sub_halved = {}
        for header, body in sections:
            if not header or not header.startswith("[sub_resource"):
                continue
            sub_id = re.search(r'id="([^"]+)"', header)
            if not sub_id:
                continue
            atlas_ref = re.search(r'atlas = ExtResource\("([^"]+)"\)', body)
            if atlas_ref:
                sub_halved[sub_id.group(1)] = is_halved(atlas_ref.group(1))
            else:
                refs = re.findall(r'ExtResource\("([^"]+)"\)', body)
                sub_halved[sub_id.group(1)] = any(is_halved(r) for r in refs)

        new_sections = []
        for header, body in sections:
            if header is not None and header.startswith("[sub_resource"):
                atlas_ref = re.search(
                    r'atlas = ExtResource\("([^"]+)"\)', body
                )
                if atlas_ref and is_halved(atlas_ref.group(1)):
                    body, count = RECT2_RE.subn(
                        halve_rect,
                        body,
                        count=0,
                    )
                    # Only the `region =` rect is texture space;
                    # subn above rewrote every Rect2 in the block,
                    # which for an AtlasTexture is just the region.
                    if count:
                        self.changes.append("atlas region x%d" % count)
                new_sections.append((header, body))
                continue
            if header is None or not header.startswith("[node"):
                new_sections.append((header, body))
                continue

            type_match = re.search(r'type="([^"]+)"', header)
            node_type = type_match.group(1) if type_match else None

            texture_ref = re.search(
                r'(?m)^texture = (?:ExtResource|SubResource)\("([^"]+)"\)',
                body,
            )
            frames_ref = re.search(
                r'(?m)^sprite_frames = SubResource\("([^"]+)"\)', body
            )
            texture_halved = False
            if texture_ref:
                ref = texture_ref.group(1)
                texture_halved = is_halved(ref) or sub_halved.get(
                    ref, False
                )
            frames_halved = bool(
                frames_ref and sub_halved.get(frames_ref.group(1), False)
            )

            if re.search(r"(?m)^region_rect = ", body):
                if texture_ref and texture_halved:
                    body = RECT2_RE.sub(halve_rect, body, count=1)
                    self.changes.append("region_rect")
                elif texture_ref:
                    pass  # Small texture, not halved: region stays.
                else:
                    self.problems.append(
                        "%s: region_rect with no texture in its section"
                        % self.path
                    )
            elif re.search(r"(?m)^region_enabled = true", body):
                self.problems.append(
                    "%s: regioned sprite with no region_rect line"
                    % self.path
                )

            wants_scale = node_type in (
                "Sprite2D",
                "AnimatedSprite2D",
            ) and (texture_halved or frames_halved)
            untyped_sprite = (
                node_type is None and texture_ref and texture_halved
            )
            if wants_scale or untyped_sprite:
                scale_match = re.search(r"(?m)^scale = ", body)
                if scale_match:
                    line_match = re.search(
                        r"(?m)^scale = Vector2\([^)]*\)$", body
                    )
                    if line_match:
                        body = (
                            body[: line_match.start()]
                            + "scale = "
                            + scaled_vector(
                                VECTOR2_RE.search(line_match.group(0)), 2.0
                            )
                            + body[line_match.end() :]
                        )
                        self.changes.append("scale x2")
                elif wants_scale:
                    body = "\nscale = Vector2(2, 2)" + body
                    self.changes.append("scale added")
                offset_match = re.search(r"(?m)^offset = ", body)
                if offset_match:
                    line_match = re.search(
                        r"(?m)^offset = Vector2\([^)]*\)$", body
                    )
                    if line_match:
                        body = (
                            body[: line_match.start()]
                            + "offset = "
                            + scaled_vector(
                                VECTOR2_RE.search(line_match.group(0)),
                                FACTOR,
                            )
                            + body[line_match.end() :]
                        )
                        self.changes.append("offset /2")
            new_sections.append((header, body))

        if self.problems:
            return False
        new_text = join_sections(new_sections)
        if new_text != text:
            if not self.dry_run:
                self.path.write_text(new_text, encoding="utf-8")
            return True
        return False


def edit_code(path: Path, halved: dict, dry_run: bool) -> list:
    """Texture-pixel constants in code, halved in place."""
    text = path.read_text(encoding="utf-8")
    original = text
    notes = []
    if path.name == "part.gd":
        # Each _ART row is [path, Rect2, bench size]: halve the
        # rect only when that row's texture is being halved
        # (the crystal's 512px art is not).
        count = 0

        def halve_art_row(match: re.Match) -> str:
            nonlocal count
            if match.group(1) in halved:
                count += 1
                return '"%s",\n\t\t%s,' % (
                    match.group(1),
                    halve_rect(RECT2_RE.search(match.group(2))),
                )
            return match.group(0)

        text = re.sub(
            r'"(res://[^"]+\.png)",\s*\n\s*(Rect2\([^)]*\)),',
            halve_art_row,
            text,
        )
        notes.append("part _ART rects x%d" % count)
    elif path.name == "exterior.gd":
        text, count = RECT2_RE.subn(halve_rect, text)
        notes.append("exterior image rects x%d" % count)
    elif path.name == "screw.gd":
        text = re.sub(
            r"const _HEAD_LOCAL := Vector2\([^)]*\)",
            lambda m: "const _HEAD_LOCAL := "
            + scaled_vector(VECTOR2_RE.search(m.group(0)), FACTOR),
            text,
        )
        text = re.sub(
            r"const _TIP_LOCAL := Vector2\([^)]*\)",
            lambda m: "const _TIP_LOCAL := "
            + scaled_vector(VECTOR2_RE.search(m.group(0)), FACTOR),
            text,
        )
        text = re.sub(
            r"const _HEAD_RADIUS_LOCAL := [\d.]+",
            lambda m: "const _HEAD_RADIUS_LOCAL := "
            + fmt(float(m.group(0).split(":=")[1]) * FACTOR),
            text,
        )
        text = re.sub(
            r"const _SHAFT_RADIUS_LOCAL := [\d.]+",
            lambda m: "const _SHAFT_RADIUS_LOCAL := "
            + fmt(float(m.group(0).split(":=")[1]) * FACTOR),
            text,
        )
        notes.append("screw roll geometry")
    if text != original and not dry_run:
        path.write_text(text, encoding="utf-8")
    return notes if text != original else []


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    halved = halved_images()
    print("halving %d images (>= %d px wide)" % (len(halved), MIN_WIDTH))

    scene_files = sorted((ROOT / "src").rglob("*.tscn")) + sorted(
        (ROOT / "src").rglob("*.tres")
    ) + [ROOT / "settings.tres"]
    problems = []
    for scene in scene_files:
        edit = SceneEdit(scene, halved, dry_run)
        if edit.run() and edit.changes:
            print(
                "  %s: %s"
                % (scene.relative_to(ROOT), ", ".join(edit.changes))
            )
        problems.extend(edit.problems)

    for code in [
        ROOT / "src/parts/part.gd",
        ROOT / "src/ui/exterior/exterior.gd",
        ROOT / "src/interaction_points/screw.gd",
    ]:
        notes = edit_code(code, halved, dry_run)
        if notes:
            print("  %s: %s" % (code.relative_to(ROOT), ", ".join(notes)))

    if problems:
        print("PROBLEMS:")
        for problem in problems:
            print("  " + problem)
        return 1

    if not dry_run:
        for res_path, (width, height) in halved.items():
            png = ROOT / res_path[len("res://") :]
            with Image.open(png) as image:
                image.resize(
                    (round(width * FACTOR), round(height * FACTOR)),
                    Image.LANCZOS,
                ).save(png, optimize=True)
        print("images resized")
    return 0


if __name__ == "__main__":
    sys.exit(main())
