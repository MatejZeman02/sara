## The Tool Options panel shows the Text tool's Font and Size rows although the
## top bar shows them too, so the panel is not empty with Text selected, and the
## two controls hold the same value.
##
## Built the way the app builds it: the modules through the door, a machine, the
## real bar in the tree, and the docker joined to the bar's `refitted`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const TextModuleScript = preload("res://modules/sara-base-modules/text/module.gd")

## Wide enough that the bar's first row holds everything, at any theme scale.
const ROOMY := 4000.0

## A fresh profile, so the bar holds what a fresh bar holds.
static var scratch_profile: String = SaDataRoot.path("test_the_text_tool_rows.cfg")

var _saved_path: String = ""
var _saved_row: bool = false
var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _bar_host: Node = null
var _bar: TopMenuBar = null
var _host: Node = null
var _docker: ToolOptionsDocker = null


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _saved_row = SaSettings.second_row
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_scratch_profile()
    SaSettings.load_settings()
    SaSettings.second_row = false
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript, TextModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    _bar = TopMenuBar.new()
    _bar.add_tool_options(options)
    _bar_host = Node.new()
    _bar_host.name = "TextBarHost"
    EventBus.add_child(_bar_host)
    _bar_host.add_child(_bar)
    # A bar outside a container keeps the width written to it only with its
    # anchors pinned together.
    _bar.set_anchor(SIDE_RIGHT, 0.0)
    _host = Node.new()
    _docker = ToolOptionsDocker.new()
    _host.add_child(_docker)
    _docker.peer_bar = options
    _bar.rows.refitted.connect(_docker.sync_from_tool)
    _docker.target_tool_machine = _machine
    _machine.set_active_tool(&"text")
    _lay_out(ROOMY)


func after_each() -> void:
    _host.free()
    _bar_host.free()
    _docker = null
    _bar = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _remove_scratch_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row


func test_the_panel_shows_font_and_size_while_the_bar_does() -> void:
    for key: StringName in [&"text_font", &"text_size"]:
        assert_true(_docker.bar_shows(key), "The roomy bar shows '%s'" % key)
        assert_true(_docker.shown_keys().has(key), "and the panel shows it as well")
    assert_false(_docker._empty_label.visible, "The panel is not empty")


func test_a_value_written_on_the_tool_reaches_the_panel_row() -> void:
    _machine.active_tool.set("font_size", 123.0)
    _docker.sync_values_from_tool()
    var control := _docker.options.control(&"text_size")
    assert_not_null(control, "The panel built a Size control")
    var read: Variant = control.get("value") if control != null else null
    assert_eq(read, 123.0, "and it reads what the tool holds")


func _row_of(key: StringName) -> Control:
    return _docker._rows.get(key, null) as Control


func _label_of(key: StringName) -> Label:
    var row := _row_of(key)
    assert_not_null(row, "The docker built a row for '%s'" % key)
    var label := row.get_node_or_null("Label") as Label if row != null else null
    assert_not_null(label, "and it has a label column")
    return label


## What the row's label reads, or a word no label reads when there is none.
func _text_of(key: StringName) -> String:
    var label := _label_of(key)
    return label.text if label != null else "(no label)"


func _lay_out(width: float) -> void:
    _bar.size.x = width
    _bar.apply_layout_settings()


func _remove_scratch_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)
