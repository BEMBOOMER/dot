#!/usr/bin/env python3
"""Create DOT's simple coral-on-paper PNG icon without external dependencies."""
import struct
import zlib
from pathlib import Path


def png(size: int) -> bytes:
    rows = []
    center = (size - 1) / 2
    radius = size * 0.28
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            edge = min(x, y, size - 1 - x, size - 1 - y)
            rounded = edge >= size * 0.12
            inside = (x - center) ** 2 + (y - center) ** 2 <= radius**2
            row.extend((255, 79, 129, 255) if rounded and inside else (245, 240, 232, 255))
        rows.append(row)
    raw = b"".join(rows)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


if __name__ == "__main__":
    target = Path(__file__).parents[1] / "assets/icons/dot_tray_template.png"
    target.write_bytes(png(32))
