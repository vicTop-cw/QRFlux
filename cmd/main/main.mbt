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
/// Parse a non-empty decimal string to a positive Int32.
/// Returns None on empty input or non-digit characters.
fn parse_int(s : String) -> Int32? {
  let chars = s.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut result = 0
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i].to_int()
    if c < 0x30 || c > 0x39 {
      return None
    }
    result = result * 10 + (c - 0x30)
  }
  Some(result)
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
/// Parse a hex character to its numeric value (0~15). Returns -1 if invalid.
fn hex_val(c : Int32) -> Int32 {
  if c >= 0x30 && c <= 0x39 {
    c - 0x30
  } else if c >= 0x41 && c <= 0x46 {
    c - 0x41 + 10
  } else if c >= 0x61 && c <= 0x66 {
    c - 0x61 + 10
  } else {
    -1
  }
}

///|
/// Parse a hex string to a byte array. Returns None on invalid input or odd length.
fn hex_to_bytes(hex : String) -> FixedArray[Int32]? {
  let chars = hex.to_array()
  let n = chars.length()
  if n == 0 || n % 2 != 0 {
    return None
  }
  let data = FixedArray::make(n / 2, 0)
  for i = 0; i < n / 2; i = i + 1 {
    let hi = hex_val(chars[i * 2].to_int())
    let lo = hex_val(chars[i * 2 + 1].to_int())
    if hi < 0 || lo < 0 {
      return None
    }
    data[i] = hi * 16 + lo
  }
  Some(data)
}

///|
/// Convert a byte array to a UTF-8 string for display.
/// If all bytes are printable ASCII, output directly; otherwise output hex.
fn bytes_to_display(bytes : FixedArray[Int32]) -> String {
  let mut all_printable = true
  for i = 0; i < bytes.length(); i = i + 1 {
    let b = bytes[i]
    if b < 0x20 || b > 0x7e {
      all_printable = false
      break
    }
  }
  if all_printable {
    let mut s = ""
    for i = 0; i < bytes.length(); i = i + 1 {
      s = s + bytes[i].unsafe_to_char().to_string()
    }
    s
  } else {
    let mut s = ""
    for i = 0; i < bytes.length(); i = i + 1 {
      s = s + hex2(bytes[i])
    }
    s
  }
}

///|
/// Run static decode: hex (packaged bytes) -> decode_static -> original data.
fn run_decode_static(hex : String) -> Unit {
  match hex_to_bytes(hex) {
    None => println("Error: invalid hex string")
    Some(bytes) =>
      match @qr.decode_static(bytes) {
        None =>
          println(
            "Error: decode_static failed (invalid package or unknown algo)",
          )
        Some(data) => {
          println("# decoded: " + data.length().to_string() + " bytes")
          println(bytes_to_display(data))
        }
      }
  }
}

///|
/// Run dynamic decode: hex frames (semicolon-separated) -> reassemble -> data.
fn run_decode_dynamic(hex : String) -> Unit {
  let frames : Array[FixedArray[Int32]] = []
  let chars = hex.to_array()
  let mut start = 0
  let mut i = 0
  while i <= chars.length() {
    if i == chars.length() || chars[i].to_int() == 0x3b {
      // ';'
      if i > start {
        let mut segment = ""
        for j = start; j < i; j = j + 1 {
          segment = segment + chars[j].to_string()
        }
        match hex_to_bytes(segment) {
          Some(bytes) => frames.push(bytes)
          None => {
            println(
              "Error: invalid hex in frame " + frames.length().to_string(),
            )
            return
          }
        }
      }
      start = i + 1
    }
    i = i + 1
  }
  if frames.length() == 0 {
    println("Error: no frames provided")
    return
  }
  match @qr.reassemble_frames(frames) {
    None =>
      println(
        "Error: reassemble_frames failed (missing/duplicate frames or checksum mismatch)",
      )
    Some(data) => {
      println(
        "# decoded: " +
        data.length().to_string() +
        " bytes, " +
        frames.length().to_string() +
        " frames",
      )
      println(bytes_to_display(data))
    }
  }
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
  println(
    "      --text <string>      text to encode (UTF-8, required for encode)",
  )
  println("      --ecl <L|M|Q|H>      error correction level (default M)")
  println("      --format <pbm|svg|png|hex>  output format (default pbm)")
  println(
    "      --output <file>      output file (not supported, writes to stdout)",
  )
  println(
    "      --encode-static      use static pipeline (compress + package header)",
  )
  println(
    "      --encode-dynamic     use dynamic stream pipeline (split into frames,",
  )
  println("                            one QR per frame, supports >1KB data)")
  println(
    "      --frame-size <n>     per-frame payload bytes (default 500, dynamic)",
  )
  println("")
  println("  moon run cmd/main -- --decode-static --hex <hex_string>")
  println("    Decode static pipeline data from packaged bytes (hex).")
  println("")
  println("  moon run cmd/main -- --decode-dynamic --hex <hex1;hex2;...>")
  println(
    "    Decode dynamic stream data from frame bytes (hex, semicolon-separated).",
  )
  println("")
  println("Formats:")
  println("  pbm  - Portable Bitmap ASCII (P1), text output")
  println("  svg  - SVG vector image, text output")
  println(
    "  png  - PNG binary, output as base64 (decode: | base64 -d > out.png)",
  )
  println(
    "  hex  - Packaged/frame bytes as hex (for --decode-static/--decode-dynamic)",
  )
}

