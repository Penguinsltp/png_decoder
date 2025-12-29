///|
/// PNG 解码错误分类。
pub enum PngErrorKind {
  InvalidSignature
  MissingChunk
  InvalidChunk
  CrcMismatch
  Unsupported
  InflateError
  InvalidData
  LimitExceeded
  UnexpectedEof
}

///|
pub fn PngErrorKind::to_string(kind : PngErrorKind) -> String {
  match kind {
    InvalidSignature => "InvalidSignature"
    MissingChunk => "MissingChunk"
    InvalidChunk => "InvalidChunk"
    CrcMismatch => "CrcMismatch"
    Unsupported => "Unsupported"
    InflateError => "InflateError"
    InvalidData => "InvalidData"
    LimitExceeded => "LimitExceeded"
    UnexpectedEof => "UnexpectedEof"
  }
}

///|
/// PNG 解码错误。
pub suberror PngError (PngErrorKind, String)

///|
pub fn PngError::new(kind~ : PngErrorKind, message~ : String) -> PngError {
  PngError((kind, message))
}

///|
pub fn PngError::kind(e : PngError) -> PngErrorKind {
  let PngError((kind, _)) = e
  kind
}

///|
pub fn PngError::message(e : PngError) -> String {
  let PngError((_, message)) = e
  message
}

///|
pub fn PngError::to_string(e : PngError) -> String {
  let PngError((kind, message)) = e
  "(" + PngErrorKind::to_string(kind) + ") " + message
}

///|
fn[T] raise_png(kind : PngErrorKind, message : String) -> T raise PngError {
  raise PngError((kind, message))
}
