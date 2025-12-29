///|
pub enum PngTextEncoding {
  Latin1
  Utf8
}

///|
pub struct PngTextEntry {
  keyword : String
  text : String
  encoding : PngTextEncoding
  language_tag : String?
  translated_keyword : String?
  compressed : Bool
}

///|
pub struct PngPhys {
  pixels_per_unit_x : UInt
  pixels_per_unit_y : UInt
  unit_is_meter : Bool
}

///|
pub struct PngTime {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
}

///|
pub struct PngIccp {
  name : String
  profile : Bytes
}

///|
pub struct PngMetadata {
  gamma : UInt?
  srgb_intent : Int?
  iccp : PngIccp?
  phys : PngPhys?
  time : PngTime?
  texts : ReadOnlyArray[PngTextEntry]
}

///|
fn latin1_to_string(view : BytesView) -> String {
  let sb = StringBuilder::new()
  for i = 0; i < view.length(); i = i + 1 {
    sb.write_char(view[i].to_char())
  }
  sb.to_string()
}

///|
fn bytes_to_utf8_string(view : BytesView) -> String raise PngError {
  let sb = StringBuilder::new()
  let to_char = fn(cp : Int) -> Char raise PngError {
    cp
    .to_char()
    .unwrap_or_else(fn() {
      raise_png(InvalidChunk, "invalid UTF-8: invalid code point")
    })
  }
  let mut i = 0
  while i < view.length() {
    let b0 = view[i].to_int()
    if b0 < 0x80 {
      sb.write_char(to_char(b0))
      i = i + 1
    } else if b0 >= 0xC2 && b0 <= 0xDF {
      if i + 1 >= view.length() {
        raise_png(InvalidChunk, "invalid UTF-8: truncated sequence")
      }
      let b1 = view[i + 1].to_int()
      if b1 < 0x80 || b1 > 0xBF {
        raise_png(InvalidChunk, "invalid UTF-8: bad continuation byte")
      }
      let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      sb.write_char(to_char(cp))
      i = i + 2
    } else if b0 >= 0xE0 && b0 <= 0xEF {
      if i + 2 >= view.length() {
        raise_png(InvalidChunk, "invalid UTF-8: truncated sequence")
      }
      let b1 = view[i + 1].to_int()
      let b2 = view[i + 2].to_int()
      if b1 < 0x80 || b1 > 0xBF || b2 < 0x80 || b2 > 0xBF {
        raise_png(InvalidChunk, "invalid UTF-8: bad continuation byte")
      }
      if b0 == 0xE0 && b1 < 0xA0 {
        raise_png(InvalidChunk, "invalid UTF-8: overlong encoding")
      }
      if b0 == 0xED && b1 >= 0xA0 {
        raise_png(InvalidChunk, "invalid UTF-8: surrogate half")
      }
      let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      if cp >= 0xD800 && cp <= 0xDFFF {
        raise_png(InvalidChunk, "invalid UTF-8: surrogate half")
      }
      sb.write_char(to_char(cp))
      i = i + 3
    } else if b0 >= 0xF0 && b0 <= 0xF4 {
      if i + 3 >= view.length() {
        raise_png(InvalidChunk, "invalid UTF-8: truncated sequence")
      }
      let b1 = view[i + 1].to_int()
      let b2 = view[i + 2].to_int()
      let b3 = view[i + 3].to_int()
      if b1 < 0x80 ||
        b1 > 0xBF ||
        b2 < 0x80 ||
        b2 > 0xBF ||
        b3 < 0x80 ||
        b3 > 0xBF {
        raise_png(InvalidChunk, "invalid UTF-8: bad continuation byte")
      }
      if b0 == 0xF0 && b1 < 0x90 {
        raise_png(InvalidChunk, "invalid UTF-8: overlong encoding")
      }
      if b0 == 0xF4 && b1 > 0x8F {
        raise_png(InvalidChunk, "invalid UTF-8: code point too large")
      }
      let cp = ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      if cp > 0x10FFFF {
        raise_png(InvalidChunk, "invalid UTF-8: code point too large")
      }
      let cp0 = cp - 0x10000
      let hi = 0xD800 + (cp0 >> 10)
      let lo = 0xDC00 + (cp0 & 0x3FF)
      sb.write_char(to_char(hi))
      sb.write_char(to_char(lo))
      i = i + 4
    } else {
      raise_png(InvalidChunk, "invalid UTF-8: invalid leading byte")
    }
  }
  sb.to_string()
}

///|
fn find_nul(view : BytesView, start : Int) -> Int? {
  for i = start; i < view.length(); i = i + 1 {
    if view[i].to_int() == 0 {
      return Some(i)
    }
  }
  None
}

///|
fn parse_gama(chunk : BytesView) -> UInt raise PngError {
  if chunk.length() != 4 {
    raise_png(InvalidChunk, "invalid gAMA length")
  }
  let r = Reader::new(chunk)
  Reader::read_u32_be(r)
}

///|
fn parse_srgb(chunk : BytesView) -> Int raise PngError {
  if chunk.length() != 1 {
    raise_png(InvalidChunk, "invalid sRGB length")
  }
  chunk[0].to_int()
}

