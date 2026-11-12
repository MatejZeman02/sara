## Changing a setting on a switched-off page of the brush editor switches the
## page on.
##
## Ticking Fuzzy per dab on the Rotation page of Chisel Marker, whose Rotation
## is off, would leave the tip not turning with no hint why. An edit on a
## switched-off page switches the page on, `SaBrushEditorPages._switch_on_for`.
##
## **The page column is hosted in the tree, the window is not.** A `Window`
## added to the tree in a headless run hangs, the reason the other editor suites give, so
## the window is built and bound detached and its page column is moved under a
## control under the `EventBus` autoload, because the root is busy while the
## runner sets it up. The window's wiring stays as it was, because the pages and
## the list hear each other through the window object, and the root is what a
## real press is pushed into.
##
## **No undo case.** The brush editor keeps no undo.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The window builds curve controls and a scratchpad with a canvas in it.
const REQUIRES_GPU := true

const ROTATION := "Rotation"
const FUZZY := "fuzzy_per_dab"
const CHISEL := "Chisel Marker"

static var scratch_dir: String = SaDataRoot.path("test_switch_on")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Control = null
var _window: SaBrushEditorWindow = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)


## The host is freed now and not queued: the runner never yields a frame, so a
## queued host stayed under `EventBus` across the whole run and took a click
## meant for a later suite's control (the loupe's suite is one that did).
func after_each() -> void:
    if _host != null:
        _host.free()
    _host = null
    if _window != null:
        _window.free()
    _window = null
    Fixtures.teardown(_surface, _machine)
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


## The brush tool's settings made Chisel Marker as it ships, whose Rotation is
## off, and the editor opened on its Rotation page with the page column in the
## tree.
func _open_on_rotation() -> int:
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
    var at := _window.pages.index_of(ROTATION)
    _window.show_page(at)
    _host = Control.new()
    _host.size = Vector2(900, 1400)
    var column := _window.page_scroll
    column.get_parent().remove_child(column)
    _host.add_child(column)
    column.position = Vector2.ZERO
    column.size = _host.size
    EventBus.add_child(_host)
    return at


func _chisel(script: Script) -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == CHISEL:
            return SaShippedPresets.build(script, entry) as SaStampBrushSettings
    return null


## Lays the hosted column out now. A suite cannot await a frame, the runner
## calls each test and goes on, so the sort every container queues for the end
## of the frame is asked for here, outermost first, twice, because a scroll
## moved by the first pass sorts its child again.
func _settle() -> void:
    for _pass in 2:
        _sort(_host)


static func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)


func _rotation() -> SaCurveOption:
    return (_machine.get_tool("brush").get("settings") as SaStampBrushSettings).rotation_option


func _control() -> SaCurveOptionControl:
    return _window.pages.curve_control as SaCurveOptionControl


func _ticked(index: int) -> bool:
    return bool((_window.page_list.row_report()[index] as Dictionary)["on"])


## A motion over *at* and then *events*, pushed into the root, so a control
## that presses only while hovered is hovered first.
func _push(at: Vector2, events: Array) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var over := InputEventMouseMotion.new()
    over.position = at
    over.global_position = at
    root.push_input(over)
    for event: InputEvent in events:
        root.push_input(event)


