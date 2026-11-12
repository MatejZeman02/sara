## The top bar overflows into a list rather than growing a
## second row.
##
## A tall second bar and no scrolling on a tablet are why the overflow exists.
## The sentinel separator is still there but optional, and the default is the
## overflow.
##
## The rows are asked for the split at three widths, with the sentinel's switch
## on and off: which controls stay on each row, which go into the overflow, in
## what order, and whether the second row shows. The widths are worked out from
## the bar the way `test_top_bar_rows.gd` works its out, because a detached bar
## is measured at Godot's font and not Sara's, and the rule is the same at both.
##
## Built detached the way that suite builds its bar, so the list opens in place
## rather than in a window's root, which `scenarios/the-second-bar-overflows-rather-than-growing-a-row.json`
## photographs in the running app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, which need a machine, a
## surface and therefore a device.
const REQUIRES_GPU := true

## Wide enough that each row holds everything, at any theme scale.
const ROOMY := 4000.0

## How far under a row's need the middle width sits.
const SHORT := 100.0

static var scratch_profile: String = SaDataRoot.path("test_r1_overflow.cfg")

var _saved_path: String = ""
var _saved_row: bool = false
var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _saved_row = SaSettings.second_row
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    # One row, and the sentinel after the brush's own controls, where an older
    # stored profile keeps it. A fresh profile has two rows and the sentinel
    # after the menus, and its first row holds no control to split.
    SaSettings.second_row = false
    var order := SaSettings.get_layout_order("TopMenuBar")
    order.erase(SaSettings.ROW_SENTINEL)
    order.insert(order.find("Rotation"), SaSettings.ROW_SENTINEL)
    SaSettings.set_layout_order("TopMenuBar", order)


func after_each() -> void:
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## A bar with its tool options, the way `test_top_bar_rows.gd` builds one.
func _bar() -> TopMenuBar:
    if _machine == null:
        _surface = Fixtures.make_surface()
        _machine = Fixtures.make_bound_machine(_surface)
    var bar := TopMenuBar.new()
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    bar.add_tool_options(options)
    bar._ready()
    # A detached bar keeps the width written to it only with its anchors
    # pinned together, which the warning about opposite anchors is the reason for.
    bar.set_anchor(SIDE_RIGHT, 0.0)
    return bar


func _lay_out(bar: TopMenuBar, width: float) -> void:
    bar.size.x = width
    bar.apply_layout_settings()


## The names of the shown controls in *container*, in order, leaving out the
## breaks drawn between the groups, which are not controls.
func _names(container: Container) -> Array[String]:
    var out: Array[String] = []
    for child in container.get_children():
        var control := child as Control
        if control != null and control.visible and not String(control.name).begins_with(SaTopBarRows.BREAK_NAME):
            out.append(String(control.name))
    return out


## Each row gives up a run from the start of its leave order, as the roomy bar
## read it, and keeps the rest in the order it held them. The list holds what
## left the first row and then what left the second, each in the order the bar
## showed them, so it reads the way the bar did whatever order they left in.
##
## The order is not a cut from each row's end, which would send Size and Opacity
## into the list at 1280 while Keep blend and the symmetry toggles stayed.
func _assert_the_order(
    bar: TopMenuBar, whole_1: Array[String], whole_2: Array[String], leave_1: Array[String], leave_2: Array[String], tag: String
) -> void:
    var row_1 := _names(bar.rows.row_container(1))
    var row_2 := _names(bar.rows.row_container(2))
    assert_eq(row_1, _kept(whole_1, row_1), "%s: the first row keeps the order it had" % tag)
    assert_eq(row_2, _kept(whole_2, row_2), "%s: and so does the second" % tag)
    var left_1 := _kept(whole_1, _names(bar.rows.overflow.box))
    var left_2 := _kept(whole_2, _names(bar.rows.overflow.box))
    assert_eq(left_1.size() + row_1.size(), whole_1.size(), "%s: what left the first row is in the list" % tag)
    assert_eq(left_2.size() + row_2.size(), whole_2.size(), "%s: and what left the second" % tag)
    var first_1 := _sorted(leave_1.slice(0, left_1.size()))
    var first_2 := _sorted(leave_2.slice(0, left_2.size()))
    assert_eq(_sorted(left_1), first_1, "%s: the first row gave up the start of its leave order" % tag)
    assert_eq(_sorted(left_2), first_2, "%s: and so did the second" % tag)
    var list := left_1.duplicate()
    list.append_array(left_2)
    var held := _names(bar.rows.overflow.box)
    assert_eq(held, list, "%s: the list is what left the first row and then the second, in bar order" % tag)


## The names of *whole* that are also in *names*, in the order *whole* holds them.
func _kept(whole: Array[String], names: Array[String]) -> Array[String]:
    var out: Array[String] = []
    for name in whole:
        if names.has(name):
            out.append(name)
    return out


func _sorted(names: Array) -> Array:
    var out := names.duplicate()
    out.sort()
    return out


