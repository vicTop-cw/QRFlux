// GF(256) boundary polish tests (blackbox).
// 边界与薄弱点覆盖：乘法表一致性、特征 2 加法、费马逆元、幂恒等、
// rs_compute_divisor 首项 monic、rs_compute_remainder 余式次数、
// 多项式乘法/求值辅助、RS 编码往返与差错检测、QR 端到端往返。
// 仅调用 src/qr 的 pub fn；辅助函数本文件内私有。
// GF(256) 加法即 XOR（特征 2），逆元用费马小定理 x^254（因 x^255=1）。

///|
/// Helper: 从 Array 构造 FixedArray[Int32]。
fn gbp_mk(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Helper: 比较两个 FixedArray[Int32] 是否相等。
fn gbp_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Helper: 检查 FixedArray 是否全 0。
fn gbp_is_zero(a : FixedArray[Int32]) -> Bool {
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != 0 {
      return false
    }
  }
  true
}

///|
/// Helper: 多项式乘法，系数从高到低（与 rs_compute_divisor 约定一致）。
/// a[0] 为最高次系数。返回 c，c[0] 为最高次，c.length = a.length + b.length - 1。
fn gbp_poly_mul(
  a : FixedArray[Int32],
  b : FixedArray[Int32],
) -> FixedArray[Int32] {
  let la = a.length()
  let lb = b.length()
  let lc = la + lb - 1
  let c = FixedArray::make(lc, 0)
  for i = 0; i < la; i = i + 1 {
    for j = 0; j < lb; j = j + 1 {
      let k = i + j
      c[k] = c[k] ^ @qr.gf_mul(a[i], b[j])
    }
  }
  c
}

///|
/// Helper: 多项式求值（Horner 法），系数从高到低，poly[0] 为最高次。
fn gbp_poly_eval(poly : FixedArray[Int32], x : Int32) -> Int32 {
  let n = poly.length()
  if n == 0 {
    return 0
  }
  let mut result = poly[0]
  for i = 1; i < n; i = i + 1 {
    result = @qr.gf_mul(result, x) ^ poly[i]
  }
  result
}

///|
/// Helper: 拼接两个 FixedArray（data ++ ecc）。
fn gbp_concat(
  a : FixedArray[Int32],
  b : FixedArray[Int32],
) -> FixedArray[Int32] {
  let la = a.length()
  let lb = b.length()
  let c = FixedArray::make(la + lb, 0)
  for i = 0; i < la; i = i + 1 {
    c[i] = a[i]
  }
  for i = 0; i < lb; i = i + 1 {
    c[la + i] = b[i]
  }
  c
}

///|
/// 乘法边界角点：0×0=0、0×255=0、255×0=0、1×1=1、1×255=255、255×255 封闭。
test "gf256 boundary polish: mul corner values" {
  assert_true(@qr.gf_mul(0, 0) == 0)
  assert_true(@qr.gf_mul(0, 255) == 0)
  assert_true(@qr.gf_mul(255, 0) == 0)
  assert_true(@qr.gf_mul(1, 1) == 1)
  assert_true(@qr.gf_mul(1, 255) == 255)
  assert_true(@qr.gf_mul(255, 1) == 255)
  let r = @qr.gf_mul(255, 255)
  assert_true(r >= 0 && r < 256)
  // 2*128 = 29 (alpha^1 * alpha^7 = alpha^8 = 0x1D，归约 0x11D)
  assert_true(@qr.gf_mul(2, 128) == 29)
}

///|
/// 全 256×256 乘法表封闭性：任意 a,b ∈ GF(256)，gf_mul(a,b) ∈ 0..255。
test "gf256 boundary polish: mul table closed full sweep" {
  for a = 0; a < 256; a = a + 1 {
    for b = 0; b < 256; b = b + 1 {
      let r = @qr.gf_mul(a, b)
      assert_true(r >= 0 && r < 256)
    }
  }
}

///|
/// 乘法表非零行是 1..255 的置换：固定 a≠0，映射 b→a*b 是双射（无重复）。
/// 这是 x×x^(-1)=1 的群论推论：GF(256)* 是 255 阶循环群。
test "gf256 boundary polish: mul table nonzero rows are permutations" {
  for a = 1; a < 256; a = a + 1 {
    let seen = FixedArray::make(256, false)
    for b = 0; b < 256; b = b + 1 {
      let r = @qr.gf_mul(a, b)
      assert_true(r >= 0 && r < 256)
      assert_true(seen[r] == false)
      seen[r] = true
    }
  }
}

