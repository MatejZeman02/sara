## The canvas right-click menu: the permanent tool's switches and
## choices over the same specs the bar builds from, the commands that asked
## to be there, and the right press that opens it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A machine holding the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _bar = ToolOptionsBar.new()
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)


func after_each() -> void:
    _bar.free()
    Fixtures.teardown(_surface, _machine)
    _registries = null


func _brush() -> ToolState:
    return _machine.get_tool("brush")


## The right-click menu offers the switches and the choices of the shown
## tool, never a slider, and the commands that asked to be there. Built
## detached: the menu is a Window and nothing here needs a tree.
func test_the_context_menu_offers_switches_choices_and_commands() -> void:
    var menu := ToolContextMenu.new()
    menu.bar = _bar
    menu.commands = _registries.commands
    _machine.set_active_tool(&"brush")
    menu.rebuild()

    var keys: Array = []
    for row: Dictionary in menu.option_rows():
        if not keys.has(row["key"]):
            keys.append(row["key"])
    assert_true(keys.has(&"eraser_toggled"), "The erase switch is a row")
    assert_true(keys.has(&"stabilizer_mode"), "and the stabilizer's choices")
    assert_true(keys.has(&"blend_mode"), "and the blend modes from the registry")
    assert_false(keys.has(&"radius"), "and no slider, because a menu has none")
    assert_true(menu.command_rows().has(&"symmetry_horizontal"), "The symmetry commands asked to be here")

    var brush: Variant = _brush()
    var rows := menu.option_rows()
    for id in rows.size():
        if rows[id]["key"] == &"eraser_toggled":
            menu._on_id_pressed(id)
    assert_true(brush.eraser_toggled, "Pressing the switch flips the brush")
    for id in rows.size():
        if rows[id]["key"] == &"stabilizer_mode" and rows[id]["value"] == 2:
            menu._on_id_pressed(id)
    assert_eq(brush.settings.stabilizer_mode, 2, "and a choice writes its id")
    var horizontal := menu.command_rows().find(&"symmetry_horizontal")
    menu._on_id_pressed(ToolContextMenu.ID_COMMAND_BASE + horizontal)
    assert_true(_surface.get_document().symmetry.mirror_horizontal, "and a command row runs the command")

    _machine.set_active_tool(&"eyedropper")
    menu.rebuild()
    keys.clear()
    for row: Dictionary in menu.option_rows():
        if not keys.has(row["key"]):
            keys.append(row["key"])
    # The sample size is a slider, which the menu does not offer, so its Sample
    # choice is the one row left.
    assert_eq(keys, [&"sample_from"], "The eyedropper's menu is its Sample choice")
    menu.free()


## The menu is the app's own row list, so a choice is a heading with
## its rows under it rather than a submenu, and every row is a Control the note
## mode can point at.
func test_the_menu_is_rows_under_headings_and_not_submenus() -> void:
    var menu := ToolContextMenu.new()
    menu.bar = _bar
    menu.commands = _registries.commands
    _machine.set_active_tool(&"brush")
    menu.rebuild()

    assert_true(menu is SaChoicePopup, "The menu is the row list")
    assert_true(menu.section_titles().has("Stabilizer"), "The stabilizer is a heading")
    assert_true(menu.row_ids().has(&"stabilizer_mode_1"), "with its choices as rows under it")
    assert_true(menu.row_ids().has(&"eraser_toggled"), "and a switch is a row named for its key")
    for row_id: StringName in menu.row_ids():
        assert_not_null(menu.label_button(row_id), "Row %s is a control" % row_id)
    menu.free()


## A switch's box marks without closing the list, because a painter turning two
## switches on is one opening of the menu. The label presses the box, so it writes the same flip and leaves the list open as well.
func test_a_switch_marks_from_its_box_and_flips_from_its_label() -> void:
    var menu := ToolContextMenu.new()
    menu.bar = _bar
    menu.commands = _registries.commands
    _machine.set_active_tool(&"brush")
    menu.rebuild()

    assert_not_null(menu.check_box(&"eraser_toggled"), "The erase switch carries a box")
    assert_false(menu.is_checked(&"eraser_toggled"), "which starts where the option does")
    menu.press_check(&"eraser_toggled")
    assert_true(_brush().eraser_toggled, "Ticking it turns erase on")
    menu.press_check(&"eraser_toggled")
    assert_false(_brush().eraser_toggled, "and unticking it turns it off again")

    menu.press_row(&"eraser_toggled")
    assert_true(_brush().eraser_toggled, "The label writes the flip too")
    menu.free()


## The mark says where each option stands, over all of them at once: a menu with
## a stabilizer and a blend mode in it has two rows marked and not one.
func test_every_choice_row_that_is_its_options_answer_is_marked() -> void:
    var menu := ToolContextMenu.new()
    menu.bar = _bar
    menu.commands = _registries.commands
    _machine.set_active_tool(&"brush")
    _brush().settings.stabilizer_mode = 2
    menu.rebuild()

    assert_true(menu.is_marked(&"stabilizer_mode_2"), "The stabilizer's own row is marked")
    assert_false(menu.is_marked(&"stabilizer_mode_0"), "and the rows beside it are not")
    var blend: StringName = StringName("blend_mode_%s" % _bar.read_option(&"blend_mode"))
    assert_true(menu.is_marked(blend), "and the blend mode is marked in the same pass")
    menu.free()


## A command row carries the chord it answers to at its right, which is the hint
## a `PopupMenu` accelerator could only draw from an InputMap the row has no
## other reason to know about.
func test_a_command_row_says_the_chord_it_answers_to() -> void:
    var menu := ToolContextMenu.new()
    menu.bar = _bar
    menu.commands = _registries.commands
    _machine.set_active_tool(&"brush")
    menu.rebuild()

    var hinted := 0
    for row: Dictionary in menu.row_report():
        if String(row["id"]).begins_with("cmd_") and not String(row["hint"]).is_empty():
            hinted += 1
    assert_true(hinted > 0, "At least one command row shows its chord")
    menu.free()


## A right press asks the machine's host for the menu, once, on the press,
## and not while the left button is down.
func test_a_right_press_asks_for_the_menu_and_never_reaches_the_tool() -> void:
    var asked: Array = []
    _machine.context_menu_requested.connect(func(at: Vector2) -> void: asked.append(at))
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_RIGHT
    press.pressed = true
    press.global_position = Vector2(300, 200)
    _machine.handle_input(press)
    assert_eq(asked, [Vector2(300, 200)], "The press asks, with where it landed")
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_RIGHT
    release.pressed = false
    _machine.handle_input(release)
    assert_eq(asked.size(), 1, "and the release does not")
    var mid_stroke := InputEventMouseButton.new()
    mid_stroke.button_index = MOUSE_BUTTON_RIGHT
    mid_stroke.pressed = true
    mid_stroke.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
    _machine.handle_input(mid_stroke)
    assert_eq(asked.size(), 1, "nor a right press with the left button down")
