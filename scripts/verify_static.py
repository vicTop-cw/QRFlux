"""Static-pipeline end-to-end verification.

Validates that encode_static QR codes can be decoded by zxing-cpp and the
decoded bytes match the packaged bytes emitted by cmd/main.

Usage:
  moon run cmd/main > batch.txt
  python scripts/verify_static.py batch.txt

Each STATIC_CASE block contains:
  STATIC_CASE <label> data_len=N ecl=X version=V size=S mask=M algo=A compressed=C pkg_len=P
  <matrix rows>
  PACKED <hex>
  END_STATIC

We decode the matrix with zxing-cpp and compare the result against the
PACKED hex (the expected packaged bytes from encode_static).
"""
import sys
import re
import time
from collections import defaultdict

import numpy as np
import zxingcpp
from PIL import Image

SCALE = 10
QUIET = 8


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


def parse_blocks(content: str):
    """Yield (header_dict, matrix_rows, packed_bytes) for each STATIC_CASE."""
    lines = content.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("STATIC_CASE "):
            m = re.match(
                r"STATIC_CASE (\S+) data_len=(\d+) ecl=(\w+) version=(\d+) "
                r"size=(\d+) mask=(\d+) algo=(\d+) compressed=(\d+) pkg_len=(\d+)",
                line,
            )
            if not m:
                i += 1
                continue
            header = {
                "label": m.group(1),
                "data_len": int(m.group(2)),
                "ecl": m.group(3),
                "version": int(m.group(4)),
                "size": int(m.group(5)),
                "mask": int(m.group(6)),
                "algo": int(m.group(7)),
                "compressed": int(m.group(8)),
                "pkg_len": int(m.group(9)),
            }
            size = header["size"]
            i += 1
            matrix = []
            while i < len(lines) and len(matrix) < size:
                row = lines[i]
                if row and all(c in "01" for c in row):
                    matrix.append(row)
                i += 1
            # Find PACKED line
            packed = None
            while i < len(lines):
                if lines[i].startswith("PACKED "):
                    packed = bytes.fromhex(lines[i][7:])
                    i += 1
                    break
                if lines[i] == "END_STATIC":
                    i += 1
                    break
                i += 1
            yield header, matrix, packed
        else:
            i += 1


def main(path: str) -> int:
    with open(path, encoding="utf-8") as f:
        content = f.read()
    blocks = list(parse_blocks(content))
    if not blocks:
        print("no STATIC_CASE blocks found")
        return 1
    print(f"Found {len(blocks)} STATIC_CASE blocks\n")
    results = []
    for header, matrix, packed in blocks:
        label = header["label"]
        ver = header["version"]
        ecl = header["ecl"]
        algo = header["algo"]
        comp = header["compressed"]
        dlen = header["data_len"]
        if packed is None:
            print(f"{label}: MISSING PACKED line")
            results.append((label, ver, ecl, False, "no packed"))
            continue
        t0 = time.perf_counter()
        res = zxingcpp.read_barcodes(matrix_to_image(matrix), return_errors=True)
        elapsed = time.perf_counter() - t0
        qr_bars = [
            b
            for b in res
            if not isinstance(b, zxingcpp.Error) and str(b.format) == "QR Code"
        ]
        got = qr_bars[0].bytes if qr_bars else None
        ok = got == packed
        results.append((label, ver, ecl, ok, None))
        tag = f"algo={algo} comp={comp}"
        status = "OK" if ok else "FAIL"
        print(f"{label}: ver={ver} ecl={ecl} {tag} -> {status} ({elapsed*1000:.1f}ms)")
        if not ok:
            if got is None:
                print(f"    decode returned no QR barcode")
            else:
                diffs = [
                    j
                    for j in range(min(len(packed), len(got)))
                    if packed[j] != got[j]
                ]
                print(
                    f"    expect len={len(packed)} got len={len(got)} "
                    f"diffs={len(diffs)} ({len(diffs)/len(packed)*100:.2f}%)"
                )
                if diffs:
                    print(f"    first diff at pos {diffs[0]}")

    # Summary
    total = len(results)
    passed = sum(1 for r in results if r[3])
    failed = total - passed
    print("\n" + "=" * 60)
    print(f"STATIC PIPELINE SUMMARY: {passed}/{total} passed, {failed} failed")
    # By pattern
    by_pat = defaultdict(lambda: [0, 0])
    for r in results:
        pat = r[0].split("_")[1]  # s_<pattern>_<len>_<ecl>
        by_pat[pat][0] += 1
        if r[3]:
            by_pat[pat][1] += 1
    print("\nBy data pattern:")
    for pat in sorted(by_pat):
        tot, ok = by_pat[pat]
        print(f"  {pat}: {ok}/{tot}")
    # By ECC
    by_ecl = defaultdict(lambda: [0, 0])
    for r in results:
        by_ecl[r[2]][0] += 1
        if r[3]:
            by_ecl[r[2]][1] += 1
    print("\nBy ECC level:")
    for ecl in ["L", "M"]:
        if ecl in by_ecl:
            tot, ok = by_ecl[ecl]
            print(f"  {ecl}: {ok}/{tot}")
    if failed:
        print("\nFailed cases:")
        for r in results:
            if not r[3]:
                print(f"  {r[0]} (ver={r[1]} ecl={r[2]})")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "batch.txt"))
