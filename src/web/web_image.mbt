/// Web-facing image decode entry: base64 image -> self-implemented pixel
/// pipeline -> payload. Returns a small JSON envelope so JavaScript can
/// consume it without ABI concerns.
///
/// Format auto-detection by magic bytes: PNG (89 50 4E 47) and BMP
/// (42 4D) are decoded by self-implemented decoders; other formats must
/// be converted to one of these by the caller.

///|
/// Hex digit to string. Uses a match over integer literals instead of
/// indexing a digit string: on the js backend `s[i]` yields a UTF-16
/// code unit (Int), whose `.to_string()` formats the numeric value
/// ("f" -> "102"), silently corrupting hex output.
fn web_hex_digit(v : Int32) -> String {
  match v {
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
/// Encode bytes as lowercase hex.
fn web_bytes_to_hex(data : FixedArray[Int32]) -> String {
  let mut sb = ""
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i] & 0xFF
    sb = sb + web_hex_digit(b / 16) + web_hex_digit(b % 16)
  }
  sb
}

///|
/// Decode a QR code from a base64-encoded image (PNG or BMP screenshot).
/// Pipeline: base64 -> format sniff -> PNG/BMP decode (self-implemented)
/// -> Otsu binarization -> finder localization -> affine/perspective
/// resample -> decode.
/// Returns JSON: {"ok":true,"bytes":N,"hex":"..."} or
/// {"ok":false,"error":"..."}.
pub fn web_decode_image(image_b64 : String) -> String {
  let bytes : Bytes = @base64.decode(image_b64) catch {
    _ => return "{\"ok\":false,\"error\":\"invalid base64\"}"
  }
  let gray = match @qr.decode_image_gray(bytes) {
    Some(g) => g
    None =>
      return "{\"ok\":false,\"error\":\"unsupported or corrupt image (need non-interlaced PNG or uncompressed BMP)\"}"
  }
  match @qr.decode_from_pixels(gray) {
    Some(data) =>
      "{\"ok\":true,\"bytes\":" +
      data.length().to_string() +
      ",\"hex\":\"" +
      web_bytes_to_hex(data) +
      "\"}"
    None => "{\"ok\":false,\"error\":\"no decodable QR code found\"}"
  }
}
