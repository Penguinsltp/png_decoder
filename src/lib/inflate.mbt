///|
priv struct BitReader {
  data : BytesView
  mut pos : Int
  mut bit_buf : UInt
  mut bit_count : Int
}

///|
fn BitReader::new(data : BytesView, start_pos : Int) -> BitReader {
  { data, pos: start_pos, bit_buf: 0U, bit_count: 0 }
}

///|
fn BitReader::ensure_bits(br : BitReader, n : Int) -> Unit raise PngError {
  while br.bit_count < n {
    if br.pos >= br.data.length() {
      raise_png(UnexpectedEof, "unexpected EOF in bitstream")
    }
    let b = br.data[br.pos].to_uint()
    br.pos = br.pos + 1
    br.bit_buf = br.bit_buf | (b << br.bit_count)
    br.bit_count = br.bit_count + 8
  }
}

///|
fn BitReader::peek_bits(br : BitReader, n : Int) -> UInt raise PngError {
  if n == 0 {
    0U
  } else {
    BitReader::ensure_bits(br, n)
    br.bit_buf & ((1U << n) - 1U)
  }
}

///|
fn BitReader::drop_bits(br : BitReader, n : Int) -> Unit raise PngError {
  if n == 0 {
    ()
  } else {
    BitReader::ensure_bits(br, n)
    br.bit_buf = br.bit_buf >> n
    br.bit_count = br.bit_count - n
  }
}

///|
fn BitReader::read_bits(br : BitReader, n : Int) -> UInt raise PngError {
  let v = BitReader::peek_bits(br, n)
  BitReader::drop_bits(br, n)
  v
}

///|
fn BitReader::align_to_byte(br : BitReader) -> Unit raise PngError {
  let skip = br.bit_count % 8
  BitReader::drop_bits(br, skip)
}

///|
fn reverse_bits(v : UInt, bits : Int) -> UInt {
  let mut v = v
  let mut r = 0U
  for i = 0; i < bits; i = i + 1 {
    r = (r << 1) | (v & 1U)
    v = v >> 1
  }
  r
}

///|
priv struct Huffman {
  table_sym : Array[Int]
  table_bits : Array[Int]
  max_bits : Int
}

///|
fn Huffman::from_code_lengths(lengths : Array[Int]) -> Huffman raise PngError {
  let mut max_bits = 0
  for i = 0; i < lengths.length(); i = i + 1 {
    let l = lengths[i]
    if l < 0 || l > 15 {
      raise_png(InflateError, "invalid huffman code length")
    }
    if l > max_bits {
      max_bits = l
    }
  }
  if max_bits == 0 {
    raise_png(InflateError, "empty huffman tree")
  }
  let bl_count = Array::make(max_bits + 1, 0)
  for i = 0; i < lengths.length(); i = i + 1 {
    let l = lengths[i]
    if l > 0 {
      bl_count[l] = bl_count[l] + 1
    }
  }
  let next_code = Array::make(max_bits + 1, 0U)
  let mut code = 0U
  for bits = 1; bits <= max_bits; bits = bits + 1 {
    code = (code + UInt::trunc_double(bl_count[bits - 1].to_double())) << 1
    next_code[bits] = code
  }
  let size = 1 << max_bits
  let table_sym = Array::make(size, -1)
  let table_bits = Array::make(size, 0)
  for symbol = 0; symbol < lengths.length(); symbol = symbol + 1 {
    let len = lengths[symbol]
    if len > 0 {
      let c = next_code[len]
      next_code[len] = c + 1U
      let rev = reverse_bits(c, len)
      let step = 1 << len
      let mut i = rev.reinterpret_as_int()
      while i < size {
        table_sym[i] = symbol
        table_bits[i] = len
        i = i + step
      }
    }
  }
  { table_sym, table_bits, max_bits }
}

///|
fn Huffman::decode(h : Huffman, br : BitReader) -> Int raise PngError {
  let bits = BitReader::peek_bits(br, h.max_bits)
  let idx = bits.reinterpret_as_int()
  let sym = h.table_sym[idx]
  let len = h.table_bits[idx]
  if len == 0 || sym < 0 {
    raise_png(InflateError, "invalid huffman code")
  }
  BitReader::drop_bits(br, len)
  sym
}

