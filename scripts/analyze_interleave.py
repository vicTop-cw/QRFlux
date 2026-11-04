"""Analyze interleave bug: compare QRFlux vs reference codeword sequence."""
import re
import qrcode
import qrcode.base as base
import qrcode.constants as const
import numpy as np

SEED = 12345


def gen_rand(seed, n):
    out = []
    for _ in range(n):
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        out.append((seed >> 16) & 0xFF)
    return bytes(out)


def alignment_pattern_positions(version):
    if version == 1:
        return []
    numalign = version // 7 + 2
    if numalign == 1:
        step = 0
    else:
        step = (version * 8 + numalign * 3 + 5) // (numalign * 4 - 4) * 2
    size = version * 4 + 17
    result = [0] * numalign
    for i in range(numalign - 1):
        result[numalign - 1 - i] = size - 7 - i * step
    result[0] = 6
    return result


def mark_function_modules(version, size):
    isfn = np.zeros((size, size), dtype=bool)
    for i in range(size):
        isfn[6, i] = True
        isfn[i, 6] = True
    for (cx, cy) in [(3, 3), (size - 4, 3), (3, size - 4)]:
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                x, y = cx + dx, cy + dy
                if 0 <= x < size and 0 <= y < size:
                    isfn[y, x] = True
    alignpos = alignment_pattern_positions(version)
    numalign = len(alignpos)
    for i in range(numalign):
        for j in range(numalign):
            skip = (i == 0 and j == 0) or (i == 0 and j == numalign - 1) or (i == numalign - 1 and j == 0)
            if not skip:
                cx, cy = alignpos[i], alignpos[j]
                for dy in range(-2, 3):
                    for dx in range(-2, 3):
                        isfn[cy + dy, cx + dx] = True
    for i in range(9):
        isfn[8, i] = True
        isfn[i, 8] = True
    for i in range(8):
        isfn[size - 1 - i, 8] = True
    for i in range(8):
        isfn[8, size - 1 - i] = True
    if version >= 7:
        for i in range(6):
            for j in range(3):
                isfn[size - 11 + j, i] = True
                isfn[i, size - 11 + j] = True
    return isfn


def mask_pattern(mask, x, y):
    if mask == 0: return (x + y) % 2 == 0
    elif mask == 1: return y % 2 == 0
    elif mask == 2: return x % 3 == 0
    elif mask == 3: return (x + y) % 3 == 0
    elif mask == 4: return (x // 3 + y // 2) % 2 == 0
    elif mask == 5: return x * y % 2 + x * y % 3 == 0
    elif mask == 6: return (x * y % 2 + x * y % 3) % 2 == 0
    else: return ((x + y) % 2 + x * y % 3) % 2 == 0


def extract_codewords(mat, version, mask):
    size = version * 4 + 17
    isfn = mark_function_modules(version, size)
    bits = []
    right = size - 1
    while right >= 1:
        if right <= 6:
            right -= 1
        for vert in range(size):
            for j in range(2):
                x = right - j
                upward = ((right + 1) & 2) == 0
                y = size - 1 - vert if upward else vert
                if not isfn[y, x]:
                    bit = int(mat[y, x])
                    if mask_pattern(mask, x, y):
                        bit = 1 - bit
                    bits.append(bit)
        right -= 2
    codewords = []
    for i in range(0, len(bits) - 7, 8):
        b = 0
        for j in range(8):
            b = (b << 1) | bits[i + j]
        codewords.append(b)
    return codewords, len(bits)


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
        box_size=1, border=0,
    )
    if mask is not None:
        qr.mask_pattern = mask
    qr.add_data(data)
    qr.make(fit=False)
    size = qr.modules_count
    ref = np.zeros((size, size), dtype=np.int8)
    for y in range(size):
        for x in range(size):
            ref[y, x] = 1 if qr.modules[y][x] else 0
    return ref, qr.best_mask_pattern(), qr


def analyze(label, ver, ecl, n):
    print(f'\n=== {label}: V{ver} {ecl} n={n} ===')
    flux_mat, fver, fecl, mask, fn = load_qrflux_matrix(label)
    data = gen_rand(SEED, n)
    ref_mat, ref_mask, _ = gen_reference(data, ver, ecl, mask=mask)

    # Get block structure from qrcode lib
    ecl_val = getattr(const, 'ERROR_CORRECT_' + ecl)
    blocks = base.rs_blocks(ver, ecl_val)
    numblocks = len(blocks)
    total_data = sum(b.data_count for b in blocks)
    total_ecc = sum(b.total_count - b.data_count for b in blocks)
    # short/long block counts
    data_lens = [b.data_count for b in blocks]
    ecc_len = blocks[0].total_count - blocks[0].data_count
    short_data = min(data_lens)
    long_data = max(data_lens)
    num_short = sum(1 for d in data_lens if d == short_data)
    num_long = numblocks - num_short
    print(f'  blocks={numblocks}, ecc_per_block={ecc_len}, short_data={short_data}×{num_short}, long_data={long_data}×{num_long}')
    print(f'  total_data={total_data}, total_ecc={total_ecc}, total={total_data + total_ecc}')
    has_long = num_long > 0
    print(f'  has long blocks: {has_long}  -> bug triggered: {has_long}')

    flux_cw, flux_bits = extract_codewords(flux_mat, ver, mask)
    ref_cw, ref_bits = extract_codewords(ref_mat, ver, mask)
    print(f'  flux: {flux_bits} bits, {len(flux_cw)} codewords')
    print(f'  ref:  {ref_bits} bits, {len(ref_cw)} codewords')

    minlen = min(len(flux_cw), len(ref_cw))
    diffs = [(i, flux_cw[i], ref_cw[i]) for i in range(minlen) if flux_cw[i] != ref_cw[i]]
    print(f'  codeword diffs: {len(diffs)}')
    if diffs:
        print(f'  first diff at index {diffs[0][0]} (expected ~{short_data * numblocks} = short_data×numblocks)')
        # Show first 6 diffs
        for (i, f, r) in diffs[:6]:
            print(f'    cw[{i}]: flux=0x{f:02x} ref=0x{r:02x}')


def main():
    # Analyze all failing cases + a few passing for contrast
    cases = [
        ('v7_Q_84', 7, 'Q', 84),
        ('v8_Q_106', 8, 'Q', 106),
        ('v8_H_82', 8, 'H', 82),
        ('v9_M_178', 9, 'M', 178),
        ('v10_Q_149', 10, 'Q', 149),
        ('v10_H_117', 10, 'H', 117),
        ('v11_M_239', 11, 'M', 239),
        ('v11_H_135', 11, 'H', 135),
        # Passing cases for contrast
        ('v7_L_152', 7, 'L', 152),
        ('v7_M_120', 7, 'M', 120),
        ('v7_H_62', 7, 'H', 62),
        ('v8_M_150', 8, 'M', 150),
        ('v9_Q_128', 9, 'Q', 128),
        ('v9_H_96', 9, 'H', 96),
    ]
    for (label, ver, ecl, n) in cases:
        analyze(label, ver, ecl, n)


if __name__ == '__main__':
    main()
