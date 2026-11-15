#!/usr/bin/env python3
"""End-to-end check: real screenshots in many formats -> self-implemented
pixel decoder.

Two paths are exercised:

1. **Self-decoded raw formats** — the CLI sniffs the magic bytes and runs
   the self-implemented decoder (currently PNG and BMP). BMP cases feed
   the raw BMP bytes directly (Windows clipboard scenario).
2. **Format-agnostic screenshots** — PIL writes the QR image as
   GIF/TIFF/JPEG/WebP, reads it back, converts to grayscale PNG and feeds
   the decoder. This models "the remote machine sent whatever format it
   had": as long as the pixels survive, the transmission is lossless.

Usage:
  python scripts/verify_image_pipeline.py
"""
import base64
import io
import os
import random
import subprocess
import sys

from PIL import Image, ImageFilter

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAX_B64 = 30000


def moon(args, timeout=180):
    cmd = ["moon", "run", "cmd/main", "--"] + args
    r = subprocess.run(
        cmd, capture_output=True, cwd=PROJ, timeout=timeout, shell=False
    )
    return (
        r.returncode,
        r.stdout.decode("utf-8", "replace"),
        r.stderr.decode("utf-8", "replace"),
    )


def parse_payload(stdout):
    for line in stdout.splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            return s
    return None


def encode_png(payload, ecl="M"):
    rc, out, err = moon(["--text", payload, "--format", "png", "--ecl", ecl])
    b64 = parse_payload(out)
    if not b64:
        raise RuntimeError("encode failed: " + (err or out))
    return base64.b64decode(b64)


