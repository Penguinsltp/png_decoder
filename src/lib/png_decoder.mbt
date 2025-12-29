///|
pub struct Image {
  width : Int
  height : Int
  rgba : Bytes
}

///|
/// PNG 解码选项。
pub struct DecodeOptions {
  max_width : Int?
  max_height : Int?
  max_pixels : Int?
  max_idat_bytes : Int?
  max_decompressed_bytes : Int?
}

///|
pub fn DecodeOptions::default() -> DecodeOptions {
  {
    max_width: Some(20000),
    max_height: Some(20000),
    max_pixels: Some(100_000_000),
    max_idat_bytes: Some(256 * 1024 * 1024),
    max_decompressed_bytes: Some(512 * 1024 * 1024),
  }
}

///|
/// 构造 `DecodeOptions`，未传入的字段为 `None`。
pub fn DecodeOptions::new(
  max_width? : Int,
  max_height? : Int,
  max_pixels? : Int,
  max_idat_bytes? : Int,
  max_decompressed_bytes? : Int,
) -> DecodeOptions {
  { max_width, max_height, max_pixels, max_idat_bytes, max_decompressed_bytes }
}

///|
/// 不限制任何资源上限。
pub fn DecodeOptions::unlimited() -> DecodeOptions {
  {
    max_width: None,
    max_height: None,
    max_pixels: None,
    max_idat_bytes: None,
    max_decompressed_bytes: None,
  }
}

///|
/// PNG 解码结果（图像 + 元数据）。
pub struct DecodedPng {
  image : Image
  metadata : PngMetadata
}

///|
priv struct Ihdr {
  width : Int
  height : Int
  bit_depth : Int
  color_type : Int
  interlace : Int
}

///|
fn validate_dimensions(
  ihdr : Ihdr,
  options : DecodeOptions,
) -> Unit raise PngError {
  match options.max_width {
    Some(m) =>
      if ihdr.width > m {
        raise_png(LimitExceeded, "image width exceeds limit")
      }
    None => ()
  }
  match options.max_height {
    Some(m) =>
      if ihdr.height > m {
        raise_png(LimitExceeded, "image height exceeds limit")
      }
    None => ()
  }
  match options.max_pixels {
    Some(m) => {
      let pixels = Int64::from_int(ihdr.width) * Int64::from_int(ihdr.height)
      if pixels > Int64::from_int(m) {
        raise_png(LimitExceeded, "image pixel count exceeds limit")
      }
    }
    None => ()
  }
}

///|
fn bits_per_pixel(ihdr : Ihdr) -> Int raise PngError {
  let channels = match ihdr.color_type {
    0 => 1
    2 => 3
    3 => 1
    4 => 2
    6 => 4
    _ => raise_png(Unsupported, "unsupported color type")
  }
  channels * ihdr.bit_depth
}

///|
fn filter_bpp(ihdr : Ihdr) -> Int raise PngError {
  let bpp_bits = bits_per_pixel(ihdr)
  (bpp_bits + 7) / 8
}

///|
fn paeth(a : Int, b : Int, c : Int) -> Int {
  let p = a + b - c
  let pa = Int::abs(p - a)
  let pb = Int::abs(p - b)
  let pc = Int::abs(p - c)
  if pa <= pb && pa <= pc {
    a
  } else if pb <= pc {
    b
  } else {
    c
  }
}

