## The brush editor's switches are On and Off buttons, as in Tool Options.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every switch the editor shows, the `SmudgeSampleMergedRow` and the
## `PageTitleRow` among them, is dressed by
## `SaOnOffSwitch`, the class the Tool Options docker dresses its own rows with.
##
## The window is built detached and its page column hosted under the `EventBus`
## autoload, for the reason the page-switch suite gives, inside a viewport of its own, and
## a click is pushed into that viewport as a real press, so nothing another
## suite left in the root can take it. The page scrolls to the control first:
## Sample merged sits below a column of a thousand pixels, and a column lifted
## by hand to bring it into view took the press on nothing in the whole run.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The window builds curve controls and a scratchpad with a canvas in it.
const REQUIRES_GPU := true

const CHISEL := "Chisel Marker"

static var scratch_dir: String = SaDataRoot.path("test_on_off")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Control = null
var _viewport: SubViewport = null
var _window: SaBrushEditorWindow = null
var _docker_host: Node = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)


func after_each() -> void:
    if _viewport != null:
        _viewport.free()
    _viewport = null
    _host = null
    if _window != null:
        _window.free()
    _window = null
    if _docker_host != null:
        _docker_host.free()
    _docker_host = null
    Fixtures.teardown(_surface, _machine)
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


## The brush made Chisel Marker as it ships, whose Rotation is off, and the
## editor opened on *page_title* with its page column in the tree.
func _open_on(page_title: String) -> int:
    var state := _machine.get_tool("brush")
    var settings := state.get("settings") as SaStampBrushSettings
    var built := _chisel(settings.get_script() as Script)
    for property: Dictionary in built.get_property_list():
        var name := String(property["name"])
        if int(property["usage"]) & PROPERTY_USAGE_STORAGE and name != "script" and not name.begins_with("resource_"):
            settings.set(name, built.get(name))
    _window = SaBrushEditorWindow.new()
    var specs: Array[SaOptionSpec] = []
    specs.assign(_machine.get_descriptor(&"brush").options)
    _window.bind_tool(state, specs, _store())
    var at := _window.pages.index_of(page_title)
    _window.show_page(at)
    _host = Control.new()
    _host.size = Vector2(900, 1000)
    var column := _window.page_scroll
    column.get_parent().remove_child(column)
    _host.add_child(column)
    column.position = Vector2.ZERO
    column.size = _host.size
    _viewport = SubViewport.new()
    _viewport.size = Vector2i(1920, 1080)
    _viewport.add_child(_host)
    EventBus.add_child(_viewport)
    _settle()
    return at


func _chisel(script: Script) -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == CHISEL:
            return SaShippedPresets.build(script, entry) as SaStampBrushSettings
    return null


func _settings() -> SaStampBrushSettings:
    return _machine.get_tool("brush").get("settings") as SaStampBrushSettings


func _settle() -> void:
    for _pass in 2:
        _sort(_host)


static func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)


## A real press and release at the middle of *control*, after a motion over
## it, so a button that presses only while hovered is, pushed into the
## suite's own viewport.
func _click(control: Control) -> void:
    # The page scrolls to the control, as a painter's wheel would, because a
    # press below the column's edge lands on nothing.
    _window.page_scroll.ensure_control_visible(control)
    _settle()
    var at := control.get_global_rect().get_center()
    var over := InputEventMouseMotion.new()
    over.position = at
    over.global_position = at
    _viewport.push_input(over)
    for pressed: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
        event.position = at
        event.global_position = at
        _viewport.push_input(event)
    _settle()


## Every switch on the open page: the page's own, each plain `BOOL` row and
## each switch above one of several graphs. A pair's halves are named buttons
## under one label and are left out, as `PageLayout.place_row` leaves them.
func _switches() -> Dictionary:
    var out: Dictionary = {}
    var pages := _window.pages
    if pages.page_switch != null:
        out["page switch"] = pages.page_switch
    for spec: SaOptionSpec in pages.open_specs():
        if spec == null or not spec.in_editor or pages.page_controls == null:
            continue
        if spec.kind == SaOptionSpec.Kind.BOOL and spec.pair_with.is_empty() and not _is_paired(spec):
            var control := pages.page_controls.control(spec.key) as Button
            if control != null:
                out[String(spec.key)] = control
        elif spec.kind == SaOptionSpec.Kind.CURVE_OPTION:
            var named := pages.page_body.find_child("%sEnabled" % String(spec.key).to_pascal_case(), true, false) as Button
            if named != null:
                out[String(spec.key)] = named
    return out


func _is_paired(spec: SaOptionSpec) -> bool:
    for other: SaOptionSpec in _window.pages.open_specs():
        if other != null and other.pair_with == spec.key:
            return true
    return false