///|
fn ensure_out_limit(out_len : Int, max_out : Int?) -> Unit raise PngError {
  match max_out {
    Some(m) =>
      if out_len > m {
        raise_png(LimitExceeded, "decompressed data exceeds limit")
      }
    None => ()
  }
}

///|

///|
let length_base : ReadOnlyArray[Int] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83,
  99, 115, 131, 163, 195, 227, 258,
]

///|
let length_extra : ReadOnlyArray[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5,
  5, 0,
]

///|
let dist_base : ReadOnlyArray[Int] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
  1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
]

///|
let dist_extra : ReadOnlyArray[Int] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
  12, 12, 13, 13,
]

///|
fn decode_huffman_block(
  br : BitReader,
  litlen : Huffman,
  dist : Huffman,
  out : Array[Byte],
  max_out : Int?,
) -> Unit raise PngError {
  while true {
    let sym = Huffman::decode(litlen, br)
    if sym < 256 {
      out.push(sym.to_byte())
      ensure_out_limit(out.length(), max_out)
    } else if sym == 256 {
      break
    } else if sym <= 285 {
      let i = sym - 257
      let mut len = length_base[i]
      let extra = length_extra[i]
      if extra > 0 {
        len = len + BitReader::read_bits(br, extra).reinterpret_as_int()
      }
      let dist_sym = Huffman::decode(dist, br)
      if dist_sym < 0 || dist_sym >= 30 {
        raise_png(InflateError, "invalid distance symbol")
      }
      let mut distance = dist_base[dist_sym]
      let dist_ex = dist_extra[dist_sym]
      if dist_ex > 0 {
        distance = distance +
          BitReader::read_bits(br, dist_ex).reinterpret_as_int()
      }
      if distance <= 0 || distance > out.length() {
        raise_png(InflateError, "invalid distance")
      }
      for k = 0; k < len; k = k + 1 {
        let src = out.length() - distance
        out.push(out[src])
        ensure_out_limit(out.length(), max_out)
      }
    } else {
      raise_png(InflateError, "invalid length symbol")
    }
  }
}

///|
fn read_u16_le_byte_aligned(br : BitReader) -> Int raise PngError {
  BitReader::align_to_byte(br)
  if br.pos + 2 > br.data.length() {
    raise_png(UnexpectedEof, "unexpected EOF")
  }
  let b0 = br.data[br.pos].to_int()
  let b1 = br.data[br.pos + 1].to_int()
  br.pos = br.pos + 2
  b0 | (b1 << 8)
}

///|
fn decode_dynamic_trees(br : BitReader) -> (Huffman, Huffman) raise PngError {
  let hlit = BitReader::read_bits(br, 5).reinterpret_as_int() + 257
  let hdist = BitReader::read_bits(br, 5).reinterpret_as_int() + 1
  let hclen = BitReader::read_bits(br, 4).reinterpret_as_int() + 4
  let code_len_order = [
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
  ]
  let code_lengths = Array::make(19, 0)
  for i = 0; i < hclen; i = i + 1 {
    code_lengths[code_len_order[i]] = BitReader::read_bits(br, 3).reinterpret_as_int()
  }
  let code_len_huff = Huffman::from_code_lengths(code_lengths)
  let total = hlit + hdist
  let lengths = Array::make(total, 0)
  let mut idx = 0
  while idx < total {
    let sym = Huffman::decode(code_len_huff, br)
    if sym <= 15 {
      lengths[idx] = sym
      idx = idx + 1
    } else if sym == 16 {
      if idx == 0 {
        raise_png(InflateError, "repeat previous with no previous")
      }
      let repeat = BitReader::read_bits(br, 2).reinterpret_as_int() + 3
      let prev = lengths[idx - 1]
      for j = 0; j < repeat; j = j + 1 {
        if idx >= total {
          break
        }
        lengths[idx] = prev
        idx = idx + 1
      }
    } else if sym == 17 {
      let repeat = BitReader::read_bits(br, 3).reinterpret_as_int() + 3
      for j = 0; j < repeat; j = j + 1 {
        if idx >= total {
          break
        }
        lengths[idx] = 0
        idx = idx + 1
      }
    } else if sym == 18 {
      let repeat = BitReader::read_bits(br, 7).reinterpret_as_int() + 11
      for j = 0; j < repeat; j = j + 1 {
        if idx >= total {
          break
        }
        lengths[idx] = 0
        idx = idx + 1
      }
    } else {
      raise_png(InflateError, "invalid code length symbol")
    }
  }
  let litlen_lengths = lengths.sub(start=0, end=hlit).to_array()
  let dist_lengths = lengths.sub(start=hlit, end=total).to_array()
  let litlen = Huffman::from_code_lengths(litlen_lengths)
  let dist = Huffman::from_code_lengths(dist_lengths)
  (litlen, dist)
}

