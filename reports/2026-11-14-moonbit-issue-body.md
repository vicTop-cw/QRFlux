## Summary

The same source produces different results depending on the **build context**: a `foreign_library` package built for the `js` backend returns **wrong results silently**, while `moon test --target js` and the native build of the identical code are correct.

The wrong result is not an error — it is a JSON envelope reporting `ok:true` with a corrupted payload (length correct, contents wrong).

## Environment

- moon `0.1.20261104 (940aa18 2026-11-04)`
- moonc `v0.10.20+65efd5b93`
- Node `v24.14.0`
- Windows `10.0.26200`
- Repo: `https://github.com/vicTop-cw/QRFlux` @ `f520304`

## Reproduction

```sh
git clone https://github.com/vicTop-cw/QRFlux
cd QRFlux
moon build --target js
node scripts/repro_wasm_export_issue.cjs   # exits 1 when the issue reproduces
```

Output (deterministic):

```
expected payload hex : 4869            ("Hi")
native CLI (correct) : Hi
js artifact (foreign): 52565457        <-- wrong, no error signalled
```

The artifact under test is the `foreign_library` package `src/wasmapi` (see `src/wasmapi/moon.pkg`), which exports
`qrflux_decode_image_png(base64Png) -> String` via `#export_name`, and internally calls into
`src/web` → `src/qr`:

`base64 decode → PNG decode (zlib via core/compress/zlib) → Otsu binarize → finder localization → affine/perspective resample → QR payload`

## Where it diverges (step-by-step instrumentation)

| Step | Expected | Observed in the foreign_library js artifact |
|---|---|---|
| base64 → PNG bytes | PNG signature `0x89` | `first=137` — correct |
| PNG → grayscale | 290×290 | 290×290 — correct |
| grayscale → payload | `4869` | `52565457` — **wrong** |

## Individually verified correct *inside the same artifact*

| Probe | Result |
|---|---|
| traversal of a 14784-char string, in-package and cross-package | identical to the JS side |
| 11088 Buffer writes, byte-by-byte verified | `bad=0` |
| pure arithmetic via a cross-package call | correct |
| in-package base64 decode (the same logic, compiled *inside* the foreign_library package) | byte-exact (PNG signature OK) |
| same code under `moon test --target js` (1323 tests incl. PNG roundtrip and perspective) | all pass |
| same code, native (CLI `--decode-image-b64`) | correct |

Also ruled out: `--release` optimization (identical in a debug build), the standard library base64 decoder (a local re-implementation behaves the same), iterator vs. indexed access, and short cross-package calls.

## Suspected cause

A code-generation / build-context difference for the `js` backend when the consuming package is a `foreign_library`. The failing step is `decode_from_pixels` (or its transitive callees) inside `src/qr`; every input reaching it is proven correct.

## Notes

I could not reduce this to a smaller standalone case. The repo/commit above is the smallest reproduction I have, and the repro script is deterministic. Happy to run further instrumentation or share the generated `.js` artifact.
