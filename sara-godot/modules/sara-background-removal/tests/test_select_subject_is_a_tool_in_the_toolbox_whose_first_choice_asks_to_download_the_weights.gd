## Select Subject is a tool in the toolbox whose first choice
## asks to download the weights.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The base modules and this one register into one set of registries over a
## test surface, and a tool machine is bound to it as the app binds the main
## canvas's. A local server stands in for Google Drive and logs what it is
## asked, so a choice the dialog cancels is read as no request.
extends "res://tests/test_framework.gd"

const SubjectModule = preload("../module.gd")
const SelectSubjectTool = preload("../select_subject_tool.gd")
const WeightsServer = preload("weights_server.gd")
const WeightsDownload = preload("../weights_download.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const BASE_MODULES: Array[String] = [
    "res://modules/sara-base-modules/stamp-brush/module.gd",
    "res://modules/sara-base-modules/base/module.gd",
]
## The frames a download of the test's bytes is given, far more than it needs.
const PATIENCE := 1200

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _module: SaModule = null
var _machine: ToolMachine = null
var _server: Node = null


func after_each() -> void:
    if _server != null and is_instance_valid(_server):
        _server.queue_free()
    _server = null
    if _module != null:
        _forget_weights()
    for each: SaModule in _modules:
        each.unregister(_registries.context)
    _modules.clear()
    _module = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    _registries = null


## Registers the base modules and this one, this one first when *first*, and
## binds a machine to the surface. *bytes* are what the local server sends.
func _build(bytes: PackedByteArray, first: bool = false) -> void:
    _server = WeightsServer.new(bytes)
    (Engine.get_main_loop() as SceneTree).root.add_child(_server)
    _surface = Fixtures.make_surface()
    _registries = SaRegistries.new()
    var surface := _surface
    _registries.build_context(func() -> SaEasel: return surface.easel, func() -> Array: return [surface])
    _module = SubjectModule.new(_server.url(), sha256_of(bytes))
    # A suite before this one can leave a toolbox order holding the row already.
    SaSettings.set_layout_order(SubjectModule.TOOLBOX, [])
    var order: Array[SaModule] = []
    for path: String in BASE_MODULES:
        order.append(load(path).new())
    order.insert(0 if first else order.size(), _module)
    for each: SaModule in order:
        each.register(_registries.context.for_module(each.get_id()))
        _modules.append(each)
    _forget_weights()
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _surface.tool_machine = _machine
    await _frames(1)


func _forget_weights() -> void:
    var path: String = _module.weights_path()
    for each: String in [path, path + ".part"]:
        if FileAccess.file_exists(each):
            DirAccess.remove_absolute(each)


static func made_bytes(count: int) -> PackedByteArray:
    var out := PackedByteArray()
    out.resize(count)
    for i: int in count:
        out[i] = (i * 17 + (i >> 9)) & 0xFF
    return out


static func sha256_of(bytes: PackedByteArray) -> String:
    var hashing := HashingContext.new()
    hashing.start(HashingContext.HASH_SHA256)
    hashing.update(bytes)
    return hashing.finish().hex_encode()


func _frames(count: int) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    for _frame: int in count:
        await tree.process_frame


func _dialog_open() -> bool:
    var dialog: Window = _module.dialog
    return dialog != null and is_instance_valid(dialog) and dialog.visible


## The tool rows of a fresh toolbox's order, which no stored order overrides
## in the runner's settings.
func _rows() -> Array:
    return SaSettings.get_layout_order(SubjectModule.TOOLBOX).filter(func(row: String) -> bool: return row.ends_with(" Tool"))


func test_the_toolbox_row_stands_after_the_magic_wand_s_whichever_module_registers_first() -> void:
    for first: bool in [false, true]:
        await _build(made_bytes(100), first)
        assert_true(_registries.tools.has(SubjectModule.TOOL), "the tool is registered")
        var rows := _rows()
        assert_eq(
            rows.find("Select Subject Tool"),
            rows.find("Magic Wand Tool") + 1,
            "the toolbox's row right after the Magic Wand's, this module first %s: %s" % [first, rows]
        )
        var descriptor: SaToolDescriptor = _registries.tools.get_descriptor(SubjectModule.TOOL)
        assert_eq(descriptor.category, &"select", "in the selection group")
        assert_eq(descriptor.display_name, "Select Subject", "named Select Subject")
        var wand_group: Array = []
        for group: Array in SaToolBoxGroups.from_registry(_registries.tools.list_descriptors()):
            if group.has("wand"):
                wand_group = group
        assert_true(
            wand_group.has(String(SubjectModule.TOOL)) and wand_group.has(String(SubjectModule.BOX_TOOL)),
            "Select Subject and Object Selection share the Magic Wand's button, so W steps through them: %s" % [wand_group]
        )
        assert_eq(descriptor.cursor_shape, Control.CURSOR_CROSS, "with a crosshair")
        assert_true(descriptor.reads_keys.has(KEY_SHIFT) and descriptor.reads_keys.has(KEY_ALT), "reading Shift and Alt")
        assert_not_null(SaUI.get_icon(descriptor.icon_name), "an icon of its own: %s" % descriptor.icon_name)
        var keys: Array[StringName] = []
        for option: SaOptionSpec in descriptor.options:
            keys.append(option.key)
        assert_eq(keys, [&"sample_merged"] as Array[StringName], "and the wand's Merged")
        after_each()


