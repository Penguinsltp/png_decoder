///|
fn bytes_from_ints(ints : ReadOnlyArray[Int]) -> Bytes {
  let arr = ints.op_as_view().map(fn(x : Int) { x.to_byte() })
  Bytes::from_array(arr.op_as_view())
}

///|
let png1_ints : ReadOnlyArray[Int] = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0,
  0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99,
  248, 207, 192, 240, 31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0, 0, 0, 73, 69,
  78, 68, 174, 66, 96, 130,
]

///|
let png2_ints : ReadOnlyArray[Int] = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 2, 0, 0,
  0, 2, 1, 3, 0, 0, 0, 72, 120, 159, 103, 0, 0, 0, 6, 80, 76, 84, 69, 0, 0, 0, 255,
  255, 255, 165, 217, 159, 221, 0, 0, 0, 2, 116, 82, 78, 83, 255, 128, 8, 15, 179,
  106, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 112, 96, 104, 0, 0, 1, 68, 0, 193,
  58, 122, 28, 86, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]

///|
let png3_ints : ReadOnlyArray[Int] = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 3, 0, 0,
  0, 1, 1, 0, 0, 0, 0, 51, 155, 41, 25, 0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99,
  112, 0, 0, 0, 66, 0, 65, 41, 55, 244, 239, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66,
  96, 130,
]

///|
let png4_ints : ReadOnlyArray[Int] = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 3, 0, 0,
  0, 3, 8, 6, 0, 0, 1, 33, 47, 133, 41, 0, 0, 0, 47, 73, 68, 65, 84, 120, 156, 99,
  224, 18, 97, 253, 207, 16, 37, 226, 248, 159, 129, 171, 194, 241, 127, 84, 69,
  237, 127, 6, 35, 17, 101, 32, 81, 17, 15, 20, 114, 83, 254, 111, 228, 6, 20, 118,
  139, 255, 15, 0, 38, 118, 15, 121, 202, 147, 146, 16, 0, 0, 0, 0, 73, 69, 78, 68,
  174, 66, 96, 130,
]

///|
test "解码 RGBA8 1x1" {
  let img = decode_png(bytes_from_ints(png1_ints).op_as_view())
  assert_eq(img.width, 1)
  assert_eq(img.height, 1)
  let got = img.rgba.to_array()
  let expected = [255, 0, 0, 255].map(fn(x : Int) { x.to_byte() })
  assert_eq(got, expected)
}

///|
test "解码 调色板(1-bit) + tRNS 2x2" {
  let img = decode_png(bytes_from_ints(png2_ints).op_as_view())
  assert_eq(img.width, 2)
  assert_eq(img.height, 2)
  let got = img.rgba.to_array()
  // 像素索引：[0,1; 1,0]，其中索引 1 的 alpha = 128
  let expected = [
    0, 0, 0, 255, 255, 255, 255, 128, 255, 255, 255, 128, 0, 0, 0, 255,
  ].map(fn(x : Int) { x.to_byte() })
  assert_eq(got, expected)
}

///|
test "解码 灰度(1-bit) 3x1" {
  let img = decode_png(bytes_from_ints(png3_ints).op_as_view())
  assert_eq(img.width, 3)
  assert_eq(img.height, 1)
  let got = img.rgba.to_array()
  let expected = [0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255].map(fn(
    x : Int,
  ) {
    x.to_byte()
  })
  assert_eq(got, expected)
}

///|
test "解码 Adam7 交错 RGBA8 3x3" {
  let img = decode_png(bytes_from_ints(png4_ints).op_as_view())
  assert_eq(img.width, 3)
  assert_eq(img.height, 3)
  let rgba = img.rgba.to_array()
  fn pixel(rgba : Array[Byte], x : Int, y : Int) -> (Int, Int, Int, Int) {
    let i = (y * 3 + x) * 4
    (
      rgba[i].to_int(),
      rgba[i + 1].to_int(),
      rgba[i + 2].to_int(),
      rgba[i + 3].to_int(),
    )
  }

  // 像素生成公式：px[y][x] = (x*40+10, y*50+20, (x+y)*30+5, 255)
  assert_eq(pixel(rgba, 0, 0), (10, 20, 5, 255))
  assert_eq(pixel(rgba, 2, 0), (90, 20, 65, 255))
  assert_eq(pixel(rgba, 0, 2), (10, 120, 65, 255))
  assert_eq(pixel(rgba, 2, 2), (90, 120, 125, 255))
}

