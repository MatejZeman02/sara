## The Brush Editor's scratchpad: the chrome it builds, the width it asks for and
## what it refuses to do without a canvas behind it.
##
## **Detached, and every assertion here is chosen so it can be.**
## Adding a `Window` to the tree in a headless run hangs, and the editor is a
## `Window`, so the pad is built alone. That leaves out everything that needs a
## rendering device, which the scenario is for: what a test can hold is that the
## pad exists before anything binds it, that it does not paint when there is
## nothing to paint on, and that the arithmetic behind its width is the editor's
## width rather than a number somebody typed.
extends "res://tests/test_framework.gd"

const PadScript = preload("res://ui/brush_editor/preview/editor_scratchpad.gd")


func _pad() -> SaEditorScratchpad:
    return PadScript.new()


func test_the_pad_builds_its_own_viewport_and_canvas() -> void:
    var pad := _pad()
    assert_not_null(pad.viewport, "The pad has a viewport of its own")
    assert_not_null(pad.canvas, "and a canvas inside it")
    assert_eq(pad.canvas.canvas_size, Vector2i(SaEditorScratchpad.EDGE, SaEditorScratchpad.EDGE), "one chunk square")
    assert_not_null(pad.clear_button, "and the button that throws the doodle away")
    # The reason the viewport is there at all: a canvas centres itself against
    # its viewport's rect, so a canvas sharing the dialog's viewport would be
    # drawn over the page list at whatever scale filled the window.
    assert_true(pad.canvas.get_parent() == pad.viewport, "The canvas is inside the viewport, not beside it")
    pad.free()


## The width is "sized by the editor's width", so it has to move when the editor
## does, and it has to stop before the pad becomes a sliver. The share
## is what a profile with no width of its own gets, read back through
## `restore_width`, and the column's minimum is nought so the grabber can shut
## it. The width the pad asks for is `open_width`, not a minimum size.
func test_the_width_follows_the_editor_and_stops_at_the_floor() -> void:
    var pad := _pad()
    var was_width: int = SaSettings.brush_editor_pad_width
    SaSettings.brush_editor_pad_width = 0
    pad.size_to_editor(900)
    pad.restore_width()
    var wide: int = pad.snap.open_width
    assert_eq(wide, SaUI.px(int(round(900.0 * SaEditorScratchpad.WIDTH_SHARE))), "900 gives the share of 900")

    pad.size_to_editor(1400)
    pad.restore_width()
    assert_true(pad.snap.open_width > wide, "A wider editor gives a wider pad")

    pad.size_to_editor(200)
    pad.restore_width()
    assert_eq(pad.snap.open_width, SaUI.px(SaEditorScratchpad.MIN_WIDTH), "and a narrow one keeps the floor")
    assert_almost_eq(pad.custom_minimum_size.x, 0.0, 0.001, "No minimum, so the grabber can take the column to nought")
    SaSettings.brush_editor_pad_width = was_width
    pad.free()


