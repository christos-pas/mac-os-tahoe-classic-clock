#!/usr/bin/env python3
"""Measure lock-screen clock geometry from a screenshot PNG."""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("error: Pillow required (python3 -m pip install --user pillow)", file=sys.stderr)
    sys.exit(1)


def is_glass_clock_pixel(r: int, g: int, b: int) -> bool:
    luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    if luma <= 180:
        return False
    return max(r, g, b) - min(r, g, b) < 100


def is_solid_clock_pixel(r: int, g: int, b: int) -> bool:
    return r > 235 and g > 235 and b > 235


def row_fill(pixels, x_start: int, x_end: int, y: int, *, solid: bool) -> float:
    width = x_end - x_start
    if width <= 0:
        return 0.0
    test = is_solid_clock_pixel if solid else is_glass_clock_pixel
    count = sum(test(*pixels[x, y]) for x in range(x_start, x_end))
    return count / width


def bands_from_rows(rows: list[int], height: int, *, min_gap: float) -> list[tuple[int, int]]:
    if not rows:
        return []
    gap_px = max(2, int(height * min_gap))
    bands: list[tuple[int, int]] = []
    start = rows[0]
    prev = rows[0]
    for y in rows[1:]:
        if y - prev > gap_px:
            bands.append((start, prev + 1))
            start = y
        prev = y
    bands.append((start, prev + 1))
    return bands


def measure(path: Path, *, solid: bool) -> dict:
    im = Image.open(path).convert("RGB")
    width, height = im.size
    pixels = im.load()

    x_start = int(width * 0.22)
    x_end = int(width * 0.78)
    y_start = int(height * 0.05)
    y_end = int(height * 0.35)

    threshold = 0.025 if solid else 0.03
    rows = [
        y
        for y in range(y_start, y_end)
        if threshold < row_fill(pixels, x_start, x_end, y, solid=solid) < 0.85
    ]
    if not rows:
        raise ValueError(f"no clock band found in {path}")

    if solid:
        bands = bands_from_rows(rows, height, min_gap=0.012)
        if not bands:
            raise ValueError(f"no clock bands found in {path}")
        time_band = max(bands, key=lambda band: band[1] - band[0])
        date_band = next((band for band in bands if band[1] <= time_band[0]), None)
        time_top, time_bottom = time_band
        date_top = date_band[0] / height if date_band else max(0.0, (time_top / height) - 0.03)
    else:
        time_top = min(rows)
        time_bottom = max(rows) + 1
        date_rows = [
            y
            for y in range(y_start, time_top)
            if row_fill(pixels, x_start, x_end, y, solid=False) > 0.02
        ]
        date_top = min(date_rows) / height if date_rows else max(0.0, (time_top / height) - 0.03)

    time_top_f = time_top / height
    time_bottom_f = time_bottom / height

    min_x = width
    max_x = 0
    for y in range(time_top, time_bottom):
        for x in range(x_start, x_end):
            test = is_solid_clock_pixel if solid else is_glass_clock_pixel
            if test(*pixels[x, y]):
                min_x = min(min_x, x)
                max_x = max(max_x, x)

    return {
        "dateTop": date_top,
        "timeTop": time_top_f,
        "timeBottom": time_bottom_f,
        "timeCenterY": (time_top_f + time_bottom_f) / 2,
        "timeCapHeight": time_bottom_f - time_top_f,
        "timeWidth": (max_x - min_x + 1) / width if max_x >= min_x else 0.0,
    }


def suggest(reference: dict, ours: dict, screen_height: float, current: dict) -> dict:
    size_scale = reference["timeCapHeight"] / max(ours["timeCapHeight"], 1e-6)
    target_size = current["timePointSize"] * size_scale
    return {
        "timeHeightFraction": min(0.22, max(0.11, target_size / screen_height)),
        "verticalCenterFraction": min(
            0.30,
            max(
                0.14,
                current["verticalCenterFraction"]
                + (reference["timeCenterY"] - ours["timeCenterY"]),
            ),
        ),
        "dateOffsetRatio": min(
            0.22,
            max(
                0.06,
                current["dateOffsetRatio"]
                - (reference["dateTop"] - ours["dateTop"]) * screen_height / max(current["timePointSize"], 1),
            ),
        ),
        "targetTimePointSize": target_size,
    }


def main() -> int:
    if len(sys.argv) < 3:
        print(
            "usage: measure_clock.py reference.png ours.png [screen_height [timeHeightFraction verticalCenterFraction dateOffsetRatio]]",
            file=sys.stderr,
        )
        return 1

    reference_path = Path(sys.argv[1])
    ours_path = Path(sys.argv[2])
    screen_height = float(sys.argv[3]) if len(sys.argv) > 3 else 982.0
    time_height_fraction = float(sys.argv[4]) if len(sys.argv) > 4 else 0.155
    vertical_center_fraction = float(sys.argv[5]) if len(sys.argv) > 5 else 0.27
    date_offset_ratio = float(sys.argv[6]) if len(sys.argv) > 6 else 0.15

    reference = measure(reference_path, solid=False)
    ours = measure(ours_path, solid=True)

    current = {
        "timePointSize": min(220.0, max(120.0, screen_height * time_height_fraction)),
        "verticalCenterFraction": vertical_center_fraction,
        "dateOffsetRatio": date_offset_ratio,
    }

    suggestion = suggest(reference, ours, screen_height, current)

    print(json.dumps({"reference": reference, "ours": ours, "suggestion": suggestion}, indent=2))
    print(
        f"\nReference time center: {reference['timeCenterY']*100:.1f}%  cap height: {reference['timeCapHeight']*100:.1f}%  date top: {reference['dateTop']*100:.1f}%",
        file=sys.stderr,
    )
    print(
        f"Ours       time center: {ours['timeCenterY']*100:.1f}%  cap height: {ours['timeCapHeight']*100:.1f}%  date top: {ours['dateTop']*100:.1f}%",
        file=sys.stderr,
    )
    print(
        f"Suggested  timeHeightFraction={suggestion['timeHeightFraction']:.4f}  "
        f"verticalCenterFraction={suggestion['verticalCenterFraction']:.4f}  "
        f"dateOffsetRatio={suggestion['dateOffsetRatio']:.4f}  "
        f"targetSize={suggestion['targetTimePointSize']:.1f}pt",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
