"""Clean up raw foley phone recordings into game-ready WAV files.

Balanced, light-touch recipe agreed with Levi: high-pass the rumble,
gently reduce steady room noise, trim leading and trailing silence,
split a recording only where takes are separated by clear silence,
apply short de-click fades, and peak-normalize with a gain cap so
very quiet recordings keep some of their natural quietness.

Usage:
    python scripts/clean_foley.py [source_dir] [output_dir]
    python scripts/clean_foley.py --analyze [source_dir]

Defaults: source C:/Users/lsl/Downloads/foley, output foley_cleaned/
next to this repo root. Originals are never modified. A manifest.csv
in the output folder records levels and gain for every output file.
"""

import subprocess
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

FFMPEG = r"C:\Users\lsl\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe"
SAMPLE_RATE = 48000
BLOCK_SEC = 0.005
PRE_ROLL_SEC = 0.03
TAIL_SEC = 0.15
MERGE_GAP_SEC = 0.12
SPLIT_GAP_SEC = 0.6
FADE_IN_SEC = 0.005
FADE_OUT_SEC = 0.04
TARGET_PEAK_DB = -1.0
MAX_GAIN_DB = 24.0
# Gentle steady-noise reduction plus rumble removal. Nothing else.
FILTER_CHAIN = "highpass=f=80,afftdn=nr=8:tn=1"


def decode(path: Path, use_filters: bool) -> np.ndarray:
    command = [FFMPEG, "-v", "quiet", "-i", str(path)]
    if use_filters:
        command += ["-af", FILTER_CHAIN]
    command += ["-f", "f32le", "-ac", "1", "-ar", str(SAMPLE_RATE), "pipe:1"]
    result = subprocess.run(command, capture_output=True, check=True)
    return np.frombuffer(result.stdout, dtype=np.float32).copy()


def block_levels_db(audio: np.ndarray) -> np.ndarray:
    block = int(SAMPLE_RATE * BLOCK_SEC)
    count = len(audio) // block
    if count == 0:
        return np.array([-100.0])
    frames = audio[: count * block].reshape(count, block)
    rms = np.sqrt(np.mean(frames.astype(np.float64) ** 2, axis=1))
    return 20.0 * np.log10(rms + 1e-10)


def find_segments(audio: np.ndarray) -> list[tuple[int, int, float]]:
    """Return (start, end, threshold_db) sample spans of kept sound."""
    levels = block_levels_db(audio)
    block = int(SAMPLE_RATE * BLOCK_SEC)
    peak_block_db = float(np.max(levels))
    noise_db = float(np.percentile(levels, 10))
    threshold_db = min(
        max(noise_db + 14.0, peak_block_db - 42.0, -62.0),
        peak_block_db - 10.0,
    )
    above = levels > threshold_db
    if not np.any(above):
        return [(0, len(audio), threshold_db)]

    # Fill short dips so rattles and shakes stay one region.
    merge_blocks = int(MERGE_GAP_SEC / BLOCK_SEC)
    filled = above.copy()
    index = 0
    while index < len(filled):
        if not filled[index]:
            end = index
            while end < len(filled) and not filled[end]:
                end += 1
            if 0 < index and end < len(filled) and end - index <= merge_blocks:
                filled[index:end] = True
            index = end
        else:
            index += 1

    regions: list[tuple[int, int]] = []
    index = 0
    while index < len(filled):
        if filled[index]:
            end = index
            while end < len(filled) and filled[end]:
                end += 1
            regions.append((index, end))
            index = end
        else:
            index += 1

    # Split only where regions are separated by clear silence.
    split_blocks = int(SPLIT_GAP_SEC / BLOCK_SEC)
    groups: list[tuple[int, int]] = [regions[0]]
    for start_block, end_block in regions[1:]:
        prev_start, prev_end = groups[-1]
        if start_block - prev_end >= split_blocks:
            groups.append((start_block, end_block))
        else:
            groups[-1] = (prev_start, end_block)

    pre = int(PRE_ROLL_SEC * SAMPLE_RATE)
    tail = int(TAIL_SEC * SAMPLE_RATE)
    segments = []
    for start_block, end_block in groups:
        start = max(0, start_block * block - pre)
        end = min(len(audio), end_block * block + tail)
        segments.append((start, end, threshold_db))
    return segments


