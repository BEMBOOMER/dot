#!/usr/bin/env python3
"""Generate DOT launcher icons and preserve the existing tray templates.

The renderer intentionally uses only the Python standard library so icon
generation also works in a clean release environment.
"""

import math
import random
import struct
import zlib
from pathlib import Path


SIZE = 1024
BACKGROUND = (10, 10, 11)
BOTTOM = (11, 30, 140)
MIDDLE = (61, 90, 254)
TOP = (157, 176, 255)
SEED = 0xD07


def chunk(kind: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def encode_png(width: int, height: int, pixels: list[tuple[int, int, int, int]]) -> bytes:
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            row.extend(pixels[y * width + x])
        rows.append(row)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
        + chunk(b"IEND", b"")
    )


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    return tuple(round(start + (end - start) * amount) for start, end in zip(a, b))


def gradient_color(y: float, top_y: float, bottom_y: float) -> tuple[int, int, int]:
    position = max(0.0, min(1.0, (bottom_y - y) / (bottom_y - top_y)))
    middle_stop = 0.55
    if position < middle_stop:
        return lerp(BOTTOM, MIDDLE, position / middle_stop)
    return lerp(MIDDLE, TOP, (position - middle_stop) / (1 - middle_stop))


def circle_layer(size: int = SIZE, safe_zone: bool = False) -> list[tuple[int, int, int, int]]:
    """Render the blue circle on transparency, with deterministic fine grain."""
    pixels = [(0, 0, 0, 0)] * (size * size)
    scale = size / SIZE
    center = size / 2
    radius = size * (0.28 if not safe_zone else 0.27)
    rng = random.Random(SEED)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(size * size)]
    for y in range(size):
        for x in range(size):
            distance = math.hypot(x + 0.5 - center, y + 0.5 - center)
            edge = max(0.0, min(1.0, radius + 1.5 * scale - distance))
            if edge == 0:
                continue
            alpha = round(255 * min(1.0, edge))
            red, green, blue = gradient_color(y, center - radius, center + radius)
            grain = noise[y * size + x] * 0.07
            rgb = tuple(max(0, min(255, round(channel * (1 + grain)))) for channel in (red, green, blue))
            pixels[y * size + x] = (*rgb, alpha)
    return pixels


def composite(
    background: tuple[int, int, int, int],
    layer: list[tuple[int, int, int, int]],
    size: int = SIZE,
) -> list[tuple[int, int, int, int]]:
    output = [background] * (size * size)
    for index, foreground in enumerate(layer):
        output[index] = over(output[index], foreground)
    return output


def over(base: tuple[int, int, int, int], foreground: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    alpha = foreground[3] / 255
    base_alpha = base[3] / 255
    output_alpha = alpha + base_alpha * (1 - alpha)
    if output_alpha == 0:
        return (0, 0, 0, 0)
    return tuple(
        round(
            (foreground[channel] * alpha + base[channel] * base_alpha * (1 - alpha))
            / output_alpha
        )
        for channel in range(3)
    ) + (round(output_alpha * 255),)


def overlay(base: list[tuple[int, int, int, int]], layer: list[tuple[int, int, int, int]]) -> list[tuple[int, int, int, int]]:
    return [over(background, foreground) for background, foreground in zip(base, layer)]


def rounded_background(size: int = SIZE) -> list[tuple[int, int, int, int]]:
    pixels = [(0, 0, 0, 0)] * (size * size)
    margin = round(100 * size / SIZE)
    radius = round(185 * size / SIZE)
    for y in range(size):
        for x in range(size):
            nearest_x = max(margin + radius, min(size - margin - radius, x))
            nearest_y = max(margin + radius, min(size - margin - radius, y))
            distance = math.hypot(x - nearest_x, y - nearest_y)
            edge = max(0.0, min(1.0, radius + 1.5 * size / SIZE - distance))
            if edge:
                pixels[y * size + x] = (*BACKGROUND, round(255 * edge))
    return pixels


def write(path: Path, pixels: list[tuple[int, int, int, int]], size: int = SIZE) -> None:
    path.write_bytes(encode_png(size, size, pixels))


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    icons = root / "assets/icons"
    icons.mkdir(parents=True, exist_ok=True)

    circle = circle_layer()
    write(icons / "app_icon.png", composite((*BACKGROUND, 255), circle))
    mac = overlay(rounded_background(), circle)
    write(icons / "app_icon_macos.png", mac)
    write(icons / "app_icon_foreground.png", circle_layer(safe_zone=True), SIZE)

    preview_size = 512
    preview = circle_layer(preview_size)
    write(root / "docs/icon-preview.png", composite((*BACKGROUND, 255), preview, preview_size), preview_size)
