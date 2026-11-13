/// QR Code Model 2 tables from ISO/IEC 18004.
/// Indexed by version 1..40 (index 0 is padding, unused).

///|
/// Number of error correction codewords per block, per ECC level.
/// Levels: 0=Low, 1=Medium, 2=Quartile, 3=High.
pub let ecc_cw_per_block_low : FixedArray[Int32] = [
  0, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28,
  28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
]

///|
pub let ecc_cw_per_block_medium : FixedArray[Int32] = [
  0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26,
  26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
  28,
]

///|
pub let ecc_cw_per_block_quartile : FixedArray[Int32] = [
  0, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26,
  30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
  30,
]

///|
pub let ecc_cw_per_block_high : FixedArray[Int32] = [
  0, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26,
  28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
  30,
]

///|
/// Number of error correction blocks per version, per ECC level.
pub let num_ecc_blocks_low : FixedArray[Int32] = [
  0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12,
  12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25,
]

///|
pub let num_ecc_blocks_medium : FixedArray[Int32] = [
  0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18,
  20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49,
]

///|
pub let num_ecc_blocks_quartile : FixedArray[Int32] = [
  0, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23,
  25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68,
]

///|
pub let num_ecc_blocks_high : FixedArray[Int32] = [
  0, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34,
  30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81,
]

///|
#derive(Eq, Debug)
pub enum EccLevel {
  Low
  Medium
  Quartile
  High
}

///|
pub extend EccLevel with Eq::{not_equal, equal}

///|
pub extend EccLevel with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn EccLevel::from_string(s : String) -> EccLevel {
  match s {
    "L" | "Low" => Low
    "M" | "Medium" => Medium
    "Q" | "Quartile" => Quartile
    "H" | "High" => High
    _ => Low
  }
}

///|
pub fn ecc_codewords_per_block(level : EccLevel, version : Int32) -> Int32 {
  match level {
    Low => ecc_cw_per_block_low[version]
    Medium => ecc_cw_per_block_medium[version]
    Quartile => ecc_cw_per_block_quartile[version]
    High => ecc_cw_per_block_high[version]
  }
}

///|
pub fn num_ecc_blocks(level : EccLevel, version : Int32) -> Int32 {
  match level {
    Low => num_ecc_blocks_low[version]
    Medium => num_ecc_blocks_medium[version]
    Quartile => num_ecc_blocks_quartile[version]
    High => num_ecc_blocks_high[version]
  }
}

///|
/// Format bits for ECC level (2-bit value used in format info).
pub fn format_bits(level : EccLevel) -> Int32 {
  match level {
    Low => 1
    Medium => 0
    Quartile => 3
    High => 2
  }
}

///|
/// ECC tolerance description.
pub fn ecc_tolerance(level : EccLevel) -> Int32 {
  match level {
    Low => 7
    Medium => 15
    Quartile => 25
    High => 30
  }
}

///|
/// Convenience constructors (cross-package enum ctor usage helper).
pub fn ecc_low() -> EccLevel {
  Low
}

///|
pub fn ecc_medium() -> EccLevel {
  Medium
}

///|
pub fn ecc_quartile() -> EccLevel {
  Quartile
}

///|
pub fn ecc_high() -> EccLevel {
  High
}