///|
/// 加法/减法边界（特征 2，加法即 XOR）：x+x=0、x+0=x、x-x=0。
test "gf256 boundary polish: add sub characteristic 2" {
  for x = 0; x < 256; x = x + 1 {
    assert_true((x ^ x) == 0) // x+x=0
    assert_true((x ^ 0) == x) // x+0=x
    assert_true((x ^ x) == 0) // x-x=0（减法同加法）
  }
  // 边界角点
  assert_true((255 ^ 255) == 0)
  assert_true((128 ^ 128) == 0)
  assert_true((1 ^ 1) == 0)
  // x+1 ≠ x（1 不是加法单位元，0 才是）
  assert_true((0x53 ^ 1) != 0x53)
  // 加法逆元即自身：x + x = 0 → -x = x
  for x = 0; x < 256; x = x + 1 {
    assert_true((x ^ x) == 0)
  }
}

///|
/// 加法结合律与交换律（XOR）：(a+b)+c=a+(b+c)、a+b=b+a。
test "gf256 boundary polish: add assoc comm" {
  let xs = [0, 1, 2, 0x53, 128, 200, 255]
  for a in xs {
    for b in xs {
      assert_true((a ^ b) == (b ^ a))
      for c in xs {
        assert_true((a ^ b ^ c) == (a ^ (b ^ c)))
      }
    }
  }
}

///|
/// 逆元（费马小定理）：1^(-1)=1，x×x^254=1 对全 1~255 成立。
/// 因 GF(256)* 阶为 255，x^255=1，故 x^(-1)=x^254。
test "gf256 boundary polish: inv via fermat x^254" {
  // 1 的逆是 1
  assert_true(@qr.gf_pow(1, 254) == 1)
  // 全 1~255: x * x^254 == 1
  for x = 1; x < 256; x = x + 1 {
    let inv = @qr.gf_pow(x, 254)
    assert_true(@qr.gf_mul(x, inv) == 1)
    assert_true(inv >= 1 && inv < 256)
  }
}

///|
/// 0 无逆元：全 0~255 中无 y 使 0*y==1（0 是吸收元）。
test "gf256 boundary polish: inv zero has no inverse" {
  for y = 0; y < 256; y = y + 1 {
    assert_true(@qr.gf_mul(0, y) == 0)
  }
}

///|
/// 逆元的对合性：(x^(-1))^(-1)=x。即 inv(inv(x))=x，全 1~255。
test "gf256 boundary polish: inv involution" {
  for x = 1; x < 256; x = x + 1 {
    let inv = @qr.gf_pow(x, 254)
    let invinv = @qr.gf_pow(inv, 254)
    assert_true(invinv == x)
  }
}

///|
/// 幂运算 Fermat：x^256=x 对全 0~255 成立（含 0：0^256=0）。
/// 因 x^255=1（x≠0），故 x^256=x；对 0，0^n=0 (n>=1)。
test "gf256 boundary polish: pow 256 equals x fermat" {
  for x = 0; x < 256; x = x + 1 {
    assert_true(@qr.gf_pow(x, 256) == x)
  }
}

///|
/// 幂运算边界：x^0=1（含 x=0 约定）、x^1=x、0^n=0 (n>=1)。
test "gf256 boundary polish: pow 0 and 1 boundary" {
  for x = 0; x < 256; x = x + 1 {
    assert_true(@qr.gf_pow(x, 0) == 1)
    assert_true(@qr.gf_pow(x, 1) == x)
  }
  // 0^n = 0 for n >= 1
  for n = 1; n < 20; n = n + 1 {
    assert_true(@qr.gf_pow(0, n) == 0)
  }
  // 1^n = 1 for all n
  for n = 0; n < 20; n = n + 1 {
    assert_true(@qr.gf_pow(1, n) == 1)
  }
}

