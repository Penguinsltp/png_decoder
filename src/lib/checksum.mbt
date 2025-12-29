///|
let crc32_table : Array[UInt] = {
  let table = Array::make(256, 0U)
  let poly = 0xEDB88320U
  for i = 0; i < 256; i = i + 1 {
    let mut c = UInt::trunc_double(i.to_double())
    for j = 0; j < 8; j = j + 1 {
      if (c & 1U) == 1U {
        c = (c >> 1) ^ poly
      } else {
        c = c >> 1
      }
    }
    table[i] = c
  }
  table
}

///|
fn crc32_update(crc : UInt, data : BytesView) -> UInt {
  let mut crc = crc
  for i = 0; i < data.length(); i = i + 1 {
    let byte = data[i].to_uint()
    let idx = (crc ^ byte) & 0xFFU
    crc = crc32_table[idx.reinterpret_as_int()] ^ (crc >> 8)
  }
  crc
}

///|
fn adler32(data : BytesView) -> UInt {
  let mod_adler = 65521
  let mut s1 = 1
  let mut s2 = 0
  for i = 0; i < data.length(); i = i + 1 {
    s1 = (s1 + data[i].to_int()) % mod_adler
    s2 = (s2 + s1) % mod_adler
  }
  (UInt::trunc_double(s2.to_double()) << 16) |
  UInt::trunc_double(s1.to_double())
}