///|
fn unfilter_scanline(
  filter : Int,
  bpp : Int,
  cur : Array[Byte],
  prev : Array[Byte]?,
) -> Unit raise PngError {
  let len = cur.length()
  match filter {
    0 => ()
    1 =>
      for i = 0; i < len; i = i + 1 {
        let left = if i >= bpp { cur[i - bpp].to_int() } else { 0 }
        cur[i] = (cur[i].to_int() + left).land(0xFF).to_byte()
      }
    2 =>
      for i = 0; i < len; i = i + 1 {
        let up = match prev {
          Some(p) => p[i].to_int()
          None => 0
        }
        cur[i] = (cur[i].to_int() + up).land(0xFF).to_byte()
      }
    3 =>
      for i = 0; i < len; i = i + 1 {
        let left = if i >= bpp { cur[i - bpp].to_int() } else { 0 }
        let up = match prev {
          Some(p) => p[i].to_int()
          None => 0
        }
        cur[i] = (cur[i].to_int() + (left + up) / 2).land(0xFF).to_byte()
      }
    4 =>
      for i = 0; i < len; i = i + 1 {
        let left = if i >= bpp { cur[i - bpp].to_int() } else { 0 }
        let up = match prev {
          Some(p) => p[i].to_int()
          None => 0
        }
        let up_left = if i >= bpp {
          match prev {
            Some(p) => p[i - bpp].to_int()
            None => 0
          }
        } else {
          0
        }
        cur[i] = (cur[i].to_int() + paeth(left, up, up_left))
          .land(0xFF)
          .to_byte()
      }
    _ => raise_png(InvalidData, "invalid filter type")
  }
}

///|
fn scale_sample_to_u8(sample : Int, bit_depth : Int) -> Int {
  if bit_depth == 8 {
    sample
  } else if bit_depth == 16 {
    sample >> 8
  } else {
    let maxv = (1 << bit_depth) - 1
    (sample * 255 + maxv / 2) / maxv
  }
}

///|
fn read_packed_sample(line : Array[Byte], bit_depth : Int, idx : Int) -> Int {
  let bits = bit_depth
  let bit_pos = idx * bits
  let byte_idx = bit_pos / 8
  let shift = 8 - bits - bit_pos % 8
  (line[byte_idx].to_int() >> shift) & ((1 << bits) - 1)
}

///|
fn write_rgba(
  out : Array[Byte],
  pixel_index : Int,
  r : Int,
  g : Int,
  b : Int,
  a : Int,
) -> Unit {
  let base = pixel_index * 4
  out[base] = r.to_byte()
  out[base + 1] = g.to_byte()
  out[base + 2] = b.to_byte()
  out[base + 3] = a.to_byte()
}

