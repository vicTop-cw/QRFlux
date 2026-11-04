///|
/// Batch cross-validation: emit QR matrices for external decoding.
/// Outputs two kinds of blocks:
///   1. CASE blocks: bare encode_binary matrices (for verify_qr.py)
///   2. STATIC_CASE blocks: encode_static pipeline matrices with packaged
///      bytes hex (for verify_static.py)

///|
/// Map ECC level name to factory value.
fn ecl_from_name(name : String) -> @qr.EccLevel {
  match name {
    "L" => @qr.ecc_low()
    "M" => @qr.ecc_medium()
    "Q" => @qr.ecc_quartile()
    _ => @qr.ecc_high()
  }
}

///|
/// Emit the QR matrix as 0/1 rows.
fn emit_matrix(qr : @qr.QrCode) -> Unit {
  for y = 0; y < qr.size(); y = y + 1 {
    let mut s = ""
    for x = 0; x < qr.size(); x = x + 1 {
      s = s + (if qr.get_module(x, y) { "1" } else { "0" })
    }
    println(s)
  }
}

///|
/// Convert a nibble (0~15) to a hex character.
fn hex_digit(d : Int32) -> String {
  match d {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "a"
    11 => "b"
    12 => "c"
    13 => "d"
    14 => "e"
    _ => "f"
  }
}

///|
/// Convert a byte to two-char hex string.
fn hex2(b : Int32) -> String {
  hex_digit((b >> 4) & 0x0F) + hex_digit(b & 0x0F)
}

///|
/// Compute byte-mode capacity for a given version and ECC level using the
/// encoder's own functions, ensuring consistency with encode_binary.
/// capacity = (num_data_codewords * 8 - 4 (mode) - char_count_bits) / 8
fn byte_capacity(version : Int32, level : @qr.EccLevel) -> Int32 {
  let data_bits = @qr.num_data_codewords(version, level) * 8
  let cc_bits = @qr.char_count_bits(@qr.mode_byte(), version)
  let avail = data_bits - 4 - cc_bits
  if avail < 8 {
    0
  } else {
    avail / 8
  }
}

///|
/// Emit a bare encode_binary CASE block with deterministic PRNG data.
fn emit_case(
  label : String,
  len : Int32,
  ecl : String,
  min_ver : Int32,
) -> Unit {
  let data = gen_random(len)
  let level = ecl_from_name(ecl)
  let qr = @qr.encode_binary(data, level, min_ver)
  println(
    "CASE " +
    label +
    " len=" +
    len.to_string() +
    " ecl=" +
    ecl +
    " version=" +
    qr.version().to_string() +
    " size=" +
    qr.size().to_string() +
    " mask=" +
    qr.mask().to_string(),
  )
  emit_matrix(qr)
}

///|
/// Emit a static-pipeline STATIC_CASE block.
/// Outputs the QR matrix plus the packaged bytes as hex for byte-level
/// comparison after external decoding.
fn emit_static_case(
  label : String,
  data : FixedArray[Int32],
  ecl : String,
  min_ver : Int32,
) -> Unit {
  let level = ecl_from_name(ecl)
  let result = @qr.encode_static(data, level, min_ver)
  match result {
    None =>
      println(
        "STATIC_CASE_SKIP " +
        label +
        " data_len=" +
        data.length().to_string() +
        " ecl=" +
        ecl +
        " reason=too_large",
      )
    Some(r) => {
      let qr = r.qr()
      println(
        "STATIC_CASE " +
        label +
        " data_len=" +
        data.length().to_string() +
        " ecl=" +
        ecl +
        " version=" +
        qr.version().to_string() +
        " size=" +
        qr.size().to_string() +
        " mask=" +
        qr.mask().to_string() +
        " algo=" +
        r.algo_id().to_string() +
        " compressed=" +
        (if r.compressed() { "1" } else { "0" }) +
        " pkg_len=" +
        r.packaged_size().to_string(),
      )
      emit_matrix(qr)
      let pb = r.packaged_bytes()
      let mut hex = "PACKED "
      for i = 0; i < pb.length(); i = i + 1 {
        hex = hex + hex2(pb[i])
      }
      println(hex)
      println("END_STATIC")
    }
  }
}

///|
/// Deterministic pseudo-random bytes (seed=12345, same as legacy).
fn gen_random(len : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(len, 0)
  let mut seed = 12345
  for i = 0; i < len; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    data[i] = (seed >> 16) & 0xFF
  }
  data
}

///|
/// High-repetition pattern "ABCDABCD..." (RLE-friendly).
fn gen_repeat(len : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(len, 0)
  let pat : FixedArray[Int32] = FixedArray::make(4, 0)
  pat[0] = 0x41
  pat[1] = 0x42
  pat[2] = 0x43
  pat[3] = 0x44
  for i = 0; i < len; i = i + 1 {
    data[i] = pat[i % 4]
  }
  data
}

///|
/// All-zero bytes.
fn gen_zero(len : Int32) -> FixedArray[Int32] {
  FixedArray::make(len, 0)
}

