## A digit typed over the canvas sets the brush's opacity with a
## painting tool and the active layer's with any other, by Photoshop's rule.
##
## The sequence is 5, then 4 and 5 quickly, then 0, with the brush and
## with the move tool, reading both opacities after each. The pairing is timed,
## so the sequence is typed through `SaOpacityDigitCommands.apply` with the clock
## handed in, and the keys themselves go through the router in the cases
## after it: the digit row, the numpad, and the Czech digit row that arrives
## with a letter as its keycode.
##
## The corner says "Brush opacity 50%" under the brush and
## 'Layer opacity 50%, "Layer 1"' under the eyedropper. The last cases read the
## corner's words for both.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## Where the preset the bar loads is written, and cleared again after each case.
static var scratch_dir: String = SaDataRoot.path("test_n68_presets")

## The Czech layout's key 5 on the digit row types `ř` without Shift, and Godot
## hands its letter over as the keycode.
const CZECH_FIVE: int = 0x159

var _surface: SaSurface = null
var _machine: ToolMachine = null

## The corner's host and the bar's, in the tree so `SaBrushSlotCommands.preset_box`
## finds the bar from the root the way it does in the app. Null until a case asks.
var _host: Node = null
var _previous_embedding: bool = true


func before_each() -> void:
    SaOpacityDigitCommands.forget_pending()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)


func after_each() -> void:
    SaOpacityDigitCommands.forget_pending()
    if _host != null:
        # Freeing the host runs `SaMessage._uninstall`, so the corner goes with it.
        _host.free()
        _host = null
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _previous_embedding
        ScratchFolder.empty(scratch_dir)
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _brush_opacity() -> float:
    return float(_machine.get_tool(&"brush").get("settings").opacity)


func _layer_opacity() -> float:
    return _surface.get_document().active_layer.opacity


## The sequence at the clock the painter would type it: a pause after
## the 5, the pair within the moment, a pause before the 0. Answers the brush's
## and the layer's opacity after each step.
func _type_the_sequence() -> Array:
    var readings: Array = []
    var pause := SaOpacityDigitCommands.PAIR_MSEC + 200
    var at := 10000
    for step: Array in [[5, 0], [4, pause], [5, 100], [0, pause]]:
        at += int(step[1])
        assert_true(SaOpacityDigitCommands.apply(_machine, int(step[0]), at), "the digit %d is taken" % step[0])
        readings.append([_brush_opacity(), _layer_opacity()])
    return readings


func test_with_the_brush_the_digits_set_the_brushs_opacity() -> void:
    _machine.set_active_tool(&"brush")
    assert_eq(_machine.active_tool_name, &"brush", "the brush is the active tool")
    var readings := _type_the_sequence()
    var brush: Array = readings.map(func(r: Array) -> float: return snappedf(r[0], 0.001))
    assert_eq(brush, [0.5, 0.4, 0.45, 1.0], "5 is 50 %, 4 then 5 quickly is 45 %, and 0 is 100 %")
    for reading: Array in readings:
        assert_almost_eq(float(reading[1]), 1.0, 0.0001, "and the layer's opacity is untouched")


func test_with_the_move_tool_the_digits_set_the_layers_opacity() -> void:
    _machine.set_active_tool(&"transform")
    assert_eq(_machine.active_tool_name, &"transform", "the move tool is the active tool")
    var readings := _type_the_sequence()
    var layer: Array = readings.map(func(r: Array) -> float: return snappedf(r[1], 0.001))
    assert_eq(layer, [0.5, 0.4, 0.45, 1.0], "5 is 50 %, 4 then 5 quickly is 45 %, and 0 is 100 %")
    for reading: Array in readings:
        assert_almost_eq(float(reading[0]), 1.0, 0.0001, "and the brush's opacity is untouched")


## Photoshop's two corners of the pair: a leading 0 is a single figure, and
## two noughts are nothing.
func test_a_leading_nought_pairs_too() -> void:
    _machine.set_active_tool(&"brush")
    SaOpacityDigitCommands.apply(_machine, 0, 1000)
    SaOpacityDigitCommands.apply(_machine, 5, 1100)
    assert_almost_eq(_brush_opacity(), 0.05, 0.0001, "0 then 5 is 5 %")
    SaOpacityDigitCommands.apply(_machine, 0, 5000)
    SaOpacityDigitCommands.apply(_machine, 0, 5100)
    assert_almost_eq(_brush_opacity(), 0.0, 0.0001, "0 then 0 is 0 %")


