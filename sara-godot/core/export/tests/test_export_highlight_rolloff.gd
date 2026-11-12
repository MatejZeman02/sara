## An export to a format that clips (PNG, JPEG and the 16-bit
## TIFF) may run the view's own highlight rolloff over a value outside 0 to 1
## instead of clipping it outright, with the export dialog's rolloff check
## saying which of the two will happen. A painter: "The Export should respect
## if tonemapper is enabled and don't simply clip HDR color on png/tiff."
##
## `shaders/compute/tonemap_rolloff.gmacs` is the port of `highlight_rolloff`
## in `shaders/canvas/tonemap.gdshader`, run through `SaExportGamut`'s cell
## walk after the gamut conversion and before the byte rounding.
##
## A pure red ramp rather than a grey one, because a grey's magnitude clips to
## white under both operators (white stays white): only a
## chromatic value shows the difference, on the channels a plain clip leaves at
## zero and the rolloff brings towards white as chroma falls.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the cell walk dispatches a real kernel.
const REQUIRES_GPU := true

const CHUNK := SaChunk.SIZE
const KNEE := 0.5
const DESATURATION := 0.15


## A chunk-sized RGBA32F texture whose every texel is `(stored, 0, 0, 1)`.
func _make_red(stored: float) -> SaTexture:
    var texture := SaTexture.new(Vector2i(CHUNK, CHUNK))
    var texels := PackedFloat32Array()
    texels.resize(CHUNK * CHUNK * 4)
    for i in CHUNK * CHUNK:
        texels[i * 4 + 0] = stored
        texels[i * 4 + 1] = 0.0
        texels[i * 4 + 2] = 0.0
        texels[i * 4 + 3] = 1.0
    texture.rd.texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


func _clipped_byte(stored: float) -> Color:
    var texture := _make_red(stored)
    return SaExportGamut.encoded_byte_image(texture, SaColorSpace.srgb()).get_pixel(0, 0)


func _rolled_byte(stored: float) -> Color:
    var texture := _make_red(stored)
    var tonemap := SaExportGamut.tonemap_params(true, KNEE, DESATURATION, 1.0)
    return SaExportGamut.encoded_byte_image(texture, SaColorSpace.srgb(), null, tonemap).get_pixel(0, 0)


func test_tonemap_params_is_empty_when_disabled() -> void:
    assert_true(SaExportGamut.tonemap_params(false, KNEE, DESATURATION, 1.0).is_empty(), "off means nothing to dispatch")
    assert_false(SaExportGamut.tonemap_params(true, KNEE, DESATURATION, 1.0).is_empty(), "on means a push constant")


func test_the_files_top_value_is_one_clipped_and_rolled() -> void:
    assert_eq(_clipped_byte(4.0).r8, 255, "the clipped file's peak channel tops out at 255")
    assert_eq(_rolled_byte(4.0).r8, 255, "the rolled file's peak channel tops out there too, white stays white")


func test_the_clipped_file_is_flat_from_one_up() -> void:
    var at_one := _clipped_byte(1.0)
    var at_two := _clipped_byte(2.0)
    var at_four := _clipped_byte(4.0)
    assert_eq(at_one, at_two, "a clip has nothing left to move once the peak channel is already 255")
    assert_eq(at_one, at_four, "flat all the way to a stored 4")
    assert_eq(at_one.g8, 0, "and the channels the document never wrote stay at 0")


func test_the_rolled_file_still_rises_at_two() -> void:
    var at_one := _rolled_byte(1.0)
    var at_two := _rolled_byte(2.0)
    var at_four := _rolled_byte(4.0)
    assert_eq(at_one.r8, 255, "the peak channel is capped at the knee crossing, same as the clip")
    assert_true(at_two.g8 > at_one.g8, "chroma keeps falling past the knee, so green keeps rising towards white")
    assert_true(at_four.g8 > at_two.g8, "and further still by a stored 4")


func test_a_value_at_or_under_the_knee_is_unaffected() -> void:
    var clipped := _clipped_byte(0.4)
    var rolled := _rolled_byte(0.4)
    assert_eq(clipped, rolled, "under the knee the rolloff is the identity, so both agree with a plain clip")
