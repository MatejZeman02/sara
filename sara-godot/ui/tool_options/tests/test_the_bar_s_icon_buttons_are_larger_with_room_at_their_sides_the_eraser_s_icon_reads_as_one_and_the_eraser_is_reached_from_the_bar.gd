## The bar's icon buttons are larger with room at their sides,
## the eraser's icon reads as one, and the Eraser is reached from the bar.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## On a tablet an erase toggle 24 by 22 logical pixels with a 16 pixel icon is
## barely hit by a pen tip, so the erase toggle after Keep Blend Mode, the
## mirrors and the rotation's reset all take
## `SaBarIconButton`'s size. The toggle is pressed here through a touch, which
## Godot hands on as the left press it emulates, as the tablet does, and the
## Eraser tool is picked by a touch on its toolbox button, the toolbox a fresh
## layout keeps open at the tablet's size.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

## A surface builds an easel, which needs a RenderingDevice, and a touch reaches
## a button only through a window that takes input.
const REQUIRES_GPU := true

## Where the bar stands in the window, clear of the window's corner.
const BAR_AT := Vector2(40, 40)

## The tablet, 2944 by 1840, at the scale it starts at and at a second, smaller one.
const TABLET := Vector2i(2944, 1840)
const TABLET_SCALES := [2.0, 1.7]

## The row a docker starts under, `MainDockers.below_bar`.
const TOP := 79

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _module: SaModule = null
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _module = StampModuleScript.new()
    _module.register(_registries.context.for_module(_module.get_id()))
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _machine.set_active_tool(&"brush")
    _host = Node.new()
    _host.name = "U366Host"
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.position = BAR_AT


func after_each() -> void:
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
        _bar = null
    _module.unregister(_registries.context)
    _registries.context.for_module(_module.get_id()).remove_all_registrations()
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    _registries = null


func _erase_toggle() -> Button:
    return _bar.options.control(&"eraser_toggled") as Button


## Asserts *button* has the bar's one icon size, under *what*.
func _assert_bar_size(button: Button, what: String) -> void:
    assert_not_null(button, "The bar has %s" % what)
    if button == null:
        return
    var asked := button.custom_minimum_size
    assert_eq(asked.x, float(SaUI.px(SaBarIconButton.WIDTH)), "%s is the bar's icon width" % what)
    assert_true(asked.x >= float(SaUI.px(44)), "%s is at least 44 logical pixels wide" % what)
    assert_eq(asked.y, float(SaUI.px(SaBarIconButton.HEIGHT)), "%s asks the row's height" % what)
    assert_eq(button.get_theme_constant("icon_max_width"), SaUI.px(SaBarIconButton.ICON), "%s draws the larger icon" % what)
    assert_true(button.expand_icon, "%s fits its icon to the room the box leaves" % what)
    assert_eq(button.icon_alignment, HORIZONTAL_ALIGNMENT_CENTER, "%s keeps room at both sides" % what)


func test_every_icon_button_on_the_bar_takes_one_size() -> void:
    _assert_bar_size(_erase_toggle(), "the erase toggle")
    assert_eq(_erase_toggle().icon, SaUI.get_icon("eraser"), "and the toggle draws the eraser's icon")
    _assert_bar_size(_bar.switches.mirror_h_btn, "the left to right mirror")
    _assert_bar_size(_bar.switches.mirror_v_btn, "the top to bottom mirror")
    var rotation := SaTopBarRotation.new(SaView.new())
    rotation.attach(_host)
    _assert_bar_size(rotation.reset_button, "the rotation's reset")
    var keep := _bar.keep_blend_chk
    assert_eq(
        keep.custom_minimum_size.y,
        float(SaUI.px(SaBarIconButton.HEIGHT)),
        "Keep Blend Mode beside them asks the same height, so the row stands them level"
    )


func test_the_icons_stand_as_tall_as_keep_blend_mode_once_laid_out() -> void:
    await _laid_out()
    var keep := _bar.keep_blend_chk.get_global_rect()
    for button: Button in [_erase_toggle(), _bar.switches.mirror_h_btn, _bar.switches.mirror_v_btn]:
        var rect := button.get_global_rect()
        assert_true(rect.size.y >= keep.size.y, "%s is %s tall, as tall as Keep Blend Mode at least" % [button.name, rect.size.y])
        assert_eq(rect.size.y, button.get_parent_control().size.y, "%s is as tall as its row" % button.name)
        assert_true(rect.size.x >= float(SaUI.px(44)), "%s is %s wide, at least 44 logical" % [button.name, rect.size.x])


