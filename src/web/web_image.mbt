/// Web-facing image decode entry: base64 image -> self-implemented pixel
/// pipeline -> payload. Returns a small JSON envelope so JavaScript can
/// consume it without ABI concerns.
///
/// Format auto-detection by magic bytes: PNG (89 50 4E 47) and BMP
/// (42 4D) are decoded by self-implemented decoders; other formats must
/// be converted to one of these by the caller.

///|
/// Encode bytes as lowercase hex.
fn web_bytes_to_hex(data : FixedArray[Int32]) -> String {
  let digits = "0123456789abcdef"
  let mut sb = ""
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i] & 0xFF
    sb = sb + digits[b / 16].to_string() + digits[b % 16].to_string()
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