///|
fn decode_scanline_to_rgba(
  ihdr : Ihdr,
  line : Array[Byte],
  x0 : Int,
  y : Int,
  dx : Int,
  width : Int,
  out : Array[Byte],
  palette : Array[Byte]?,
  trns : BytesView?,
  trns_gray : Int?,
  trns_rgb : (Int, Int, Int)?,
) -> Unit raise PngError {
  let mut x = x0
  let mut pix = 0
  while x < width {
    let pixel_index = y * width + x
    match ihdr.color_type {
      0 => {
        let sample = if ihdr.bit_depth < 8 {
          read_packed_sample(line, ihdr.bit_depth, pix)
        } else if ihdr.bit_depth == 8 {
          line[pix].to_int()
        } else {
          (line[pix * 2].to_int() << 8) | line[pix * 2 + 1].to_int()
        }
        let g = scale_sample_to_u8(sample, ihdr.bit_depth)
        let a = match trns_gray {
          Some(t) => if sample == t { 0 } else { 255 }
          None => 255
        }
        write_rgba(out, pixel_index, g, g, g, a)
      }
      2 => {
        let base = if ihdr.bit_depth == 8 { pix * 3 } else { pix * 6 }
        let r16 = if ihdr.bit_depth == 8 {
          line[base].to_int()
        } else {
          (line[base].to_int() << 8) | line[base + 1].to_int()
        }
        let g16 = if ihdr.bit_depth == 8 {
          line[base + 1].to_int()
        } else {
          (line[base + 2].to_int() << 8) | line[base + 3].to_int()
        }
        let b16 = if ihdr.bit_depth == 8 {
          line[base + 2].to_int()
        } else {
          (line[base + 4].to_int() << 8) | line[base + 5].to_int()
        }
        let r = scale_sample_to_u8(r16, ihdr.bit_depth)
        let g = scale_sample_to_u8(g16, ihdr.bit_depth)
        let b = scale_sample_to_u8(b16, ihdr.bit_depth)
        let a = match trns_rgb {
          Some((tr, tg, tb)) =>
            if r16 == tr && g16 == tg && b16 == tb {
              0
            } else {
              255
            }
          None => 255
        }
        write_rgba(out, pixel_index, r, g, b, a)
      }
      3 => {
        let index = if ihdr.bit_depth < 8 {
          read_packed_sample(line, ihdr.bit_depth, pix)
        } else {
          line[pix].to_int()
        }
        let pal = match palette {
          Some(p) => p
          None => raise_png(MissingChunk, "missing PLTE")
        }
        let pi = index * 3
        if pi + 2 >= pal.length() {
          raise_png(InvalidData, "palette index out of range")
        }
        let r = pal[pi].to_int()
        let g = pal[pi + 1].to_int()
        let b = pal[pi + 2].to_int()
        let a = match trns {
          Some(t) => if index < t.length() { t[index].to_int() } else { 255 }
          None => 255
        }
        write_rgba(out, pixel_index, r, g, b, a)
      }
      4 => {
        if ihdr.bit_depth != 8 && ihdr.bit_depth != 16 {
          raise_png(Unsupported, "unsupported gray+alpha bit depth")
        }
        let base = if ihdr.bit_depth == 8 { pix * 2 } else { pix * 4 }
        let g16 = if ihdr.bit_depth == 8 {
          line[base].to_int()
        } else {
          (line[base].to_int() << 8) | line[base + 1].to_int()
        }
        let a16 = if ihdr.bit_depth == 8 {
          line[base + 1].to_int()
        } else {
          (line[base + 2].to_int() << 8) | line[base + 3].to_int()
        }
        let g = scale_sample_to_u8(g16, ihdr.bit_depth)
        let a = scale_sample_to_u8(a16, ihdr.bit_depth)
        write_rgba(out, pixel_index, g, g, g, a)
      }
      6 => {
        if ihdr.bit_depth != 8 && ihdr.bit_depth != 16 {
          raise_png(Unsupported, "unsupported rgba bit depth")
        }
        let base = if ihdr.bit_depth == 8 { pix * 4 } else { pix * 8 }
        let r16 = if ihdr.bit_depth == 8 {
          line[base].to_int()
        } else {
          (line[base].to_int() << 8) | line[base + 1].to_int()
        }
        let g16 = if ihdr.bit_depth == 8 {
          line[base + 1].to_int()
        } else {
          (line[base + 2].to_int() << 8) | line[base + 3].to_int()
        }
        let b16 = if ihdr.bit_depth == 8 {
          line[base + 2].to_int()
        } else {
          (line[base + 4].to_int() << 8) | line[base + 5].to_int()
        }
        let a16 = if ihdr.bit_depth == 8 {
          line[base + 3].to_int()
        } else {
          (line[base + 6].to_int() << 8) | line[base + 7].to_int()
        }
        let r = scale_sample_to_u8(r16, ihdr.bit_depth)
        let g = scale_sample_to_u8(g16, ihdr.bit_depth)
        let b = scale_sample_to_u8(b16, ihdr.bit_depth)
        let a = scale_sample_to_u8(a16, ihdr.bit_depth)
        write_rgba(out, pixel_index, r, g, b, a)
      }
      _ => raise_png(Unsupported, "unsupported color type")
    }
    pix = pix + 1
    x = x + dx
  }
}

///|
fn parse_ihdr(data : BytesView) -> Ihdr raise PngError {
  if data.length() != 13 {
    raise_png(InvalidChunk, "invalid IHDR length")
  }
  let r = Reader::new(data)
  let w = Reader::read_u32_be(r).reinterpret_as_int()
  let h = Reader::read_u32_be(r).reinterpret_as_int()
  let bit_depth = Reader::read_u8(r).to_int()
  let color_type = Reader::read_u8(r).to_int()
  let compression = Reader::read_u8(r).to_int()
  let filter = Reader::read_u8(r).to_int()
  let interlace = Reader::read_u8(r).to_int()
  if w <= 0 || h <= 0 {
    raise_png(InvalidChunk, "invalid image dimensions")
  }
  if compression != 0 || filter != 0 {
    raise_png(Unsupported, "unsupported PNG compression/filter")
  }
  { width: w, height: h, bit_depth, color_type, interlace }
}