///|
fn inflate_deflate_stream(
  br : BitReader,
  max_out : Int?,
) -> Array[Byte] raise PngError {
  let fixed_litlen = {
    let lengths = Array::make(288, 0)
    for i = 0; i <= 143; i = i + 1 {
      lengths[i] = 8
    }
    for i = 144; i <= 255; i = i + 1 {
      lengths[i] = 9
    }
    for i = 256; i <= 279; i = i + 1 {
      lengths[i] = 7
    }
    for i = 280; i <= 287; i = i + 1 {
      lengths[i] = 8
    }
    Huffman::from_code_lengths(lengths)
  }
  let fixed_dist = {
    let lengths = Array::make(32, 5)
    Huffman::from_code_lengths(lengths)
  }
  let out = Array::new()
  let mut done = false
  while !done {
    done = BitReader::read_bits(br, 1) == 1U
    let btype = BitReader::read_bits(br, 2).reinterpret_as_int()
    if btype == 0 {
      let len = read_u16_le_byte_aligned(br)
      let nlen = read_u16_le_byte_aligned(br)
      if ((len ^ nlen) & 0xFFFF) != 0xFFFF {
        raise_png(InflateError, "invalid stored block lengths")
      }
      match max_out {
        Some(m) =>
          if out.length() + len > m {
            raise_png(LimitExceeded, "decompressed data exceeds limit")
          }
        None => ()
      }
      if br.pos + len > br.data.length() {
        raise_png(UnexpectedEof, "unexpected EOF")
      }
      for i = 0; i < len; i = i + 1 {
        out.push(br.data[br.pos + i])
      }
      br.pos = br.pos + len
    } else if btype == 1 {
      decode_huffman_block(br, fixed_litlen, fixed_dist, out, max_out)
    } else if btype == 2 {
      let (litlen, dist) = decode_dynamic_trees(br)
      decode_huffman_block(br, litlen, dist, out, max_out)
    } else {
      raise_png(InflateError, "invalid deflate block type")
    }
  }
  out
}

///|
fn zlib_inflate_limited(
  data : BytesView,
  max_out : Int?,
) -> Bytes raise PngError {
  if data.length() < 6 {
    raise_png(InflateError, "zlib stream too short")
  }
  let cmf = data[0].to_int()
  let flg = data[1].to_int()
  let cm = cmf & 0x0F
  let cinfo = (cmf >> 4) & 0x0F
  if cm != 8 || cinfo > 7 {
    raise_png(InflateError, "unsupported zlib header")
  }
  if ((cmf << 8) + flg) % 31 != 0 {
    raise_png(InflateError, "bad zlib header check")
  }
  if (flg & 0x20) != 0 {
    raise_png(Unsupported, "zlib preset dictionary not supported")
  }
  let br = BitReader::new(data, 2)
  let out = inflate_deflate_stream(br, max_out)
  BitReader::align_to_byte(br)
  if br.pos + 4 != data.length() {
    raise_png(InflateError, "trailing data after zlib stream")
  }
  let rr = Reader::new(data.sub(start=br.pos, end=br.pos + 4))
  let adler_expected = Reader::read_u32_be(rr)
  let out_bytes = Bytes::from_array(out.op_as_view())
  let adler_actual = adler32(out_bytes.op_as_view())
  if adler_actual != adler_expected {
    raise_png(InflateError, "adler32 mismatch")
  }
  out_bytes
}
