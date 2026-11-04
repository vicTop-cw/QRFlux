"""Static pipeline real-image round-trip verification.

Validates the full closed loop:
  encode_static -> PBM image -> zxing-cpp decode -> packaged bytes
  -> Python decode_static (unpackage + RLE decompress) -> original data

Usage:
  python scripts/verify_image_roundtrip.py

Prerequisites:
  pip install zxing-cpp Pillow numpy
  moon (MoonBit toolchain, buildable QRFlux project)
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


# ---------- MoonBit-compatible helpers ----------

def crc32_moonbit(data: bytes) -> int:
    """CRC32 matching MoonBit's package.crc32 (poly 0xEDB88320, logical shift)."""
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
    """RLE decompress matching MoonBit's rle_decompress (simple, 2-byte pairs).

    This is what decode_static actually uses. Each pair [count, value] expands
    to count copies of value. Mismatches optimized compress when count >= 255.
    """
    result = bytearray()
    i = 0
    n = len(data)
    while i < n:
        if i + 1 >= n:
            break
        count = data[i]
        value = data[i + 1]
        result.extend(bytes([value]) * count)
        i += 2
    return bytes(result)


def rle_decompress_optimized(data: bytes) -> bytes:
    """RLE decompress matching MoonBit's rle_decompress_optimized.

    Handles extended runs: [255, high, low, value] for count >= 255.
    """
    result = bytearray()
    i = 0
    n = len(data)
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
            count = data[i]
            value = data[i + 1]
            result.extend(bytes([value]) * count)
            i += 2
    return bytes(result)


def unpackage(pkg: bytes):
    """Unpackage matching MoonBit's unpackage_from_header.

    Returns (payload, original_size, compressed, algo) or None.
    """
    if len(pkg) < 32:
        return None
    if pkg[0:4] != b"QRFX":
        return None
    if pkg[4] != 1:
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
    compressed = (flags & 1) != 0
    return payload, original_size, compressed, algo


def decode_static(qr_bytes: bytes):
    """Python equivalent of MoonBit's decode_static.

    Returns (restored_data, algo_id, mode) or None.
    """
    result = unpackage(qr_bytes)
    if result is None:
        return None
    payload, original_size, compressed, algo = result
    if algo == 0:
        return payload, algo, "none"
    elif algo == 1:
        return rle_decompress_simple(payload), algo, "simple"
    else:
        return None


# ---------- PBM parsing ----------

def parse_pbm(pbm_text: str) -> np.ndarray:
    """Parse PBM P1 ASCII format into grayscale numpy array.

    1 (black) -> 0, 0 (white) -> 255.
    """
    lines = pbm_text.strip().split("\n")
    idx = 0
    while idx < len(lines) and not lines[idx].startswith("P1"):
        idx += 1
    if idx >= len(lines):
        raise ValueError("P1 marker not found")
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
    if len(pixels) != w * h:
        raise ValueError(f"Expected {w * h} pixels, got {len(pixels)}")
    arr = np.array(pixels, dtype=np.uint8).reshape(h, w)
    return (1 - arr) * 255


# ---------- CLI runner ----------

def run_encode_static(text: str, ecl: str, fmt: str = "pbm"):
    """Run CLI encode-static. Returns (header, image, output, stderr)."""
    cmd = [
        "moon", "run", "cmd/main", "--",
        "--encode-static", "--text", text,
        "--ecl", ecl, "--format", fmt,
    ]
    proc = subprocess.run(
        cmd, capture_output=True, text=True,
        cwd=PROJECT_ROOT, timeout=180,
    )
    output = proc.stdout
    stderr = proc.stderr
    m = re.match(
        r"# static: version=(\d+) size=(\d+) algo=(\d+) compressed=(\d+) pkg_len=(\d+)",
        output,
    )
    if not m:
        return None, None, output, stderr
    header = {
        "version": int(m.group(1)),
        "size": int(m.group(2)),
        "algo": int(m.group(3)),
        "compressed": int(m.group(4)),
        "pkg_len": int(m.group(5)),
    }
    rest = output[m.end() + 1:]
    if fmt == "pbm":
        img = parse_pbm(rest)
        return header, img, output, stderr
    return header, rest, output, stderr


def decode_with_zxing(img: np.ndarray):
    """Decode QR from image. Returns bytes or None."""
    res = zxingcpp.read_barcodes(img, return_errors=True)
    qr_bars = [
        b for b in res
        if not isinstance(b, zxingcpp.Error) and str(b.format) == "QR Code"
    ]
    return qr_bars[0].bytes if qr_bars else None


