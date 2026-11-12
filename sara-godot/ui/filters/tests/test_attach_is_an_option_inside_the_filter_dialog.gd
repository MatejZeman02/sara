## Attach is an option inside the filter dialog.
##
## Attach is an optional button inside the dialog, not a secondary button for
## every filter in the list. Ticked,
## Apply attaches the filter to the active layer with the settings the dialog's
## widgets hold and writes no pixel. Unticked, Apply writes the pixels in as it
## always did and attaches nothing. For a filter that cannot be attached the
## option is dimmed and its tooltip is the first line of the reason.
##
## The Attach rows the Filter menu drew beside every filter and the browser's
## Attach button are gone with it, so this suite holds that half too.
##
## The box is a toggle of three, Bake, Attach and Layer, on Bake
## whenever the dialog opens, so this suite picks Attach where it ticks
## the box, and Bake is the box unticked.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const KEY := &"sara-base-modules.threshold"
const BROKEN_KEY := &"r7_suite.broken"
const PROBLEM := "line 3: cannot return a vec3 from a vec4 function\nand a second line nobody shows"


## A filter whose module wrote a kernel that does not compile, which is what
## "cannot be attached" means here: the menu's Attach row was dimmed by exactly
## this answer and this box is dimmed by the same one.
class Broken:
    extends SaFilter

    func title() -> String:
        return "Broken"

    func build(ui: SaDialog) -> void:
        ui.title("Broken")
        ui.apply_cancel()

    func problem() -> String:
        return PROBLEM

    func run(_ctx: SaFilterContext) -> void:
        pass


var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true

    _host = Node.new()
    _host.name = "R7TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(Vector2i(512, 512))
    _doc = _easel.document
    _doc.fill_layer(PAINT, _doc.active_layer)
    Bench.composite(_easel)

    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _registry = SaFilterRegistry.new()
    _registry.register(Bench.threshold(), &"sara-base-modules")
    _registry.register(Broken.new(), &"r7_suite")
    # The easel's chain reads records through its own registry, so what the
    # window's dialog attaches has to be known there as well: without this the
    # write path finds no pass and silently does nothing.
    _easel.compositor.filter_chain.registry = _registry

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    # A pick is remembered for the next filter, and no suite leaves it for another.
    SaSettings.filter_way = "bake"
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _doc = null
    _registry = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


## The apply row's controls, which is where the box has to be.
func _buttons() -> HBoxContainer:
    var row := SaFilterDialogFrame.apply_row(_window.dialog)
    assert_not_null(row, "the dialog drew an Apply row")
    return row.control as HBoxContainer


## The layer's own value at one point, off the GPU, which is the pixel an
## attach must leave alone. The chunk is worked out from the point the way
## `test_one_shot_is_attach_and_flatten.gd` does it.
func _stored(at: Vector2i) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)
    return Bench.texel(_doc.active_layer.get_field(grid), at - grid * SaChunk.SIZE)


func test_the_dialog_offers_an_attach_way_beside_apply() -> void:
    _window.open_filter(KEY)

    var toggle := _window.way_toggle
    assert_not_null(toggle, "The dialog offers the toggle of three")
    assert_eq(toggle.options.size(), 3, "with three stops")
    assert_eq(toggle.options[1]["label"], "Attach", "its second named Attach, as the menu's rows and the browser's button were")
    assert_eq(toggle.value, &"bake", "and on Bake by default, so Apply writes unless the painter asks otherwise")
    assert_false(toggle.dimmed.has(&"attach"), "and Attach can be picked, since this filter can be attached")
    var buttons := _buttons()
    assert_false(buttons.is_ancestor_of(toggle), "The toggle is not a control of the Apply row")
    assert_eq(buttons.get_child(0), _window.dialog.cancel_button, "which starts with Cancel")
    assert_eq(buttons.get_child(1), _window.dialog.apply_button, "and ends with Apply")


func test_apply_on_attach_attaches_the_filter_and_writes_no_pixel() -> void:
    var sample := Vector2i(100, 100)
    var before := _stored(sample)
    var steps := _doc.undo_redo.get_history_count()

    _window.open_filter(KEY)
    _window.dialog.row(&"level").drive(0.8)
    _window.dialog.flush_rerun()
    assert_true(_window.way_toggle.pick(&"attach"), "Attach takes the pick")
    _window.apply_filter()

    assert_false(_window.visible, "Apply closes the window")
    assert_eq(_doc.active_layer.filters.size(), 1, "The layer gained one attached filter")
    var record := _doc.active_layer.filters[0]
    assert_eq(record.key, KEY, "the one the dialog was editing")
    assert_eq(record.parameters, {"level": 0.8}, "with the settings the widgets held when Apply was pressed")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one history step")
    assert_eq(_stored(sample), before, "and the layer's own pixel is untouched")

    _doc.undo_redo.undo()
    assert_true(_doc.active_layer.filters.is_empty(), "One undo takes the attachment off again")
    assert_eq(_stored(sample), before, "and the pixel was the same all along")


func test_apply_on_bake_writes_the_pixels_and_attaches_nothing() -> void:
    var sample := Vector2i(100, 100)
    var before := _stored(sample)
    var steps := _doc.undo_redo.get_history_count()

    _window.open_filter(KEY)
    _window.dialog.row(&"level").drive(0.9)
    _window.dialog.flush_rerun()
    assert_eq(_window.way(), &"bake", "The toggle starts on Bake, so this is the ordinary Apply")
    _window.apply_filter()

    assert_true(_doc.active_layer.filters.is_empty(), "Nothing was attached")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "the write is one history step")
    assert_true(_stored(sample) != before, "and the pixel is the threshold's answer")


func test_a_filter_that_cannot_be_attached_gets_a_dimmed_way_that_says_why() -> void:
    _window.open_filter(BROKEN_KEY)

    var toggle := _window.way_toggle
    assert_not_null(toggle, "The broken filter's dialog still offers the toggle")
    assert_true(toggle.dimmed.has(&"attach"), "but Attach is dimmed, as a control that cannot act always is")
    assert_false(toggle.pick(&"attach"), "and refuses the pick")
    assert_eq(
        toggle.dimmed[&"attach"],
        PROBLEM.split("\n")[0].strip_edges(),
        "and its tooltip is the first line of the reason, which is what the menu's Attach row carried"
    )
    assert_false(JSON.stringify(_window.describe()).is_empty(), "and the dump answers")


func test_the_browser_offers_no_attach_button() -> void:
    var docker := FiltersDocker.new()
    docker.browser.watch(_registry, SaCommandRegistry.new())

    assert_not_null(docker.find_child("BrowserOpenButton", true, false), "The Filters docker still offers its Open button")
    assert_null(docker.find_child("BrowserAttachButton", true, false), "and offers no Attach button beside it")
    docker.free()


func test_the_edit_window_the_double_click_opens_shows_no_way_toggle() -> void:
    var record := SaFilterOps.new(_doc).attach(_doc.active_layer, KEY, {"level": 0.4})
    var window := SaFilterEditWindow.new()
    window.watch(_registry)
    window.open(record, _doc)

    assert_not_null(window.dialog, "The edit window built the filter's page")
    var row: SaPageRow = null
    for declared: SaPageRow in window.dialog.rows():
        if window.dialog.widget_name(declared.key) == "apply_cancel":
            row = declared
    assert_not_null(row, "which has an Apply row of its own")
    assert_null(row.control.get_node_or_null("WayToggle"), "and offers no way toggle, because Apply there edits the attachment")
    window.free()
