## The Brush Editor's size rows read the same pixels the top bar's do.
##
## A spec flagged `scale_by_canvas` holds a fraction of the document's smaller
## dimension, and the number that turns it into pixels is the window's, not a literal 1.0
## in `editor_pages.gd`, which would draw every size in the editor as "Size: 0 px"
## while the bar's own row read the pixels correctly.
##
## **Detached, and the window is never shown.** A `Window` in the tree maps a
## real OS window and the headless run blocks until the watchdog fires, which is
## what `test_brush_editor_window.gd` says. That leaves the picture to the
## scenario and the arithmetic to this file.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The window builds curve controls and a scratchpad with a canvas in it.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_d7_editor_size")

## A 1920 by 1080 document's smaller dimension, which is what the default
## document gives the bar and now gives the editor.
const A4_MIN: float = 1080.0

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _brush() -> ToolState:
    return _machine.get_tool("brush")


func _specs() -> Array[SaOptionSpec]:
    var out: Array[SaOptionSpec] = []
    out.assign(_machine.get_descriptor(&"brush").options)
    return out


## The window bound with *document_min*, walked to the page holding the radius.
func _window(document_min: float) -> SaBrushEditorWindow:
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), _store(), "", document_min)
    window.show_page(window.pages.index_of("General"))
    return window


func _radius_slider(window: SaBrushEditorWindow) -> FactorSlider:
    return window.pages.page_controls.control(&"radius") as FactorSlider


## The claim itself, and the number the whole defect was.
func test_the_size_row_reads_the_document_and_not_one_pixel() -> void:
    var window := _window(A4_MIN)
    var slider := _radius_slider(window)
    assert_not_null(slider, "The General page draws a radius row")
    assert_almost_eq(slider.display_value_multiplier, A4_MIN, 0.01, "and turns its fraction into a 1080-tall document's pixels")

    # The three sizes Sara ships, which is what the scenario loads and what the
    # top bar reads beside them.
    var brush: ToolState = _brush()
    for wanted: Array in [[0.00463, "5.00"], [0.023148, "25.00"], [0.185185, "200.00"]]:
        brush.settings.radius = float(wanted[0])
        window.pages.page_controls.sync(brush, &"brush_editor_page", window.canvas_min)
        assert_eq(slider._label.text, "Radius: %s px" % String(wanted[1]), "%s of the canvas is those pixels" % str(wanted[0]))
    window.free()


## What a multiplier of one reads, kept as an assertion rather than as a memory:
## the canvas fraction itself shown as though it were pixels, which is the
## defect was.
##
## **Two of the three do not read zero, and that is the row's doing rather than
## a lost proof.** The row carries two decimals so a half pixel can show at
## all, so a multiplier of one draws "0.02" and "0.19" where one decimal would
## round them to nought. The wrongness is unchanged and is what the assertion names:
## the numbers are the fractions, three orders of magnitude under the pixels
## they stand for, and the test above is the same three at 1080. The first
## reads "0.00" because the row always has its two decimals.
func test_a_multiplier_of_one_shows_the_fraction_as_though_it_were_pixels() -> void:
    var window := _window(1.0)
    var slider := _radius_slider(window)
    var brush: ToolState = _brush()
    for wanted: Array in [[0.00463, "0.00"], [0.023148, "0.02"], [0.185185, "0.19"]]:
        brush.settings.radius = float(wanted[0])
        window.pages.page_controls.sync(brush, &"brush_editor_page", window.canvas_min)
        assert_eq(
            slider._label.text,
            "Radius: %s px" % String(wanted[1]),
            "%s of one pixel is drawn as the fraction, not as the pixels it stands for" % str(wanted[0])
        )
    window.free()


## A window nobody told gets the same fallback the bar and the Tool Options
## docker use when there is no document behind them, rather than a one.
func test_a_window_nobody_told_falls_back_the_way_the_bar_does() -> void:
    assert_eq(SaBrushEditorWindow.NO_DOCUMENT, 1000.0, "The fallback is the bar's own 1000")
    var window := SaBrushEditorWindow.new()
    assert_eq(window.canvas_min, SaBrushEditorWindow.NO_DOCUMENT, "A window built and not bound holds it")
    window.bind_tool(_brush(), _specs(), _store())
    assert_eq(window.canvas_min, SaBrushEditorWindow.NO_DOCUMENT, "and a bind that names no document leaves it")
    assert_almost_eq(_radius_slider(window).display_value_multiplier, 1000.0, 0.01, "so the rows draw a plausible page")
    window.free()


## The number is handed over rather than reached for, which is the whole shape of
## this window: it has no document and must not go looking for one.
func test_the_number_arrives_through_bind_tool() -> void:
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), _store(), "", 256.0)
    assert_eq(window.canvas_min, 256.0, "The bind wrote it")
    assert_almost_eq(_radius_slider(window).display_value_multiplier, 256.0, 0.01, "and the row was built against it")
    window.bind_tool(_brush(), _specs(), _store(), "", 512.0)
    assert_almost_eq(_radius_slider(window).display_value_multiplier, 512.0, 0.01, "A second bind moves it")
    window.free()


## The dump's half, so a scenario can hold the claim rather than a screenshot of
## a number having to.
func test_the_report_names_the_document_the_rows_were_drawn_against() -> void:
    var window := _window(A4_MIN)
    var report: Dictionary = window.editor_report()
    assert_true(report.has("canvas_min"), "The report carries it")
    assert_almost_eq(float(report["canvas_min"]), A4_MIN, 0.01, "and it is the number the bind gave")
    window.free()