///|
fn parse_phys(chunk : BytesView) -> PngPhys raise PngError {
  if chunk.length() != 9 {
    raise_png(InvalidChunk, "invalid pHYs length")
  }
  let r = Reader::new(chunk)
  let x = Reader::read_u32_be(r)
  let y = Reader::read_u32_be(r)
  let unit = Reader::read_u8(r).to_int()
  if unit != 0 && unit != 1 {
    raise_png(InvalidChunk, "invalid pHYs unit specifier")
  }
  { pixels_per_unit_x: x, pixels_per_unit_y: y, unit_is_meter: unit == 1 }
}

///|
fn parse_time(chunk : BytesView) -> PngTime raise PngError {
  if chunk.length() != 7 {
    raise_png(InvalidChunk, "invalid tIME length")
  }
  let r = Reader::new(chunk)
  let year = Reader::read_u16_be(r)
  let month = Reader::read_u8(r).to_int()
  let day = Reader::read_u8(r).to_int()
  let hour = Reader::read_u8(r).to_int()
  let minute = Reader::read_u8(r).to_int()
  let second = Reader::read_u8(r).to_int()
  { year, month, day, hour, minute, second }
}

///|
fn parse_text(chunk : BytesView) -> PngTextEntry raise PngError {
  let nul = find_nul(chunk, 0).unwrap_or_else(fn() {
    raise_png(InvalidChunk, "invalid tEXt: missing NUL separator")
  })
  let keyword = latin1_to_string(chunk.sub(start=0, end=nul))
  let text = latin1_to_string(chunk.sub(start=nul + 1))
  {
    keyword,
    text,
    encoding: Latin1,
    language_tag: None,
    translated_keyword: None,
    compressed: false,
  }
}

///|
fn parse_ztxt(chunk : BytesView, max_out : Int?) -> PngTextEntry raise PngError {
  let nul = find_nul(chunk, 0).unwrap_or_else(fn() {
    raise_png(InvalidChunk, "invalid zTXt: missing NUL separator")
  })
  if nul + 2 > chunk.length() {
    raise_png(InvalidChunk, "invalid zTXt length")
  }
  let keyword = latin1_to_string(chunk.sub(start=0, end=nul))
  let compression_method = chunk[nul + 1].to_int()
  if compression_method != 0 {
    raise_png(Unsupported, "unsupported zTXt compression method")
  }
  let compressed = chunk.sub(start=nul + 2)
  let inflated = zlib_inflate_limited(compressed, max_out)
  let text = latin1_to_string(inflated.op_as_view())
  {
    keyword,
    text,
    encoding: Latin1,
    language_tag: None,
    translated_keyword: None,
    compressed: true,
  }
}

///|
fn parse_itxt(chunk : BytesView, max_out : Int?) -> PngTextEntry raise PngError {
  let nul0 = find_nul(chunk, 0).unwrap_or_else(fn() {
    raise_png(InvalidChunk, "invalid iTXt: missing keyword terminator")
  })
  if nul0 + 3 > chunk.length() {
    raise_png(InvalidChunk, "invalid iTXt length")
  }
  let keyword = latin1_to_string(chunk.sub(start=0, end=nul0))
  let compression_flag = chunk[nul0 + 1].to_int()
  let compression_method = chunk[nul0 + 2].to_int()
  let mut p = nul0 + 3
  let nul1 = find_nul(chunk, p).unwrap_or_else(fn() {
    raise_png(InvalidChunk, "invalid iTXt: missing language tag terminator")
  })
  let language_tag = bytes_to_utf8_string(chunk.sub(start=p, end=nul1))
  p = nul1 + 1
  let nul2 = find_nul(chunk, p).unwrap_or_else(fn() {
    raise_png(
      InvalidChunk,
      "invalid iTXt: missing translated keyword terminator",
    )
  })
  let translated_keyword = bytes_to_utf8_string(chunk.sub(start=p, end=nul2))
  p = nul2 + 1
  let text_bytes = if compression_flag == 1 {
    if compression_method != 0 {
      raise_png(Unsupported, "unsupported iTXt compression method")
    }
    zlib_inflate_limited(chunk.sub(start=p), max_out).op_as_view()
  } else if compression_flag == 0 {
    chunk.sub(start=p)
  } else {
    raise_png(InvalidChunk, "invalid iTXt compression flag")
  }
  let text = bytes_to_utf8_string(text_bytes)
  {
    keyword,
    text,
    encoding: Utf8,
    language_tag: Some(language_tag),
    translated_keyword: Some(translated_keyword),
    compressed: compression_flag == 1,
  }
}

///|
fn parse_iccp(chunk : BytesView, max_out : Int?) -> PngIccp raise PngError {
  let nul = find_nul(chunk, 0).unwrap_or_else(fn() {
    raise_png(InvalidChunk, "invalid iCCP: missing profile name terminator")
  })
  if nul + 2 > chunk.length() {
    raise_png(InvalidChunk, "invalid iCCP length")
  }
  let name = latin1_to_string(chunk.sub(start=0, end=nul))
  let compression_method = chunk[nul + 1].to_int()
  if compression_method != 0 {
    raise_png(Unsupported, "unsupported iCCP compression method")
  }
  let compressed = chunk.sub(start=nul + 2)
  let profile = zlib_inflate_limited(compressed, max_out)
  { name, profile }
}
