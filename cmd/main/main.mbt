/// Batch cross-validation: emit several QR matrices for external decoding.
fn main {
  // (label, byte length, ECC level name)
  let cases : Array[(String, Int, String)] = [
    ("a", 10, "L"),
    ("b", 10, "M"),
    ("c", 10, "H"),
    ("d", 30, "L"),
    ("e", 30, "Q"),
    ("f", 100, "M"),
    ("g", 200, "L"),
    ("h", 300, "L"),
    ("i", 2900, "L"),  // V40 Low
  ]
  for c in cases {
    let (label, len, ecl) = c
    let data = FixedArray::make(len, 0)
    // deterministic pseudo-random bytes
    let mut seed = 12345
    for i = 0; i < len; i = i + 1 {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
      data[i] = (seed >> 16) & 0xFF
    }
    let level = match ecl {
      "L" => @qr.ecc_low()
      "M" => @qr.ecc_medium()
      "Q" => @qr.ecc_quartile()
      _ => @qr.ecc_high()
    }
    let qr = @qr.encode_binary(data, level, 1)
    println("CASE " + label + " len=" + len.to_string() + " ecl=" + ecl +
      " version=" + qr.version().to_string() + " size=" + qr.size().to_string() +
      " mask=" + qr.mask().to_string())
    for y = 0; y < qr.size(); y = y + 1 {
      let mut s = ""
      for x = 0; x < qr.size(); x = x + 1 {
        s = s + (if qr.get_module(x, y) { "1" } else { "0" })
      }
      println(s)
    }
  }
}
