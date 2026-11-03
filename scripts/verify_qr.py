"""Cross-validation: decode QRFlux-generated matrices with zxing-cpp.

Usage:
  moon run cmd/main > batch.txt
  python scripts/verify_qr.py batch.txt

Each CASE block is a QR matrix printed by cmd/main. This script re-derives
the expected payload with the same deterministic PRNG and compares against
the decoded bytes.
"""
import sys, re
import numpy as np
import zxingcpp
from PIL import Image

SEED = 12345
SCALE = 10
QUIET = 8

def gen_rand(seed: int, n: int) -> bytes:
    out = []
    for _ in range(n):
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        out.append((seed >> 16) & 0xFF)
    return bytes(out)

def matrix_to_image(rows: list[str]) -> np.ndarray:
    size = len(rows)
    img = Image.new("L", ((size + 2 * QUIET) * SCALE, (size + 2 * QUIET) * SCALE), 255)
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "1":
                for dy in range(SCALE):
                    for dx in range(SCALE):
                        px[(x + QUIET) * SCALE + dx, (y + QUIET) * SCALE + dy] = 0
    return np.array(img)

def main(path: str) -> int:
    with open(path, encoding="utf-8") as f:
        content = f.read()
    blocks = re.split(r"^CASE ", content, flags=re.M)[1:]
    if not blocks:
        print("no CASE blocks found")
        return 1
    ok = 0
    for blk in blocks:
        lines = blk.strip().splitlines()
        m = re.match(r"(\w+) len=(\d+) ecl=(\w+) version=(\d+) size=(\d+) mask=(\d+)", lines[0])
        label, ecl, ver, size, mask = m.group(1), m.group(3), int(m.group(4)), int(m.group(5)), int(m.group(6))
        n = int(m.group(2))
        rows = lines[1 : 1 + size]
        res = zxingcpp.read_barcodes(matrix_to_image(rows))
        expect = gen_rand(SEED, n)
        got = res[0].bytes if res else None
        if got == expect:
            ok += 1
            print(f"{label}: ver={ver} ecl={ecl} mask={mask} n={n} -> OK")
        else:
            print(f"{label}: ver={ver} ecl={ecl} mask={mask} n={n} -> FAIL got={got!r}")
    print(f"passed {ok}/{len(blocks)}")
    return 0 if ok == len(blocks) else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "batch.txt"))
