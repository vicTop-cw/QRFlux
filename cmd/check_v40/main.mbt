/// Test script to verify V40 capacity
fn main {
  let ver = 40
  let raw = (16 * ver + 128) * ver + 64
  let numalign = ver / 7 + 2
  let raw_adjusted = raw - (25 * numalign - 10) * numalign + 55 - 36
  
  println("V40 raw modules: " + raw.to_string())
  println("V40 adjusted modules: " + raw_adjusted.to_string())
  println("V40 total codewords: " + (raw_adjusted / 8).to_string())
  
  // Check ECC parameters
  let ecc_low = 30  // From table
  let blocks_low = 10  // From QR spec
  
  let ecc_total = ecc_low * blocks_low
  let data_cw = raw_adjusted / 8 - ecc_total
  
  println("V40 Low ECC per block: " + ecc_low.to_string())
  println("V40 Low blocks: " + blocks_low.to_string())
  println("V40 Low total ECC: " + ecc_total.to_string())
  println("V40 Low data codewords: " + data_cw.to_string())
}
