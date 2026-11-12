## The thumbnail is a dialog function of its own.
##
## `ui.thumbnail()` puts the small picture in a filter's dialog for every kind
## of filter. A point filter records a pass and shows nothing, so the picture
## is made by running the pass over a reduced copy of the layer into the
## thumbnail's texture, on the GPU, and the box sits beside the picture, a row
## of its own. The window is built and never added to the tree, because a
## `Window` in the tree maps an OS window and hangs the runner, and handed the
## filter and the context `open_filter` would have made, the way the other
## dialog suites hand them.
##
## The texels read below are this suite's own check on what the picture holds.
## The thumbnail's path reads nothing back, and the last test holds that on the
## files that make the picture.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")
const BoxBlur = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const INVERTED := Color(0.75, 0.5, 0.25, 1.0)

## The calls a readback is made through, none of which the picture's files may
## hold (hard rule 1).
const READBACKS := ["texture_get_data", "buffer_get_data", "get_texture_image_float", "read_pixels", ".read()"]


## A filter that shows a texture, the layer's own pixels, and declares the
## thumbnail by its name.
class ShowsTheLayer:
    extends SaFilter

    func title() -> String:
        return "Shows The Layer"

    func build(ui: SaDialog) -> void:
        ui.title(title())
        ui.thumbnail()
        ui.apply_cancel()

    func run(ctx: SaFilterContext) -> void:
        ctx.show(ctx.layer_pixels(0))


var _easel: SaEasel = null
var _doc: SaDocument = null
var _window: SaFilterDialogWindow = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 512))
    _doc = _easel.document
    _doc.fill_layer(PAINT, _doc.active_layer)
    _window = SaFilterDialogWindow.new()
    Bench.composite(_easel)


func after_each() -> void:
    _window.free()
    _window = null
    _easel.free()
    _easel = null
    _doc = null


## Opens *filter* in the window over the active layer and runs it once, the way
## `open_filter` does on open. Answers the thumbnail's report.
func _run_in_the_window(filter: SaFilter, owner: StringName) -> Dictionary:
    _window.filter = filter
    _window.context = SaFilterContext.new(_doc, _doc.active_layer, owner, filter.title(), true)
    _window.dialog = SaDialog.for_filter(filter)
    _window.dialog.realize(_window._frame.rows)
    _window.run_filter()
    return _window.dialog.preview_control.describe()


func _texel_of_the_thumbnail(at: Vector2i) -> Color:
    return Bench.texel(_window.dialog.preview_control._held, at)


func test_the_thumbnail_is_a_row_of_its_own() -> void:
    var dialog := SaDialog.new()
    var row := dialog.thumbnail()
    assert_not_null(dialog.preview_control, "ui.thumbnail() puts a picture in the dialog")
    var host := VBoxContainer.new()
    dialog.realize(host)
    assert_eq(dialog.widget_name(row.key), "thumbnail", "under its own name")
    assert_eq(
        dialog.preview_control.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "and it fills the column as the preview did"
    )
    host.free()


func test_a_point_filter_fills_the_thumbnail_from_a_reduced_copy() -> void:
    var shown := _run_in_the_window(InvertFilter.new(), Bench.OWNER)
    assert_not_null(_window.context.point, "The run recorded a point pass")
    assert_true(bool(shown["holds_texture"]), "and the thumbnail holds a texture after it")
    assert_eq(int(shown["point_runs"]), 1, "made by running the pass over the reduced copy")
    var reduced := SaFilterPreview.REDUCED_SIDE
    assert_eq(shown["texture_size"], [reduced, reduced], "a 512 layer reduced to the side the thumbnail runs at")
    var middle := _texel_of_the_thumbnail(Vector2i(reduced >> 1, reduced >> 1))
    assert_almost_eq(middle.r, INVERTED.r, 0.01, "and the picture is the layer inverted: %s" % middle)
    assert_almost_eq(middle.b, INVERTED.b, 0.01, "channel for channel")
    var layer := Bench.texel(_doc.active_layer.get_field(Vector2i.ZERO), Vector2i(10, 10))
    assert_almost_eq(layer.r, PAINT.r, 1e-5, "while the layer itself is untouched")