func test_a_touch_on_the_erase_toggle_makes_the_brush_erase() -> void:
    await _laid_out()
    var toggle := _erase_toggle()
    var brush := _machine.active_tool
    assert_false(brush.eraser_toggled, "The brush starts painting")

    _touch(toggle.get_global_rect().get_center())
    assert_true(toggle.button_pressed, "A touch on the toggle presses it")
    assert_true(brush.eraser_toggled, "and the brush is erasing")
    assert_true(brush._is_erasing(), "so its next stroke erases")

    _touch(toggle.get_global_rect().get_center())
    assert_false(toggle.button_pressed, "A second touch lets it go")
    assert_false(brush._is_erasing(), "and the brush paints again")


func test_a_fresh_layout_at_the_tablets_size_keeps_the_toolbox_open() -> void:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS), OK, "the shipped default reads")
    var order: Array = cfg.get_value(DockerLayoutStore.META_SECTION, SaDockerLayoutRefit.CLOSE_ORDER, [])
    var written_for: Vector2i = cfg.get_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_WRITTEN_FOR, Vector2i())
    assert_true(bool(cfg.get_value("ToolBoxDocker", "visible", false)), "The shipped layout opens the toolbox")
    assert_false(order.has("ToolBoxDocker"), "and never closes it for room")
    var dockers: Dictionary = {}
    for section in cfg.get_sections():
        if String(section).begins_with("_") or not bool(cfg.get_value(section, "visible", false)):
            continue
        var rect := Rect2i(cfg.get_value(section, "position"), cfg.get_value(section, "size"))
        var floor_size: Vector2i = cfg.get_value(section, SaDockerLayoutRefit.FLOOR_SIZE, Vector2i.ONE)
        dockers[section] = {"rect": rect, "min": floor_size.max(Vector2i.ONE)}
    for scale: float in TABLET_SCALES:
        for screen: Vector2i in [TABLET, Vector2i(TABLET.y, TABLET.x)]:
            var host := Vector2i((Vector2(screen) / scale).floor()) - Vector2i(0, SaStatusLine.rows_taken())
            var placed := SaDockerLayoutFit.new(host, TOP, written_for, order).place(dockers)
            assert_true(placed.has("ToolBoxDocker"), "The toolbox stays open on a host of %s, %s at %s" % [host, screen, scale])


func test_a_touch_on_the_toolboxs_eraser_picks_the_eraser_tool() -> void:
    var toolbox := ToolBoxDockerScript.new() as ToolBoxDocker
    toolbox.name = "ToolBoxDocker"
    toolbox.target_tool_machine = _machine
    _host.add_child(toolbox)
    toolbox.rebuild_from_registry(_registries.tools)
    var button := toolbox.button_for_tool("eraser")
    assert_not_null(button, "The toolbox has a button for the Eraser")
    if button == null:
        return
    assert_eq(button.icon, SaUI.get_icon("eraser"), "and it draws the eraser's icon")
    toolbox.show()
    await _frames(3)
    # A finger on the button, as on the tablet: the toolbox is a window of its
    # own embedded in the root, so the point is its place plus the button's.
    toolbox.position = Vector2i(400, 200)
    await _frames(2)
    _touch(Vector2(toolbox.position) + button.get_global_rect().get_center())
    assert_eq(_machine.active_tool_name, &"eraser", "A touch on its button picks the Eraser tool")


## The new icon is a slanted block with a band across it, and no longer the
## marker it was.
func test_the_eraser_icon_is_a_slanted_block_with_a_band() -> void:
    var file := FileAccess.open("res://assets/icons/eraser.svg", FileAccess.READ)
    assert_not_null(file, "eraser.svg ships")
    if file == null:
        return
    var text := file.get_as_text()
    assert_true(text.contains('viewBox="0 0 16 16"'), "drawn on the icon set's grid")
    assert_true(text.contains("rotate(-45"), "a block slanted as Krita's is")
    assert_eq(text.count("<rect"), 2, "its outline and the band across it")
    assert_true(text.contains('stroke-width="1"'), "in the set's line weight")


func _laid_out() -> void:
    await _frames(3)


func _frames(count: int) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    for i in count:
        await tree.process_frame


## A finger down and up at *at*, a point in the root's canvas, through
## `Input.parse_input_event` as the Android port delivers one, so Godot
## emulates the left press a button answers.
func _touch(at: Vector2) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var on_screen := root.get_final_transform() * at
    for pressed: bool in [true, false]:
        var event := InputEventScreenTouch.new()
        event.index = 0
        event.position = on_screen
        event.pressed = pressed
        Input.parse_input_event(event)
        Input.flush_buffered_events()