///|
test "Result API: 成功" {
  let res = decode_png_result(bytes_from_ints(png1_ints).op_as_view())
  match res {
    Ok(img) => {
      assert_eq(img.width, 1)
      assert_eq(img.height, 1)
    }
    Err(_) => fail("should be Ok")
  }
}

///|
test "Result API: 触发像素上限" {
  let options = DecodeOptions::new(max_pixels=1)
  let res = decode_png_with_options_result(
    bytes_from_ints(png4_ints).op_as_view(),
    options~,
  )
  match res {
    Ok(_) => fail("should be Err")
    Err(PngError((LimitExceeded, _))) => ()
    Err(e) => fail("unexpected error: " + PngError::message(e))
  }
}

///|
test "Result API: CRC 错误" {
  let arr = bytes_from_ints(png1_ints).to_array()
  // 随便翻转一个字节，使 CRC 校验失败
  arr[25] = (arr[25].to_int() ^ 1).to_byte()
  let bad = Bytes::from_array(arr.op_as_view())
  let res = decode_png_with_options_result(
    bad.op_as_view(),
    options=DecodeOptions::unlimited(),
  )
  match res {
    Ok(_) => fail("should be Err")
    Err(PngError((CrcMismatch, _))) => ()
    Err(e) => fail("unexpected error: " + PngError::message(e))
  }
}

///|
test "Result API: 签名错误" {
  let arr = bytes_from_ints(png1_ints).to_array()
  arr[0] = Byte::default()
  let bad = Bytes::from_array(arr.op_as_view())
  let res = decode_png_result(bad.op_as_view())
  match res {
    Ok(_) => fail("should be Err")
    Err(PngError((InvalidSignature, _))) => ()
    Err(e) => fail("unexpected error: " + PngError::message(e))
  }
}

///|
test "Result API: 缺少 IHDR" {
  // signature + IEND(空) 的最小结构（CRC 固定为 AE426082）
  let bytes = Bytes::from_array(
    [
      137, 80, 78, 71, 13, 10, 26, 10, // PNG signature
       0, 0, 0, 0, // length
       73, 69, 78, 68, // IEND
       174, 66, 96, 130, // crc
    ]
    .map(fn(x : Int) { x.to_byte() })
    .op_as_view(),
  )
  let res = decode_png_result(bytes.op_as_view())
  match res {
    Ok(_) => fail("should be Err")
    Err(PngError((MissingChunk, _))) => ()
    Err(e) => fail("unexpected error: " + PngError::message(e))
  }
}

///|
test "Result API: 缺少 IEND" {
  let arr = bytes_from_ints(png1_ints).to_array()
  // 去掉最后 12 字节（IEND chunk）
  let truncated = Bytes::from_array(arr.sub(start=0, end=arr.length() - 12))
  let res = decode_png_result(truncated.op_as_view())
  match res {
    Ok(_) => fail("should be Err")
    Err(PngError((MissingChunk, _))) => ()
    Err(e) => fail("unexpected error: " + PngError::message(e))
  }
}

///|
test "Result API: IDAT 上限" {
  let options = DecodeOptions::new(max_idat_bytes=1)
  let res = decode_png_with_options_result(
    bytes_from_ints(png1_ints).op_as_view(),
    options~,
  )
  match res {
    Ok(_) => fail("should be Err")
    Err(PngError((LimitExceeded, _))) => ()
    Err(e) => fail("unexpected error: " + PngError::message(e))
  }
}

///|
test "Result API: 解压输出上限" {
  let options = DecodeOptions::new(max_decompressed_bytes=1)
  let res = decode_png_with_options_result(
    bytes_from_ints(png1_ints).op_as_view(),
    options~,
  )
  match res {
    Ok(_) => fail("should be Err")
    Err(PngError((LimitExceeded, _))) => ()
    Err(e) => fail("unexpected error: " + PngError::message(e))
  }
}

