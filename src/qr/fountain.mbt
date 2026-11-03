// Luby Transform (LT) Fountain Codes implementation.
// Allows lossless recovery from any subset of encoded blocks (K + overhead).

///|
/// LT Fountain Code encoder/decoder.
pub struct LTFountain {
  block_size : Int;
  num_blocks : Int;
}

///|
/// Create a new LT fountain encoder/decoder.
pub fn LTFountain::new(block_size : Int, num_blocks : Int) -> LTFountain {
  { block_size, num_blocks }
}

///|
/// Split data into K original blocks.
pub fn LTFountain::split(self : LTFountain, data : FixedArray[Int]) -> Array[FixedArray[Int]] {
  let blocks = Array::make(self.num_blocks, FixedArray::make(self.block_size, 0))
  
  for i = 0; i < self.num_blocks; i = i + 1 {
    let start = i * self.block_size
    for j = 0; j < self.block_size; j = j + 1 {
      if start + j < data.length() {
        blocks[i][j] = data[start + j]
      }
    }
  }
  
  blocks
}

///|
/// Generate an encoded block with given seed.
/// The degree (number of original blocks to XOR) is determined by Robust Soliton distribution.
pub fn LTFountain::encode_block(self : LTFountain, blocks : Array[FixedArray[Int]], seed : Int) -> FixedArray[Int] {
  // Calculate degree using Robust Soliton distribution
  let degree = self.robust_soliton_degree(seed)
  
  // Initialize encoded block with zeros
  let encoded = FixedArray::make(self.block_size, 0)
  
  // Select 'degree' random blocks using seed
  let selected_indices = self.select_blocks(seed, degree)
  
  // XOR selected blocks
  for idx in selected_indices {
    for j = 0; j < self.block_size; j = j + 1 {
      encoded[j] = encoded[j] ^ blocks[idx][j]
    }
  }
  
  encoded
}

///|
/// Robust Soliton distribution: determines the degree for each encoded block.
/// Returns a degree value between 1 and K.
pub fn LTFountain::robust_soliton_degree(self : LTFountain, seed : Int) -> Int {
  // Use seed to generate pseudo-random number
  let r = self.pseudo_random(seed) % 1000
  
  // Simplified: use uniform distribution with occasional high degrees
  if r < 500 {
    // Degree 1 (most common)
    1
  } else if r < 800 {
    // Degree 2
    2
  } else if r < 950 {
    // Degree 3
    3
  } else {
    // Higher degree (spike)
    let d = (r % 10) + 4
    if d > self.num_blocks { self.num_blocks } else { d }
  }
}

///|
/// Pseudo-random number generator (deterministic from seed).
pub fn LTFountain::pseudo_random(_self : LTFountain, seed : Int) -> Int {
  // Simple LCG (Linear Congruential Generator)
  let a = 1103515245
  let c = 12345
  let m = 0x7FFFFFFF
  (a * seed + c) & m
}

///|
/// Select 'degree' random block indices using seed.
pub fn LTFountain::select_blocks(self : LTFountain, seed : Int, degree : Int) -> Array[Int] {
  let indices = Array::make(0, 0)
  let mut current_seed = seed
  
  for i = 0; i < degree; i = i + 1 {
    current_seed = self.pseudo_random(current_seed)
    let idx = current_seed % self.num_blocks
    
    // Avoid duplicates
    let mut duplicate = false
    for j in indices {
      if j == idx {
        duplicate = true
        break
      }
    }
    
    if !duplicate {
      indices.push(idx)
    }
  }
  
  indices
}

///|
/// Decode original data from encoded blocks.
/// Uses simple XOR-based decoding.
pub fn LTFountain::decode(self : LTFountain, encoded_blocks : Array[(Int, FixedArray[Int])]) -> FixedArray[Int]? {
  // Check if we have enough blocks
  if encoded_blocks.length() < self.num_blocks {
    return None
  }
  
  // Initialize original blocks
  let original_blocks = Array::make(self.num_blocks, FixedArray::make(self.block_size, 0))
  let resolved = Array::make(self.num_blocks, false)
  
  // Build neighbor list for each encoded block
  let neighbors = Array::make(encoded_blocks.length(), Array::make(0, 0))
  for i = 0; i < encoded_blocks.length(); i = i + 1 {
    let (seed, _) = encoded_blocks[i]
    let degree = self.robust_soliton_degree(seed)
    let selected = self.select_blocks(seed, degree)
    for idx in selected {
      neighbors[i].push(idx)
    }
  }
  
  // Simple decoding: try to resolve blocks iteratively
  let mut resolved_count = 0
  let max_iterations = self.num_blocks * 20
  
  for iter = 0; iter < max_iterations; iter = iter + 1 {
    let mut progress = false
    
    for i = 0; i < encoded_blocks.length(); i = i + 1 {
      let (seed, encoded) = encoded_blocks[i]
      let nb = neighbors[i]
      
      // Count unresolved neighbors
      let mut unresolved_count = 0
      let mut last_unresolved = -1
      for idx in nb {
        if !resolved[idx] {
          unresolved_count = unresolved_count + 1
          last_unresolved = idx
        }
      }
      
      // If exactly one unresolved neighbor, we can resolve it
      if unresolved_count == 1 {
        let target_idx = last_unresolved
        
        // Calculate the original block by XORing with resolved neighbors
        let original = FixedArray::make(self.block_size, 0)
        for j = 0; j < self.block_size; j = j + 1 {
          original[j] = encoded[j]
        }
        
        // XOR with already resolved neighbors
        for idx in nb {
          if resolved[idx] {
            for j = 0; j < self.block_size; j = j + 1 {
              original[j] = original[j] ^ original_blocks[idx][j]
            }
          }
        }
        
        original_blocks[target_idx] = original
        resolved[target_idx] = true
        resolved_count = resolved_count + 1
        progress = true
        
        // Check if all blocks are resolved
        if resolved_count == self.num_blocks {
          break
        }
      }
    }
    
    if !progress {
      break
    }
  }
  
  // Check if all blocks are resolved
  if resolved_count < self.num_blocks {
    return None
  }
  
  // Reassemble original data
  let total_len = self.num_blocks * self.block_size
  let data = FixedArray::make(total_len, 0)
  
  for i = 0; i < self.num_blocks; i = i + 1 {
    for j = 0; j < self.block_size; j = j + 1 {
      data[i * self.block_size + j] = original_blocks[i][j]
    }
  }
  
  Some(data)
}

///|
/// Encode entire data into multiple encoded blocks.
pub fn LTFountain::encode_all(self : LTFountain, data : FixedArray[Int], num_encoded : Int) -> Array[(Int, FixedArray[Int])] {
  let blocks = self.split(data)
  let encoded = Array::make(0, (0, FixedArray::make(0, 0)))
  
  for i = 0; i < num_encoded; i = i + 1 {
    let block = self.encode_block(blocks, i + 1)  // Use i+1 as seed
    encoded.push((i + 1, block))
  }
  
  encoded
}
