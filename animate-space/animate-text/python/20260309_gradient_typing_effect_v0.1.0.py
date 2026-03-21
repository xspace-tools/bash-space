#!/usr/bin/env python3
# python/20260309_gradient_typing_effect_v0.1.0.py
"""
Animated typing GIF generator with gradient text.
Called directly or via _run/20260309_run_typing_effect_v0.1.0.sh.

Pass --brand <hex> to derive the gradient automatically (hue-shift + lighten).
Pass --gradient1 / --gradient2 to set both stops manually.
"""

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.1.0 — Refactor: all tunables moved into CONFIG block; output dir
#             updated from generated-assets → exports; paths derived from
#             config constants rather than hardcoded strings; comments rewritten
#             to explain why, not what; file-path comment added to line 1.
#   v0.0.0 — Initial release. Gradient typing GIF generator with --brand flag
#             and fixed-baseline vertical rendering.
# ─────────────────────────────────────────────────────────────────────────────

import argparse
import colorsys
import math
import os
from datetime import datetime
from typing import Dict, Tuple

from PIL import Image, ImageDraw, ImageFont

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG — change values here, not inside the renderer
# ─────────────────────────────────────────────────────────────────────────────
# Single source of truth for every tunable. Need a wider canvas? Change WIDTH.
# Renamed the output folder? Change OUTPUT_SUBDIR. Nothing else needs touching.

# ── Canvas ────────────────────────────────────────────────────────────────────
DEFAULT_WIDTH  = 1200
DEFAULT_HEIGHT = 200

# ── Animation timing ──────────────────────────────────────────────────────────
DEFAULT_FPS         = 24
CHAR_DELAY          = 0.1   # seconds between each character appearing
FADE_DURATION       = 0.3   # line fade-in at the start of each sentence
PAUSE_BETWEEN_LINES = 2.0   # hold time after the line finishes typing

# ── Typography ────────────────────────────────────────────────────────────────
DEFAULT_FONT_FILENAME = "Poppins-Bold.ttf"
DEFAULT_FONT_SIZE     = 64

# ── Layout ────────────────────────────────────────────────────────────────────
DEFAULT_ALIGNMENT  = "center"   # left | center | right
MARGIN_HORIZONTAL  = 20         # padding used for left / right alignment

# ── Gradient defaults (ignored when --brand is supplied) ──────────────────────
DEFAULT_GRADIENT_START = "#00C800"
DEFAULT_GRADIENT_END   = "#B4FF00"

# ── Brand → gradient transform (mirrors the Dart theme engine) ────────────────
BRAND_HUE_SHIFT_DEG  = -6.0    # degrees to rotate hue for the start color
BRAND_LIGHTEN_AMOUNT = 0.12    # how much lighter the start stop is vs the brand

# ── Directory names (relative to project root) ────────────────────────────────
OUTPUT_SUBDIR = "exports"   # renamed from generated-assets
FONTS_SUBDIR  = "fonts"

# ─────────────────────────────────────────────────────────────────────────────
# PATHS — derived from config, not hardcoded inline
# ─────────────────────────────────────────────────────────────────────────────
# python/ sits one level below the project root, so we step up one dir.

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_ROOT_DIR   = os.path.normpath(os.path.join(_SCRIPT_DIR, ".."))

FONTS_DIR  = os.path.join(_ROOT_DIR, FONTS_SUBDIR)
OUTPUT_DIR = os.path.join(_ROOT_DIR, OUTPUT_SUBDIR)

os.makedirs(OUTPUT_DIR, exist_ok=True)


# ─────────────────────────────────────────────────────────────────────────────
# COLOR UTILITIES
# ─────────────────────────────────────────────────────────────────────────────

def hex_to_rgb(hex_str: str) -> Tuple[int, int, int]:
    h = hex_str.strip().lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgb_to_hex(rgb: Tuple[int, int, int]) -> str:
    return "#{:02X}{:02X}{:02X}".format(*rgb)


def linear_gradient(
    c1: Tuple[int, int, int],
    c2: Tuple[int, int, int],
    width: int
):
    """Return a list of (r,g,b) tuples interpolated across `width` steps."""
    result = []
    for i in range(width):
        t = i / (width - 1) if width > 1 else 0
        result.append((
            int(c1[0] + (c2[0] - c1[0]) * t),
            int(c1[1] + (c2[1] - c1[1]) * t),
            int(c1[2] + (c2[2] - c1[2]) * t),
        ))
    return result


def ease_in_out(t: float) -> float:
    """Smooth step — nicer than linear for fade-ins."""
    t = max(0.0, min(1.0, t))
    return 3 * t * t - 2 * t * t * t


