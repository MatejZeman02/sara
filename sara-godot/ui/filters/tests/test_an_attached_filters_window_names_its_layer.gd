## An attached filter's window says which layer it edits:
## "Gaussian Blur on Swamp", "Gaussian Blur 2 on Swamp" for a second copy on
## the same layer, and "Gaussian Blur on the whole picture" for a filter on the
## document's root, in the OS title and in the drag bar's heading both.
##
## Swamp sits inside a group, so the walk in `SaAttachedFilter.holder_in` is
## asked for a member and not only for a layer at the top. There is still no
## preview strip, for the reason `SaFilterEditWindow.LEFT_OUT` gives. The
## running app's half is
## `scenarios/an-attached-filters-window-names-its-layer.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const OWNER := &"n107_suite"


## A filter with the Gaussian Blur's title, one slider and a preview row, so the
## window has a page to build and a row to leave out. The tree's own blur is a
## module and a suite names none.
class Blur:
    extends SaFilter

    var radius: SaSlider

    func title() -> String:
        return "Gaussian Blur"

    func build(ui: SaDialog) -> void:
        ui.title(title())
        ui.preview()
        radius = ui.slider("Radius", 1, 50, 10)
        ui.apply_cancel()

    func parameters() -> Dictionary:
        return {"radius": float(radius.value)}

    func set_parameters(values: Dictionary) -> void:
        if values.has("radius"):
            radius.value = values["radius"]

    func run(_ctx: SaFilterContext) -> void:
        pass


var _easel: SaEasel
var _doc: SaDocument
var _registry: SaFilterRegistry
var _blur: StringName
var _swamp: SaLayer
var _group: SaLayer
var _window: SaFilterEditWindow


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _registry = SaFilterRegistry.new()
    var blur := Blur.new()
    _registry.register(blur, OWNER)
    _blur = SaFilterRegistry.key_for(OWNER, blur)
    var ops := SaLayerOps.new(_doc)
    _swamp = ops.add()
    _swamp.name = "Swamp"
    _group = ops.group_layers([_swamp])
    _window = SaFilterEditWindow.new()
    _window.watch(_registry)


func after_each() -> void:
    _window.free()
    _easel.free()
    _registry = null


## Attaches one blur under *node*, null for the document's root.
func _attach(node: SaLayer) -> SaAttachedFilter:
    return SaFilterOps.new(_doc).attach(node, _blur)


## What the drag bar's heading reads, which is the title alone.
func _heading() -> String:
    var label := _window.drag_handle.find_child("TitleLabel", true, false) as Label
    return label.text if label != null else ""


## Opens the window on *record* and asserts it reads *said* in all three places
## a painter or a capture reads it.
func _assert_named(record: SaAttachedFilter, said: String) -> void:
    _window.open(record, _doc)
    assert_eq(_window.title, said, "The window is titled '%s'" % said)
    assert_eq(_heading(), said, "and its heading reads the same")
    assert_eq(_window.describe()["title"], said, "and its state dump says so")


func test_a_filter_on_a_layer_inside_a_group_names_the_layer() -> void:
    assert_eq(_swamp.group, _group, "Swamp is a member of the group")
    _assert_named(_attach(_swamp), "Gaussian Blur on Swamp")


func test_a_second_copy_on_the_layer_names_its_number_and_the_layer() -> void:
    var first := _attach(_swamp)
    var second := _attach(_swamp)
    _assert_named(second, "Gaussian Blur 2 on Swamp")
    _assert_named(first, "Gaussian Blur on Swamp")


func test_a_filter_on_the_document_names_the_whole_picture() -> void:
    _assert_named(_attach(null), "Gaussian Blur on the whole picture")


func test_a_filter_on_the_group_names_the_group() -> void:
    _assert_named(_attach(_group), "Gaussian Blur on %s" % _group.name)


## The walk itself, for each place a record can hang, and a record that hangs
## nowhere, which reads the filter's title alone. A member is a child of the
## document and not of its group, so a grouped layer is found.
func test_the_walk_finds_the_node_a_record_hangs_under() -> void:
    assert_eq(_swamp.get_parent(), _doc, "A member is a child of the document, not of its group")
    assert_eq(SaAttachedFilter.holder_in(_doc, _attach(_swamp)), _swamp, "A member's record hangs under the member")
    assert_eq(SaAttachedFilter.holder_in(_doc, _attach(_group)), _group, "a group's under the group")
    assert_eq(SaAttachedFilter.holder_in(_doc, _attach(null)), _doc, "and a root record under the document")
    var loose := SaAttachedFilter.new(_blur)
    assert_null(SaAttachedFilter.holder_in(_doc, loose), "A record the document does not hold hangs nowhere")
    assert_null(SaAttachedFilter.holder_in(null, loose), "and so does any record without a document")
    _assert_named(loose, "Gaussian Blur")


func test_the_preview_strip_is_still_left_out() -> void:
    _window.open(_attach(_swamp), _doc)
    for declared: SaPageRow in _window.dialog.rows():
        var widget := _window.dialog.widget_name(declared.key)
        if declared.line != null and SaFilterEditWindow.LEFT_OUT.has(widget):
            assert_false(declared.line.visible, "The %s row stays out" % widget)