func test_the_box_sits_beside_the_picture_and_hides_nothing() -> void:
    _run_in_the_window(InvertFilter.new(), Bench.OWNER)
    var picture := _window.dialog.preview_control
    assert_true(picture.visible, "The window no longer hides a point filter's picture")
    # The box is a row of the dialog, and the row before the picture's,
    # so hiding the picture never moves it.
    var box := _window.dialog.canvas_box
    assert_not_null(box, "and the Preview box is beside it")
    if box != null:
        var rows := _window.dialog.rows()
        var picture_at := rows.map(func(one: SaPageRow) -> Control: return one.control).find(picture)
        assert_eq(rows[picture_at - 1].control, box, "above it, not in its place")


func test_a_rerun_puts_a_new_picture_in() -> void:
    var first := _run_in_the_window(InvertFilter.new(), Bench.OWNER)
    _window.run_filter()
    var second: Dictionary = _window.dialog.preview_control.describe()
    assert_eq(int(second["point_runs"]), int(first["point_runs"]) + 1, "Every run of a point filter runs its pass again")
    assert_eq(int(second["textures_bound"]), int(first["textures_bound"]) + 1, "into a texture of its own")


func test_the_reduced_pass_is_masked_by_the_selection() -> void:
    _doc.selection.select_ellipse(Rect2i(0, 0, 512, 512))
    _run_in_the_window(InvertFilter.new(), Bench.OWNER)
    var reduced := SaFilterPreview.REDUCED_SIDE
    var inside := _texel_of_the_thumbnail(Vector2i(reduced >> 1, reduced >> 1))
    var outside := _texel_of_the_thumbnail(Vector2i(1, 1))
    assert_almost_eq(inside.r, INVERTED.r, 0.01, "Inside the ellipse the picture is inverted: %s" % inside)
    assert_almost_eq(outside.r, PAINT.r, 0.01, "and in its corner it is the layer as it stands: %s" % outside)


func test_a_filter_that_shows_a_texture_fills_it_too() -> void:
    var shown := _run_in_the_window(ShowsTheLayer.new(), &"")
    assert_null(_window.context.point, "The run showed a texture and recorded no pass")
    assert_true(bool(shown["holds_texture"]), "and the thumbnail holds a texture after it")
    assert_eq(int(shown["point_runs"]), 0, "the one the run showed, with no pass run for it")
    assert_eq(shown["texture_size"], [512, 512], "at the run's own size")


func test_a_neighbourhood_filter_fills_it_at_full_size() -> void:
    # The kernels' owner is the folder under modules, sara-base-modules, which
    # a filter registered by hand has to tell the loader.
    ModuleLoader.module_dirs[&"sara-base-modules"] = "res://modules/sara-base-modules/base"
    var shown := _run_in_the_window(BoxBlur.new(), &"sara-base-modules")
    assert_true(_window.context.point is SaNeighbourhoodPass, "The box blur records a neighbourhood pass")
    assert_true(bool(shown["holds_texture"]), "and the thumbnail holds a texture after it")
    assert_eq(int(shown["point_runs"]), 0, "gathered at full size rather than over the reduced copy")
    var middle := _texel_of_the_thumbnail(Vector2i(256, 256))
    assert_almost_eq(middle.r, PAINT.r, 0.01, "A flat layer blurs to itself: %s" % middle)


func test_the_reduced_copy_keeps_the_aspect_and_never_grows() -> void:
    assert_eq(SaFilterPreview.Reducer.size_for(Vector2i(1600, 800)), Vector2i(400, 200), "A wide rectangle stays wide")
    assert_eq(SaFilterPreview.Reducer.size_for(Vector2i(800, 1600)), Vector2i(200, 400), "a tall one tall")
    assert_eq(SaFilterPreview.Reducer.size_for(Vector2i(120, 90)), Vector2i(120, 90), "and a small one is its own size")
    assert_eq(SaFilterPreview.Reducer.size_for(Vector2i(4000, 1)), Vector2i(400, 1), "a sliver keeps one row")
    assert_eq(SaFilterPreview.Reducer.size_for(Vector2i.ZERO), Vector2i.ZERO, "and nothing to cover is no copy")


func test_the_picture_is_made_without_a_readback() -> void:
    for path: String in ["res://ui/filters/preview/sa_filter_preview.gd", "res://ui/filters/sa_filter_dialog_window.gd"]:
        var source := FileAccess.get_file_as_string(path)
        assert_false(source.is_empty(), "%s was read" % path)
        for readback: String in READBACKS:
            assert_false(source.contains(readback), "%s makes no %s call" % [path.get_file(), readback])
