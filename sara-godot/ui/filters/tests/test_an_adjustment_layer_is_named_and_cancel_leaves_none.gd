## An adjustment layer is named for its filter, and Cancel in
## the window its settings open in leaves no layer.
##
## Brightness/Contrast was added as a layer named
## `Brightness_Contrast`, since a `Node` name cannot hold a slash, an empty
## adjustment layer left behind when the painter pressed Cancel, the next pick
## opening at the cancelled window's values, and a freed-object error on Apply
## and on Cancel, the frame freeing the very button whose `pressed` was still
## being sent.
##
## The browser and the window are both put in the tree, under a host with its
## subwindows embedded, the way `test_a_filter_dialog_opens_at_its_controls.gd`
## holds its window, so the pick hands the layer it made to the window that the
## running app has, and the frame empties itself as it does there. The running
## app is `scenarios/an-adjustment-layer-is-named-for-its-filter-and-cancel-leaves-no-layer.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"

var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _types: SaLayerTypeRegistry = null
var _browser: SaLayerKindBrowser = null
var _window: SaFilterEditWindow = null
var _brightness: SaBrightnessContrastFilter = null
var _hue: SaHueSaturationLightnessFilter = null
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "S45TestHost"
    EventBus.add_child(_host)

    var registries := Fixtures.make_registries()
    _types = registries.layer_types
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(registries.blend_modes)
    _doc = _easel.document
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _registry = SaFilterRegistry.new()
    _brightness = SaBrightnessContrastFilter.new()
    _hue = SaHueSaturationLightnessFilter.new()
    _registry.register(_brightness, OWNER)
    _registry.register(_hue, OWNER)
    _easel.compositor.filter_chain.registry = _registry

    _window = SaFilterEditWindow.new()
    _window.watch(_registry)
    _host.add_child(_window)
    _browser = SaLayerKindBrowser.new()
    _browser.browser.target_canvas = _canvas
    _browser.browser.watch(_registry, SaCommandRegistry.new())
    _host.add_child(_browser)


func after_each() -> void:
    _browser.free()
    _window.free()
    _canvas.free()
    _easel.free()
    _host.free()
    _registry = null
    _types = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


## Picks *filter* in the browser for *kind_id* and adds the layer, which opens
## its settings in the window, and answers the layer made.
func _add(filter: SaFilter, kind_id: StringName = SaBackdropLayer.TYPE_ID) -> SaLayer:
    _browser.open_for(_doc, _types.get_descriptor(kind_id), _types)
    _browser.browser.pick(SaFilterRegistry.key_for(OWNER, filter))
    _browser.open_selected()
    return _browser.made


func _layer_count() -> int:
    var count := 0
    for child in _doc.get_children():
        if child is SaLayer and child != _doc.stroke_layer:
            count += 1
    return count


## Moves Brightness to *value* the way the window's rerun lands a slider: the
## widget writes the store, and the window writes the store onto the record.
func _move_brightness(value: float) -> void:
    _brightness.store.write(&"brightness", value)
    _window.write_back()


## Presses *button* the way a hand does, through its own `pressed`, and checks
## the close it answers frees nothing the signal is still being sent from: the
## button lives through its own signal, out of the window and queued, and is
## freed here because a suite has no frame to end.
func _press_quietly(button: Button, named: String) -> void:
    var emptied: Array[Node] = []
    emptied.append_array(_window._frame.rows.get_children())
    emptied.append_array(_window._frame.footer.get_children())
    var line: Node = null
    for node in emptied:
        if node == button or node.is_ancestor_of(button):
            line = node
    button.pressed.emit()
    assert_true(is_instance_valid(button), "%s lives through its own pressed signal" % named)
    if is_instance_valid(line):
        assert_true(line.is_queued_for_deletion(), "and its row is queued rather than freed inside it")
    assert_eq(_window._frame.rows.get_child_count() + _window._frame.footer.get_child_count(), 0, "The window is emptied")
    for node in emptied:
        if is_instance_valid(node):
            node.free()


