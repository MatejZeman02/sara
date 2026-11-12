## A sensor ticked in the brush editor reaches the brush the editor shows.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Ticking Fuzzy per dab on Chisel Marker's Rotation page once left the tip
## unturned. The door's dump read `ticked: ["fuzzy_per_dab"]` and
## `active: []`: the box was ticked and the option held nothing. The cause was
## the sensor list's signal, `sensor_toggled(key, on)`, connected to a handler
## declared `(on, key)`. A press emitted a key where a bool was typed, the call
## failed, and the box stayed ticked over an option nobody wrote. Every suite
## before this one called `set_sensor_active` by name, so none went through the
## signal a hand fires.
##
## The editor is opened the way `test_the_brush_editor_opens_with_its_curve_in_sight.gd`
## opens it, inside a `SubViewport` that embeds it, because a `Window` added to
## a headless tree hangs. Each press is a left button event pushed into the
## window, so it reaches the checkbox through the GUI's own hit test. The
## stroke is the tool's own settings run through `SaDynamics`, dab by dab, the
## path `state_brush.gd` reads `dab.rotation` from. That the turn then lands in
## the texels at `tip.angle + dab.rotation` is another suite's.
##
## In `tests/` rather than the editor's own folder, because it builds Chisel
## Marker from the stamp module's shipped recipe, which `ui` never names.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## The window builds curve controls and a pad with a canvas in it.
const REQUIRES_GPU := true

const SCREEN := Vector2i(1920, 1080)
const BAR := 65
const PAGE := "Rotation"
const FUZZY := "fuzzy_per_dab"
const DABS := 24

static var scratch_dir: String = SaDataRoot.path("test_sensor_tick")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Node = null
var _kept_scale: float = 1.0
var _kept_font_scale: float = 1.0
var _kept_theme: Theme = null
var _kept_inset: Callable = Callable()
var _kept_embedding: bool = true
var _kept_page: String = ""
var _kept_settings: Resource = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _kept_scale = SaUI.user_scale
    _kept_font_scale = SaUI.user_font_scale
    _kept_theme = SaUI.shared_theme
    SaUI.user_scale = 1.0
    SaUI.user_font_scale = 1.0
    SaUI.init_global_theme(null)
    _kept_inset = SaDialogWindow.top_inset
    SaDialogWindow.top_inset = func() -> int: return BAR
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _kept_page = SaSettings.brush_editor_page
    SaSettings.brush_editor_page = PAGE
    _host = Node.new()
    _host.name = "EditorHostTest"
    EventBus.add_child(_host)
    var brush := _machine.get_tool("brush")
    _kept_settings = brush.get("settings") as Resource
    brush.set("settings", ShippedPresetsScript.build(StateBrushScript.BrushSettingsScript, _recipe("Chisel Marker")))


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _machine.get_tool("brush").set("settings", _kept_settings)
    SaSettings.brush_editor_page = _kept_page
    SaUI.user_scale = _kept_scale
    SaUI.user_font_scale = _kept_font_scale
    SaUI.shared_theme = _kept_theme
    SaDialogWindow.top_inset = _kept_inset
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    Fixtures.teardown(_surface, _machine)
    if DirAccess.dir_exists_absolute(scratch_dir):
        for file_name: String in DirAccess.get_files_at(scratch_dir):
            DirAccess.remove_absolute(scratch_dir.path_join(file_name))
        DirAccess.remove_absolute(scratch_dir)


# --- The two clauses ------------------------------------------------------


## The first clause: Rotation switched on by its page switch, Fuzzy per dab
## ticked with a click, the box and the option agree, and the dabs turn.
func test_a_ticked_fuzzy_per_dab_reaches_chisel_marker_and_its_dabs_turn() -> void:
    var window := _opened()
    var option := _rotation(window)
    assert_not_null(option, "Chisel Marker carries a rotation option")
    if option == null:
        return
    assert_false(option.active_sensors().any(_is_fuzzy), "Fuzzy per dab is not ticked as Chisel Marker ships")
    _click(window, window.pages.page_switch)
    assert_true(option.enabled, "The page switch, clicked, turned Rotation on")

    _click(window, _box(window))
    var report := (window.pages.curve_control as SaCurveOptionControl).option_report()
    assert_true((report["ticked"] as Array).has(FUZZY), "The box is ticked, %s" % [report["ticked"]])
    assert_true((report["active"] as Array).has(FUZZY), "and the brush's option holds it, %s" % [report["active"]])
    assert_eq(report["ticked"], report["active"], "The list draws what the option holds")
    assert_eq(_names(option), report["active"], "and the option is the brush's own, not a copy")

    var turns := _turns()
    assert_true(turns.size() == DABS, "A stroke of %d dabs was evaluated" % DABS)
    var spread := _spread(turns)
    assert_true(spread > deg_to_rad(20.0), "Its dabs turn, over %.1f degrees" % rad_to_deg(spread))


