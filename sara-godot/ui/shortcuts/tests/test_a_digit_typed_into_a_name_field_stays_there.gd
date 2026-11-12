## The other half of the opacity digits: a digit typed into the Layers docker's name
## field is part of the name, and no opacity changes.
##
## The Layers docker's own list opens its own name field on the active layer,
## in a `SubViewport` standing in for the docker's window for the reason
## `test_text_box_keyboard.gd` gives, and the key goes to the router the way a
## docker hands it one. The brush is the active tool in one case and the move
## tool in the other, so both opacities a digit could reach are read.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Node = null
var _router: ShortcutRouter = null


func before_each() -> void:
    SaOpacityDigitCommands.forget_pending()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    var registries := Fixtures.make_registries()
    var machine := _machine
    SaAppCommands.register_all(registries, Callable(), func() -> ToolMachine: return machine)
    _router = ShortcutRouter.new()
    _router.bind_commands(registries.commands)
    _host = Node.new()
    _host.name = "OpacityDigitNameFieldTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaOpacityDigitCommands.forget_pending()
    _router.free()
    _host.free()
    Fixtures.teardown(_surface, _machine)


## The list in a viewport of its own with the active layer's name field open
## and focused. Answers the viewport and the field.
func _open_the_name_field() -> Array:
    var viewport := SubViewport.new()
    viewport.gui_disable_input = false
    _host.add_child(viewport)
    var list := SaLayerList.new()
    viewport.add_child(list)
    var layer := _surface.get_document().active_layer
    var idx := list.add_item(str(layer.name), 0, false, layer)
    assert_true(list.begin_rename(idx), "the name field opens")
    var edit := viewport.gui_get_focus_owner() as LineEdit
    assert_true(edit != null, "and has the keyboard")
    return [viewport, edit]


func _digit(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.unicode = OS.get_keycode_string(keycode).unicode_at(0)
    event.pressed = true
    return event


func _type_into_the_field(tool_id: StringName) -> void:
    _machine.set_active_tool(tool_id)
    var opened := _open_the_name_field()
    var viewport: SubViewport = opened[0]
    var edit: LineEdit = opened[1]
    if edit == null:
        return
    edit.text = "Sky "
    edit.caret_column = edit.text.length()
    for keycode: Key in [KEY_5, KEY_KP_4]:
        var event := _digit(keycode)
        _router.handle_viewport_input(event, viewport)
        assert_false(viewport.is_input_handled(), "the router leaves %s to the field" % OS.get_keycode_string(keycode))
    assert_almost_eq(float(_machine.get_tool(&"brush").get("settings").opacity), 1.0, 0.0001, "the brush's opacity is untouched")
    assert_almost_eq(_surface.get_document().active_layer.opacity, 1.0, 0.0001, "and so is the layer's")


func test_with_the_brush_a_digit_in_the_name_field_sets_no_opacity() -> void:
    _type_into_the_field(&"brush")


func test_with_the_move_tool_a_digit_in_the_name_field_sets_no_opacity() -> void:
    _type_into_the_field(&"transform")


## The control: the same key through the same door with nothing focused is an
## opacity, so the two cases above are the field's doing and not a dead key.
func test_with_the_field_closed_the_same_key_sets_the_opacity() -> void:
    _machine.set_active_tool(&"transform")
    var viewport := SubViewport.new()
    _host.add_child(viewport)
    _router.handle_viewport_input(_digit(KEY_5), viewport)
    assert_true(viewport.is_input_handled(), "the router takes the 5")
    assert_almost_eq(_surface.get_document().active_layer.opacity, 0.5, 0.0001, "and the layer is at 50 %")