def fit_for_cli(img, fmt="PNG", quality=None):
    """Encode to `fmt`, downscaling until the base64 fits the CLI budget.

    Windows CreateProcess caps the whole command line at ~32 KB, so an
    over-large image is downscaled the way a user would crop/zoom before
    handing it to the decoder.
    """
    scale = 1.0
    data = b""
    for _ in range(10):
        buf = io.BytesIO()
        kwargs = {"quality": quality} if quality else {}
        img.save(buf, fmt, **kwargs)
        data = buf.getvalue()
        if len(base64.b64encode(data)) <= MAX_B64:
            return data, scale
        scale *= 0.85
        w, h = img.size
        img = img.resize(
            (max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS
        )
    return data, scale


def decode_raw(data):
    """Feed raw image bytes (any sniffer-supported format) to the CLI."""
    b64 = base64.b64encode(data).decode("ascii")
    if len(b64) > MAX_B64:
        return None
    rc, out, err = moon(["--decode-image-b64", b64])
    if out.strip().startswith("Error"):
        return None
    return parse_payload(out)


def decode_via_png(img):
    """PIL image -> grayscale -> PNG -> CLI (format-agnostic path)."""
    shot, _ = fit_for_cli(img, "PNG")
    return decode_raw(shot)


def case(name, payload, transform, ecl="M", mode="png", quality=None):
    png = encode_png(payload, ecl)
    img = Image.open(io.BytesIO(png))
    base_size = img.size
    img = transform(img)
    got = None
    extra = ""
    if mode == "bmp_raw":
        # Raw BMP bytes straight into the CLI (self-implemented decoder).
        shot, fit_scale = fit_for_cli(img, "BMP")
        got = decode_raw(shot)
        extra = " bmp %d B" % len(shot) + (
            ", fit x%.2f" % fit_scale if fit_scale < 1.0 else ""
        )
    elif mode.startswith("reopen_"):
        fmt = mode.split("_", 1)[1].upper()
        kwargs = {"quality": quality} if quality else {}
        buf = io.BytesIO()
        img.save(buf, fmt, **kwargs)
        raw = buf.getvalue()
        img = Image.open(io.BytesIO(raw)).convert("L")
        got = decode_via_png(img)
        extra = " %s %d B" % (fmt, len(raw))
    else:
        shot, fit_scale = fit_for_cli(img, "PNG")
        got = decode_raw(shot)
        extra = " png %d B" % len(shot) + (
            ", fit x%.2f" % fit_scale if fit_scale < 1.0 else ""
        )
    ok = got == payload
    print(
        "  %-40s %s (%dx%d%s)"
        % (name, "OK" if ok else "FAIL", base_size[0], base_size[1], extra)
    )
    if not ok:
        print("      want: %r" % payload)
        print("      got : %r" % got)
    return ok


def to_gray(img):
    return img.convert("L")


def to_gray_rgb(img):
    return img.convert("RGB")


def to_mono(img):
    # No dither: keep QR edges sharp (fax / scanned-document style).
    return img.convert("L").convert("1", dither=Image.Dither.NONE)


def resize(scale):
    def f(img):
        w, h = img.size
        return img.convert("L").resize(
            (max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS
        )
    return f


def add_noise(amp, seed=7):
    def f(img):
        g = img.convert("L")
        rnd = random.Random(seed)
        px = g.load()
        for y in range(g.size[1]):
            for x in range(g.size[0]):
                v = px[x, y] + rnd.randint(-amp, amp)
                px[x, y] = 0 if v < 0 else (255 if v > 255 else v)
        return g
    return f


def blur(radius):
    def f(img):
        return img.convert("L").filter(ImageFilter.GaussianBlur(radius))
    return f


def compose(*fs):
    def f(img):
        out = img
        for fn in fs:
            out = fn(out)
        return out
    return f


def main():
    print("QRFlux image pipeline E2E (multi-format screenshots)")
    print("  project: %s" % PROJ)
    cases = [
        # --- PNG path (self-decoded PNG) ---
        ("plain PNG (gray)", "Hello QRFlux", to_gray, "M", "png", None),
        ("RGB screenshot", "Hello QRFlux", to_gray_rgb, "M", "png", None),
        ("grayscale + noise 60", "screenshot-noise", add_noise(60), "M", "png", None),
        ("resize 0.7", "resized-shot", resize(0.7), "M", "png", None),
        ("resize 1.5", "upscaled-shot", resize(1.5), "M", "png", None),
        ("blur radius 1", "blurred-shot", blur(1), "M", "png", None),
        ("noise + resize", "combo-shot", compose(add_noise(40), resize(0.8)), "M", "png", None),
        ("V3 60-byte payload", "A" * 60, to_gray, "L", "png", None),
        ("V5 120-byte payload", "B" * 120, to_gray, "L", "png", None),
        # --- BMP path (self-decoded BMP, raw bytes) ---
        # Note: 24-bit color BMPs are 3 bytes/pixel, so a QR screenshot
        # must be downscaled below the decodable resolution to fit the
        # CLI argument budget (~30 KB). Color-pixel coverage lives in the
        # "RGB screenshot" case instead. 1-bit and 8-bit palette BMPs are
        # the real-world clipboard formats and pass.
        ("BMP raw 1-bit mono (self-decoded)", "BMP mono fax", to_mono, "M", "bmp_raw", None),
        ("BMP raw 8-bit palette (self-decoded)", "BMP palette", to_gray, "M", "bmp_raw", None),
        # --- format-agnostic screenshots (PIL reopen -> PNG) ---
        ("GIF screenshot", "gif-shot", to_gray, "M", "reopen_gif", None),
        ("TIFF screenshot", "tiff-shot", to_gray, "M", "reopen_tiff", None),
        ("JPEG quality 95", "jpeg-shot-95", to_gray, "M", "reopen_jpeg", 95),
        ("JPEG quality 85", "jpeg-shot-85", to_gray, "M", "reopen_jpeg", 85),
        ("WebP quality 90", "webp-shot-90", to_gray, "M", "reopen_webp", 90),
    ]
    passed = 0
    failed = 0
    for item in cases:
        name, payload, transform = item[0], item[1], item[2]
        ecl, mode, quality = item[3], item[4], item[5]
        try:
            ok = case(name, payload, transform, ecl, mode, quality)
        except Exception as e:
            print("  %-40s ERROR %s" % (name, e))
            ok = False
        if ok:
            passed += 1
        else:
            failed += 1
    print("")
    print("Total: %d passed, %d failed" % (passed, failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