func _button(at: Vector2, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.position = at
    event.global_position = at
    return event


func _drag(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    event.position = at
    event.global_position = at
    return event


## The turn of each of *count* dabs of one stroke under *settings*, through the
## dynamics a stroke is laid with.
func _turns(settings: SaStampBrushSettings, count: int) -> Array[float]:
    var dynamics := SaDynamics.new(settings)
    dynamics.begin_stroke()
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 8787)
    info.hovering = false
    info.pressure = 1.0
    var out: Array[float] = []
    for i in count:
        info.position = Vector2(4.0 * i, 0.0)
        info.next_dab()
        out.append(dynamics.evaluate(info, 40.0, PI / 4.0).rotation)
    return out


static func _spread(values: Array[float]) -> float:
    return values.max() - values.min()


## "A suite opens the brush editor on a preset whose Rotation is off, ticks
## Fuzzy per dab with a real mouse click, and reads Rotation on, the page list's
## tick on, and a stroke whose dabs turn."
func test_ticking_fuzzy_per_dab_with_a_click_switches_rotation_on() -> void:
    var at := _open_on_rotation()
    assert_true(at >= 0, "The brush has a Rotation page")
    assert_false(_rotation().enabled, "Chisel Marker ships with Rotation off")
    assert_false(_ticked(at), "and the list's dot is off")
    var settings := _machine.get_tool("brush").get("settings") as SaStampBrushSettings
    var still := _turns(settings, 8)
    assert_true(_spread(still) < 1e-6, "Off, every dab stands at the tip's angle: %s" % [still])
    var control := _control()
    assert_not_null(control, "The Rotation page draws its curve control")
    _settle()
    control.select_sensor(FUZZY)
    _settle()
    var box := control.find_child("Check_" + FUZZY, true, false) as CheckBox
    assert_not_null(box, "The sensor list has a Fuzzy per dab box")
    assert_false(box.button_pressed, "and it starts unticked")
    var centre := box.get_global_rect().get_center()
    _push(centre, [_button(centre, true), _button(centre, false)])
    _settle()
    assert_true(box.button_pressed, "The click at %s ticked the box" % centre)
    assert_not_null(_rotation().sensor_for(SaSensor.Id.FUZZY_PER_DAB), "and the option reads the sensor")
    assert_true(_rotation().sensor_for(SaSensor.Id.FUZZY_PER_DAB).active, "active")
    assert_true(_rotation().enabled, "The edit switched Rotation on")
    assert_true(_ticked(at), "the page list's dot shows it")
    assert_true(_window.pages.page_switch.button_pressed, "and so does the switch at the top of the page")
    var turned := _turns(settings, 8)
    assert_true(_spread(turned) > 0.1, "A stroke's dabs now turn one from the next: %s" % [turned])


## "A suite drags the strength slider of a switched-off page and reads the page
## on."
func test_dragging_the_strength_of_a_switched_off_page_switches_it_on() -> void:
    var at := _open_on_rotation()
    _settle()
    var slider := _control().find_child("Strength", true, false) as FactorSlider
    assert_not_null(slider, "The page has a Strength slider")
    var rect := slider.get_global_rect()
    var from := Vector2(rect.position.x + rect.size.x * 0.8, rect.get_center().y)
    var to := Vector2(rect.position.x + rect.size.x * 0.4, rect.get_center().y)
    var was := _rotation().strength
    _push(from, [_button(from, true), _drag(to), _button(to, false)])
    _settle()
    assert_true(absf(_rotation().strength - was) > 1e-3, "The drag moved the strength, %f from %f" % [_rotation().strength, was])
    assert_true(_rotation().enabled, "and switched Rotation on")
    assert_true(_ticked(at), "with the list's dot")


## "and a suite loads a preset with a page off and reads it still off": a load,
## a sync and the page built again are no painter's edit.
func test_loading_a_preset_with_a_page_off_leaves_it_off() -> void:
    var at := _open_on_rotation()
    _settle()
    var store := _window.preset_bar.session.preset_store
    var settings := _machine.get_tool("brush").get("settings") as SaStampBrushSettings
    var stored := store.save_preset("Rotation off", settings)
    _rotation().enabled = true
    _window.sync_ticks()
    assert_true(_ticked(at), "Switched on by hand before the load")
    assert_true(store.apply_preset(stored, settings), "The preset applies")
    _window._on_preset_loaded(stored)
    _settle()
    assert_false(_rotation().enabled, "The loaded preset's Rotation is off")
    assert_false(_ticked(at), "and the list says so")
    assert_false(_window.pages.page_switch.button_pressed, "and so does the page's switch")


## "or through a plain row the page declares for that option": the Masking page's
## switch is a row, `masking_enabled`, and its Mask Size is a plain row beside
## it.
func test_a_plain_row_on_a_page_whose_switch_is_a_row_switches_it_on() -> void:
    _open_on_rotation()
    var settings := _machine.get_tool("brush").get("settings") as SaStampBrushSettings
    var at := _window.pages.index_of("Masking Brush")
    assert_true(at >= 0, "The brush has a Masking Brush page")
    settings.masking.enabled = false
    _window.show_page(at)
    _window.sync_ticks()
    assert_false(_ticked(at), "The page starts off")
    _settle()
    var slider := _window.pages.page_controls.control(&"masking_size") as FactorSlider
    assert_not_null(slider, "The page draws a Mask Size slider")
    assert_true(slider.is_visible_in_tree(), "where a hand can reach it")
    var rect := slider.get_global_rect()
    var from := Vector2(rect.position.x + rect.size.x * 0.3, rect.get_center().y)
    var to := Vector2(rect.position.x + rect.size.x * 0.6, rect.get_center().y)
    var was := settings.masking.size
    _push(from, [_button(from, true), _drag(to), _button(to, false)])
    var now := settings.masking.size
    assert_true(absf(now - was) > 1e-4, "The drag moved the mask's size, %f from %f" % [now, was])
    assert_true(settings.masking.enabled, "and switched the Masking Brush on")
    assert_true(_ticked(at), "with the list's dot")
    assert_true(_window.pages.page_switch.button_pressed, "and the page's switch")
    _window.pages.page_switch.set_pressed(false)
    assert_false(settings.masking.enabled, "The page's own switch turns it off again and nothing turns it back")


## Switching the page off by its own switch stays off: the switch is not an
## edit of what it switches.
func test_the_switch_turned_off_stays_off() -> void:
    var at := _open_on_rotation()
    _window.set_page_enabled(at, true)
    _window.pages.page_switch.set_pressed(false)
    assert_false(_rotation().enabled, "The switch turned Rotation off")
    assert_false(_ticked(at), "and the list follows")


## An option with its own switch inside a page, on the page several curve
## options share, is switched on by an edit of its own widget and no other.
func test_an_option_with_its_own_switch_is_switched_on_by_its_own_edit() -> void:
    _open_on_rotation()
    var pages := _window.pages
    var shared := -1
    for i in pages.count():
        if pages.curve_option_at(i) != null and not pages.has_switch(i):
            shared = i
    assert_true(shared >= 0, "The brush has a page several curve options share")
    _window.show_page(shared)
    assert_true(pages.curve_controls.size() > 1, "and it carries more than one widget")
    var first := pages.curve_controls[0] as SaCurveOptionControl
    var second := pages.curve_controls[1] as SaCurveOptionControl
    first.option.enabled = false
    second.option.enabled = false
    first.set_strength(first.option.strength * 0.5 + 0.1)
    assert_true(first.option.enabled, "The edited option is switched on")
    assert_false(second.option.enabled, "and its neighbour is left off")