## The names of what *row* holds, in the order a short row gives them up.
func _leave_names(bar: TopMenuBar, row: int) -> Array[String]:
    var out: Array[String] = []
    for node in bar.rows.leave_order(row):
        out.append(String(node.name))
    return out


## The three widths for one state of the switch: roomy, a hundred short of what
## the rows need, and so narrow the first row holds almost nothing.
##
## What a row needs is read with its sliders at their minimum, because at the
## roomy width they have grown into the spare room, and a need read off them
## would put the middle width above the point where anything is cut.
func _widths(bar: TopMenuBar) -> Array[float]:
    _lay_out(bar, ROOMY)
    var pinned_1 := ROOMY - bar.rows.row_budget(1, ROOMY)
    var pinned_2 := ROOMY - bar.rows.row_budget(2, ROOMY)
    var need := maxf(pinned_1 + _least(bar, 1), pinned_2 + _least(bar, 2))
    return [ROOMY, need - SHORT, pinned_1 + 120.0]


## What *row* spends with every slider on it at the minimum width.
func _least(bar: TopMenuBar, row: int) -> float:
    var spent := bar.rows.row_spent(row)
    var base := float(DockerUtils.px(ToolOptionsBar.SLIDER_MIN_WIDTH))
    for slider: FactorSlider in bar.rows._options.sliders():
        if slider.visible and slider.get_parent() == bar.rows.row_container(row):
            spent -= slider.custom_minimum_size.x - base
    return spent


func _assert_the_split(two_rows: bool) -> void:
    SaSettings.second_row = two_rows
    var bar := _bar()
    var widths := _widths(bar)
    var whole_1 := _names(bar.rows.row_container(1))
    var whole_2 := _names(bar.rows.row_container(2))
    var leave_1 := _leave_names(bar, 1)
    var leave_2 := _leave_names(bar, 2)
    var label := "two rows" if two_rows else "one row"
    assert_true(whole_1.size() > 4, "%s: the bar holds controls to split: %s" % [label, whole_1])
    assert_eq(whole_2.is_empty(), not two_rows, "%s: and the second row holds some only when it shows" % label)

    _lay_out(bar, widths[0])
    var roomy_tag := "%s at %d" % [label, int(widths[0])]
    assert_eq(bar.rows.second_row.visible, two_rows, "%s: the second row shows only when asked for" % roomy_tag)
    assert_eq(_names(bar.rows.overflow.box), [] as Array[String], "%s at %d: nothing overflows" % [label, int(widths[0])])
    assert_false(bar.rows.overflow.visible, "and the button is hidden, since the list is empty")

    var held_before := 0
    for at: int in [1, 2]:
        var width: float = widths[at]
        _lay_out(bar, width)
        var held := _names(bar.rows.overflow.box)
        var tag := "%s at %d" % [label, int(width)]
        assert_eq(bar.rows.second_row.visible, two_rows, "%s: the second row shows only when the switch asks for it" % tag)
        assert_almost_eq(bar.rows._second_row_forced_by, 0.0, 0.01, "%s: and nothing forces it" % tag)
        assert_true(held.size() > held_before, "%s: more goes into the overflow than at the wider width: %s" % [tag, held])
        assert_true(bar.rows.overflow.visible, "%s: and the button shows" % tag)
        _assert_the_order(bar, whole_1, whole_2, leave_1, leave_2, tag)
        for row: int in [1, 2] if two_rows else [1]:
            assert_true(
                bar.rows.row_spent(row) <= bar.rows.row_budget(row) + 0.5,
                "%s: row %d fits: %d of %d" % [tag, row, int(bar.rows.row_spent(row)), int(bar.rows.row_budget(row))]
            )
        held_before = held.size()

    _lay_out(bar, widths[0])
    assert_eq(_names(bar.rows.overflow.box), [] as Array[String], "%s: widened again, every control comes back" % label)
    assert_eq(_names(bar.rows.row_container(1)), whole_1, "to the first row in the order it left")
    assert_eq(_names(bar.rows.row_container(2)), whole_2, "and to the second")
    bar.free()


## The sentinel's switch off, which an older profile has:
## one row, and its tail in the overflow.
func test_one_row_overflows_at_three_widths_and_never_grows_a_second() -> void:
    assert_false(SaSettings.second_row, "The suite's profile has one row")
    assert_true(SaTopBarOverflow.enabled(), "and the overflow on")
    _assert_the_split(false)


## The switch on: two rows, each cut from its own end, and the one list holding
## the first row's tail and then the second's.
func test_two_rows_overflow_at_three_widths() -> void:
    _assert_the_split(true)