func test_cancel_hands_back_accept_keeps_and_a_third_choice_asks_nothing() -> void:
    var bytes := made_bytes(300000)
    await _build(bytes)
    _machine.set_active_tool(&"wand")
    _machine.set_active_tool(SubjectModule.TOOL)
    assert_true(_dialog_open(), "the first choice opens the dialog at once")
    _module.dialog.cancel()
    await _frames(20)
    assert_false(_dialog_open(), "Cancel closes it")
    assert_eq(_machine.default_tool_name, &"wand", "and puts the Magic Wand, in hand before, back in hand")
    assert_eq(_server.requests.size(), 0, "the server's log is empty: %s" % [_server.requests])

    _machine.set_active_tool(SubjectModule.TOOL)
    assert_true(_dialog_open(), "a second choice opens it again")
    _module.dialog.accept()
    var tree := Engine.get_main_loop() as SceneTree
    for _frame: int in PATIENCE:
        await tree.process_frame
        var download: WeightsDownload = _module.dialog.download
        if download == null or download.outcome != WeightsDownload.Outcome.RUNNING:
            break
    assert_true(FileAccess.file_exists(_module.weights_path()), "Accept keeps the file: %s" % _module.dialog.status.text)
    assert_eq(_machine.default_tool_name, SubjectModule.TOOL, "and the Select Subject tool stays in hand")
    assert_false(_dialog_open(), "the dialog closed")

    _machine.set_active_tool(&"wand")
    _machine.set_active_tool(SubjectModule.TOOL)
    await _frames(20)
    assert_false(_dialog_open(), "a third choice opens no dialog")
    assert_eq(_server.requests.size(), 1, "and the server's log shows one request: %s" % [_server.requests])
    (_machine.active_tool as SelectSubjectTool).click()
    await _frames(5)
    assert_false(_dialog_open(), "a click opens no dialog")
    # The served bytes are no model file, so the click runs the
    # network and says why it cannot.
    assert_true(
        _module.said.begins_with("Select Subject could not run: "), "and runs the network on the weights kept: %s" % _module.said
    )


func test_the_x_closes_as_cancel_does() -> void:
    await _build(made_bytes(100))
    _machine.set_active_tool(&"lasso")
    _machine.set_active_tool(SubjectModule.TOOL)
    assert_true(_dialog_open(), "the dialog opens")
    _module.dialog.close_requested.emit()
    await _frames(5)
    assert_false(_dialog_open(), "the × closes it")
    assert_eq(_machine.default_tool_name, &"lasso", "and hands back the Lasso")
    assert_eq(_server.requests.size(), 0, "having asked nothing")


func test_the_command_puts_the_tool_in_hand_and_no_select_row_runs_it() -> void:
    await _build(made_bytes(100))
    var command: SaCommandDescriptor = _registries.commands.get_descriptor(SubjectModule.COMMAND)
    assert_not_null(command, "a command a chord can be bound to")
    assert_false(command.show_in_select_menu, "which is no row of the Select menu")
    assert_true(command.handler.call(), "and puts the tool in hand")
    assert_eq(_machine.default_tool_name, SubjectModule.TOOL, "the Select Subject tool")
    assert_true(_dialog_open(), "opening the dialog with no weights kept")
    _module.dialog.cancel()


func test_shift_adds_and_alt_subtracts() -> void:
    var modes: Array[int] = []
    var tool := SelectSubjectTool.new()
    tool.settings = SelectSubjectTool.Click.new(func(mode: int, _merged: bool, _on: SaSurface) -> void: modes.append(mode))
    for keys: Array in [[false, false], [true, false], [false, true]]:
        var press := InputEventMouseButton.new()
        press.button_index = MOUSE_BUTTON_LEFT
        press.pressed = true
        press.shift_pressed = keys[0]
        press.alt_pressed = keys[1]
        tool.handle_input(press)
    assert_eq(
        modes,
        [SaSelection.Mode.REPLACE, SaSelection.Mode.ADD, SaSelection.Mode.SUBTRACT] as Array[int],
        "a plain click replaces, Shift adds, Alt subtracts"
    )