///|
/// Emit a dynamic-stream DYNAMIC_CASE block for one frame.
/// Outputs the QR matrix plus the full frame bytes (header + payload) as
/// hex, so an external decoder can recover the frame bytes and reassemble.
fn emit_dynamic_case(
  label : String,
  frame : FixedArray[Int32],
  frame_idx : Int32,
  total_frames : Int32,
  ecl : String,
) -> Unit {
  let level = ecl_from_name(ecl)
  let qr = @qr.encode_binary(frame, level, 1)
  println(
    "DYNAMIC_CASE " +
    label +
    " frame=" +
    frame_idx.to_string() +
    "/" +
    total_frames.to_string() +
    " frame_len=" +
    frame.length().to_string() +
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
  // Emit full frame bytes (header + payload) as hex for reassembly verification.
  let mut hex = "FRAME_HEX "
  for i = 0; i < frame.length(); i = i + 1 {
    hex = hex + hex2(frame[i])
  }
  println(hex)
  println("END_DYNAMIC")
}

///|
/// Run dynamic stream encoding: split data into frames, encode each frame
/// as a QR, and emit DYNAMIC_CASE blocks to stdout.
fn run_dynamic(
  data : FixedArray[Int32],
  ecl : String,
  frame_size : Int32,
  label : String,
  format : String,
) -> Unit {
  // Guard: frame_size must be positive; clamp to a safe lower bound.
  let fs = if frame_size < 1 { 1 } else { frame_size }
  let frames = @qr.split_into_frames(data, fs)
  let total = frames.length()
  if total == 0 {
    println(
      "# dynamic: no frames (data_len=" +
      data.length().to_string() +
      ", frame_size=" +
      fs.to_string() +
      ")",
    )
    return
  }
  // Emit a summary header line first.
  println(
    "# dynamic: data_len=" +
    data.length().to_string() +
    " frame_size=" +
    fs.to_string() +
    " total_frames=" +
    total.to_string() +
    " ecl=" +
    ecl,
  )
  if format == "hex" {
    // Output frame bytes as hex, semicolon-separated (for --decode-dynamic).
    let mut hex = ""
    for i = 0; i < total; i = i + 1 {
      if i > 0 {
        hex = hex + ";"
      }
      for j = 0; j < frames[i].length(); j = j + 1 {
        hex = hex + hex2(frames[i][j])
      }
    }
    println(hex)
    return
  }
  for i = 0; i < total; i = i + 1 {
    emit_dynamic_case(label, frames[i], i, total, ecl)
  }
}

///|
/// Run CLI mode: parse arguments and generate a single QR image.
fn run_cli(args : Array[String]) -> Unit {
  let mut text : String = ""
  let mut has_text : Bool = false
  let mut ecl : String = "M"
  let mut format : String = "pbm"
  let mut use_static : Bool = false
  let mut use_dynamic : Bool = false
  let mut use_decode_static : Bool = false
  let mut use_decode_dynamic : Bool = false
  let mut hex_data : String = ""
  let mut frame_size : Int32 = 500
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
    } else if a == "--encode-dynamic" {
      use_dynamic = true
    } else if a == "--decode-static" {
      use_decode_static = true
    } else if a == "--decode-dynamic" {
      use_decode_dynamic = true
    } else if a == "--hex" {
      i = i + 1
      if i < args.length() {
        hex_data = args[i]
      }
    } else if a == "--frame-size" {
      i = i + 1
      if i < args.length() {
        match parse_int(args[i]) {
          Some(n) => if n > 0 { frame_size = n }
          None => ()
        }
      }
    } else if a == "--output" {
      i = i + 1
    } else if a == "--help" || a == "-h" {
      print_usage()
      return
    }
    i = i + 1
  }
  // Decode modes (don't require --text, use --hex instead)
  if use_decode_static {
    if hex_data == "" {
      println("Error: --hex is required for --decode-static")
      return
    }
    run_decode_static(hex_data)
    return
  }
  if use_decode_dynamic {
    if hex_data == "" {
      println("Error: --hex is required for --decode-dynamic")
      return
    }
    run_decode_dynamic(hex_data)
    return
  }
  if !has_text {
    println("Error: --text is required")
    println("")
    print_usage()
    return
  }
  let data = utf8_to_bytes(text)
  let level = ecl_from_name(ecl)
  if use_dynamic {
    // Dynamic stream pipeline: split into frames, one QR per frame.
    // Emit DYNAMIC_CASE blocks (matrix + frame hex) to stdout.
    run_dynamic(data, ecl, frame_size, "cli", format)
    return
  }
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
        if format == "hex" {
          let pb = r.packaged_bytes()
          let mut hex = ""
          for j = 0; j < pb.length(); j = j + 1 {
            hex = hex + hex2(pb[j])
          }
          println(hex)
        } else {
          emit_image(qr, format)
        }
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
  // Full version sweep: V12~V39 × L/M/Q/H (all 28 versions).
  // Capacity is computed dynamically via the encoder's own functions to
  // guarantee consistency (avoids hard-coded table drift).
  // Data length = capacity - 5 (leave a small margin, ~95%+ utilization).
  let rep_versions : Array[Int32] = [
    12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
    32, 33, 34, 35, 36, 37, 38, 39,
  ]
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