# ---------- Test data generators ----------

def gen_printable(n: int, seed: int = 12345) -> str:
    """Generate n printable ASCII characters (32~126), deterministic."""
    chars = []
    s = seed
    for _ in range(n):
        s = (s * 1103515245 + 12345) & 0x7FFFFFFF
        chars.append(chr(32 + (s >> 16) % 95))
    return "".join(chars)


# ---------- Main ----------

def main() -> int:
    print("=" * 70)
    print("QRFlux Static Pipeline - Real Image Round-Trip Verification")
    print("Flow: encode_static -> PBM -> zxing-cpp -> decode_static -> compare")
    print("=" * 70)
    print()

    cases = [
        ("hello_5B",        "Hello",              "M"),
        ("hello_world_11B", "Hello World",        "M"),
        ("random_100B",     gen_printable(100),   "M"),
        ("random_500B",     gen_printable(500),   "M"),
        ("utf8_chinese",    "你好QRFlux",          "M"),
        ("repeat_A_100B",   "A" * 100,            "M"),
    ]

    results = []
    for label, text, ecl in cases:
        original = text.encode("utf-8")
        print(f"[{label}] text={len(original)}B ecl={ecl}")
        t0 = time.perf_counter()
        header, img, output, stderr = run_encode_static(text, ecl, "pbm")
        t_encode = time.perf_counter() - t0
        if header is None:
            print(f"  ENCODE FAIL: {output.strip()[:120]}")
            results.append((label, "FAIL", "encode failed", None, 0, 0, 0))
            print()
            continue
        print(f"  encode: V{header['version']} size={header['size']} "
              f"algo={header['algo']} comp={header['compressed']} "
              f"pkg={header['pkg_len']}B ({t_encode * 1000:.0f}ms)")

        t0 = time.perf_counter()
        decoded = decode_with_zxing(img)
        t_decode = time.perf_counter() - t0
        if decoded is None:
            print(f"  DECODE FAIL: zxing-cpp no barcode ({t_decode * 1000:.0f}ms)")
            results.append((label, "FAIL", "zxing decode failed", header, t_encode, t_decode, 0))
            print()
            continue
        print(f"  zxing: {len(decoded)}B ({t_decode * 1000:.0f}ms)")

        t0 = time.perf_counter()
        dec_result = decode_static(decoded)
        t_unpack = time.perf_counter() - t0
        if dec_result is None:
            print(f"  UNPACKAGE FAIL ({t_unpack * 1000:.0f}ms)")
            results.append((label, "FAIL", "unpackage failed", header, t_encode, t_decode, t_unpack))
            print()
            continue
        restored, algo, mode = dec_result
        if restored == original:
            print(f"  ROUND-TRIP OK: {len(restored)}B restored ({t_unpack * 1000:.0f}ms)")
            results.append((label, "OK", None, header, t_encode, t_decode, t_unpack))
        else:
            unpg = unpackage(decoded)
            bug_note = ""
            if unpg and unpg[3] == 1:
                opt_restored = rle_decompress_optimized(unpg[0])
                if opt_restored == original:
                    bug_note = " (RLE bug: simple!=optimized, optimized OK)"
                    print(f"  ROUND-TRIP FAIL{bug_note}")
                    print(f"    BUG: decode_static uses rle_decompress (simple) but")
                    print(f"         encode uses rle_compress_optimized (extended runs)")
            if not bug_note:
                print(f"  ROUND-TRIP FAIL: expect {len(original)}B got {len(restored)}B")
            results.append((label, "FAIL", f"data mismatch{bug_note}", header, t_encode, t_decode, t_unpack))
        print()

    print("=" * 70)
    total = len(results)
    passed = sum(1 for r in results if r[1] == "OK")
    failed = total - passed
    print(f"SUMMARY: {passed}/{total} passed, {failed} failed")
    print()
    for r in results:
        label, status, detail, h, te, td, tu = r
        ver = f"V{h['version']}" if h else "?"
        algo = h["algo"] if h else "?"
        comp = h["compressed"] if h else "?"
        d = f" - {detail}" if detail else ""
        print(f"  {label:20s} {status:5s} {ver:4s} algo={algo} comp={comp} "
              f"enc={te * 1000:.0f}ms dec={td * 1000:.0f}ms unpack={tu * 1000:.0f}ms{d}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
