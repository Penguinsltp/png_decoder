///|
priv struct Reader {
  data : BytesView
  mut pos : Int
}

///|
fn Reader::new(data : BytesView) -> Reader {
  { data, pos: 0 }
}

///|
fn Reader::remaining(r : Reader) -> Int {
  r.data.length() - r.pos
}

///|
fn Reader::read_u8(r : Reader) -> Byte raise PngError {
  if r.pos >= r.data.length() {
    raise_png(UnexpectedEof, "unexpected EOF")
  }
  let b = r.data[r.pos]
  r.pos = r.pos + 1
  b
}

///|
fn Reader::read_u16_be(r : Reader) -> Int raise PngError {
  let b0 = Reader::read_u8(r).to_int()
  let b1 = Reader::read_u8(r).to_int()
  (b0 << 8) | b1
}

///|
fn Reader::read_u32_be(r : Reader) -> UInt raise PngError {
  let b0 = Reader::read_u8(r).to_uint()
  let b1 = Reader::read_u8(r).to_uint()
  let b2 = Reader::read_u8(r).to_uint()
  let b3 = Reader::read_u8(r).to_uint()
  (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}

///|
fn Reader::read_bytes_view(r : Reader, len : Int) -> BytesView raise PngError {
  if len < 0 || Reader::remaining(r) < len {
    raise_png(UnexpectedEof, "unexpected EOF")
  }
  let start = r.pos
  r.pos = r.pos + len
  r.data.sub(start~, end=start + len)
}
