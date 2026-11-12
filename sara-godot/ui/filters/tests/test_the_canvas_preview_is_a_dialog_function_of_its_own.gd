## The canvas preview is a dialog function of its own.
##
## The Preview box was the filter window's, made in `_preview_on_canvas` when a
## run recorded a point pass, so a filter could neither ask for it nor leave it
## out. Now `ui.canvas_preview()` declares it as a row of the dialog, the
## window reads the dialog's box, and `ui.preview()` is both calls, the switch
## standing above the thumbnail. What the box does on the running canvas is the
## scenario's to show, because the window here is never in a tree and so has no
## canvas to hand a pass to.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")

const PAINT := Color(0.25, 0.5, 0.75, 1.0)


## A point filter that declares the picture alone.
class PictureOnly:
    extends SaFilter

    func title() -> String:
        return "Picture only"

    func build(ui: SaDialog) -> void:
        ui.title(title())
        ui.thumbnail()
        ui.apply_cancel()

    func run(ctx: SaFilterContext) -> void:
        ctx.point_pass("invert", "invert", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))


## A point filter that declares the switch alone.
class SwitchOnly:
    extends PictureOnly

    func title() -> String:
        return "Switch only"

    func build(ui: SaDialog) -> void:
        ui.title(title())
        ui.canvas_preview()
        ui.apply_cancel()


## A filter that shows a texture, which has no canvas preview to switch.
class ShowsTheLayer:
    extends SaFilter

    func title() -> String:
        return "Shows the layer"

    func build(ui: SaDialog) -> void:
        ui.title(title())
        ui.thumbnail()
        ui.canvas_preview()
        ui.apply_cancel()

    func run(ctx: SaFilterContext) -> void:
        ctx.show(ctx.layer_pixels(0))


var _easel: SaEasel = null
var _doc: SaDocument = null
var _window: SaFilterDialogWindow = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(256, 256))
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
## `open_filter` does on open, and answers the dialog's description.
func _run_in_the_window(filter: SaFilter, owner: StringName) -> Dictionary:
    _window.filter = filter
    _window.context = SaFilterContext.new(_doc, _doc.active_layer, owner, filter.title(), true)
    _window.dialog = SaDialog.new()
    filter.build(_window.dialog)
    _window.dialog.realize(_window._frame.rows)
    _window.run_filter()
    return _window.dialog.describe()


## The student-facing names of every row the dialog declared, in order.
func _names(dialog: SaDialog) -> Array:
    return dialog.rows().map(func(one: SaPageRow) -> String: return dialog.widget_name(one.key))


func test_a_build_that_calls_only_the_thumbnail_gets_no_box() -> void:
    var described := _run_in_the_window(PictureOnly.new(), Bench.OWNER)
    assert_not_null(_window.dialog.preview_control, "ui.thumbnail() puts the picture in")
    assert_null(_window.dialog.canvas_box, "and no Preview box, because nothing asked for one")
    assert_eq(described["canvas_preview"], {}, "which the dump says")
    assert_false(_names(_window.dialog).has("canvas_preview"), "and no row is named for it")
    assert_true(bool(described["preview"]["holds_texture"]), "while the picture still holds the run")


func test_a_build_that_calls_only_the_switch_gets_no_thumbnail() -> void:
    var described := _run_in_the_window(SwitchOnly.new(), Bench.OWNER)
    assert_null(_window.dialog.preview_control, "ui.canvas_preview() puts no picture in")
    assert_eq(described["preview"], {}, "which the dump says")
    var box := _window.dialog.canvas_box
    assert_not_null(box, "and the Preview box is there")
    assert_eq(_names(_window.dialog), ["canvas_preview", "apply_cancel"], "as a row of the dialog")
    assert_eq(described["canvas_preview"], {"on": true, "enabled": true}, "ticked by default, and live for a point pass")
    assert_true(box.is_inside_tree() or box.get_parent() != null, "realized into the page like any row")


