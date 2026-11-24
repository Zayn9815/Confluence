#!/usr/bin/env python3
"""
Deterministic AppIcon generator for Confluence (com.bilal.confluence).
Renders a matte obsidian (#0B0D11) background with subtle metallic radial vignette
and a geometric brushed champagne-gold (#D4AF37) candlestick silhouette cleanly sliced
by an upward precision break-of-structure vector arrow. Zero text inside icon.
Pure Python stdlib (no Pillow required).
"""

import json
import math
import struct
import zlib
from pathlib import Path


def write_png(path: Path, width: int, height: int, rgba_bytes: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter type 0 (None)
        raw.extend(rgba_bytes[y * stride : (y + 1) * stride])

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), level=6))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def sd_rounded_box(px: float, py: float, cx: float, cy: float, hx: float, hy: float, r: float) -> float:
    dx = abs(px - cx) - hx + r
    dy = abs(py - cy) - hy + r
    return math.hypot(max(dx, 0.0), max(dy, 0.0)) + min(max(dx, dy), 0.0) - r


def sd_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    h = max(0.0, min(1.0, (pax * bax + pay * bay) / max(bax * bax + bay * bay, 1e-9)))
    return math.hypot(pax - bax * h, pay - bay * h)


def clamp01(v: float) -> float:
    return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = clamp01((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def render_icon(size: int) -> bytes:
    buf = bytearray(size * size * 4)
    inv = 1.0 / size

    # Normalized coordinates in [0, 1] x [0, 1]
    # Three ascending institutional candlesticks (left muted slate-gold, middle champagne, right bright gold)
    candles = [
        # (cx, body_cy, body_hx, body_hy, wick_top, wick_bot, intensity)
        (0.28, 0.64, 0.052, 0.115, 0.45, 0.81, 0.72),
        (0.49, 0.54, 0.056, 0.140, 0.32, 0.75, 0.88),
        (0.70, 0.41, 0.058, 0.155, 0.19, 0.64, 1.00),
    ]

    # Precision Break-of-Structure upward diagonal vector arrow slicing across candles
    arrow_p0 = (0.18, 0.77)
    arrow_p1 = (0.48, 0.56)
    arrow_p2 = (0.55, 0.61)
    arrow_p3 = (0.83, 0.24)
    head_l = (0.71, 0.26)
    head_r = (0.81, 0.36)

    for y in range(size):
        ny = (y + 0.5) * inv
        row_offset = y * size * 4
        for x in range(size):
            nx = (x + 0.5) * inv

            # 1. Matte Obsidian background (#0B0D11) + subtle metallic radial vignette
            dx = nx - 0.50
            dy = ny - 0.46
            dist = math.hypot(dx, dy)
            vignette = 1.0 - smoothstep(0.12, 0.78, dist)
            # Subtle brushed micro-sheen along 35-deg diagonal
            sheen = 0.5 + 0.5 * math.sin((nx * 0.8 + ny * 0.6) * math.pi * 2.0)

            r = 11.0 + vignette * 16.0 + sheen * 3.0
            g = 13.0 + vignette * 19.0 + sheen * 3.5
            b = 17.0 + vignette * 25.0 + sheen * 4.5

            # Subtle precision outer hairline ring
            ring_d = abs(sd_rounded_box(nx, ny, 0.5, 0.5, 0.435, 0.435, 0.14))
            ring_alpha = (1.0 - smoothstep(0.0018, 0.0045, ring_d)) * 0.26
            r = r * (1.0 - ring_alpha) + 212.0 * ring_alpha
            g = g * (1.0 - ring_alpha) + 175.0 * ring_alpha
            b = b * (1.0 - ring_alpha) + 55.0 * ring_alpha

            # Subtle horizontal BOS reference dashed level at y = 0.36
            if 0.16 <= nx <= 0.84:
                bos_line_d = abs(ny - 0.36)
                dash = 1.0 if int(nx * 28) % 2 == 0 else 0.0
                bos_a = (1.0 - smoothstep(0.0015, 0.004, bos_line_d)) * 0.22 * dash
                r = r * (1.0 - bos_a) + 212.0 * bos_a
                g = g * (1.0 - bos_a) + 175.0 * bos_a
                b = b * (1.0 - bos_a) + 55.0 * bos_a

            # 2. Geometric candlestick silhouettes (brushed champagne gold)
            candle_cov = 0.0
            candle_int = 0.0
            for cx, cy, hx, hy, w_top, w_bot, intensity in candles:
                d_body = sd_rounded_box(nx, ny, cx, cy, hx, hy, 0.014)
                d_wick = sd_segment(nx, ny, cx, w_top, cx, w_bot) - 0.011
                d = min(d_body, d_wick)
                cov = 1.0 - smoothstep(-0.0025, 0.0025, d)
                if cov > candle_cov:
                    candle_cov = cov
                    candle_int = intensity

            # 3. Clean obsidian slice gap around BOS arrow (carves through candlesticks cleanly)
            d_seg1 = sd_segment(nx, ny, *arrow_p0, *arrow_p1)
            d_seg2 = sd_segment(nx, ny, *arrow_p1, *arrow_p2)
            d_seg3 = sd_segment(nx, ny, *arrow_p2, *arrow_p3)
            d_hl = sd_segment(nx, ny, *arrow_p3, *head_l)
            d_hr = sd_segment(nx, ny, *arrow_p3, *head_r)
            d_arrow_center = min(d_seg1, d_seg2, d_seg3, d_hl, d_hr)

            cut_mask = 1.0 - smoothstep(0.025, 0.031, d_arrow_center)
            candle_cov *= (1.0 - cut_mask)

            if candle_cov > 0.0:
                # Brushed champagne gold metallic gradient (#B48C28 -> #E8CB6D)
                grad = clamp01(1.0 - (ny * 0.65 + (1.0 - nx) * 0.35))
                brushed = 0.94 + 0.06 * math.sin((nx * 24.0 - ny * 18.0))
                cr = (176.0 + 64.0 * grad) * candle_int * brushed
                cg = (138.0 + 62.0 * grad) * candle_int * brushed
                cb = (42.0 + 48.0 * grad) * candle_int * brushed
                r = r * (1.0 - candle_cov) + cr * candle_cov
                g = g * (1.0 - candle_cov) + cg * candle_cov
                b = b * (1.0 - candle_cov) + cb * candle_cov

            # 4. Crisp luminous champagne-ivory BOS vector arrow
            arrow_cov = 1.0 - smoothstep(0.0135, 0.0175, d_arrow_center)
            if arrow_cov > 0.0:
                ag = clamp01((nx - 0.18) / 0.65)
                ar = 220.0 + 30.0 * ag
                ag_c = 188.0 + 44.0 * ag
                ab = 88.0 + 92.0 * ag
                r = r * (1.0 - arrow_cov) + ar * arrow_cov
                g = g * (1.0 - arrow_cov) + ag_c * arrow_cov
                b = b * (1.0 - arrow_cov) + ab * arrow_cov

            idx = row_offset + x * 4
            buf[idx] = int(max(0, min(255, round(r))))
            buf[idx + 1] = int(max(0, min(255, round(g))))
            buf[idx + 2] = int(max(0, min(255, round(b))))
            buf[idx + 3] = 255

    return bytes(buf)


def generate_app_icon(assets_dir: Path) -> None:
    appicon_dir = assets_dir / "AppIcon.appiconset"
    appicon_dir.mkdir(parents=True, exist_ok=True)

    # Modern Xcode single-size 1024x1024 universal iOS AppIcon + explicit Contents.json
    icon_1024 = render_icon(1024)
    write_png(appicon_dir / "AppIcon-1024.png", 1024, 1024, icon_1024)

    contents = {
        "images": [
            {
                "filename": "AppIcon-1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (appicon_dir / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

    root_contents = {"info": {"author": "xcode", "version": 1}}
    (assets_dir / "Contents.json").write_text(json.dumps(root_contents, indent=2) + "\n")
    print(f"Generated AppIcon-1024.png in {appicon_dir}")


if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parent.parent
    generate_app_icon(repo_root / "Confluence" / "Resources" / "Assets.xcassets")
