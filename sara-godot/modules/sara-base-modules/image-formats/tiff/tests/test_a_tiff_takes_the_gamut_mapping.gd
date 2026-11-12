## The gamut mapping preference reaches the 16-bit
## TIFF and leaves the 32-bit one alone.
##
## The preference offers clip or oklab, and Oklab locks the hue and moves chroma
## until in range. The PNG, JPEG and EXR halves stay in the skeleton's
## `test_the_gamut_mapping_preference.gd`, and this is the TIFF's, which moved
## with the writer into this module. One texture holding a negative channel and
## a channel above one is written in each mode. The 16-bit files have to differ,
## because the narrowing took the mode, and the 32-bit files have to be the same
## byte for byte, which is the no-clamp invariant (hard rule 5).
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the cell walk dispatches real kernels.
const REQUIRES_GPU := true

## The texture's side, small because the file is all that is read.
const SIDE := 16

## A colour outside the cube on two sides, red above one and green below zero.
const OUTSIDE := Color(1.2, -0.2, 0.3, 1.0)

var _scratch: Array[String] = []


func after_each() -> void:
    for path: String in _scratch:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _scratch.clear()


## A square RGBA32F texture whose every texel is *stored*.
func _filled(stored: Color) -> SaTexture:
    var texture := SaTexture.new(Vector2i(SIDE, SIDE))
    var texels := PackedFloat32Array()
    texels.resize(SIDE * SIDE * 4)
    for i in SIDE * SIDE:
        texels[i * 4 + 0] = stored.r
        texels[i * 4 + 1] = stored.g
        texels[i * 4 + 2] = stored.b
        texels[i * 4 + 3] = stored.a
    texture.rd.texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


func _path(file: String) -> String:
    var path := SaDataRoot.path("g1-tiff-%s" % file)
    _scratch.append(path)
    return path


## Both modes of one texture at *bits*, returned as the two files' bytes.
func _both(bits: int) -> Array[PackedByteArray]:
    var texture := _filled(OUTSIDE)
    var written: Array[PackedByteArray] = []
    for mode: String in [SaGamutMapping.CLIP, SaGamutMapping.OKLAB]:
        var path := _path("%s-%d.tiff" % [mode, bits])
        assert_eq(
            SaExportTiff.export_texture(
                texture, path, 96.0, SaColorSpace.srgb(), bits, PackedFloat32Array(), mode, SaExportMetadata.new()
            ),
            OK,
            "The %d-bit TIFF in %s is written" % [bits, mode]
        )
        written.append(FileAccess.get_file_as_bytes(path))
    return written


func test_the_16_bit_tiff_takes_the_mode() -> void:
    var written := _both(16)
    assert_false(written[0].is_empty(), "The clipped 16-bit TIFF was written")
    assert_true(written[0] != written[1], "and the oklab one differs from it")


func test_the_32_bit_tiff_never_sees_the_mapping() -> void:
    var written := _both(32)
    assert_false(written[0].is_empty(), "The clipped 32-bit TIFF was written")
    assert_eq(written[1], written[0], "The 32-bit TIFF never sees the mapping")
