# Penguinsltp/png_decoder

基于MoonBit 实现的 PNG 解码器。

## 安装

在你的模块目录下执行：

```sh
moon add Penguinsltp/png_decoder
```

然后在你的包 `moon.pkg.json` 中导入（示例）：

```json
{
  "import": [
    { "path": "Penguinsltp/png_decoder/src/lib", "alias": "png" }
  ]
}
```

## 功能

- PNG chunk 解析与 CRC32 校验（对每个 chunk 严格校验 CRC）。
- 规范校验：chunk type 合法性（reserved bit）、未知 critical chunk 报错、PLTE/tRNS/IDAT 等关键约束。
- 支持 zlib/DEFLATE 解压（含 Adler32 校验）。
- 支持 5 种行滤波（None/Sub/Up/Average/Paeth）反滤波。
- 支持 Adam7 交错（interlace=1）与非交错（interlace=0）。
- 支持颜色类型：0(灰度)、2(RGB)、3(索引色/调色板)、4(灰度+Alpha)、6(RGBA)。
- 支持位深：1/2/4/8/16（输出统一为 RGBA8；16-bit 会降为 8-bit）。
- 支持透明：tRNS（索引色/灰度/RGB）。
- 支持解析并导出常见元数据 chunk：`gAMA` / `sRGB` / `iCCP` / `pHYs` / `tIME` / `tEXt` / `zTXt` / `iTXt`。