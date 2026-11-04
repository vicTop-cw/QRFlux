"""Dynamic stream end-to-end verification.

Validates the full dynamic pipeline:
  data -> compress -> split_into_frames -> encode_binary (per frame) -> QR matrix
  -> zxing-cpp decode -> reassemble -> decompress -> restored data

Usage:
  python scripts/verify_dynamic.py [batch_file]

If batch_file is not given, automatically runs `moon run e2e_probe` to generate
dynamic_batch.txt in the project root, then verifies it.

Each DYNAMIC_CASE block contains:
  DYNAMIC_CASE label=<...> data_len=N ecl=X rle=0/1 comp_len=N frames=K max_payload=P
  ORIG_HEX <hex>
  COMP_HEX <hex>
  FRAME idx=I version=V size=S mask=M frame_len=L
  FRAME_HEX <hex>
  <matrix rows of 0/1>
  ...
  END_CASE
"""
import sys
import os
import re
import time
import subprocess

import numpy as np
import zxingcpp
from PIL import Image

SCALE = 10
QUIET = 8
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def matrix_to_image(rows):
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


def decode_qr(matrix):
    res = zxingcpp.read_barcodes(matrix_to_image(matrix), return_errors=True)
    qr_bars = [
        b
        for b in res
        if not isinstance(b, zxingcpp.Error) and str(b.format) == "QR Code"
    ]
    return qr_bars[0].bytes if qr_bars else None


def crc16(data):
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def parse_frame_header(b):
    if len(b) < 16:
        return None
    if b[0:4] != b"\x51\x52\x46\x4c":
        return None
    if b[4] != 1:
        return None
    return {
        "total_frames": (b[5] << 8) | b[6],
        "current_frame": (b[7] << 8) | b[8],
        "data_length": (b[9] << 24) | (b[10] << 16) | (b[11] << 8) | b[12],
        "checksum": (b[13] << 8) | b[14],
    }


def reassemble_frames(frame_bytes_list):
    frames = []
    for idx, fb in enumerate(frame_bytes_list):
        if fb is None:
            return None, f"frame {idx} is None (QR decode failed)"
        hdr = parse_frame_header(fb)
        if hdr is None:
            return None, f"frame {idx} header parse failed"
        frames.append((hdr, fb[16:]))
    frames.sort(key=lambda f: f[0]["current_frame"])
    for i, (hdr, _) in enumerate(frames):
        if hdr["current_frame"] != i:
            return None, f"frame index gap at {i}: got {hdr['current_frame']}"
    data = b"".join(p for _, p in frames)
    expected_len = frames[0][0]["data_length"]
    if len(data) != expected_len:
        return None, f"length mismatch: {len(data)} != {expected_len}"
    expected_crc = frames[0][0]["checksum"]
    actual_crc = crc16(data)
    if actual_crc != expected_crc:
        return None, f"crc16 mismatch: {actual_crc:#06x} != {expected_crc:#06x}"
    return data, None


def rle_decompress_optimized(data):
    result = bytearray()
    i = 0
    while i < len(data):
        if data[i] == 255:
            if i + 3 >= len(data):
                break
            count = (data[i + 1] << 8) | data[i + 2]
            value = data[i + 3]
            result.extend(bytes([value]) * count)
            i += 4
        else:
            if i + 1 >= len(data):
                break
            count = data[i]
            value = data[i + 1]
            result.extend(bytes([value]) * count)
            i += 2
    return bytes(result)


def rle_decompress_buggy(data):
    """Matches MoonBit strategy.mbt rle_decompress (ignores 255 marker)."""
    result = bytearray()
    i = 0
    while i < len(data):
        if i + 1 >= len(data):
            break
        count = data[i]
        value = data[i + 1]
        result.extend(bytes([value]) * count)
        i += 2
    return bytes(result)