func test_a_build_that_calls_preview_gets_both_in_order() -> void:
    var described := _run_in_the_window(InvertFilter.new(), Bench.OWNER)
    assert_not_null(_window.dialog.preview_control, "ui.preview() puts the picture in")
    assert_not_null(_window.dialog.canvas_box, "and the Preview box")
    assert_eq(_names(_window.dialog), ["canvas_preview", "preview", "apply_cancel"], "the box first, then the picture under it")
    assert_true(bool(described["preview"]["holds_texture"]), "the picture holds the run")
    assert_eq(described["canvas_preview"], {"on": true, "enabled": true}, "and the box is ticked and live")


func test_the_box_is_greyed_out_for_a_filter_that_shows_a_texture() -> void:
    var described := _run_in_the_window(ShowsTheLayer.new(), &"")
    assert_null(_window.context.point, "The run showed a texture and recorded no pass")
    assert_eq(described["canvas_preview"], {"on": true, "enabled": false}, "so the box has nothing to switch")
    assert_true(_window.dialog.canvas_box.tooltip_text.contains("thumbnail"), "and its tooltip says where the picture is")


func test_unticking_the_box_leaves_the_thumbnail_running() -> void:
    _run_in_the_window(InvertFilter.new(), Bench.OWNER)
    var first := int(_window.dialog.preview_control.describe()["point_runs"])
    _window.dialog.canvas_box.button_pressed = false
    _window.run_filter()
    assert_eq(_window.dialog.describe()["canvas_preview"], {"on": false, "enabled": true}, "The box is unticked")
    assert_false(bool(_window.describe()["on_canvas"]), "nothing is handed to the canvas")
    var second := int(_window.dialog.preview_control.describe()["point_runs"])
    assert_eq(second, first + 1, "and the thumbnail still runs the pass")


## Threshold's dialog names both calls. It is a pixel function
## whose generated build places them above its slider, as
## every pixel function's dialog does.
func test_threshold_declares_the_two_calls() -> void:
    var dialog := SaDialog.for_filter(Bench.threshold())
    var host := VBoxContainer.new()
    dialog.realize(host)
    assert_eq(
        _names(dialog).slice(0, 3),
        ["canvas_preview", "preview", "slider"],
        "Threshold's dialog names both functions, the box above the picture"
    )
    host.free()


func test_no_build_under_modules_calls_preview() -> void:
    var found := _module_sources("res://modules")
    # The adjustments, Levels, Curves and the colour lookup place the pictures
    # under their controls themselves, and every other filter leaves them to
    # the dialog.
    assert_true(found.size() >= 4, "the filters under modules that place their pictures were read: %d" % found.size())
    for path: String in found:
        var source := FileAccess.get_file_as_string(path)
        assert_false(source.contains("ui.preview()"), "%s calls the two functions rather than ui.preview()" % path)
        assert_true(source.contains("ui.canvas_preview()"), "%s declares the Preview box" % path)


func test_the_panel_and_the_edit_window_leave_the_box_out() -> void:
    for name: String in ["preview", "thumbnail", "canvas_preview"]:
        assert_true(SaFilterPanel.LEFT_OUT.has(name), "The layer's filter panel leaves out %s" % name)
        assert_true(SaFilterEditWindow.LEFT_OUT.has(name), "and so does the edit window")


## Every script under *root* whose `build` declares a filter's picture, tests
## and fixtures left out, since they are what a stranger wrote.
func _module_sources(root: String) -> Array:
    var out: Array = []
    var dir := DirAccess.open(root)
    if dir == null:
        return out
    for sub in dir.get_directories():
        if sub == "tests" or sub.begins_with("."):
            continue
        out.append_array(_module_sources(root.path_join(sub)))
    for file in dir.get_files():
        if not file.ends_with(".gd"):
            continue
        var path := root.path_join(file)
        var source := FileAccess.get_file_as_string(path)
        if source.contains("func build(ui") and (source.contains("ui.thumbnail()") or source.contains("ui.preview()")):
            out.append(path)
    return out