///|
/// rs_compute_divisor degree=1/2/4/8：长度==degree，首项系数隐式=1。
/// 通过构造 codeword g(x)=[1, div...] 验证 remainder==0 来确认 monic。
test "gf256 boundary polish: rs divisor degree 1 2 4 8 monic" {
  for d in [1, 2, 4, 8] {
    let div = @qr.rs_compute_divisor(d)
    assert_true(div.length() == d)
    // 构造 g(x) 完整系数 = [1, div[0], ..., div[d-1]]（首项 1 补回）
    let g = FixedArray::make(d + 1, 0)
    g[0] = 1
    for i = 0; i < d; i = i + 1 {
      g[i + 1] = div[i]
    }
    // g(x) mod divisor == 0 当且仅当首项系数确实是 1
    let rem = @qr.rs_compute_remainder(g, div)
    assert_true(gbp_is_zero(rem))
  }
}

///|
/// rs_compute_divisor 已知值：degree=1 → [1]，degree=2 → [3, 2]。
/// degree=4 用 poly_mul 逐步构造 (x+1)(x+2)(x+4)(x+8) 验证。
test "gf256 boundary polish: rs divisor known values" {
  assert_true(gbp_eq(@qr.rs_compute_divisor(1), gbp_mk([1])))
  assert_true(gbp_eq(@qr.rs_compute_divisor(2), gbp_mk([3, 2])))
  // 根 alpha^i，alpha=2：g_i = (x + alpha^i) = [1, alpha^i]
  let g1 = gbp_mk([1, 1]) // (x + 1)
  let g2 = gbp_mk([1, 2]) // (x + 2)
  let g3 = gbp_mk([1, 4]) // (x + 4)
  let g4 = gbp_mk([1, 8]) // (x + 8)
  let g1234 = gbp_poly_mul(gbp_poly_mul(gbp_poly_mul(g1, g2), g3), g4)
  // g1234 = [1, c3, c2, c1, c0]，divisor 应为 [c3, c2, c1, c0]
  let div4 = @qr.rs_compute_divisor(4)
  assert_true(div4.length() == 4)
  assert_true(g1234[0] == 1) // 首项 monic
  for i = 0; i < 4; i = i + 1 {
    assert_true(g1234[i + 1] == div4[i])
  }
}