def parse_batch(content):
    lines = content.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("DYNAMIC_CASE "):
            m = re.match(
                r"DYNAMIC_CASE label=(\S+) data_len=(\d+) ecl=(\w+) rle=(\d+) "
                r"comp_len=(\d+) frames=(\d+) max_payload=(\d+)",
                line,
            )
            if not m:
                i += 1
                continue
            case = {
                "label": m.group(1),
                "data_len": int(m.group(2)),
                "ecl": m.group(3),
                "rle": int(m.group(4)),
                "comp_len": int(m.group(5)),
                "frames": int(m.group(6)),
                "max_payload": int(m.group(7)),
                "orig_hex": "",
                "comp_hex": "",
                "frame_list": [],
            }
            i += 1
            while i < len(lines) and lines[i] != "END_CASE":
                if lines[i].startswith("ORIG_HEX "):
                    case["orig_hex"] = lines[i][9:]
                    i += 1
                elif lines[i].startswith("COMP_HEX "):
                    case["comp_hex"] = lines[i][9:]
                    i += 1
                elif lines[i].startswith("FRAME "):
                    fm = re.match(
                        r"FRAME idx=(\d+) version=(\d+) size=(\d+) "
                        r"mask=(\d+) frame_len=(\d+)",
                        lines[i],
                    )
                    if not m:
                        i += 1
                        continue
                    frame = {
                        "idx": int(fm.group(1)),
                        "version": int(fm.group(2)),
                        "size": int(fm.group(3)),
                        "mask": int(fm.group(4)),
                        "frame_len": int(fm.group(5)),
                    }
                    i += 1
                    frame_hex = ""
                    if i < len(lines) and lines[i].startswith("FRAME_HEX "):
                        frame_hex = lines[i][10:]
                        i += 1
                    size = frame["size"]
                    matrix = []
                    while i < len(lines) and len(matrix) < size:
                        row = lines[i]
                        if row and all(c in "01" for c in row):
                            matrix.append(row)
                            i += 1
                        else:
                            break
                    frame["frame_hex"] = frame_hex
                    frame["matrix"] = matrix
                    case["frame_list"].append(frame)
                else:
                    i += 1
            yield case
        i += 1


def generate_batch():
    print("Generating dynamic batch via `moon run e2e_probe` ...")
    for cmd in (["moon", "run", "e2e_probe"], ["moon", "run", "--target", "js", "e2e_probe"]):
        try:
            proc = subprocess.run(
                cmd, capture_output=True, text=True, cwd=PROJECT_ROOT, timeout=300
            )
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
        if proc.returncode == 0 and "DYNAMIC_CASE" in proc.stdout:
            return proc.stdout
        print(f"  cmd {cmd} rc={proc.returncode}")
        if proc.stderr:
            print(f"  stderr: {proc.stderr[:500]}")
    print("ERROR: failed to generate batch. Run `moon run e2e_probe` manually.")
    sys.exit(1)