## The second clause: the same tick on a page whose switch is off. The tick
## still reaches the option and the list agrees with it. Whether the edit
## switches the page on is a separate question, so the dabs are read and reported rather
## than held to a turn: off, they stay at the tip's own angle.
func test_a_tick_on_a_switched_off_page_is_kept_by_the_option() -> void:
    var window := _opened()
    var option := _rotation(window)
    if option == null:
        assert_true(false, "Chisel Marker carries a rotation option")
        return
    if option.enabled:
        _click(window, window.pages.page_switch)
    assert_false(option.enabled, "Rotation is off before the tick")

    _click(window, _box(window))
    var report := (window.pages.curve_control as SaCurveOptionControl).option_report()
    assert_true((report["ticked"] as Array).has(FUZZY), "The box is ticked, %s" % [report["ticked"]])
    assert_true((report["active"] as Array).has(FUZZY), "and the option holds it on an off page, %s" % [report["active"]])
    assert_eq(report["ticked"], report["active"], "The list draws what the option holds")

    var spread := _spread(_turns())
    if option.enabled:
        assert_true(spread > deg_to_rad(20.0), "The tick switched Rotation on, and the dabs turn")
    else:
        assert_almost_eq(spread, 0.0, 1e-6, "Rotation still off, so the dabs keep the tip's angle")


## A sync after the tick draws the option, so the box never shows a tick the
## option does not hold, so the list always draws what the option holds.
func test_the_list_draws_the_option_after_a_sync() -> void:
    var window := _opened()
    var option := _rotation(window)
    if option == null:
        assert_true(false, "Chisel Marker carries a rotation option")
        return
    var control := window.pages.curve_control as SaCurveOptionControl
    _click(window, _box(window))
    var sensor := option.sensor_for(SaSensor.Id.FUZZY_PER_DAB)
    assert_not_null(sensor, "The tick stored the sensor on the option")
    if sensor == null:
        return
    sensor.active = false
    control.sync()
    var report := control.option_report()
    assert_false((report["ticked"] as Array).has(FUZZY), "Unticked on the option, the box follows")
    assert_eq(report["ticked"], report["active"], "and the two agree")


# --- Helpers --------------------------------------------------------------------


func _recipe(preset_name: String) -> Dictionary:
    for entry: Dictionary in ShippedPresetsScript.entries():
        if String(entry["name"]) == preset_name:
            return entry
    assert_true(false, "%s is a shipped recipe" % preset_name)
    return {}


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


## The editor bound to the brush, opened on the Rotation page and laid out.
func _opened() -> SaBrushEditorWindow:
    var window := SaBrushEditorWindow.new()
    var screen := SubViewport.new()
    screen.size = SCREEN
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    screen.add_child(window)
    var specs: Array[SaOptionSpec] = []
    specs.assign(_machine.get_descriptor(&"brush").options)
    window.bind_tool(_machine.get_tool("brush"), specs, _store())
    window.popup_centered()
    _settle(window)
    assert_eq(window.page_list.title_at(window.page_list.selected), PAGE, "The editor opened on Rotation")
    return window


func _rotation(window: SaBrushEditorWindow) -> SaCurveOption:
    var option := window.pages.curve_option_at(window.pages.index_of(PAGE)) as SaCurveOption
    var brush_option := (_machine.get_tool("brush").get("settings") as Resource).get("rotation_option") as SaCurveOption
    assert_true(option == brush_option, "The page edits the brush's own rotation option")
    return option


## Fuzzy per dab's checkbox, scrolled into the list's view.
func _box(window: SaBrushEditorWindow) -> CheckBox:
    var list := window.pages.curve_control.find_child("SensorList", true, false) as SaSensorList
    var box := list.box_for(FUZZY)
    list.ensure_visible(FUZZY)
    list.scroll_vertical = int(box.get_parent_control().position.y)
    _settle(window)
    return box


## A left press and release over the middle of *control*, pushed into the window
## in its own space, which is what the embedder hands an embedded window.
func _click(window: Window, control: Control) -> void:
    assert_not_null(control, "There is a control to click")
    if control == null:
        return
    var at := control.get_global_rect().get_center()
    for pressed: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
        event.position = Vector2(window.position) + at
        event.global_position = event.position
        (window.get_parent() as Viewport).push_input(event)
    _settle(window)


func _settle(window: Window) -> void:
    for _pass in range(2):
        _sort_children(window)
        _ask_again(window)
    var kept := window.size
    window.size = kept + Vector2i.ONE
    window.size = kept
    _sort_children(window)


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()


func _is_fuzzy(sensor: SaSensor) -> bool:
    return sensor.id == SaSensor.Id.FUZZY_PER_DAB


func _names(option: SaCurveOption) -> Array[String]:
    var found: Array[String] = []
    for sensor: SaSensor in option.active_sensors():
        found.append(SaSensor.key_of(sensor.id))
    return found


## Each dab's turn along a straight stroke, read off the brush's own settings
## the way `state_brush.gd` reads them: a press, then one `next_dab` and one
## `evaluate` per dab.
func _turns() -> Array[float]:
    var settings := _machine.get_tool("brush").get("settings") as Resource
    var dynamics := SaDynamics.new(settings)
    dynamics.begin_stroke()
    var info := SaStrokeInfo.new()
    info.begin(Vector2(100.0, 100.0), 4242)
    info.hovering = false
    var turns: Array[float] = []
    for i in DABS:
        info.position = Vector2(100.0 + 4.0 * i, 100.0)
        info.pressure = 1.0
        info.next_dab()
        turns.append(dynamics.evaluate(info, 40.0).rotation)
    return turns


func _spread(turns: Array[float]) -> float:
    if turns.is_empty():
        return 0.0
    return turns.max() - turns.min()