///|
/// All-0xFF bytes.
fn gen_ff(len : Int32) -> FixedArray[Int32] {
  FixedArray::make(len, 0xFF)
}

///|
/// Printable ASCII text (32~126), deterministic.
fn gen_text(len : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(len, 0)
  let mut seed = 98765
  for i = 0; i < len; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    data[i] = 32 + (seed >> 16) % 95
  }
  data
}

///|
/// Encode a Unicode codepoint into UTF-8 bytes, pushing into arr.
fn utf8_push_codepoint(arr : Array[Int32], cp : Int32) -> Unit {
  if cp < 0x80 {
    arr.push(cp)
  } else if cp < 0x800 {
    arr.push(0xC0 | (cp >> 6))
    arr.push(0x80 | (cp & 0x3F))
  } else if cp < 0x10000 {
    arr.push(0xE0 | (cp >> 12))
    arr.push(0x80 | ((cp >> 6) & 0x3F))
    arr.push(0x80 | (cp & 0x3F))
  } else {
    arr.push(0xF0 | (cp >> 18))
    arr.push(0x80 | ((cp >> 12) & 0x3F))
    arr.push(0x80 | ((cp >> 6) & 0x3F))
    arr.push(0x80 | (cp & 0x3F))
  }
}

///|
/// Convert a MoonBit String to UTF-8 bytes (FixedArray[Int32], each 0~255).
fn utf8_to_bytes(s : String) -> FixedArray[Int32] {
  let arr : Array[Int32] = []
  let chars = s.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    utf8_push_codepoint(arr, chars[i].to_int())
  }
  let data = FixedArray::make(arr.length(), 0)
  for i = 0; i < arr.length(); i = i + 1 {
    data[i] = arr[i]
  }
  data
}

///|
/// Base64-encode a byte array to a string (standard alphabet, with padding).
fn base64_encode(data : FixedArray[Int32]) -> String {
  let table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_array()
  let n = data.length()
  let mut result = ""
  let mut i = 0
  while i < n {
    let b0 = data[i]
    let b1 = if i + 1 < n { data[i + 1] } else { 0 }
    let b2 = if i + 2 < n { data[i + 2] } else { 0 }
    let e0 = (b0 >> 2) & 0x3F
    let e1 = ((b0 << 4) | (b1 >> 4)) & 0x3F
    let e2 = ((b1 << 2) | (b2 >> 6)) & 0x3F
    let e3 = b2 & 0x3F
    result = result + table[e0].to_string() + table[e1].to_string()
    if i + 1 < n {
      result = result + table[e2].to_string()
    } else {
      result = result + "="
    }
    if i + 2 < n {
      result = result + table[e3].to_string()
    } else {
      result = result + "="
    }
    i = i + 3
  }
  result
}

///|
/// Emit QR image in the requested format to stdout.
/// pbm/svg: text output directly. png: base64-encoded binary to stdout.
fn emit_image(qr : @qr.QrCode, format : String) -> Unit {
  match format {
    "pbm" => println(@qr.to_pbm(qr, 4))
    "svg" => println(@qr.to_svg(qr, 10, 4))
    "png" => println(base64_encode(@qr.to_png(qr, 10, 4)))
    _ => println("Error: unknown format '" + format + "', use pbm/svg/png")
  }
}

///|
/// Print CLI usage to stdout.
fn print_usage() -> Unit {
  println("QRFlux CLI - pure MoonBit QR code generator")
  println("")
  println("Usage:")
  println("  moon run cmd/main > batch.txt")
  println("    Batch cross-validation mode (default, backward compatible).")
  println("")
  println("  moon run cmd/main -- --text \"Hello\" --ecl M --format pbm")
  println("    Generate a single QR image. Options:")
  println("      --text <string>      text to encode (UTF-8, required)")
  println("      --ecl <L|M|Q|H>      error correction level (default M)")
  println("      --format <pbm|svg|png>  image format (default pbm)")
  println(
    "      --output <file>      output file (not supported, writes to stdout)",
  )
  println(
    "      --encode-static      use static pipeline (compress + package header)",
  )
  println("")
  println("Formats:")
  println("  pbm  - Portable Bitmap ASCII (P1), text output")
  println("  svg  - SVG vector image, text output")
  println(
    "  png  - PNG binary, output as base64 (decode: | base64 -d > out.png)",
  )
}