def apply_fades(audio: np.ndarray) -> np.ndarray:
    result = audio.astype(np.float32, copy=True)
    fade_in = min(int(FADE_IN_SEC * SAMPLE_RATE), len(result))
    fade_out = min(int(FADE_OUT_SEC * SAMPLE_RATE), len(result))
    if fade_in > 1:
        ramp = 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, fade_in))
        result[:fade_in] *= ramp.astype(np.float32)
    if fade_out > 1:
        ramp = 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, fade_out))
        result[-fade_out:] *= ramp.astype(np.float32)
    return result


def peak_db(audio: np.ndarray) -> float:
    return 20.0 * float(np.log10(np.max(np.abs(audio)) + 1e-12))


def rms_db(audio: np.ndarray) -> float:
    value = float(np.sqrt(np.mean(audio.astype(np.float64) ** 2)))
    return 20.0 * float(np.log10(value + 1e-12))


def clean_file(
    source: Path, output_dir: Path, used_names: set[str]
) -> list[dict]:
    audio = decode(source, use_filters=True)
    segments = find_segments(audio)
    stem = source.stem.strip().rstrip(".")
    rows = []
    for number, (start, end, threshold_db) in enumerate(segments):
        segment = audio[start:end]
        in_peak_db = peak_db(segment)
        gain_db = min(TARGET_PEAK_DB - in_peak_db, MAX_GAIN_DB)
        cleaned = apply_fades(segment * np.float32(10.0 ** (gain_db / 20.0)))
        if len(segments) == 1:
            name = f"{stem}.wav"
        else:
            name = f"{stem}_{chr(ord('a') + number)}.wav"
        # "screw pickup .m4a" and "screw pickup.m4a" share a stem once
        # the trailing space is stripped. Keep both takes.
        candidate = name
        copy_number = 2
        while candidate in used_names:
            candidate = f"{Path(name).stem}_take{copy_number}.wav"
            copy_number += 1
        name = candidate
        used_names.add(name)
        sf.write(output_dir / name, cleaned, SAMPLE_RATE, subtype="PCM_16")
        rows.append(
            {
                "source": source.name,
                "output": name,
                "source_sec": f"{len(audio) / SAMPLE_RATE:.2f}",
                "output_sec": f"{len(cleaned) / SAMPLE_RATE:.2f}",
                "peak_in_db": f"{in_peak_db:.1f}",
                "peak_out_db": f"{peak_db(cleaned):.1f}",
                "rms_out_db": f"{rms_db(cleaned):.1f}",
                "gain_db": f"{gain_db:.1f}",
                "gain_capped": "yes" if gain_db >= MAX_GAIN_DB - 1e-9 else "no",
                "threshold_db": f"{threshold_db:.1f}",
            }
        )
    return rows


def analyze_file(source: Path) -> None:
    raw = decode(source, use_filters=False)
    filtered = decode(source, use_filters=True)
    segments = find_segments(filtered)
    spans = ", ".join(
        f"{start / SAMPLE_RATE:.2f}-{end / SAMPLE_RATE:.2f}s"
        for start, end, _ in segments
    )
    print(
        f"{source.name:32s} raw_peak={peak_db(raw):6.1f} "
        f"filt_peak={peak_db(filtered):6.1f} "
        f"raw_noise={np.percentile(block_levels_db(raw), 10):6.1f} "
        f"filt_noise={np.percentile(block_levels_db(filtered), 10):6.1f} "
        f"segments={len(segments)} [{spans}]"
    )


def main() -> int:
    args = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
    analyze_only = "--analyze" in sys.argv
    source_dir = Path(args[0]) if len(args) > 0 else Path(r"C:\Users\lsl\Downloads\foley")
    repo_root = Path(__file__).resolve().parent.parent
    output_dir = Path(args[1]) if len(args) > 1 else repo_root / "foley_cleaned"
    sources = sorted(source_dir.glob("*.m4a"))
    if not sources:
        print(f"No .m4a files in {source_dir}")
        return 1
    if analyze_only:
        for source in sources:
            analyze_file(source)
        return 0
    output_dir.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    used_names: set[str] = set()
    for source in sources:
        file_rows = clean_file(source, output_dir, used_names)
        rows.extend(file_rows)
        print(f"{source.name}: {len(file_rows)} output(s)")
    columns = list(rows[0].keys())
    with open(output_dir / "manifest.csv", "w", encoding="utf-8") as handle:
        handle.write(",".join(columns) + "\n")
        for row in rows:
            handle.write(",".join(str(row[column]) for column in columns) + "\n")
    capped = sum(1 for row in rows if row["gain_capped"] == "yes")
    print(f"\n{len(sources)} recordings -> {len(rows)} WAV files in {output_dir}")
    print(f"Gain capped at +{MAX_GAIN_DB:.0f} dB on {capped} output(s); see manifest.csv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
