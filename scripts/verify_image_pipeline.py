#!/usr/bin/env python3
"""End-to-end check: real PNG screenshot -> self-implemented pixel decoder.

Flow:
  1. encode a payload to a PNG via the moon CLI (QRFlux's own encoder)
  2. simulate a screenshot with PIL: grayscale, resize, gaussian blur, noise
  3. base64 the PNG and decode it with the moon CLI --decode-image-b64
     (Otsu binarization + finder localization + affine resample + decode)
  4. compare the decoded payload with the original

This exercises the full "remote machine shows a QR image, local side
decodes the screenshot" loop with zero external image libraries in the
MoonBit pipeline. Note PIL writes standard dynamically-compressed PNGs,
so this also checks the decoder against non-stored zlib streams.

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


def moon(args, timeout=180):
    """Run the moon CLI with args; return (rc, stdout, stderr)."""
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
    """Extract the payload line from CLI output (skip '#' comment lines)."""
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


MAX_B64 = 28000


def fit_for_cli(img):
    """Encode to PNG, downscaling until the base64 fits the CLI budget.

    Windows command lines cap out around 32 KB, so an over-large PNG
    (e.g. a noisy screenshot) is downscaled like a user would crop/zoom
    before handing it to the decoder.
    """
    scale = 1.0
    data = b""
    for _ in range(10):
        buf = io.BytesIO()
        img.save(buf, "PNG")
        data = buf.getvalue()
        if len(base64.b64encode(data)) <= MAX_B64:
            return data, scale
        scale *= 0.85
        w, h = img.size
        img = img.resize(
            (max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS
        )
    return data, scale


def decode_png(png_bytes):
    b64 = base64.b64encode(png_bytes).decode("ascii")
    if len(b64) > MAX_B64:
        return None
    rc, out, err = moon(["--decode-image-b64", b64])
    if out.strip().startswith("Error"):
        return None
    return parse_payload(out)


def case(name, payload, transform, ecl="M"):
    png = encode_png(payload, ecl)
    img = Image.open(io.BytesIO(png))
    base_size = img.size
    img = transform(img)
    shot, fit_scale = fit_for_cli(img)
    got = decode_png(shot)
    ok = got == payload
    print(
        "  %-34s %s  (%dx%d -> %dx%d, png %d B%s)"
        % (
            name,
            "OK" if ok else "FAIL",
            base_size[0],
            base_size[1],
            img.size[0],
            img.size[1],
            len(shot),
            "" if fit_scale >= 1.0 else ", fit x%.2f" % fit_scale,
        )
    )
    if not ok:
        print("      want: %r" % payload)
        print("      got : %r" % got)
    return ok


def to_gray(img):
    return img.convert("L")


def to_gray_rgb(img):
    return img.convert("RGB")


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
    print("QRFlux image pipeline E2E (real PNG screenshots)")
    print("  project: %s" % PROJ)
    cases = [
        ("plain PNG (gray)", "Hello QRFlux", to_gray),
        ("RGB screenshot", "Hello QRFlux", to_gray_rgb),
        ("grayscale + noise 60", "screenshot-noise", add_noise(60)),
        ("resize 0.7", "resized-shot", resize(0.7)),
        ("resize 1.5", "upscaled-shot", resize(1.5)),
        ("blur radius 1", "blurred-shot", blur(1)),
        ("noise + resize", "combo-shot", compose(add_noise(40), resize(0.8))),
        ("V3 60-byte payload", "A" * 60, to_gray, "L"),
        ("V5 120-byte payload", "B" * 120, to_gray, "L"),
    ]
    passed = 0
    failed = 0
    for item in cases:
        name, payload, transform = item[0], item[1], item[2]
        ecl = item[3] if len(item) > 3 else "M"
        try:
            ok = case(name, payload, transform, ecl)
        except Exception as e:
            print("  %-34s ERROR %s" % (name, e))
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
