/// QR data segments. Only byte mode is used by QRFlux (binary payloads),
/// plus alphanumeric/numeric helpers for completeness of text entry.

pub enum Mode {
  Numeric
  Alphanumeric
  Byte
}

/// Segment mode indicator bits (4 bits each).
pub fn mode_bits(m : Mode) -> Int {
  match m {
    Numeric => 0x1
    Alphanumeric => 0x2
    Byte => 0x4
  }
}

/// Number of character-count bits by version group: (1-9, 10-26, 27-40).
pub fn char_count_bits(m : Mode, version : Int) -> Int {
  let group = (version + 7) / 17
  match m {
    Numeric => [10, 12, 14][group]
    Alphanumeric => [9, 11, 13][group]
    Byte => [8, 16, 16][group]
  }
}

pub struct Segment {
  mode : Mode
  num_chars : Int
  bitdata : BitBuffer
}

pub fn Segment::make_bytes(data : FixedArray[Int]) -> Segment {
  let bb = BitBuffer::new()
  bb.append_bytes(data)
  { mode: Byte, num_chars: data.length(), bitdata: bb }
}

pub fn Segment::num_chars(self : Segment) -> Int {
  self.num_chars
}

pub fn Segment::mode(self : Segment) -> Mode {
  self.mode
}

pub fn Segment::data(self : Segment) -> BitBuffer {
  self.bitdata
}