func test_an_adjustment_layer_is_named_for_its_filter() -> void:
    var made := _add(_brightness)
    assert_not_null(made, "Brightness/Contrast adds a layer")
    if made == null:
        return
    assert_eq(String(made.name), "Brightness Contrast", "named with a space where the title has a slash")
    assert_eq(_window.title, "Brightness/Contrast on Brightness Contrast", "and the window's title says so")
    assert_eq(_window.describe()["fresh"], "Brightness Contrast", "the window is told the layer is fresh")
    _window.accept()

    var second := _add(_brightness)
    assert_eq(String(second.name), "Brightness Contrast 2", "A second is numbered as before")
    _window.accept()
    var hue := _add(_hue)
    assert_eq(String(hue.name), "Hue Saturation Lightness", "and Hue/Saturation/Lightness takes two spaces")
    _window.accept()
    var effect := _add(_brightness, SaEffectLayer.TYPE_ID)
    assert_true(effect != null and effect.is_effect(), "An effect layer is made by the browser itself")
    if effect != null:
        assert_eq(String(effect.name), "Brightness Contrast 3", "and named by the same helper")
    _window.accept()
    var conversion := SaFilterConversion.new(_doc)
    assert_eq(conversion.layer_name_for("Blur 1.5: 50%"), "Blur 1 5 50", "Every mark a node name cannot hold is a space")


func test_cancel_leaves_the_layer_list_as_it_was() -> void:
    var before := _layer_count()
    var below := _doc.active_layer
    var made := _add(_brightness)
    if made == null:
        assert_not_null(made, "Brightness/Contrast adds a layer")
        return
    assert_eq(_layer_count(), before + 1, "The pick adds the layer")
    _move_brightness(40.0)
    assert_eq(made.filters[0].parameters["brightness"], 40.0, "the window previews on the record")

    _press_quietly(_window.dialog.cancel_button, "Cancel")

    assert_false(_window.visible, "Cancel closes the window")
    assert_eq(_layer_count(), before, "and the layer list is as it was")
    assert_true(made.get_parent() == null, "the layer is out of the document")
    assert_true(_doc.active_layer == below, "and the painter is back on the layer they were on")
    assert_true(_doc.redo(), "A redo is left")
    assert_true(made.get_parent() == _doc, "which brings the layer back")
    assert_eq(made.filters[0].parameters["brightness"], 0.0, "untouched by the cancelled window")


func test_cancel_after_another_step_keeps_the_layer() -> void:
    var made := _add(_brightness)
    if made == null:
        assert_not_null(made, "Brightness/Contrast adds a layer")
        return
    var painted := SaLayerOps.new(_doc).add()
    var standing := _doc.history.position()
    _window.cancel()
    assert_true(made.get_parent() == _doc, "A step taken while the window was up keeps the layer")
    assert_true(painted.get_parent() == _doc, "and the step")
    assert_eq(_doc.history.position(), standing, "and Cancel undoes nothing")


func test_apply_keeps_the_layer_as_one_step_over_the_add() -> void:
    var before := _layer_count()
    var made := _add(_brightness)
    if made == null:
        assert_not_null(made, "Brightness/Contrast adds a layer")
        return
    _move_brightness(25.0)
    _press_quietly(_window.dialog.apply_button, "Apply")
    assert_eq(_layer_count(), before + 1, "Apply keeps the layer")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Edit Filter", "with its values as a step of their own")
    assert_eq(made.filters[0].parameters["brightness"], 25.0, "holding what the window was left at")


func test_a_second_pick_opens_at_the_filters_defaults() -> void:
    var key := SaFilterRegistry.key_for(OWNER, _brightness)
    var made := _add(_brightness)
    if made == null:
        assert_not_null(made, "Brightness/Contrast adds a layer")
        return
    _move_brightness(40.0)
    _window.cancel()
    assert_eq(_brightness.parameters()["brightness"], 40.0, "The one instance keeps what the cancelled window wrote")

    var second := _add(_brightness)
    assert_eq(second.filters[0].parameters["brightness"], 0.0, "and a second pick adds the layer at the defaults")
    assert_eq(_window.describe()["opened_with"]["brightness"], 0.0, "with its window opened on them")

    _move_brightness(30.0)
    _browser.browser.pick(key)
    assert_eq(_brightness.parameters()["brightness"], 30.0, "A pick leaves a store an open window shows alone")
    _window.cancel()
