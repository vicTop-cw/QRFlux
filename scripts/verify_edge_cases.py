"""Static pipeline edge-case verification.

Tests boundary conditions of encode_static -> image -> zxing decode -> restore.
Covers: empty, 1 byte, all-zero, all-0xFF, text, UTF-8, max capacity,
over-capacity, high-repeat, large random.

Usage:
  python scripts/verify_edge_cases.py

Prerequisites:
  pip install zxing-cpp Pillow numpy
  moon (MoonBit toolchain)
"""
import os
import re
import sys
import time
import struct
import subprocess

import numpy as np
import zxingcpp

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


# ---------- MoonBit-compatible helpers (shared logic) ----------

def crc32_moonbit(data: bytes) -> int:
    crc = 0xFFFFFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 1:
                crc = ((crc >> 1) & 0x7FFFFFFF) ^ 0xEDB88320
            else:
                crc = (crc >> 1) & 0x7FFFFFFF
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF


def rle_decompress_simple(data: bytes) -> bytes:
    result = bytearray()
    i, n = 0, len(data)
    while i < n:
        if i + 1 >= n:
            break
        count, value = data[i], data[i + 1]
        result.extend(bytes([value]) * count)
        i += 2
    return bytes(result)


def rle_decompress_optimized(data: bytes) -> bytes:
    result = bytearray()
    i, n = 0, len(data)
    while i < n:
        if data[i] == 255:
            if i + 3 >= n:
                break
            count = (data[i + 1] << 8) | data[i + 2]
            value = data[i + 3]
            result.extend(bytes([value]) * count)
            i += 4
        else:
            if i + 1 >= n:
                break
            count, value = data[i], data[i + 1]
            result.extend(bytes([value]) * count)
            i += 2
    return bytes(result)


def unpackage(pkg: bytes):
    if len(pkg) < 32 or pkg[0:4] != b"QRFX" or pkg[4] != 1:
        return None
    flags = pkg[5]
    algo = pkg[6]
    data_length = struct.unpack(">I", pkg[7:11])[0]
    original_size = struct.unpack(">I", pkg[11:15])[0]
    checksum = struct.unpack(">I", pkg[15:19])[0]
    if len(pkg) < 32 + data_length:
        return None
    payload = pkg[32:32 + data_length]
    if crc32_moonbit(payload) != checksum:
        return None
    return payload, original_size, (flags & 1) != 0, algo


def decode_static(qr_bytes: bytes):
    result = unpackage(qr_bytes)
    if result is None:
        return None
    payload, _, _, algo = result
    if algo == 0:
        return payload, algo, "none"
    elif algo == 1:
        return rle_decompress_simple(payload), algo, "simple"
    return None


# ---------- PBM / matrix parsing ----------

def parse_pbm(pbm_text: str) -> np.ndarray:
    lines = pbm_text.strip().split("\n")
    idx = 0
    while idx < len(lines) and not lines[idx].startswith("P1"):
        idx += 1
    idx += 1
    while idx < len(lines) and lines[idx].startswith("#"):
        idx += 1
    parts = lines[idx].split()
    w, h = int(parts[0]), int(parts[1])
    idx += 1
    pixels = []
    for line in lines[idx:]:
        if line and not line.startswith("#"):
            pixels.extend(int(x) for x in line.split())
    arr = np.array(pixels, dtype=np.uint8).reshape(h, w)
    return (1 - arr) * 255


def matrix_to_image(rows: list, scale: int = 10, quiet: int = 8) -> np.ndarray:
    """Convert 0/1 matrix rows to grayscale numpy with quiet zone + scale."""
    size = len(rows)
    total = size + 2 * quiet
    img = np.full((total * scale, total * scale), 255, dtype=np.uint8)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "1":
                y0, x0 = (y + quiet) * scale, (x + quiet) * scale
                img[y0:y0 + scale, x0:x0 + scale] = 0
    return img


# ---------- CLI runners ----------

def run_encode_static_text(text: str, ecl: str, fmt: str = "pbm"):
    """Run CLI with --text. Returns (header, image, output, stderr)."""
    cmd = [
        "moon", "run", "cmd/main", "--",
        "--encode-static", "--text", text,
        "--ecl", ecl, "--format", fmt,
    ]
    proc = subprocess.run(
        cmd, capture_output=True, text=True,
        cwd=PROJECT_ROOT, timeout=180,
    )
    output, stderr = proc.stdout, proc.stderr
    m = re.match(
        r"# static: version=(\d+) size=(\d+) algo=(\d+) compressed=(\d+) pkg_len=(\d+)",
        output,
    )
    if not m:
        return None, None, output, stderr
    header = {
        "version": int(m.group(1)), "size": int(m.group(2)),
        "algo": int(m.group(3)), "compressed": int(m.group(4)),
        "pkg_len": int(m.group(5)),
    }
    rest = output[m.end() + 1:]
    if fmt == "pbm":
        return header, parse_pbm(rest), output, stderr
    return header, rest, output, stderr