///|
/// rs_compute_remainder 余式长度==除式长度（余式次数<除数次数的边界）。
/// 每个余式元素在 0..255 内。
test "gf256 boundary polish: rs remainder length equals divisor" {
  let data = gbp_mk([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  for d in [1, 2, 3, 4, 5, 8] {
    let div = @qr.rs_compute_divisor(d)
    let rem = @qr.rs_compute_remainder(data, div)
    assert_true(rem.length() == div.length())
    for i = 0; i < rem.length(); i = i + 1 {
      assert_true(rem[i] >= 0 && rem[i] < 256)
    }
  }
}

///|
/// rs_compute_remainder 边界：空数据→全 0；单字节数据→手算已知值。
test "gf256 boundary polish: rs remainder empty and single" {
  let empty = FixedArray::make(0, 0)
  let div3 = @qr.rs_compute_divisor(3)
  let rem0 = @qr.rs_compute_remainder(empty, div3)
  assert_true(gbp_is_zero(rem0))
  // 单字节 data=[5]，divisor=[3, 2] (degree 2)
  // result 初始 [0,0]; factor=5^0=5; result[j] ^= gf_mul(div[j], 5)
  let div2 = @qr.rs_compute_divisor(2)
  let single = gbp_mk([5])
  let rem1 = @qr.rs_compute_remainder(single, div2)
  assert_true(rem1.length() == 2)
  assert_true(rem1[0] == @qr.gf_mul(3, 5))
  assert_true(rem1[1] == @qr.gf_mul(2, 5))
}

///|
/// RS 编码往返：codeword = data ++ remainder(data, div) → remainder(codeword, div)==0。
/// 覆盖 "encode → 还原"（无噪声）：编码后的码字是除式的倍式。
test "gf256 boundary polish: rs roundtrip codeword remainder zero" {
  let data = gbp_mk([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])
  for d in [2, 4, 5, 7, 8] {
    let div = @qr.rs_compute_divisor(d)
    let ecc = @qr.rs_compute_remainder(data, div)
    let cw = gbp_concat(data, ecc)
    let rem = @qr.rs_compute_remainder(cw, div)
    assert_true(gbp_is_zero(rem))
  }
}

///|
/// RS 差错检测：对合法 codeword 翻转 1 字节 → remainder != 0。
/// 覆盖 "add noise → 检测"：任意单字节差错都被余式检出。
test "gf256 boundary polish: rs remainder detects single error" {
  let data = gbp_mk([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])
  let div = @qr.rs_compute_divisor(4)
  let ecc = @qr.rs_compute_remainder(data, div)
  let cw = gbp_concat(data, ecc)
  // 原始 codeword 余式为 0
  assert_true(gbp_is_zero(@qr.rs_compute_remainder(cw, div)))
  // 翻转每个位置的每个非零增量，余式必非零
  for pos = 0; pos < cw.length(); pos = pos + 1 {
    for delta in [1, 2, 0x55, 0xFF] {
      let corrupted = FixedArray::make(cw.length(), 0)
      for i = 0; i < cw.length(); i = i + 1 {
        corrupted[i] = cw[i]
      }
      corrupted[pos] = corrupted[pos] ^ delta
      let rem = @qr.rs_compute_remainder(corrupted, div)
      assert_true(gbp_is_zero(rem) == false)
    }
  }
}

///|
/// 多项式乘法辅助一致性：(x+1)(x+2)=x^2+3x+2=[1,3,2]；与 rs_compute_divisor(2) 一致。
test "gf256 boundary polish: poly mul helper sanity" {
  let g1 = gbp_mk([1, 1]) // x+1
  let g2 = gbp_mk([1, 2]) // x+2
  let prod = gbp_poly_mul(g1, g2)
  assert_true(gbp_eq(prod, gbp_mk([1, 3, 2])))
  // 与 rs_compute_divisor(2) 一致
  let div2 = @qr.rs_compute_divisor(2)
  assert_true(div2[0] == prod[1] && div2[1] == prod[2])
  // 乘以常数 1 不变
  let one = gbp_mk([1])
  assert_true(gbp_eq(gbp_poly_mul(g1, one), g1))
  // 乘以 0 得 0 多项式（长度 la+1-1=la，全 0）
  let zero = gbp_mk([0])
  let prodz = gbp_poly_mul(g1, zero)
  assert_true(prodz.length() == 2)
  assert_true(gbp_is_zero(prodz))
}

///|
/// 多项式求值：g(x) 在其根处求值为 0。rs_compute_divisor(d) 的根是 alpha^0..alpha^(d-1)。
test "gf256 boundary polish: poly eval roots are zero" {
  for d in [1, 2, 3, 4, 5, 8] {
    let div = @qr.rs_compute_divisor(d)
    // 完整 g(x) 系数 = [1, div...]
    let g = FixedArray::make(d + 1, 0)
    g[0] = 1
    for i = 0; i < d; i = i + 1 {
      g[i + 1] = div[i]
    }
    // 根 alpha^i，alpha=2
    let mut root = 1
    for i = 0; i < d; i = i + 1 {
      let v = gbp_poly_eval(g, root)
      assert_true(v == 0)
      root = @qr.gf_mul(root, 2)
    }
  }
}

///|
/// 多项式求值 Horner 一致性：poly_eval([a,b,c], x) = a*x^2 + b*x + c。
/// 对全 256 个 x 验证 Horner 法与直接展开结果一致。
test "gf256 boundary polish: poly eval horner consistency" {
  // poly = [2, 3, 5] 表示 2*x^2 + 3*x + 5
  let poly = gbp_mk([2, 3, 5])
  for x = 0; x < 256; x = x + 1 {
    let direct = @qr.gf_mul(@qr.gf_pow(x, 2), 2) ^ @qr.gf_mul(x, 3) ^ 5
    let horner = gbp_poly_eval(poly, x)
    assert_true(direct == horner)
  }
}

///|
/// GF(256) 端到端往返：encode_binary → decode_from_qrcode → 还原数据。
/// 间接验证 RS 编解码在 QR 管线中的正确性（覆盖 encode → decode → 还原）。
test "gf256 boundary polish: qr encode decode roundtrip" {
  let data = gbp_mk([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello"
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(gbp_eq(d, data))
}