///|
/// Run CLI mode: parse arguments and generate a single QR image.
fn run_cli(args : Array[String]) -> Unit {
  let mut text : String = ""
  let mut has_text : Bool = false
  let mut ecl : String = "M"
  let mut format : String = "pbm"
  let mut use_static : Bool = false
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "--text" {
      i = i + 1
      if i < args.length() {
        text = args[i]
        has_text = true
      }
    } else if a == "--ecl" {
      i = i + 1
      if i < args.length() {
        ecl = args[i]
      }
    } else if a == "--format" {
      i = i + 1
      if i < args.length() {
        format = args[i]
      }
    } else if a == "--encode-static" {
      use_static = true
    } else if a == "--output" {
      i = i + 1
    } else if a == "--help" || a == "-h" {
      print_usage()
      return
    }
    i = i + 1
  }
  if !has_text {
    println("Error: --text is required")
    println("")
    print_usage()
    return
  }
  let data = utf8_to_bytes(text)
  let level = ecl_from_name(ecl)
  if use_static {
    let result = @qr.encode_static(data, level, 1)
    match result {
      None =>
        println(
          "Error: data too large for static pipeline (len=" +
          data.length().to_string() +
          ", ecl=" +
          ecl +
          ")",
        )
      Some(r) => {
        let qr = r.qr()
        println(
          "# static: version=" +
          qr.version().to_string() +
          " size=" +
          qr.size().to_string() +
          " algo=" +
          r.algo_id().to_string() +
          " compressed=" +
          (if r.compressed() { "1" } else { "0" }) +
          " pkg_len=" +
          r.packaged_size().to_string(),
        )
        emit_image(qr, format)
      }
    }
  } else {
    let qr = @qr.encode_binary(data, level, 1)
    println(
      "# version=" +
      qr.version().to_string() +
      " size=" +
      qr.size().to_string() +
      " mask=" +
      qr.mask().to_string(),
    )
    emit_image(qr, format)
  }
}

///|
/// Run batch cross-validation mode (default, backward compatible).
/// Emits CASE and STATIC_CASE blocks for verify_qr.py / verify_static.py.
fn run_batch() -> Unit {
  // === Section 1: bare encode_binary CASE blocks ===
  // Legacy cases a~i (kept unchanged for backward compatibility).
  let legacy : Array[(String, Int32, String, Int32)] = [
    ("a", 10, "L", 1),
    ("b", 10, "M", 1),
    ("c", 10, "H", 1),
    ("d", 30, "L", 1),
    ("e", 30, "Q", 1),
    ("f", 100, "M", 1),
    ("g", 200, "L", 1),
    ("h", 300, "L", 1),
    ("i", 2900, "L", 1),
  ]
  for c in legacy {
    let (label, len, ecl, mv) = c
    emit_case(label, len, ecl, mv)
  }
  // Version sweep: V1~V11 × L/M/Q/H.
  // Capacity table = max encodable bytes in byte mode per spec.
  let cap : Array[(Int32, Int32, Int32, Int32)] = [
    (17, 14, 11, 7),
    (32, 26, 20, 14),
    (53, 42, 32, 24),
    (78, 62, 46, 34),
    (106, 84, 60, 44),
    (134, 108, 74, 58),
    (154, 122, 86, 64),
    (192, 152, 108, 84),
    (230, 180, 130, 98),
    (271, 213, 151, 119),
    (311, 241, 177, 137),
  ]
  let ecl_names : Array[String] = ["L", "M", "Q", "H"]
  for vi = 0; vi < 11; vi = vi + 1 {
    let (cL, cM, cQ, cH) = cap[vi]
    let caps : Array[Int32] = [cL, cM, cQ, cH]
    for ei = 0; ei < 4; ei = ei + 1 {
      let raw = caps[ei] - 2
      let n = if raw < 1 { 1 } else { raw }
      let label = "v" +
        (vi + 1).to_string() +
        "_" +
        ecl_names[ei] +
        "_" +
        n.to_string()
      emit_case(label, n, ecl_names[ei], vi + 1)
    }
  }
  // Representative version sweep: V12~V39 × L/M/Q/H.
  // 8 representative versions (12,15,18,20,25,30,35,39) to cover the
  // previously blank V12~V39 range without exhausting all 28 versions.
  // Capacity is computed dynamically via the encoder's own functions to
  // guarantee consistency (avoids hard-coded table drift).
  // Data length = capacity - 5 (leave a small margin).
  let rep_versions : Array[Int32] = [12, 15, 18, 20, 25, 30, 35, 39]
  for ver in rep_versions {
    for ei = 0; ei < 4; ei = ei + 1 {
      let level = ecl_from_name(ecl_names[ei])
      let cap = byte_capacity(ver, level)
      let n = cap - 5
      if n > 0 {
        let label = "v" +
          ver.to_string() +
          "_" +
          ecl_names[ei] +
          "_" +
          n.to_string()
        emit_case(label, n, ecl_names[ei], ver)
      }
    }
  }
  // === Section 2: static-pipeline STATIC_CASE blocks ===
  println("=== SECTION STATIC ===")
  let patterns : Array[String] = ["random", "repeat", "zero", "ff", "text"]
  let lengths : Array[Int32] = [10, 50, 100, 200, 500]
  let static_ecls : Array[String] = ["L", "M"]
  for p in patterns {
    for len in lengths {
      for ecl in static_ecls {
        let data = match p {
          "random" => gen_random(len)
          "repeat" => gen_repeat(len)
          "zero" => gen_zero(len)
          "ff" => gen_ff(len)
          _ => gen_text(len)
        }
        let label = "s_" + p + "_" + len.to_string() + "_" + ecl
        emit_static_case(label, data, ecl, 1)
      }
    }
  }
}

///|
fn main {
  let args = @env.args()
  if args.length() > 1 {
    run_cli(args)
  } else {
    run_batch()
  }
}
