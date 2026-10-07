#!/usr/bin/env python3
"""Generate black DOT tray template PNGs using only the Python standard library."""
import struct
import zlib
from pathlib import Path


def png(size: int) -> bytes:
    rows = []
    center = size / 2
    radius = size / 3
    samples = 8
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            # Supersample the edge for a smooth circle on a transparent canvas.
            coverage = sum(
                (x + (sx + 0.5) / samples - center) ** 2
                + (y + (sy + 0.5) / samples - center) ** 2 <= radius ** 2
                for sy in range(samples) for sx in range(samples)
            )
            row.extend((0, 0, 0, round(255 * coverage / samples ** 2)))
        rows.append(row)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (struct.pack('>I', len(data)) + kind + data
                + struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF))

    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b''.join(rows), 9))
            + chunk(b'IEND', b''))


if __name__ == '__main__':
    folder = Path(__file__).resolve().parents[1] / 'assets/icons'
    for name, size in [('dot_tray.png', 18), ('dot_tray@2x.png', 36)]:
        (folder / name).write_bytes(png(size))