## The note's "the separator will still be there": what follows the sentinel is
## on the second row with the switch on, and on the first, or in the list, with
## it off.
func test_the_sentinel_keeps_working() -> void:
    var order := SaSettings.get_layout_order("TopMenuBar")
    order.erase(SaSettings.ROW_SENTINEL)
    order.insert(order.find("radius"), SaSettings.ROW_SENTINEL)
    SaSettings.set_layout_order("TopMenuBar", order)
    var bar := _bar()
    var size_slider := bar.rows._options.control_for(&"radius")
    _lay_out(bar, ROOMY)
    assert_eq(size_slider.get_parent(), bar.rows._options, "One row: the slider after the sentinel is on the first")
    SaSettings.second_row = true
    assert_eq(size_slider.get_parent(), bar.rows.second_options_row, "The switch on: it moves to the second")
    bar.free()


## The list is a control in the window and not a window of its own, and the
## button opens and closes it.
func test_the_list_is_a_control_the_button_opens_and_closes() -> void:
    var bar := _bar()
    var widths := _widths(bar)
    _lay_out(bar, widths[2])
    var overflow := bar.rows.overflow
    var list: Node = overflow.list
    assert_false(list is Window, "The list is not a Window")
    assert_true(list is Control, "but a Control")
    assert_false(overflow.list.visible, "closed until the button is pressed")
    overflow.pressed.emit()
    assert_true(overflow.list.visible, "A press on the button opens it")
    assert_true(overflow.report()["open"], "and the report says so")
    overflow.pressed.emit()
    assert_false(overflow.list.visible, "and a second press on the button closes it")
    bar.free()


## In a window that embeds its dockers, or in a docker, the list opens in an
## embedded frame of its own, since a docker is drawn over every control of the window and takes
## every press over it. The list itself stays a Control, the frame is embedded
## rather than an operating system window, and a close hides both. Embedded on
## purpose, as `test_choice_popup.gd` does it, so no real window is mapped.
func test_over_embedded_dockers_the_list_opens_in_an_embedded_frame() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "R1OverflowFrameHost"
    EventBus.add_child(host)
    # A window of the suite's own, embedded in the root, which is a docker's
    # case. The root itself is busy running the suite and refuses a child.
    var main := Window.new()
    main.size = Vector2i(400, 300)
    host.add_child(main)
    var anchor := Control.new()
    anchor.size = Vector2(24.0, 22.0)
    main.add_child(anchor)
    var panel := SaFloatingPanel.new()
    panel.add_child(Label.new())
    main.add_child(panel)

    panel.open_under(anchor)
    assert_true(panel.in_frame(), "The list is held in a frame")
    var frame := panel.get_parent() as Window
    assert_not_null(frame, "which is a window")
    assert_eq(frame.get_parent(), main, "a child of the window the list opened in, embedded rather than a window of its own")
    assert_true(frame.visible and panel.visible, "and both show")
    assert_true(frame.always_on_top, "above the dockers")
    assert_false((panel as Node) is Window, "while the list itself stays a Control")
    assert_eq(panel.window_rect().size, Vector2(frame.size), "The frame is the list's size")

    panel.close()
    assert_false(panel.visible, "A close hides the list")
    assert_false(frame.visible, "and the frame with it")
    host.free()
    tree.root.gui_embed_subwindows = was_embedding


## The switch off is the bar as it was: nothing goes into the list, and one row
## that does not fit brings the second row back.
func test_the_switch_off_scrolls_instead() -> void:
    SaSettings.set_docker_option("TopMenuBar", TopMenuBar.OVERFLOW_OPTION, false)
    assert_false(SaTopBarOverflow.enabled(), "The switch reads off")
    var bar := _bar()
    var widths := _widths(bar)
    _lay_out(bar, widths[1])
    assert_eq(_names(bar.rows.overflow.box), [] as Array[String], "Nothing goes into the list")
    assert_false(bar.rows.overflow.visible, "and the button stays hidden")
    assert_true(bar.rows.second_row.visible, "and one row that does not fit brings the second back, as before")
    bar.free()


## A control the list holds keeps its owner and its signals, the way a control
## that changes rows does.
func test_a_control_in_the_list_keeps_its_signal() -> void:
    var bar := _bar()
    var widths := _widths(bar)
    _lay_out(bar, widths[2])
    var options: ToolOptionsBar = bar.rows._options
    var sliders_held := 0
    for slider: FactorSlider in options.sliders():
        if slider.get_parent() == bar.rows.overflow.box:
            sliders_held += 1
            var connected := slider.value_changed.is_connected(options.options._on_slider_changed)
            assert_true(connected, "%s keeps its signal" % slider.name)
    assert_true(sliders_held > 0, "A narrow bar puts a slider in the list")
    bar.free()


## The capture reads the overflow off the first row's report.
func test_the_first_rows_report_carries_the_overflow() -> void:
    var bar := _bar()
    var widths := _widths(bar)
    _lay_out(bar, widths[2])
    var report: Dictionary = bar.rows.row_report(1)["overflow"]
    assert_true(report["shown"], "The report says the button shows")
    assert_false(report["is_window"], "and that the list is not a window")
    assert_eq(report["held"], _names(bar.rows.overflow.box), "and names what it holds")
    bar.free()
