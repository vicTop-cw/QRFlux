"""Cross-validation: decode QRFlux-generated matrices with zxing-cpp.

Usage:
  moon run cmd/main > batch.txt
  python scripts/verify_qr.py batch.txt

Each CASE block is a bare encode_binary QR matrix printed by cmd/main.
This script re-derives the expected payload with the same deterministic PRNG
and compares against the decoded bytes.

Static-pipeline blocks (STATIC_CASE) are ignored here; use verify_static.py
for those.
"""
import sys
import re
import time
from collections import defaultdict

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
    # Only match lines starting with "CASE " (not "STATIC_CASE ").
    blocks = re.split(r"^CASE ", content, flags=re.M)[1:]
    if not blocks:
        print("no CASE blocks found")
        return 1

    results = []  # (label, ver, ecl, n, ok, got, expect, elapsed)
    for blk in blocks:
        lines = blk.strip().splitlines()
        m = re.match(
            r"(\w+) len=(\d+) ecl=(\w+) version=(\d+) size=(\d+) mask=(\d+)",
            lines[0],
        )
        if not m:
            continue
        label = m.group(1)
        n = int(m.group(2))
        ecl = m.group(3)
        ver = int(m.group(4))
        size = int(m.group(5))
        rows = lines[1 : 1 + size]
        # Stop at first non-binary row (defensive: avoid trailing section markers).
        clean = []
        for r in rows:
            if r and all(c in "01" for c in r):
                clean.append(r)
            else:
                break
        if len(clean) != size:
            print(f"{label}: WARN expected {size} rows, got {len(clean)}")
            continue
        t0 = time.perf_counter()
        # Use return_errors=True: zxing-cpp returns more candidates in this
        # mode (default mode suppresses results when multiple format candidates
        # exist, e.g. QR Code vs Micro QR). Filter for QR Code format.
        res = zxingcpp.read_barcodes(matrix_to_image(clean), return_errors=True)
        elapsed = time.perf_counter() - t0
        expect = gen_rand(SEED, n)
        qr_bars = [
            b for b in res if not isinstance(b, zxingcpp.Error) and str(b.format) == "QR Code"
        ]
        got = qr_bars[0].bytes if qr_bars else None
        ok = got == expect
        results.append((label, ver, ecl, n, ok, got, expect, elapsed))
        status = "OK" if ok else "FAIL"
        print(f"{label}: ver={ver} ecl={ecl} n={n} -> {status} ({elapsed*1000:.1f}ms)")
        if not ok:
            if got is None:
                print(f"    decode returned no barcode")
            else:
                print(f"    expect len={len(expect)} got len={len(got)}")
                print(f"    expect[:32]={expect[:32].hex()}")
                print(f"    got[:32]  ={got[:32].hex()}")

    # Summary.
    total = len(results)
    passed = sum(1 for r in results if r[4])
    failed = total - passed
    print("\n" + "=" * 60)
    print(f"SUMMARY: {passed}/{total} passed, {failed} failed")
    # Group by version.
    by_ver = defaultdict(lambda: [0, 0])
    for r in results:
        by_ver[r[1]][0] += 1
        if r[4]:
            by_ver[r[1]][1] += 1
    print("\nBy version:")
    for ver in sorted(by_ver):
        tot, ok = by_ver[ver]
        print(f"  V{ver}: {ok}/{tot}")
    # Group by ECC level.
    by_ecl = defaultdict(lambda: [0, 0])
    for r in results:
        by_ecl[r[2]][0] += 1
        if r[4]:
            by_ecl[r[2]][1] += 1
    print("\nBy ECC level:")
    for ecl in ["L", "M", "Q", "H"]:
        if ecl in by_ecl:
            tot, ok = by_ecl[ecl]
            print(f"  {ecl}: {ok}/{tot}")
    if failed:
        print("\nFailed cases:")
        for r in results:
            if not r[4]:
                print(f"  {r[0]} (ver={r[1]} ecl={r[2]} n={r[3]})")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "batch.txt"))
