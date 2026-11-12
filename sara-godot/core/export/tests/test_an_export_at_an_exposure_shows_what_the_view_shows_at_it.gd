## of a painting pass's second board: a night scene whose lights stand above
## white, so the view's tone mapping brings them under white and an exposure
## change brings them back, and the proof folder holds "the export at two
## exposures, showing the lights hold detail at the lower one".
##
## The view multiplies by the display exposure before its rolloff, and no
## export did, so a PNG of the night could only ever be the picture at
## exposure 0. `SaExport.export_png` now takes `exposure_stops`, and the `export`
## step hands it on with `"tonemap": true`.
##
## Greys stand in for the lights, because the rolloff's peak is a grey's every
## channel: a grey at two and one at four both reach white at exposure 0, the
## detail between them gone, and at two stops under they are half white and
## white, the detail back.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the rolloff is a kernel.
const REQUIRES_GPU := true

static var scratch_path: String = SaDataRoot.path("test_p11_exposure.png")


func after_each() -> void:
    if FileAccess.file_exists(scratch_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))


## A small linear canvas filled with the grey whose light is *linear*, picked
## the way the colour step picks it, on the sRGB curve.
func _canvas_lit(linear: float) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(16, 16)
    var space := SaColorSpace.linear_srgb()
    canvas.easel = SaEasel.create_default(canvas.canvas_size, null, space)
    canvas.add_child(canvas.easel)
    var picked := space.carried_to(SaColorSpace.srgb(), Color(linear, linear, linear, 1.0))
    canvas.document.fill_layer(picked)
    canvas.easel.request_composite()
    canvas.easel.process_pending_composite()
    return canvas


## The middle byte of the PNG a grey of *linear* exports as, rolled off at
## *stops* when *tonemap*.
func _exported(linear: float, tonemap: bool, stops: float) -> int:
    var canvas := _canvas_lit(linear)
    var error := SaExport.export_png(canvas.easel, scratch_path, 8, tonemap, SaGamutMapping.CLIP, false, false, stops)
    canvas.free()
    assert_eq(error, OK, "the PNG is written")
    var image := Image.new()
    assert_eq(image.load_png_from_buffer(FileAccess.get_file_as_bytes(scratch_path)), OK, "and opens")
    return image.get_pixel(8, 8).r8


## sRGB's byte for a light of *linear*, the code a correct file holds.
func _byte_of(linear: float) -> int:
    var encoded := 12.92 * linear if linear <= 0.0031308 else 1.055 * pow(linear, 1.0 / 2.4) - 0.055
    return roundi(clampf(encoded, 0.0, 1.0) * 255.0)


func test_at_exposure_0_two_lights_above_white_are_one_white() -> void:
    assert_eq(_exported(2.0, true, 0.0), 255, "twice white is rolled to white")
    assert_eq(_exported(4.0, true, 0.0), 255, "and four times white to the same white, the detail between them gone")


func test_two_stops_under_brings_the_detail_back() -> void:
    var twice := _exported(2.0, true, -2.0)
    var four := _exported(4.0, true, -2.0)
    assert_almost_eq(float(twice), float(_byte_of(0.5)), 1.0, "twice white at two stops under is half white")
    assert_eq(four, 255, "four times white comes back to white")
    assert_true(four - twice > 60, "so the two lights are told apart again, %d against %d" % [twice, four])


func test_an_exposure_lights_up_as_well_as_down() -> void:
    assert_almost_eq(float(_exported(0.25, true, 1.0)), float(_byte_of(0.5)), 1.0, "a quarter of white one stop up is half")


func test_an_exposure_without_the_rolloff_writes_the_picture_as_it_is() -> void:
    var plain := _exported(0.25, false, 0.0)
    assert_eq(_exported(0.25, false, -2.0), plain, "the exposure rides on the rolloff and is nothing without it")
    assert_almost_eq(float(plain), float(_byte_of(0.25)), 1.0, "which is the light the canvas holds")