///|
fn validate_color(ihdr : Ihdr) -> Unit raise PngError {
  match ihdr.color_type {
    0 =>
      if !(ihdr.bit_depth == 1 ||
        ihdr.bit_depth == 2 ||
        ihdr.bit_depth == 4 ||
        ihdr.bit_depth == 8 ||
        ihdr.bit_depth == 16) {
        raise_png(Unsupported, "invalid grayscale bit depth")
      }
    2 =>
      if !(ihdr.bit_depth == 8 || ihdr.bit_depth == 16) {
        raise_png(Unsupported, "invalid truecolor bit depth")
      }
    3 =>
      if !(ihdr.bit_depth == 1 ||
        ihdr.bit_depth == 2 ||
        ihdr.bit_depth == 4 ||
        ihdr.bit_depth == 8) {
        raise_png(Unsupported, "invalid indexed bit depth")
      }
    4 =>
      if !(ihdr.bit_depth == 8 || ihdr.bit_depth == 16) {
        raise_png(Unsupported, "invalid gray+alpha bit depth")
      }
    6 =>
      if !(ihdr.bit_depth == 8 || ihdr.bit_depth == 16) {
        raise_png(Unsupported, "invalid rgba bit depth")
      }
    _ => raise_png(Unsupported, "unsupported color type")
  }
}

///|
fn decode_non_interlaced(
  ihdr : Ihdr,
  raw : BytesView,
  palette : Array[Byte]?,
  trns : BytesView?,
  trns_gray : Int?,
  trns_rgb : (Int, Int, Int)?,
) -> Bytes raise PngError {
  let bpp = filter_bpp(ihdr)
  let row_bytes = (ihdr.width * bits_per_pixel(ihdr) + 7) / 8
  let stride = row_bytes + 1
  if raw.length() != stride * ihdr.height {
    raise_png(InvalidData, "unexpected decompressed data length")
  }
  let out = Array::make(ihdr.width * ihdr.height * 4, Byte::default())
  let mut prev : Array[Byte]? = None
  for y = 0; y < ihdr.height; y = y + 1 {
    let base = y * stride
    let filter = raw[base].to_int()
    let line = raw.sub(start=base + 1, end=base + 1 + row_bytes).to_array()
    unfilter_scanline(filter, bpp, line, prev)
    decode_scanline_to_rgba(
      ihdr,
      line,
      0,
      y,
      1,
      ihdr.width,
      out,
      palette,
      trns,
      trns_gray,
      trns_rgb,
    )
    prev = Some(line)
  }
  Bytes::from_array(out.op_as_view())
}

///|
fn adam7_pass_dim(size : Int, start : Int, step : Int) -> Int {
  if size <= start {
    0
  } else {
    (size - start + step - 1) / step
  }
}

///|
fn decode_adam7(
  ihdr : Ihdr,
  raw : BytesView,
  palette : Array[Byte]?,
  trns : BytesView?,
  trns_gray : Int?,
  trns_rgb : (Int, Int, Int)?,
) -> Bytes raise PngError {
  let passes = [
    (0, 0, 8, 8),
    (4, 0, 8, 8),
    (0, 4, 4, 8),
    (2, 0, 4, 4),
    (0, 2, 2, 4),
    (1, 0, 2, 2),
    (0, 1, 1, 2),
  ]
  let out = Array::make(ihdr.width * ihdr.height * 4, Byte::default())
  let bpp = filter_bpp(ihdr)
  let bitspp = bits_per_pixel(ihdr)
  let mut offset = 0
  for pass = 0; pass < passes.length(); pass = pass + 1 {
    let (x0, y0, dx, dy) = passes[pass]
    let pw = adam7_pass_dim(ihdr.width, x0, dx)
    let ph = adam7_pass_dim(ihdr.height, y0, dy)
    if pw == 0 || ph == 0 {
      continue
    }
    let row_bytes = (pw * bitspp + 7) / 8
    let stride = row_bytes + 1
    let mut prev : Array[Byte]? = None
    for row = 0; row < ph; row = row + 1 {
      if offset + stride > raw.length() {
        raise_png(InvalidData, "unexpected decompressed data length")
      }
      let filter = raw[offset].to_int()
      let line = raw
        .sub(start=offset + 1, end=offset + 1 + row_bytes)
        .to_array()
      offset = offset + stride
      unfilter_scanline(filter, bpp, line, prev)
      let y = y0 + row * dy
      decode_scanline_to_rgba(
        ihdr,
        line,
        x0,
        y,
        dx,
        ihdr.width,
        out,
        palette,
        trns,
        trns_gray,
        trns_rgb,
      )
      prev = Some(line)
    }
  }
  if offset != raw.length() {
    raise_png(InvalidData, "unexpected decompressed data length")
  }
  Bytes::from_array(out.op_as_view())
}

