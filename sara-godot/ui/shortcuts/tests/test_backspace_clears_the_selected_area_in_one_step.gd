## Both bare keys clear the selected
## area, Krita's Backspace and Photoshop's Delete, each as one history step,
## and the layer when nothing is selected. A focused name field keeps the key.
##
## Pressed the way a keyboard sends a key and answered by the router the main
## window hands every unhandled key to, over the application's whole map, so a
## second command on either key would take the press first. The scenario of
## the same name presses both over the booted app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The proof is the pixels a clear left, which needs a RenderingDevice.
const REQUIRES_GPU := true

## Two squares inside the first chunk, one for each key, and a point that
## neither covers.
const FIRST := Rect2i(0, 0, 64, 64)
const SECOND := Rect2i(128, 128, 64, 64)
const UNSELECTED := Vector2i(100, 30)

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _router: ShortcutRouter = null
var _host: Node = null
var _pair: Array = []
var _heard: Array[String] = []
var _saved_events: Dictionary = {}


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _router = ShortcutRouter.new()
    _router.bind_commands(_registries.commands)
    _host = Node.new()
    _host.name = "ClearKeysTestHost"
    EventBus.add_child(_host)
    _pair = [SaColors.foreground, SaColors.background]
    _heard.clear()
    EventBus.corner_notice.connect(_hear)
    EventBus.paint_refused.connect(_hear)
    # Red over the whole layer, so a clear shows as alpha gone.
    _surface.easel.document.fill_layer(Color(1.0, 0.0, 0.0, 1.0))


func after_each() -> void:
    EventBus.corner_notice.disconnect(_hear)
    EventBus.paint_refused.disconnect(_hear)
    SaColors.foreground = _pair[0]
    SaColors.background = _pair[1]
    _host.free()
    _router.free()
    _router = null
    _registries = null
    Fixtures.teardown(_surface)
    _surface = null
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


func _hear(line: String) -> void:
    _heard.append(line)


