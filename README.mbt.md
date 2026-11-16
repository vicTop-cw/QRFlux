# QRFlux

Pure MoonBit QR-code lossless file transfer — compress, split, dynamic QR
stream, scan, reassemble, verify. Zero third-party dependencies.

[https://github.com/vicTop-cw/QRFlux](https://github.com/vicTop-cw/QRFlux)

## What it does

- **QR encoder** — v1–v40, all four ECC levels (L/M/Q/H), byte mode
- **QR decoder** — v1–v40, all modes, matrix entry
- **Image entry** — screenshots/pixels → module matrix: Otsu binarization,
  finder localization, affine resampling, perspective correction (V2+)
- **PNG / BMP file decode** — self-implemented chunk parsing, unfiltering,
  bit-depth & color expansion
- **Static pipeline** — RLE compression + binary packaging for small files
- **Dynamic stream** — large files split into QR frames with LT fountain
  codes; out-of-order and lost-frame recovery
- **Colored QR** — 4-color, 2 bits/module lossless codec (experimental)

## Verification

- 1332/1332 tests (`moon test --target js`)
- 165/165 cross-validated against zxing-cpp (all versions × ECC × modes)
- 16/16 multi-format screenshot E2E (PNG/BMP/GIF/TIFF/JPEG/WebP)

See the repository for full docs, CLI usage and the web demo.