## The keys, through the router the way the main window hands it one.
func _router() -> ShortcutRouter:
    var registries := Fixtures.make_registries()
    var machine := _machine
    SaAppCommands.register_all(registries, Callable(), func() -> ToolMachine: return machine)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands)
    return router


func _press(router: ShortcutRouter, keycode: int, position: Key = KEY_NONE) -> bool:
    SaOpacityDigitCommands.forget_pending()
    var event := InputEventKey.new()
    event.keycode = keycode as Key
    event.physical_keycode = position
    event.pressed = true
    return router.handle(event)


func test_the_digit_row_and_the_numpad_both_answer() -> void:
    _machine.set_active_tool(&"brush")
    var router := _router()
    assert_true(_press(router, KEY_3, KEY_3), "the digit row's 3 is taken")
    assert_almost_eq(_brush_opacity(), 0.3, 0.0001, "and sets 30 %")
    assert_true(_press(router, KEY_KP_7), "the numpad's 7 is taken")
    assert_almost_eq(_brush_opacity(), 0.7, 0.0001, "and sets 70 %")
    router.free()


func test_the_czech_digit_row_answers_by_its_position() -> void:
    _machine.set_active_tool(&"transform")
    var router := _router()
    assert_true(_press(router, CZECH_FIVE, KEY_5), "the key in the 5's place is taken though it types a letter")
    assert_almost_eq(_layer_opacity(), 0.5, 0.0001, "and sets the layer to 50 %")
    router.free()


func test_ctrl_with_a_digit_is_not_an_opacity() -> void:
    _machine.set_active_tool(&"brush")
    var router := _router()
    var event := InputEventKey.new()
    event.keycode = KEY_4
    event.ctrl_pressed = true
    event.pressed = true
    router.handle(event)
    assert_almost_eq(_brush_opacity(), 1.0, 0.0001, "Ctrl+4 leaves the opacity alone")
    router.free()


## Ten rows on the Keyboard Shortcuts page, one per digit, each on its digit and
## its numpad key, so a painter who wants the keys for something else rebinds
## them.
func test_ten_commands_one_per_digit() -> void:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, Callable())
    for digit in range(10):
        var id := SaOpacityDigitCommands.command_id(digit)
        assert_true(registries.commands.has(id), "%s is registered" % id)
        assert_true(SaShortcutRows.actions_for("brush_").has(id), "and listed in the Brush section")
        var chords := registries.commands.chord_text(id)
        assert_true(chords.begins_with(str(digit)), "%s answers to %d, it says %s" % [id, digit, chords])


## The corner installed over a host in the tree, the way the main window
## installs it, embedded so its problem dialog opens no window of its own.
func _install_corner() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _previous_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N68CornerHost"
    EventBus.add_child(_host)
    SaMessage.install(_host)


func _corner() -> String:
    var notice := SaMessage.notice_widget()
    return notice.label.text if notice != null and notice.showing() else ""


## The layer by its name under the eyedropper, and the brush
## by the tool's own name while the bar has no preset loaded, which is every
## host without a bar.
func test_the_corner_names_the_layer_and_the_brush_one_way() -> void:
    _install_corner()
    _machine.set_active_tool(&"eyedropper")
    assert_true(SaOpacityDigitCommands.apply(_machine, 5, 1000), "the eyedropper's 5 is taken")
    var layer := _surface.get_document().active_layer
    assert_eq(_corner(), 'Opacity 50%%, layer "%s"' % layer.name, "the corner names the layer it set")
    _machine.set_active_tool(&"brush")
    assert_true(SaOpacityDigitCommands.apply(_machine, 5, 5000), "the brush's 5 is taken")
    assert_eq(_corner(), 'Opacity 50%, brush "Brush"', "and the brush the same way, by the tool with no preset")


## The brush by the preset the bar has loaded, which is what a painter picked
## and what the bar's preset button reads.
func test_the_corner_names_the_brush_by_its_preset() -> void:
    _install_corner()
    _machine.set_active_tool(&"brush")
    var bar := ToolOptionsBar.new()
    bar.name = "ToolOptionsBar"
    bar.target_tool_machine = _machine
    bar.preset_store.dir = scratch_dir
    bar.preset_store.save_preset("Soft Round", StampSettingsScript.new())
    _host.add_child(bar)
    assert_true(bar.preset_box.load_preset("Soft Round"), "the bar loads the preset")
    assert_true(SaOpacityDigitCommands.apply(_machine, 3, 1000), "the brush's 3 is taken")
    assert_eq(_corner(), 'Opacity 30%, brush "Soft Round"', "the corner names the preset in the hand")