///|
let png_meta_ints : ReadOnlyArray[Int] = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0,
  0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 4, 103, 65, 77, 65, 0, 0, 177,
  143, 11, 252, 97, 5, 0, 0, 0, 1, 115, 82, 71, 66, 0, 174, 206, 28, 233, 0, 0, 0,
  27, 105, 67, 67, 80, 105, 99, 99, 0, 0, 120, 156, 75, 75, 204, 78, 205, 76, 78,
  46, 40, 202, 79, 203, 204, 73, 5, 0, 42, 142, 5, 184, 51, 164, 13, 134, 0, 0, 0,
  9, 112, 72, 89, 115, 0, 0, 14, 196, 0, 0, 14, 196, 1, 149, 43, 14, 27, 0, 0, 0,
  7, 116, 73, 77, 69, 7, 233, 12, 29, 12, 34, 56, 28, 182, 133, 115, 0, 0, 0, 13,
  116, 69, 88, 116, 67, 111, 109, 109, 101, 110, 116, 0, 104, 101, 108, 108, 111,
  230, 255, 174, 36, 0, 0, 0, 16, 122, 84, 88, 116, 90, 0, 0, 120, 156, 43, 207,
  47, 202, 73, 1, 0, 6, 166, 2, 41, 9, 217, 239, 98, 0, 0, 0, 18, 105, 84, 88, 116,
  84, 105, 116, 108, 101, 0, 0, 0, 101, 110, 0, 0, 228, 189, 160, 229, 165, 189,
  251, 20, 62, 71, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 240,
  31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96,
  130,
]

///|
fn find_text(
  entries : ReadOnlyArray[PngTextEntry],
  keyword : String,
) -> PngTextEntry? {
  for i = 0; i < entries.length(); i = i + 1 {
    let e = entries[i]
    if e.keyword == keyword {
      return Some(e)
    }
  }
  None
}

///|
test "Metadata: gAMA/sRGB/iCCP/pHYs/tIME/text" {
  let res = decode_png_with_metadata_result(
    bytes_from_ints(png_meta_ints).op_as_view(),
    options=DecodeOptions::unlimited(),
  )
  match res {
    Err(e) => fail("unexpected error: " + PngError::to_string(e))
    Ok(decoded) => {
      assert_eq(decoded.image.width, 1)
      assert_eq(decoded.image.height, 1)
      let meta = decoded.metadata
      assert_eq(meta.gamma, Some(45455U))
      assert_eq(meta.srgb_intent, Some(0))
      match meta.iccp {
        None => fail("missing iccp")
        Some(iccp) => {
          assert_eq(iccp.name, "icc")
          let expected_profile = [
            102, 97, 107, 101, 105, 99, 99, 112, 114, 111, 102, 105, 108, 101,
          ].map(fn(x : Int) { x.to_byte() })
          assert_eq(iccp.profile.to_array(), expected_profile)
        }
      }
      match meta.phys {
        None => fail("missing phys")
        Some(p) => {
          assert_eq(p.pixels_per_unit_x, 3780U)
          assert_eq(p.pixels_per_unit_y, 3780U)
          assert_true(p.unit_is_meter)
        }
      }
      match meta.time {
        None => fail("missing time")
        Some(t) => {
          assert_eq(t.year, 2025)
          assert_eq(t.month, 12)
          assert_eq(t.day, 29)
          assert_eq(t.hour, 12)
          assert_eq(t.minute, 34)
          assert_eq(t.second, 56)
        }
      }
      let comment = find_text(meta.texts, "Comment").unwrap()
      assert_eq(comment.text, "hello")
      match comment.encoding {
        Latin1 => ()
        _ => fail("unexpected encoding")
      }
      assert_false(comment.compressed)
      let z = find_text(meta.texts, "Z").unwrap()
      assert_eq(z.text, "world")
      match z.encoding {
        Latin1 => ()
        _ => fail("unexpected encoding")
      }
      assert_true(z.compressed)
      let title = find_text(meta.texts, "Title").unwrap()
      assert_eq(title.text, "你好")
      match title.encoding {
        Utf8 => ()
        _ => fail("unexpected encoding")
      }
      assert_false(title.compressed)
      assert_eq(title.language_tag, Some("en"))
      assert_eq(title.translated_keyword, Some(""))
    }
  }
}

///|
let png_unknown_critical_chunk : ReadOnlyArray[Int] = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0,
  0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 0, 65, 66, 67, 68, 219, 23, 32,
  165, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 240, 31, 0, 5, 0,
  1, 255, 137, 153, 61, 29, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]

///|
test "规范：未知 critical chunk 应报错" {
  let res = decode_png_result(
    bytes_from_ints(png_unknown_critical_chunk).op_as_view(),
  )
  match res {
    Ok(_) => fail("expected error")
    Err(e) =>
      match PngError::kind(e) {
        Unsupported => ()
        _ =>
          fail("unexpected kind: " + PngErrorKind::to_string(PngError::kind(e)))
      }
  }
}
