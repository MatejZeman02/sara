# image-formats

A Sara module: the picture formats Godot reads not at all or not well enough.

Godot opens PNG, JPEG, WebP and EXR, and Sara's skeleton keeps those four.
This module adds three more to the open dialog and, for two of them, to the
Export dialog. Without it Sara refuses a `.tif`, `.hdr` or `.ora` with a
sentence and nothing else changes.

| Format | Extensions | Read | Write |
| --- | --- | --- | --- |
| TIFF | `.tif`, `.tiff` | Yes | Yes |
| Radiance HDR | `.hdr` | Yes | No |
| OpenRaster | `.ora` | Yes | Yes |

## What each one handles

- **TIFF, read.** Uncompressed, LZW and PackBits strips, at 8, 16 or 32 bits a
  sample, integer or float. Tiled files, BigTIFF and JPEG compression are
  refused with a message.
- **TIFF, write.** 16-bit unsigned integer or 32-bit float, uncompressed. The
  float file keeps every value the canvas holds, negatives and values above 1.0
  included. The integer file is clamped to 0 to 1 like a PNG.
- **Radiance HDR, read only.** Godot has an `.hdr` loader of its own, but it
  clamps large values and refuses most of the format's layouts, so Sara reads
  the file itself and keeps the full range. There is no Radiance export.
- **OpenRaster, read and write.** The layer stack travels with the file, so a
  picture made in Krita, GIMP or MyPaint opens as the layers it was painted in,
  with names, opacity, visibility, blend modes and groups. The zip is written
  stored (not compressed) and read the same way, and Zip64 is not supported.

## Native code

TIFF files with LZW strips open about thirty times faster when the native
`tiff-lzw` library of this repository is built. A checkout without it opens the
same files in GDScript, slower. See the repository README.