///|
fn is_ascii_letter(b : Int) -> Bool {
  (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
}

///|
fn validate_chunk_type(typ : BytesView) -> Unit raise PngError {
  let t0 = typ[0].to_int()
  let t1 = typ[1].to_int()
  let t2 = typ[2].to_int()
  let t3 = typ[3].to_int()
  if !is_ascii_letter(t0) ||
    !is_ascii_letter(t1) ||
    !is_ascii_letter(t2) ||
    !is_ascii_letter(t3) {
    raise_png(InvalidChunk, "invalid chunk type")
  }
  // PNG 规范：第 3 个字节的 reserved bit 必须为 0（即必须是大写字母）。
  if (t2 & 0x20) != 0 {
    raise_png(InvalidChunk, "invalid chunk type (reserved bit set)")
  }
}

///|
fn validate_plte(chunk : BytesView) -> Unit raise PngError {
  let n = chunk.length()
  if n == 0 || n % 3 != 0 {
    raise_png(InvalidChunk, "invalid PLTE length")
  }
  let entries = n / 3
  if entries < 1 || entries > 256 {
    raise_png(InvalidChunk, "invalid PLTE length")
  }
}

///|
fn decode_png_impl(
  data : BytesView,
  options : DecodeOptions,
) -> DecodedPng raise PngError {
  let r = Reader::new(data)
  let sig = Reader::read_bytes_view(r, 8)
  let expected = [137, 80, 78, 71, 13, 10, 26, 10]
  for i = 0; i < 8; i = i + 1 {
    if sig[i].to_int() != expected[i] {
      raise_png(InvalidSignature, "invalid PNG signature")
    }
  }
  let mut ihdr : Ihdr? = None
  let mut seen_ihdr = false
  let mut seen_idat = false
  let mut ended_idat = false
  let idat = Array::new()
  let mut idat_total = 0
  let mut palette : Array[Byte]? = None
  let mut trns : BytesView? = None
  let mut trns_gray : Int? = None
  let mut trns_rgb : (Int, Int, Int)? = None

  // 常见 ancillary chunks（元数据）
  let mut gamma : UInt? = None
  let mut srgb_intent : Int? = None
  let mut iccp : PngIccp? = None
  let mut phys : PngPhys? = None
  let mut time : PngTime? = None
  let texts = Array::new()
  while true {
    if Reader::remaining(r) == 0 {
      raise_png(MissingChunk, "missing IEND")
    }
    let len_u = Reader::read_u32_be(r)
    let len = len_u.reinterpret_as_int()
    if len < 0 {
      raise_png(InvalidChunk, "invalid chunk length")
    }
    let typ = Reader::read_bytes_view(r, 4)
    let chunk = Reader::read_bytes_view(r, len)
    let crc_read = Reader::read_u32_be(r)
    let mut crc = 0xFFFFFFFFU
    crc = crc32_update(crc, typ)
    crc = crc32_update(crc, chunk)
    let crc_calc = crc ^ 0xFFFFFFFFU
    if crc_calc != crc_read {
      raise_png(CrcMismatch, "CRC mismatch")
    }
    validate_chunk_type(typ)
    let t0 = typ[0].to_int()
    let t1 = typ[1].to_int()
    let t2 = typ[2].to_int()
    let t3 = typ[3].to_int()
    if seen_idat &&
      !(t0 == 73 && t1 == 68 && t2 == 65 && t3 == 84) &&
      !(t0 == 73 && t1 == 69 && t2 == 78 && t3 == 68) {
      ended_idat = true
    }

    // PNG 规范：IHDR 必须是第一个 chunk（这里统一按 “缺少 IHDR” 处理，保持兼容）。
    if !seen_ihdr && !(t0 == 73 && t1 == 72 && t2 == 68 && t3 == 82) {
      raise_png(MissingChunk, "missing IHDR")
    }
    if t0 == 73 && t1 == 72 && t2 == 68 && t3 == 82 {
      if seen_ihdr {
        raise_png(InvalidChunk, "duplicate IHDR chunk")
      }
      ihdr = Some(parse_ihdr(chunk))
      validate_color(ihdr.unwrap())
      seen_ihdr = true
    } else if t0 == 80 && t1 == 76 && t2 == 84 && t3 == 69 {
      if palette is Some(_) {
        raise_png(InvalidChunk, "duplicate PLTE chunk")
      }
      if seen_idat {
        raise_png(InvalidChunk, "PLTE after IDAT")
      }
      validate_plte(chunk)
      palette = Some(chunk.to_array())
    } else if t0 == 116 && t1 == 82 && t2 == 78 && t3 == 83 {
      if trns is Some(_) {
        raise_png(InvalidChunk, "duplicate tRNS chunk")
      }
      if seen_idat {
        raise_png(InvalidChunk, "tRNS after IDAT")
      }
      // tRNS 的合法性和长度依赖 IHDR（以及调色板长度）。
      let h = ihdr.unwrap()
      match h.color_type {
        0 =>
          if chunk.length() != 2 {
            raise_png(InvalidChunk, "invalid tRNS length")
          }
        2 =>
          if chunk.length() != 6 {
            raise_png(InvalidChunk, "invalid tRNS length")
          }
        3 => {
          let pal = palette.unwrap_or_else(fn() {
            raise_png(MissingChunk, "tRNS before PLTE")
          })
          let max_len = pal.length() / 3
          if chunk.length() > max_len {
            raise_png(InvalidChunk, "invalid tRNS length")
          }
        }
        4 | 6 =>
          raise_png(InvalidChunk, "tRNS is not allowed for alpha color types")
        _ => raise_png(Unsupported, "unsupported color type")
      }
      trns = Some(chunk)
    } else if t0 == 73 && t1 == 68 && t2 == 65 && t3 == 84 {
      if ended_idat {
        raise_png(InvalidChunk, "IDAT after non-IDAT chunk")
      }
      let h = ihdr.unwrap()
      if h.color_type == 3 && palette is None {
        raise_png(MissingChunk, "missing PLTE")
      }
      seen_idat = true
      match options.max_idat_bytes {
        Some(m) =>
          if idat_total + len > m {
            raise_png(LimitExceeded, "IDAT data exceeds limit")
          }
        None => ()
      }
      idat_total = idat_total + len
      idat.push_iter(chunk.iter())
    } else if t0 == 103 && t1 == 65 && t2 == 77 && t3 == 65 {
      if gamma is Some(_) {
        raise_png(InvalidChunk, "duplicate gAMA chunk")
      }
      gamma = Some(parse_gama(chunk))
    } else if t0 == 115 && t1 == 82 && t2 == 71 && t3 == 66 {
      if srgb_intent is Some(_) {
        raise_png(InvalidChunk, "duplicate sRGB chunk")
      }
      srgb_intent = Some(parse_srgb(chunk))
    } else if t0 == 105 && t1 == 67 && t2 == 67 && t3 == 80 {
      if iccp is Some(_) {
        raise_png(InvalidChunk, "duplicate iCCP chunk")
      }
      iccp = Some(parse_iccp(chunk, options.max_decompressed_bytes))
    } else if t0 == 112 && t1 == 72 && t2 == 89 && t3 == 115 {
      if phys is Some(_) {
        raise_png(InvalidChunk, "duplicate pHYs chunk")
      }
      phys = Some(parse_phys(chunk))
    } else if t0 == 116 && t1 == 73 && t2 == 77 && t3 == 69 {
      if time is Some(_) {
        raise_png(InvalidChunk, "duplicate tIME chunk")
      }
      time = Some(parse_time(chunk))
    } else if t0 == 116 && t1 == 69 && t2 == 88 && t3 == 116 {
      texts.push(parse_text(chunk))
    } else if t0 == 122 && t1 == 84 && t2 == 88 && t3 == 116 {
      texts.push(parse_ztxt(chunk, options.max_decompressed_bytes))
    } else if t0 == 105 && t1 == 84 && t2 == 88 && t3 == 116 {
      texts.push(parse_itxt(chunk, options.max_decompressed_bytes))
    } else if t0 == 73 && t1 == 69 && t2 == 78 && t3 == 68 {
      if !seen_idat {
        raise_png(MissingChunk, "missing IDAT")
      }
      break
    } else {
      // 未识别 chunk：未知 critical chunk 按规范应视为错误；未知 ancillary chunk 忽略。
      let is_critical = (t0 & 0x20) == 0
      if is_critical {
        raise_png(Unsupported, "unknown critical chunk")
      }
    }
  }
  let ihdr = match ihdr {
    Some(h) => h
    None => raise_png(MissingChunk, "missing IHDR")
  }
  validate_dimensions(ihdr, options)
  let idat_bytes = Bytes::from_array(idat.op_as_view())
  let inflated = zlib_inflate_limited(
    idat_bytes.op_as_view(),
    options.max_decompressed_bytes,
  )

  // 解析灰度/真彩的 tRNS；调色板的 tRNS 直接保留为 BytesView。
  if trns is Some(t) {
    match ihdr.color_type {
      0 =>
        if t.length() == 2 {
          let rr = Reader::new(t)
          trns_gray = Some(Reader::read_u16_be(rr))
        }
      2 =>
        if t.length() == 6 {
          let rr = Reader::new(t)
          let r0 = Reader::read_u16_be(rr)
          let g0 = Reader::read_u16_be(rr)
          let b0 = Reader::read_u16_be(rr)
          trns_rgb = Some((r0, g0, b0))
        }
      _ => ()
    }
  }
  let rgba = if ihdr.interlace == 0 {
    decode_non_interlaced(
      ihdr,
      inflated.op_as_view(),
      palette,
      trns,
      trns_gray,
      trns_rgb,
    )
  } else if ihdr.interlace == 1 {
    decode_adam7(
      ihdr,
      inflated.op_as_view(),
      palette,
      trns,
      trns_gray,
      trns_rgb,
    )
  } else {
    raise_png(Unsupported, "unsupported interlace method")
  }
  let metadata : PngMetadata = {
    gamma,
    srgb_intent,
    iccp,
    phys,
    time,
    texts: ReadOnlyArray::from_array(texts.op_as_view()),
  }
  { image: { width: ihdr.width, height: ihdr.height, rgba }, metadata }
}

///|
/// 解码 PNG，输出 RGBA8。
pub fn decode_png(data : BytesView) -> Image raise Failure {
  decode_png_with_options(data, options=DecodeOptions::unlimited())
}

///|
/// 解码 PNG。
pub fn decode_png_with_options(
  data : BytesView,
  options? : DecodeOptions = DecodeOptions::default(),
) -> Image raise Failure {
  decode_png_impl(data, options).image catch {
    PngError((_, message)) => fail(message)
  }
}

///|
/// 解码 PNG，返回 `Result`。
pub fn decode_png_result(data : BytesView) -> Result[Image, PngError] {
  decode_png_with_options_result(data, options=DecodeOptions::unlimited())
}

///|
/// 解码 PNG，返回 `Result`。
pub fn decode_png_with_options_result(
  data : BytesView,
  options? : DecodeOptions = DecodeOptions::default(),
) -> Result[Image, PngError] {
  Ok(decode_png_impl(data, options).image) catch {
    e => Err(e)
  }
}

///|
/// 解码 PNG 并返回元数据（`Result`）。
pub fn decode_png_with_metadata_result(
  data : BytesView,
  options? : DecodeOptions = DecodeOptions::default(),
) -> Result[DecodedPng, PngError] {
  Ok(decode_png_impl(data, options)) catch {
    e => Err(e)
  }
}

///|
/// 解码 PNG 并返回元数据（`raise Failure`）。
pub fn decode_png_with_metadata(
  data : BytesView,
  options? : DecodeOptions = DecodeOptions::default(),
) -> DecodedPng raise Failure {
  decode_png_impl(data, options) catch {
    PngError((_, message)) => fail(message)
  }
}