def compute_gradient_start_from_brand(brand_hex: str) -> Tuple[int, int, int]:
    """
    Derive the gradient start color from the brand primary color.

    Mirrors the Dart theme computation:
      - rotate hue by BRAND_HUE_SHIFT_DEG
      - increase lightness by BRAND_LIGHTEN_AMOUNT
    The brand color itself becomes the gradient end.
    """
    h = brand_hex.strip().lstrip("#")
    if len(h) != 6:
        raise ValueError(f"Expected 6-char hex, got: {brand_hex!r}")

    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))

    # colorsys uses (h, l, s) order, all in [0, 1]
    hh, ll, ss = colorsys.rgb_to_hls(r, g, b)

    hh = ((hh * 360.0 + BRAND_HUE_SHIFT_DEG) % 360.0) / 360.0
    ll = min(1.0, ll + BRAND_LIGHTEN_AMOUNT)

    r2, g2, b2 = colorsys.hls_to_rgb(hh, ll, ss)
    return (int(round(r2 * 255)), int(round(g2 * 255)), int(round(b2 * 255)))


# ─────────────────────────────────────────────────────────────────────────────
# FONT LOADING
# ─────────────────────────────────────────────────────────────────────────────

def load_font(font_filename: str, size: int):
    """
    Try the fonts dir first, then treat font_filename as an absolute path.
    Falls back to PIL's default bitmap font — better than crashing.
    """
    candidates = [
        os.path.join(FONTS_DIR, font_filename),
        font_filename,
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size), path
        except Exception:
            pass

    return ImageFont.load_default(), "PIL-default"


# ─────────────────────────────────────────────────────────────────────────────
# RENDER CACHE
# ─────────────────────────────────────────────────────────────────────────────

# Keyed by (line_idx, chars_visible, full_text, grad_start, grad_end).
# Avoids re-rendering the same partial line on every frame.
_render_cache: Dict[Tuple, Image.Image] = {}


def render_text_line(
    line_idx: int,
    text: str,
    upto: int,
    font,
    grad_start: Tuple[int, int, int],
    grad_end: Tuple[int, int, int],
) -> Image.Image:
    """
    Render `text[:upto]` into a gradient-filled RGBA image.

    Vertical sizing is fixed to the full line's bounding box so the baseline
    never shifts between frames — that was the "kick" bug in v0.0.0.
    """
    key = (line_idx, upto, text, grad_start, grad_end)
    if key in _render_cache:
        return _render_cache[key].copy()

    visible = text[:upto]

    # Measure using a throwaway draw — ImageDraw.textbbox is cheap
    _tmp = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    full_bbox = _tmp.textbbox((0, 0), text, font=font)
    vis_bbox  = _tmp.textbbox((0, 0), visible, font=font)

    full_w = max(1, full_bbox[2] - full_bbox[0])
    full_h = max(1, full_bbox[3] - full_bbox[1])
    vis_w  = max(1, vis_bbox[2]  - vis_bbox[0])

    # Gradient spans the visible width, height is locked to the full line height
    gradient = linear_gradient(grad_start, grad_end, vis_w)
    grad_img = Image.new("RGBA", (vis_w, full_h))
    gdraw = ImageDraw.Draw(grad_img)
    for x, color in enumerate(gradient):
        gdraw.line([(x, 0), (x, full_h)], fill=color)

    # Mask: render the visible text into a grayscale image used as alpha
    mask = Image.new("L", (vis_w, full_h), 0)
    ImageDraw.Draw(mask).text(
        (-full_bbox[0], -full_bbox[1]),
        visible,
        font=font,
        fill=255,
    )

    # Punch the mask through the gradient
    out = Image.new("RGBA", (vis_w, full_h), (0, 0, 0, 0))
    out.paste(grad_img, (0, 0), mask)

    _render_cache[key] = out.copy()
    return out


# ─────────────────────────────────────────────────────────────────────────────
# LAYOUT
# ─────────────────────────────────────────────────────────────────────────────

def compute_x(text_width: int, canvas_width: int, alignment: str) -> int:
    if alignment == "left":
        return MARGIN_HORIZONTAL
    if alignment == "right":
        return canvas_width - text_width - MARGIN_HORIZONTAL
    return (canvas_width - text_width) // 2   # center


# ─────────────────────────────────────────────────────────────────────────────
# FRAME GENERATION
# ─────────────────────────────────────────────────────────────────────────────