def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf-8") as f:
            content = f.read()
    else:
        batch_path = os.path.join(PROJECT_ROOT, "dynamic_batch.txt")
        if os.path.exists(batch_path):
            with open(batch_path, encoding="utf-8") as f:
                content = f.read()
        else:
            content = generate_batch()
            with open(batch_path, "w", encoding="utf-8") as f:
                f.write(content)

    cases = list(parse_batch(content))
    if not cases:
        print("No DYNAMIC_CASE blocks found")
        return 1

    print(f"Found {len(cases)} dynamic cases\n")
    print("=" * 70)
    print("Dynamic Stream End-to-End Verification")
    print("=" * 70)

    results = []
    for case in cases:
        label = case["label"]
        print(
            f"\n[{label}] data_len={case['data_len']} ecl={case['ecl']} "
            f"rle={case['rle']} frames={case['frames']}"
        )

        frame_bytes_list = []
        qr_layer_ok = True
        t0 = time.perf_counter()
        for frame in case["frame_list"]:
            got = decode_qr(frame["matrix"])
            expected = bytes.fromhex(frame["frame_hex"])
            if got is None:
                print(f"  FRAME {frame['idx']}: QR decode FAIL (no barcode)")
                qr_layer_ok = False
                frame_bytes_list.append(None)
            elif got != expected:
                print(
                    f"  FRAME {frame['idx']}: QR decode MISMATCH "
                    f"(got {len(got)}B expect {len(expected)}B)"
                )
                qr_layer_ok = False
                frame_bytes_list.append(got)
            else:
                print(
                    f"  FRAME {frame['idx']}: QR OK "
                    f"(V{frame['version']} {len(got)}B)"
                )
                frame_bytes_list.append(got)
        decode_time = time.perf_counter() - t0

        reassemble_ok = False
        reassemble_error = None
        reassembled = None
        if all(fb is not None for fb in frame_bytes_list):
            reassembled, reassemble_error = reassemble_frames(frame_bytes_list)
            reassemble_ok = reassembled is not None
        if reassemble_ok:
            expected_comp = bytes.fromhex(case["comp_hex"])
            if reassembled != expected_comp:
                reassemble_ok = False
                reassemble_error = "reassembled != comp_hex"
                print(
                    f"  REASSEMBLE: MISMATCH vs comp_hex "
                    f"({len(reassembled)}B vs {len(expected_comp)}B)"
                )
            else:
                print(f"  REASSEMBLE: OK ({len(reassembled)}B)")
        else:
            print(f"  REASSEMBLE: FAIL ({reassemble_error})")

        e2e_ok = False
        buggy_note = None
        restored = None
        if reassemble_ok:
            if case["rle"]:
                restored = rle_decompress_optimized(reassembled)
                buggy = rle_decompress_buggy(reassembled)
                if buggy != restored:
                    buggy_note = (
                        f"MoonBit rle_decompress(buggy) -> {len(buggy)}B "
                        f"!= correct {len(restored)}B"
                    )
            else:
                restored = reassembled
            expected_orig = bytes.fromhex(case["orig_hex"])
            if restored == expected_orig:
                e2e_ok = True
                print(f"  E2E: OK (restored {len(restored)}B == original)")
            else:
                print(
                    f"  E2E: MISMATCH (restored {len(restored)}B "
                    f"vs original {len(expected_orig)}B)"
                )
            if buggy_note:
                print(f"  BUG NOTE: {buggy_note}")

        results.append(
            {
                "label": label,
                "data_len": case["data_len"],
                "frames": case["frames"],
                "qr_ok": qr_layer_ok,
                "reassemble_ok": reassemble_ok,
                "e2e_ok": e2e_ok,
                "decode_time": decode_time,
                "reassemble_error": reassemble_error,
                "buggy_note": buggy_note,
            }
        )

    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)
    total = len(results)
    qr_pass = sum(1 for r in results if r["qr_ok"])
    re_pass = sum(1 for r in results if r["reassemble_ok"])
    e2e_pass = sum(1 for r in results if r["e2e_ok"])
    print(f"QR decode layer:     {qr_pass}/{total}")
    print(f"Reassemble layer:    {re_pass}/{total}")
    print(f"End-to-end (E2E):    {e2e_pass}/{total}")
    print("\nPer-case:")
    for r in results:
        print(
            f"  {r['label']:12s} frames={r['frames']:2d} "
            f"qr={'OK' if r['qr_ok'] else 'FAIL'} "
            f"reasm={'OK' if r['reassemble_ok'] else 'FAIL'} "
            f"e2e={'OK' if r['e2e_ok'] else 'FAIL'} "
            f"({r['decode_time']*1000:.0f}ms)"
        )
    if e2e_pass < total:
        print("\nFailed:")
        for r in results:
            if not r["e2e_ok"]:
                print(f"  {r['label']}: {r['reassemble_error'] or 'content mismatch'}")
    return 0 if e2e_pass == total else 1


if __name__ == "__main__":
    sys.exit(main())