def run_batch():
    """Run batch mode, return stdout."""
    proc = subprocess.run(
        ["moon", "run", "cmd/main"],
        capture_output=True, text=True, cwd=PROJECT_ROOT, timeout=180,
    )
    return proc.stdout


def parse_static_blocks(content: str):
    """Parse STATIC_CASE blocks. Returns list of (header, matrix_rows, packed_bytes)."""
    blocks = []
    lines = content.splitlines()
    i = 0
    while i < len(lines):
        if lines[i].startswith("STATIC_CASE "):
            m = re.match(
                r"STATIC_CASE (\S+) data_len=(\d+) ecl=(\w+) version=(\d+) "
                r"size=(\d+) mask=(\d+) algo=(\d+) compressed=(\d+) pkg_len=(\d+)",
                lines[i],
            )
            if m:
                header = {
                    "label": m.group(1), "data_len": int(m.group(2)),
                    "ecl": m.group(3), "version": int(m.group(4)),
                    "size": int(m.group(5)), "mask": int(m.group(6)),
                    "algo": int(m.group(7)), "compressed": int(m.group(8)),
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
                blocks.append((header, matrix, packed))
            else:
                i += 1
        else:
            i += 1
    return blocks


def decode_with_zxing(img: np.ndarray):
    res = zxingcpp.read_barcodes(img, return_errors=True)
    qr_bars = [
        b for b in res
        if not isinstance(b, zxingcpp.Error) and str(b.format) == "QR Code"
    ]
    return qr_bars[0].bytes if qr_bars else None


# ---------- Data generators ----------

def gen_printable(n: int, seed: int = 12345) -> str:
    chars = []
    s = seed
    for _ in range(n):
        s = (s * 1103515245 + 12345) & 0x7FFFFFFF
        chars.append(chr(32 + (s >> 16) % 95))
    return "".join(chars)


# ---------- Main ----------

def main() -> int:
    print("=" * 70)
    print("QRFlux Static Pipeline - Edge Case Verification")
    print("=" * 70)
    print()

    # Pre-run batch once for all-zero / all-0xFF cases (CLI --text cannot
    # transmit null bytes or invalid UTF-8, so we use batch STATIC_CASE blocks
    # which carry the 0/1 matrix + PACKED hex, then render to image here).
    print("Pre-running batch mode for binary edge cases (all-zero, all-0xFF)...")
    t0 = time.perf_counter()
    batch_output = run_batch()
    batch_blocks = parse_static_blocks(batch_output)
    print(f"  batch: {len(batch_blocks)} STATIC_CASE blocks ({time.perf_counter() - t0:.1f}s)")
    # Index by label for lookup
    batch_by_label = {h["label"]: (h, m, p) for h, m, p in batch_blocks}
    print()

    results = []

    def verify_text_case(label, text, ecl, expect_success, original_bytes=None):
        """Verify a case using CLI --text."""
        original = original_bytes if original_bytes else text.encode("utf-8")
        print(f"[{label}] text={len(original)}B ecl={ecl} expect={'OK' if expect_success else 'FAIL'}")
        header, img, output, stderr = run_encode_static_text(text, ecl, "pbm")
        if header is None:
            if "Error: data too large" in output:
                if expect_success:
                    print(f"  UNEXPECTED FAIL: too large\n")
                    results.append((label, "FAIL", "unexpected too-large", None))
                else:
                    print(f"  EXPECTED FAIL: data too large\n")
                    results.append((label, "EXPECTED_FAIL", "too large", None))
                return
            print(f"  ENCODE ERROR: {output.strip()[:120]}\n")
            results.append((label, "FAIL", f"encode error: {output.strip()[:60]}", None))
            return
        if not expect_success:
            print(f"  UNEXPECTED OK: V{header['version']} (expected failure)\n")
            results.append((label, "FAIL", "expected failure but succeeded", header))
            return
        decoded = decode_with_zxing(img)
        if decoded is None:
            print(f"  DECODE FAIL: zxing no barcode\n")
            results.append((label, "FAIL", "zxing decode failed", header))
            return
        dec_result = decode_static(decoded)
        if dec_result is None:
            print(f"  UNPACKAGE FAIL\n")
            results.append((label, "FAIL", "unpackage failed", header))
            return
        restored, algo, mode = dec_result
        if restored == original:
            print(f"  OK: V{header['version']} algo={algo} comp={header['compressed']} "
                  f"restored {len(restored)}B\n")
            results.append((label, "OK", None, header))
        else:
            unpg = unpackage(decoded)
            bug = ""
            if unpg and unpg[3] == 1:
                opt = rle_decompress_optimized(unpg[0])
                if opt == original:
                    bug = "RLE simple/optimized mismatch"
                    print(f"  FAIL: RLE bug (simple!=optimized, optimized OK)\n")
            if not bug:
                print(f"  FAIL: expect {len(original)}B got {len(restored)}B\n")
            results.append((label, "FAIL", f"data mismatch {bug}".strip(), header))

    def verify_batch_case(label, batch_label, ecl, original_bytes):
        """Verify a case extracted from batch STATIC_CASE (binary data)."""
        print(f"[{label}] batch={batch_label} original={len(original_bytes)}B ecl={ecl}")
        entry = batch_by_label.get(batch_label)
        if entry is None:
            print(f"  SKIP: batch label '{batch_label}' not found\n")
            results.append((label, "FAIL", f"batch label {batch_label} not found", None))
            return
        header, matrix, packed = entry
        if packed is None:
            print(f"  SKIP: no PACKED line\n")
            results.append((label, "FAIL", "no PACKED line", header))
            return
        print(f"  encode: V{header['version']} algo={header['algo']} "
              f"comp={header['compressed']} pkg={header['pkg_len']}B")
        img = matrix_to_image(matrix)
        decoded = decode_with_zxing(img)
        if decoded is None:
            print(f"  DECODE FAIL: zxing no barcode\n")
            results.append((label, "FAIL", "zxing decode failed", header))
            return
        if decoded != packed:
            diffs = sum(1 for j in range(min(len(packed), len(decoded)))
                       if packed[j] != decoded[j])
            print(f"  FAIL: decoded != packed ({diffs} byte diffs)\n")
            results.append((label, "FAIL", f"decoded!=packed ({diffs} diffs)", header))
            return
        dec_result = decode_static(decoded)
        if dec_result is None:
            print(f"  UNPACKAGE FAIL\n")
            results.append((label, "FAIL", "unpackage failed", header))
            return
        restored, algo, mode = dec_result
        if restored == original_bytes:
            print(f"  OK: restored {len(restored)}B matches\n")
            results.append((label, "OK", None, header))
        else:
            unpg = unpackage(decoded)
            bug = ""
            if unpg and unpg[3] == 1:
                opt = rle_decompress_optimized(unpg[0])
                if opt == original_bytes:
                    bug = "RLE simple/optimized mismatch"
                    print(f"  FAIL: RLE bug (optimized OK, simple mismatch)\n")
            if not bug:
                print(f"  FAIL: expect {len(original_bytes)}B got {len(restored)}B\n")
            results.append((label, "FAIL", f"data mismatch {bug}".strip(), header))

    # --- Edge cases ---

    # 1. Empty data (0 bytes) - encode_static accepts empty (32B header only),
    #   round-trip succeeds (empty -> empty). Not a bug, just a design choice.
    verify_text_case("empty_0B", "", "L", expect_success=True)

    # 2. 1 byte
    verify_text_case("one_byte_1B", "A", "L", expect_success=True)

    # 3. All 0x00 (100 bytes) - via batch (CLI can't transmit null)
    verify_batch_case("all_zero_100B", "s_zero_100_L", "L", bytes([0] * 100))

    # 4. All 0xFF (100 bytes) - via batch (CLI can't transmit invalid UTF-8)
    verify_batch_case("all_ff_100B", "s_ff_100_L", "L", bytes([0xFF] * 100))

    # 5. Pure ASCII text
    verify_text_case("ascii_text", "Hello World", "M", expect_success=True)

    # 6. UTF-8 Chinese
    verify_text_case("utf8_chinese", "你好世界", "M", expect_success=True)

    # 7. Max capacity V1 L (17 bytes raw -> packaged 49B -> needs higher V)
    verify_text_case("max_v1_l_17B", gen_printable(17, seed=42), "L", expect_success=True)

    # 8. Over capacity (2950 bytes -> packaged 2982B > V40 L 2953B)
    verify_text_case("over_capacity_2950B", gen_printable(2950, seed=7), "L",
                     expect_success=False)

    # 9. High repetition 1000 bytes (triggers RLE with extended runs)
    verify_text_case("repeat_A_1000B", "A" * 1000, "L", expect_success=True)

    # 10. Random 2000 bytes (near V10~V11 capacity)
    verify_text_case("random_2000B", gen_printable(2000, seed=99), "M",
                     expect_success=True)

    # --- Summary ---
    print("=" * 70)
    total = len(results)
    ok = sum(1 for r in results if r[1] == "OK")
    expected_fail = sum(1 for r in results if r[1] == "EXPECTED_FAIL")
    fail = sum(1 for r in results if r[1] == "FAIL")
    print(f"SUMMARY: {ok} OK, {expected_fail} EXPECTED_FAIL, {fail} FAIL (total {total})")
    print()
    for r in results:
        label, status, detail, h = r
        ver = f"V{h['version']}" if h else "-"
        algo = h["algo"] if h else "-"
        comp = h["compressed"] if h else "-"
        d = f" - {detail}" if detail else ""
        print(f"  {label:24s} {status:14s} {ver:4s} algo={algo} comp={comp}{d}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
