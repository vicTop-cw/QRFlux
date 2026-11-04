"""Compare QRFlux matrix with Python qrcode reference for a failing case."""
import re
import qrcode
import numpy as np
from PIL import Image

SEED = 12345


def gen_rand(seed, n):
    out = []
    for _ in range(n):
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        out.append((seed >> 16) & 0xFF)
    return bytes(out)


def load_qrflux_matrix(label_target):
    with open('batch.txt', encoding='utf-8') as f:
        content = f.read()
    blocks = re.split(r'^CASE ', content, flags=re.M)[1:]
    for blk in blocks:
        lines = blk.strip().splitlines()
        m = re.match(r'(\w+) len=(\d+) ecl=(\w+) version=(\d+) size=(\d+) mask=(\d+)', lines[0])
        if not m:
            continue
        if m.group(1) == label_target:
            size = int(m.group(5))
            rows = lines[1:1 + size]
            mat = np.array([[int(c) for c in r] for r in rows], dtype=np.int8)
            return mat, int(m.group(4)), m.group(3), int(m.group(6)), int(m.group(2))
    return None


def gen_reference(data, version, ecl, mask=None):
    qr = qrcode.QRCode(
        version=version,
        error_correction=getattr(qrcode.constants, 'ERROR_CORRECT_' + ecl),
        box_size=1,
        border=0,
    )
    if mask is not None:
        qr.mask_pattern = mask
    qr.add_data(data)
    qr.make(fit=False)
    # qr.modules is a list of rows, each row is list of True/False (True = dark)
    size = qr.modules_count
    ref = np.zeros((size, size), dtype=np.int8)
    for y in range(size):
        for x in range(size):
            ref[y, x] = 1 if qr.modules[y][x] else 0
    return ref, qr.best_mask_pattern(), qr


def diff_report(a, b):
    """a, b: 2D int8 arrays of same shape. Returns diff mask and stats."""
    diff = (a != b)
    coords = np.argwhere(diff)
    return diff, coords


def main():
    label = 'v8_Q_106'
    flux_mat, ver, ecl, mask, n = load_qrflux_matrix(label)
    print(f'QRFlux: label={label} ver={ver} ecl={ecl} mask={mask} size={flux_mat.shape[0]} n={n}')
    data = gen_rand(SEED, n)
    # Force same mask as QRFlux to isolate data placement issues
    ref_mat, ref_mask, qr = gen_reference(data, ver, ecl, mask=mask)
    print(f'Reference: ver={ver} ecl={ecl} mask={ref_mask} size={ref_mat.shape[0]} (forced mask={mask})')
    print(f'QRFlux mask={mask}, Reference mask={ref_mask}')

    if flux_mat.shape != ref_mat.shape:
        print('SHAPE MISMATCH:', flux_mat.shape, 'vs', ref_mat.shape)
        return

    diff, coords = diff_report(flux_mat, ref_mat)
    print(f'Total diff modules: {len(coords)}')
    if len(coords) > 0:
        # Show first 20 diffs
        print('First 20 diff coords (y, x, flux, ref):')
        for (y, x) in coords[:20]:
            print(f'  ({y:3d},{x:3d}) flux={flux_mat[y,x]} ref={ref_mat[y,x]}')

    # Save both matrices for inspection
    np.savetxt('matrix_flux.txt', flux_mat, fmt='%d', delimiter='')
    np.savetxt('matrix_ref.txt', ref_mat, fmt='%d', delimiter='')

    # Also dump QRFlux codewords via debug? Not available from python; just compare matrices.
    # Check function patterns: finder, timing, alignment, format, version
    size = flux_mat.shape[0]
    # Check finder patterns (3 7x7 corners)
    def finder_ok(mat, ox, oy):
        # 7x7 finder pattern: dark border, light inner, dark 3x3 center
        for dy in range(7):
            for dx in range(7):
                x, y = ox + dx, oy + dy
                border = (dx == 0 or dx == 6 or dy == 0 or dy == 6)
                center = (2 <= dx <= 4 and 2 <= dy <= 4)
                expect = 1 if (border or center) else 0
                if mat[y, x] != expect:
                    return False
        return True
    print('Finder TL flux:', finder_ok(flux_mat, 0, 0), 'ref:', finder_ok(ref_mat, 0, 0))
    print('Finder TR flux:', finder_ok(flux_mat, size - 7, 0), 'ref:', finder_ok(ref_mat, size - 7, 0))
    print('Finder BL flux:', finder_ok(flux_mat, 0, size - 7), 'ref:', finder_ok(ref_mat, 0, size - 7))

    # Check timing patterns (row 6 and col 6, between finders)
    def timing_ok(mat):
        for i in range(8, size - 8):
            if mat[6, i] != (1 - i % 2):
                return False
            if mat[i, 6] != (1 - i % 2):
                return False
        return True
    print('Timing flux:', timing_ok(flux_mat), 'ref:', timing_ok(ref_mat))

    # Check version info (V>=7): two 6x3 blocks at fixed positions
    # Bottom-left: x in [0,5], y in [size-11, size-9]
    # Top-right: x in [size-11, size-9], y in [0,5]
    if ver >= 7:
        def version_info(mat):
            bits_bl = []
            for y in range(size - 11, size - 8):
                for x in range(6):
                    bits_bl.append(mat[y, x])
            bits_tr = []
            for y in range(6):
                for x in range(size - 11, size - 8):
                    bits_tr.append(mat[y, x])
            return bits_bl, bits_tr
        bl_f, tr_f = version_info(flux_mat)
        bl_r, tr_r = version_info(ref_mat)
        print('Version info BL match:', bl_f == bl_r)
        print('Version info TR match:', tr_f == tr_r)
        if bl_f != bl_r:
            print('  BL flux:', bl_f)
            print('  BL ref :', bl_r)

    # Check format info (15 bits, two copies)
    # Just compare the format region modules
    def format_bits_read(mat, mask):
        # Read format bits from first copy (around top-left finder)
        # bits 0-5: (8, 0..5), bit6: (8,7), bit7: (8,8), bit8: (7,8), bits 9-14: (14-i, 8) for i=9..14
        bits = [0] * 15
        for i in range(6):
            bits[i] = mat[i, 8]
        bits[6] = mat[7, 8]
        bits[7] = mat[8, 8]
        bits[8] = mat[8, 7]
        for i in range(9, 15):
            bits[i] = mat[8, 14 - i]
        return bits
    fmt_f = format_bits_read(flux_mat, mask)
    fmt_r = format_bits_read(ref_mat, ref_mask)
    print('Format bits (copy 1) flux:', fmt_f)
    print('Format bits (copy 1) ref :', fmt_r)
    print('Format bits match:', fmt_f == fmt_r)


if __name__ == '__main__':
    main()