## A bare key as a keyboard sends it: the character's code, its position and
## its label all set, and no modifier.
func _press(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.key_label = keycode
    event.pressed = true
    return event


## The active layer's colour at *point* of the first chunk, straight off the GPU.
func _texel(point: Vector2i) -> Color:
    var field: SaTexture = _surface.easel.document.active_layer.get_or_create_field(Vector2i.ZERO)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(field.rid, 0)
    var size := int(SaFieldSpec.BYTES_PER_TEXEL.get(field.format, 16))
    var at := (point.y * field.size.x + point.x) * size
    if size == 8:
        return Color(data.decode_half(at), data.decode_half(at + 2), data.decode_half(at + 4), data.decode_half(at + 6))
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


## Backspace, then Delete, each over a square of its own: what each key's
## square held goes, everything outside both stays red, and each press is one
## history step.
func test_backspace_then_delete_clear_only_the_selected_area() -> void:
    var doc: SaDocument = _surface.easel.document
    for press: Array in [[KEY_BACKSPACE, FIRST], [KEY_DELETE, SECOND]]:
        var square: Rect2i = press[1]
        var name := OS.get_keycode_string(press[0])
        doc.selection.select_rect(square)
        var steps := doc.history.step_count()

        assert_true(_router.handle(_press(press[0])), "The router takes %s" % name)

        assert_almost_eq(_texel(square.position + Vector2i(5, 5)).a, 0.0, 0.001, "%s cleared its square" % name)
        assert_almost_eq(_texel(square.end - Vector2i.ONE).a, 0.0, 0.001, "to its far corner")
        assert_almost_eq(_texel(UNSELECTED).a, 1.0, 0.001, "and left the paint outside it")
        assert_almost_eq(_texel(square.end + Vector2i(4, 4)).r, 1.0, 0.001, "red, just past its corner")
        assert_eq(doc.history.step_count(), steps + 1, "%s is one history step" % name)
    assert_almost_eq(_texel(FIRST.position + Vector2i(5, 5)).a, 0.0, 0.001, "The first square is still clear after Delete")
    assert_true(_heard.is_empty(), "A clear inside a selection says nothing: %s" % ", ".join(_heard))


## The command both keys reach, named on the Keyboard Shortcuts page with the
## two keys and the sentence that says what it does.
func test_both_keys_belong_to_the_clear_alone() -> void:
    var commands := _registries.commands
    assert_eq(commands.chord_text(&"layer_clear"), "Backspace, Delete", "The clear answers both bare keys")
    var sentence := commands.get_descriptor(&"layer_clear").sentence
    assert_true(sentence.contains("selected area"), "and says it clears the selected area: %s" % sentence)
    assert_true(sentence.contains("whole layer when nothing is selected"), "or the layer: %s" % sentence)
    var others: Array[String] = []
    for command_id: StringName in commands.list_ids():
        for chord in commands.chord_text(command_id).split(", ", false):
            if command_id != &"layer_clear" and (chord == "Backspace" or chord == "Delete"):
                others.append("%s on %s" % [command_id, chord])
    assert_true(others.is_empty(), "and nothing else does: %s" % ", ".join(others))


## With nothing selected the whole layer goes, as Krita's Clear does, and the
## corner says so, because a painter who pressed it for a selection they had
## dropped reads an empty layer as a fault.
func test_with_nothing_selected_the_layer_clears_and_says_so() -> void:
    var doc: SaDocument = _surface.easel.document
    var steps := doc.history.step_count()

    assert_true(_router.handle(_press(KEY_BACKSPACE)), "The router takes Backspace")

    assert_eq(doc.history.step_count(), steps + 1, "in one history step")
    assert_eq(doc.active_layer.chunks.size(), 0, "and the layer holds no chunk, which is no paint anywhere")
    assert_eq(_heard.size(), 1, "One line in the corner")
    assert_true(_heard[0].contains("whole layer was cleared"), "saying the whole layer went: %s" % _heard[0])


## A locked layer declines the key and says why, so the press falls through
## rather than vanishing into a command that did nothing.
func test_a_locked_layer_declines_and_says_why() -> void:
    var doc: SaDocument = _surface.easel.document
    doc.selection.select_rect(FIRST)
    doc.active_layer.is_locked = true
    var steps := doc.history.step_count()

    assert_false(_router.handle(_press(KEY_DELETE)), "Delete is declined on a locked layer")

    doc.active_layer.is_locked = false
    assert_almost_eq(_texel(FIRST.position).a, 1.0, 0.001, "The paint stays")
    assert_eq(doc.history.step_count(), steps, "and the history did not move")
    assert_eq(_heard.size(), 1, "One line in the corner")
    assert_true(_heard[0].contains("locked"), "naming the lock: %s" % _heard[0])


## The Layers docker's own name field, open and focused in a viewport standing
## in for the docker's window, keeps Backspace: the router leaves it to the
## field and the layer keeps its paint, which `text_field_keeps` in the router
## does for every bare key.
func test_backspace_in_a_focused_name_field_is_left_to_the_field() -> void:
    var doc: SaDocument = _surface.easel.document
    doc.selection.select_rect(FIRST)
    var steps := doc.history.step_count()
    var viewport := SubViewport.new()
    viewport.gui_disable_input = false
    _host.add_child(viewport)
    var list := SaLayerList.new()
    viewport.add_child(list)
    var idx := list.add_item(str(doc.active_layer.name), 0, false, doc.active_layer)
    assert_true(list.begin_rename(idx), "The name field opens")
    assert_true(viewport.gui_get_focus_owner() is LineEdit, "and has the keyboard")

    _router.handle_viewport_input(_press(KEY_BACKSPACE), viewport)

    assert_false(viewport.is_input_handled(), "The router leaves Backspace to the field")
    assert_almost_eq(_texel(FIRST.position).a, 1.0, 0.001, "and the selected paint stays")
    assert_eq(doc.history.step_count(), steps, "with no history step")


## The control for the case above: the same key through the same door with
## nothing focused is the clear, so the field is what kept it.
func test_with_nothing_focused_the_same_door_clears() -> void:
    var doc: SaDocument = _surface.easel.document
    doc.selection.select_rect(FIRST)
    var viewport := SubViewport.new()
    _host.add_child(viewport)

    _router.handle_viewport_input(_press(KEY_BACKSPACE), viewport)

    assert_true(viewport.is_input_handled(), "The router takes Backspace")
    assert_almost_eq(_texel(FIRST.position).a, 0.0, 0.001, "and the selected square is clear")


## A value slider that holds the focus keeps Backspace too, which puts it back
## to the value it was built with. A docker's window hands the router the key
## before its own controls, so without `slider_keeps` the press over a slider
## in a docker reset the slider and cleared the layer both, which the running
## app showed over the Tool Options docker's Flow.
func test_backspace_over_a_focused_slider_is_left_to_the_slider() -> void:
    var doc: SaDocument = _surface.easel.document
    doc.selection.select_rect(FIRST)
    var steps := doc.history.step_count()
    var viewport := SubViewport.new()
    _host.add_child(viewport)
    var slider := FactorSlider.new()
    slider.focus_mode = Control.FOCUS_ALL
    viewport.add_child(slider)
    slider.grab_focus()
    assert_eq(viewport.gui_get_focus_owner(), slider, "The slider holds the focus")

    _router.handle_viewport_input(_press(KEY_BACKSPACE), viewport)

    assert_false(viewport.is_input_handled(), "The router leaves Backspace to the slider")
    assert_almost_eq(_texel(FIRST.position).a, 1.0, 0.001, "and the selected paint stays")
    assert_eq(doc.history.step_count(), steps, "with no history step")
    assert_false(ShortcutRouter.slider_keeps(viewport, slider, _press(KEY_DELETE)), "Delete is not the slider's")
