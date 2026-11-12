## The filter preview is painted through the canvas's display material.
##
## A `Texture2DRD` under a bare `TextureRect` draws what the document stores,
## and Godot's 2D pipeline writes a canvas colour to the screen with no encode
## of its own, so an Oklab document's preview drew L, a and b as red, green and
## blue. That is the same fault one surface along, and the answer the minimap already took
## is to borrow the canvas's own material.
##
## Windowless, so this holds the lookup and not the picture: a `Window` in the
## tree hangs a headless run, and what a colour looks like on screen is the
## scenario's half. The lookup is the whole of the fix, because sharing the
## material object is what makes the two views impossible to get out of step.
extends "res://tests/test_framework.gd"

var _canvas: SaCanvas = null
var _preview: SaFilterPreview = null


func after_each() -> void:
    if _preview != null:
        _preview.free()
    _preview = null
    if _canvas != null:
        _canvas.free()
    _canvas = null


func test_the_preview_borrows_the_canvas_material() -> void:
    _canvas = SaCanvas.new()
    # Builds the material without a viewport, which its own comment promises.
    _canvas.sync_tonemap()
    var borrowed := SaFilterPreview.display_material_of(_canvas)
    assert_not_null(borrowed, "a canvas hands its display material out")
    assert_eq(borrowed, _canvas.material, "and it is the canvas's own object, not a copy of it")
    assert_eq(borrowed.shader, _canvas.tonemap_shader, "painted through the view shader the canvas uses")


func test_no_canvas_hands_out_nothing() -> void:
    assert_null(SaFilterPreview.display_material_of(null), "no front document, no material")
    _canvas = SaCanvas.new()
    assert_null(SaFilterPreview.display_material_of(_canvas), "and neither does a canvas whose material is not built yet")


func test_a_preview_outside_a_scene_still_shows_its_picture() -> void:
    _preview = SaFilterPreview.new()
    assert_eq(_preview.shown_display_shader(), "", "a preview with no canvas to borrow from paints through none")
    _preview.show_texture(null, Rect2i(4, 5, 6, 7))
    assert_eq(_preview.rect, Rect2i(4, 5, 6, 7), "and a show still records what it covers")
    assert_eq(_preview.shown_display_shader(), "", "and still borrows nothing rather than dying reaching for it")


func test_the_dump_says_which_shader_the_picture_is_painted_through() -> void:
    _preview = SaFilterPreview.new()
    var described := _preview.describe()
    assert_true(described.has("display_shader"), "the dump carries the shader the preview draws through")
    assert_eq(String(described["display_shader"]), "", "empty when there is no scene to borrow from")