## Every switch reads as the shared On/Off button, saying the state it holds.
func _assert_on_off(where: String) -> int:
    var switches := _switches()
    for key: String in switches:
        var button := switches[key] as Button
        assert_not_null(SaOnOffSwitch.of(button), "%s: %s is the shared On/Off button" % [where, key])
        SaOnOffSwitch.refresh(button)
        assert_eq(button.text, SaOnOffSwitch.word(button.button_pressed), "%s: %s says the state it holds" % [where, key])
        assert_eq(button.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN, "%s: %s is not a bar across the row" % [where, key])
    return switches.size()


## "A suite opens the brush editor on Smudge Pickup ... and reads every switch
## as the shared On/Off button with the text matching the value, then toggles
## one with a real click and reads the text and the brush change."
func test_smudge_pickup_s_switches_say_on_or_off_and_a_click_turns_one() -> void:
    var at := _open_on("Smudge Pickup")
    assert_true(at >= 0, "The brush has a Smudge Pickup page")
    assert_true(_assert_on_off("Smudge Pickup") >= 2, "The page has its own switch and Sample merged at least")
    var merged := _window.pages.page_controls.control(&"smudge_sample_merged") as Button
    assert_not_null(merged, "The page draws Sample merged")
    if merged == null:
        return
    var was := _settings().smudge_sample_merged
    assert_eq(merged.text, SaOnOffSwitch.word(was), "Sample merged says what the brush holds")
    _click(merged)
    assert_eq(_settings().smudge_sample_merged, not was, "The click changed the brush")
    assert_eq(merged.text, SaOnOffSwitch.word(not was), "and the button says so")


## "... and on Rotation": the page switch sits beside the title at a row's
## height, dims the page while it reads Off, and a click on it turns Rotation
## on and lifts the dimming.
func test_rotation_s_page_switch_is_on_off_beside_the_title_and_dims_the_page() -> void:
    var at := _open_on("Rotation")
    assert_true(at >= 0, "The brush has a Rotation page")
    _assert_on_off("Rotation")
    var pages := _window.pages
    var switch := pages.page_switch
    assert_not_null(switch, "Rotation has a page switch")
    if switch == null:
        return
    var option := _settings().rotation_option
    assert_false(option.enabled, "Chisel Marker ships with Rotation off")
    assert_eq(switch.text, "Off", "and the page switch says Off")
    assert_almost_eq(pages.page_body.modulate.a, SaOptionSpec.DIMMED_ALPHA, 0.001, "The page below the title is dimmed")
    var title := switch.get_parent().get_node("PageTitle") as Control
    var gap := switch.get_global_rect().position.x - title.get_global_rect().end.x
    assert_true(gap <= SaUI.px(SaTheme.GAP) + 1.0, "The switch sits beside the title, %d away" % gap)
    assert_true(switch.size.y <= SaUI.px(SaUI.BASE_ICON_SIZE + 2) + 8.0, "at the height of a row, %d" % switch.size.y)
    _click(switch)
    assert_true(option.enabled, "The click turned Rotation on")
    assert_eq(switch.text, "On", "and the switch says On")
    assert_almost_eq(pages.page_body.modulate.a, 1.0, 0.001, "and the page is no longer dimmed")


## "every plain switch row on every page of both engines": every page of every
## brush engine the machine knows.
func test_every_page_of_every_engine_draws_its_switches_as_on_off() -> void:
    _open_on("Rotation")
    var engines := 0
    var seen := 0
    for tool_id: StringName in [&"brush"] + _engine_ids():
        var state := _machine.get_tool(tool_id)
        var descriptor := _machine.get_descriptor(tool_id)
        if state == null or descriptor == null:
            continue
        engines += 1
        var specs: Array[SaOptionSpec] = []
        specs.assign(descriptor.options)
        _window.bind_tool(state, specs, _store())
        for i in _window.pages.count():
            _window.show_page(i)
            _settle()
            seen += _assert_on_off("%s, %s" % [tool_id, _window.pages.title_at(i)])
    assert_true(engines >= 2, "Both engines were walked, %d" % engines)
    assert_true(seen > 10, "and %d switches read" % seen)


func _engine_ids() -> Array[StringName]:
    var out: Array[StringName] = []
    for tool_id: StringName in _machine.registry.list_ids():
        var descriptor := _machine.get_descriptor(tool_id)
        if descriptor != null and descriptor.is_brush_engine:
            out.append(tool_id)
    return out


## "through one shared widget rather than a copy": the Tool Options docker's
## switch row is dressed by the same class.
func test_the_tool_options_docker_dresses_its_switch_with_the_same_class() -> void:
    _docker_host = Node.new()
    var docker := ToolOptionsDocker.new()
    _docker_host.add_child(docker)
    docker.target_tool_machine = _machine
    _machine.set_active_tool(&"brush")
    docker.sync_from_tool()
    var erase := docker.options.control(&"eraser_toggled") as Button
    assert_not_null(erase, "The docker has an Erase row")
    assert_not_null(SaOnOffSwitch.of(erase), "dressed by SaOnOffSwitch")
    assert_eq(erase.text, SaOnOffSwitch.word(erase.button_pressed), "and saying its state")