## The pad's canvas fits itself to the column rather than to the dialog, which
## is the one thing the first run of the scenario got wrong: the canvas centred
## against a container that had not been laid out yet and came out at a zoom of
## two pixels over 256.
##
## The fit is by the longer side, so the column is paint
## from edge to edge and a tall column costs the pad's sides rather than
## leaving dead space above and below a square.
func test_the_pad_fits_its_own_viewport_and_not_the_dialog() -> void:
    var pad := _pad()
    assert_eq(
        pad.viewport.size, Vector2i(SaEditorScratchpad.EDGE, SaEditorScratchpad.EDGE), "The viewport has a size before layout"
    )

    pad._fit_pad()
    assert_almost_eq(pad.canvas.scale.x, 1.0, 0.001, "A viewport the size of the document shows it at 1:1")
    assert_almost_eq(pad.canvas.position.x, 0.0, 0.001, "with nothing left over to centre")

    # The container is what resizes the viewport in the running app, and the
    # engine refuses a size set by hand while it is doing that. Turned off here
    # so the two column widths below can be stated rather than laid out, which a
    # detached control cannot be.
    pad.view_box.stretch = false
    pad.viewport.size = Vector2i(int(float(SaEditorScratchpad.EDGE) * 0.5), SaEditorScratchpad.EDGE)
    pad._fit_pad()
    assert_almost_eq(pad.canvas.scale.x, 1.0, 0.001, "A tall column is filled top to bottom")
    assert_almost_eq(pad.canvas.position.x, -float(SaEditorScratchpad.EDGE) * 0.25, 0.001, "and the sides are cropped evenly")
    assert_almost_eq(pad.canvas.position.y, 0.0, 0.001, "with no dead space above or below")

    pad.viewport.size = Vector2i(SaEditorScratchpad.EDGE * 2, SaEditorScratchpad.EDGE * 2)
    pad._fit_pad()
    assert_almost_eq(pad.canvas.scale.x, 2.0, 0.001, "A large column magnifies the pad rather than leaving room")
    assert_almost_eq(pad.canvas.position.x, 0.0, 0.001, "with nothing left over")
    pad.free()


## Binding is called every time the editor opens, and a window built detached has
## no rendering device behind its canvas. Neither may raise.
func test_binding_without_a_canvas_in_the_tree_is_quiet() -> void:
    var pad := _pad()
    pad.bind_tool(null, null)
    assert_null(pad.surface, "No surface without a canvas in the tree")
    assert_null(pad.painter, "and no tool instance either")
    pad.free()


## The pad reports itself for the dump, and the two counters are what is checked:
## they move while the painting's History does not.
func test_the_report_names_the_pad_and_starts_at_nothing() -> void:
    var pad := _pad()
    var report := pad.pad_report()
    assert_false(bool(report["bound"]), "Nothing is bound before the editor binds it")
    assert_eq(report["strokes"], 0, "and no stroke has been asked for")
    assert_eq(report["clears"], 0, "and nothing has been thrown away")
    assert_eq(report["size"]["x"], SaEditorScratchpad.EDGE, "The pad says how large its document is")
    pad.free()


## A `paint` step against an unbound pad is a scenario's mistake rather than a
## crash, and the count must not move for a stroke that never happened.
func test_a_paint_step_with_nothing_bound_paints_nothing() -> void:
    var pad := _pad()
    pad.scratch_step({"paint": {"from": [10, 10], "to": [200, 200]}})
    assert_eq(pad.strokes, 0, "An unbound pad counts no stroke")
    pad.free()


## The window builds the pad in its own `_init`, so a detached editor already
## holds one and the scenario's `scratch` step has something to reach.
##
## The window is never added to the tree here, for the reason in this file's
## header.
func test_the_editor_window_holds_a_pad_before_anything_opens_it() -> void:
    var window := SaBrushEditorWindow.new()
    assert_not_null(window.scratchpad, "The editor builds its pad in _init")
    assert_true(window.scratchpad.is_inside_tree() == false, "detached with the window")
    var report := window.editor_report()
    assert_true(report.has("scratch"), "and the dump carries the pad's own block")
    assert_eq((report["scratch"] as Dictionary)["strokes"], 0, "reading nothing before a stroke")
    window.free()


## Clear on a blank pad throws nothing away. It is dimmed until a
## stroke lands and dimmed again by a clear. A detached pad cannot paint, so the
## stroke is the hand's release routed the way the canvas routes it, which is
## what a stroke from the pen ends on, and a scenario paints a real one.
func test_clear_is_dimmed_while_the_pad_is_blank() -> void:
    var pad := _pad()
    assert_true(pad.clear_button.disabled, "A blank pad offers no Clear")
    pad._show_blank(false)
    assert_false(pad.clear_button.disabled, "a stroke lights it")
    pad.clear()
    assert_true(pad.clear_button.disabled, "and a clear dims it again")
    pad.free()