def make_frame(
    t: float,
    text_lines: list,
    font,
    width: int,
    height: int,
    alignment: str,
    grad_start: Tuple[int, int, int],
    grad_end: Tuple[int, int, int],
) -> Image.Image:
    """Build a single RGBA frame for time offset `t` (seconds)."""

    # Walk the timeline to find which line owns this moment
    elapsed = 0.0
    line_idx = len(text_lines) - 1
    local_t  = 0.0

    for idx, line in enumerate(text_lines):
        duration = len(line) * CHAR_DELAY + FADE_DURATION + PAUSE_BETWEEN_LINES
        if elapsed <= t < elapsed + duration:
            line_idx = idx
            local_t  = t - elapsed
            break
        elapsed += duration

    current_line = text_lines[line_idx]
    chars = min(len(current_line), int(local_t / CHAR_DELAY) + 1)

    line_img = render_text_line(line_idx, current_line, chars, font, grad_start, grad_end)

    # Fade in at the start of each line
    alpha = ease_in_out(local_t / FADE_DURATION) if local_t < FADE_DURATION else 1.0

    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    x = compute_x(line_img.width, width, alignment)
    y = (height - line_img.height) // 2

    if alpha < 1.0:
        r, g, b, a = line_img.split()
        a = a.point(lambda p: int(p * alpha))
        line_img.putalpha(a)

    canvas.paste(line_img, (x, y), line_img)
    return canvas


def generate_frames(
    text_lines: list,
    font,
    width: int,
    height: int,
    alignment: str,
    grad_start: Tuple[int, int, int],
    grad_end: Tuple[int, int, int],
    fps: int,
) -> list:
    total = sum(
        len(line) * CHAR_DELAY + FADE_DURATION + PAUSE_BETWEEN_LINES
        for line in text_lines
    )
    num_frames = int(math.ceil(total * fps))
    frames = []

    for i in range(num_frames):
        frame = make_frame(
            i / fps, text_lines, font,
            width, height, alignment, grad_start, grad_end,
        )
        frames.append(frame)
        if i % max(1, num_frames // 10) == 0:
            print(f"  Rendered {i}/{num_frames} frames")

    return frames


# ─────────────────────────────────────────────────────────────────────────────
# OUTPUT
# ─────────────────────────────────────────────────────────────────────────────

def save_gif(frames: list, path: str, fps: int) -> None:
    frames[0].save(
        path,
        save_all=True,
        append_images=frames[1:],
        duration=int(1000 / fps),
        loop=0,
        optimize=True,
        disposal=2,   # clear to background between frames — required for transparency
    )


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Generate an animated typing GIF with gradient text."
    )
    p.add_argument("--text",      help="Pipe-separated lines, e.g. 'Hello|World'")
    p.add_argument("--gradient1", default=DEFAULT_GRADIENT_START)
    p.add_argument("--gradient2", default=DEFAULT_GRADIENT_END)
    p.add_argument(
        "--brand", default=None,
        help="Primary brand hex (e.g. #00CC66). Overrides --gradient1/2 and "
             "auto-computes the start stop.",
    )
    p.add_argument("--align",    default=DEFAULT_ALIGNMENT)
    p.add_argument("--width",    type=int, default=DEFAULT_WIDTH)
    p.add_argument("--height",   type=int, default=DEFAULT_HEIGHT)
    p.add_argument("--font",     default=DEFAULT_FONT_FILENAME)
    p.add_argument("--fontsize", type=int, default=DEFAULT_FONT_SIZE)
    p.add_argument("--project",  default="project")
    p.add_argument("--version",  default="0.0.0")
    p.add_argument("--date",     default=None)
    p.add_argument("--fps",      type=int, default=DEFAULT_FPS)
    return p.parse_args()


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    args = parse_args()

    text_lines = args.text.split("|") if args.text else ["Hello world"]

    if args.brand:
        try:
            grad_end   = hex_to_rgb(args.brand)
            grad_start = compute_gradient_start_from_brand(args.brand)
        except Exception as e:
            print(f"Warning: could not derive gradient from brand ({e}). "
                  "Falling back to --gradient1/--gradient2.")
            grad_start = hex_to_rgb(args.gradient1)
            grad_end   = hex_to_rgb(args.gradient2)
    else:
        grad_start = hex_to_rgb(args.gradient1)
        grad_end   = hex_to_rgb(args.gradient2)

    font, font_path = load_font(args.font, args.fontsize)
    print(f"Font   : {font_path}")
    print(f"Output : {OUTPUT_DIR}")

    frames = generate_frames(
        text_lines, font,
        args.width, args.height, args.align,
        grad_start, grad_end, args.fps,
    )

    date     = args.date or datetime.now().strftime("%Y%m%d")
    filename = f"{date}_asset_animated_text_{args.project}_v{args.version}.gif"
    out_path = os.path.join(OUTPUT_DIR, filename)

    save_gif(frames, out_path, args.fps)
    print(f"Saved  : {out_path}")


if __name__ == "__main__":
    main()