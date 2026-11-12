## A chord steps the colour picker through its shapes and wraps.
##
## The colour picker's modes are switched by a shortcut. There are seven modes rather than
## two, so a toggle is a step that comes back round, and this walks the whole
## list and past the end.
##
## The setting is the only thing the command writes, deliberately: every picker
## in a tree rebuilds on `profile_changed`, so a command with no picker to hand
## still moves the docker. `scenarios/a-chord-steps-through-the-pickers-shapes.json`
## is the half that has to be photographed, because a shape is a picture and a
## key is not.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const SaPickerShapeScript = preload("res://ui/widgets/picker/sa_picker_shape.gd")

## The chord, in the form `chord_text` prints.
const CHORD := "Ctrl+Shift+K"

var _saved_shape: String = ""


func before_each() -> void:
    _saved_shape = SaSettings.color_picker_shape


func after_each() -> void:
    SaSettings.color_picker_shape = _saved_shape


## The commands the running app registers, plus the router that holds them.
## Freed by the caller, because the registry keeps handlers bound to it.
func _commands(router: ShortcutRouter) -> SaCommandRegistry:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    if router != null:
        router.bind_commands(registries.commands)
    return registries.commands


## The whole list, in order, and then one more step back to where it started.
func test_a_step_walks_every_shape_and_comes_back_round() -> void:
    var keys := SaPickerShapeScript.KIND_KEYS
    SaSettings.color_picker_shape = keys[0]

    for i in range(1, keys.size()):
        var landed := SaColorPicker.step_shape_kind(1)
        assert_eq(landed, keys[i], "Step %d lands on %s" % [i, keys[i]])
        assert_eq(SaSettings.color_picker_shape, keys[i], "and the setting is what carries it")

    assert_eq(SaColorPicker.step_shape_kind(1), keys[0], "and the step past the last one is the first")


## Backwards as well, because the command that steps forward is one line from a
## second that steps back, and a wrap that only works one way is half a wrap.
func test_a_step_backwards_wraps_the_other_way() -> void:
    var keys := SaPickerShapeScript.KIND_KEYS
    SaSettings.color_picker_shape = keys[0]

    assert_eq(SaColorPicker.step_shape_kind(-1), keys[keys.size() - 1], "Back from the first is the last")
    assert_eq(SaColorPicker.step_shape_kind(-1), keys[keys.size() - 2], "and back again is the one before it")


## A profile naming a shape this build does not have reads as the wheel
## everywhere else, so a step off it has to land where a step off the wheel
## lands rather than nowhere.
func test_an_unknown_shape_steps_off_the_wheel() -> void:
    SaSettings.color_picker_shape = "a-shape-this-build-has-never-had"

    assert_eq(SaColorPicker.step_shape_kind(1), SaPickerShapeScript.KIND_KEYS[1], "which is the second shape")


## The picker follows the setting rather than being written into, which is what
## lets a command that has no picker move one.
func test_a_picker_in_a_tree_follows_the_step() -> void:
    var picker := SaColorPicker.new()
    EventBus.add_child(picker)
    SaSettings.color_picker_shape = SaPickerShapeScript.KIND_KEYS[0]
    assert_eq(picker.shape.kind, 0, "The picker starts on the first shape")

    SaColorPicker.step_shape_kind(1)

    assert_eq(picker.shape.kind, 1, "and a step moves it without anybody holding it")
    assert_eq(picker.picker_report()["type_setting"], SaPickerShapeScript.KIND_KEYS[1], "which is what a dump reads")
    picker.free()


## The command is registered, carries the chord, and does what the step does.
func test_the_command_is_registered_and_carries_the_chord() -> void:
    var router := ShortcutRouter.new()
    var commands := _commands(router)

    assert_true(commands.has(&"color_picker_shape_next"), "The command is registered")
    assert_eq(commands.chord_text(&"color_picker_shape_next"), CHORD, "and answers to %s" % CHORD)

    SaSettings.color_picker_shape = SaPickerShapeScript.KIND_KEYS[0]
    assert_true(commands.execute(&"color_picker_shape_next"), "Running it consumes the event")
    assert_eq(SaSettings.color_picker_shape, SaPickerShapeScript.KIND_KEYS[1], "and steps the shape")

    router.free()


## The Keyboard Shortcuts page finds it under Colour and names it, which is
## where a painter looking for it looks. The label rather than the id, because
## the id is not what the page prints.
func test_the_shortcuts_page_lists_it_under_colour() -> void:
    var router := ShortcutRouter.new()
    var commands := _commands(router)
    assert_true(commands.has(&"color_picker_shape_next"), "registered, so the InputMap has the action")

    var found := SaShortcutRows.actions_for("color_").has(&"color_picker_shape_next")

    assert_true(found, "The Colour section finds it")
    assert_eq(
        SaShortcutRows.label_for("color_picker_shape_next", null, null, commands),
        "Next colour picker shape",
        "and names it rather than printing the id"
    )
    router.free()
