## Per-docker options: the registry, the toolbox's two, and the arithmetic that
## turns them into a column count.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Three claims: Preferences has vertical and horizontal options, and a 'max
## allowed rows/cols' option, and these are docker specific options, not the
## toggleable ones on the list. The first two are graded here as numbers and by
## `scenarios/toolbox-layout-in-preferences.json` on the running app. The
## third is graded here alone, because "not a row in the list" is a claim about
## what the page does *not* draw and a shot cannot show an absence.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const SCRATCH := "TestDockerOptions"

## What the toolbox's two were set to before this suite touched them. The
## settings autoload outlives a test run, so a suite that writes a profile has
## to put it back or the next one reads what this one left.
var _kept: Dictionary = {}

## The screen a docker is opened on, for the cases that read it as a host,
## and what the run held that the case changes.
var _screen: SubViewport = null
var _saved_override: float = -1.0
var _saved_user: float = 1.0


func before_each() -> void:
    _kept = (SaSettings.layout_docker_options.get(SaToolBoxGrid.CATEGORY, {}) as Dictionary).duplicate()
    SaToolBoxGrid.register_options()


## The config file as well as the dictionary.
##
## `set_docker_option` writes the profile and saves it, so a value this suite
## wrote survives in `profile_docker_option` even after the dictionary is put
## back, and the next `load_settings()` any suite runs brings it into memory
## again. That is not a theory: it left the toolbox vertical and one column wide
## for `test_ui_components`, three suites later, which asserts the shape branch.
func after_each() -> void:
    if _screen != null:
        _screen.free()
        _screen = null
        SaUI.os_scale_override = _saved_override
        SaUI.user_scale = _saved_user
    SaSettings.layout_docker_options[SaToolBoxGrid.CATEGORY] = _kept
    SaSettings.unregister_docker_option(SCRATCH, "shape")
    SaSettings.unregister_docker_option(SCRATCH, "lines")
    for owner: String in [SaToolBoxGrid.CATEGORY, SCRATCH]:
        for key: String in [SaToolBoxGrid.ORIENTATION, SaToolBoxGrid.MAX_LINES, "shape", "lines"]:
            var stored := "%s_%s" % [owner, key]
            if SaSettings.config.has_section_key("profile_docker_option", stored):
                SaSettings.config.erase_section_key("profile_docker_option", stored)
    for key: String in _kept:
        SaSettings.config.set_value("profile_docker_option", "%s_%s" % [SaToolBoxGrid.CATEGORY, key], _kept[key])
    SaSettings.save_settings()


# --- The registry -------------------------------------------------------------


func test_an_option_reads_its_default_until_something_writes_it() -> void:
    SaSettings.register_docker_option(
        SCRATCH, "shape", {"title": "Shape", "kind": SaSettingsLayout.OPTION_CHOICE, "values": ["a", "b"], "default": "b"}
    )

    assert_eq(SaSettings.get_docker_option(SCRATCH, "shape"), "b", "the declared default")
    SaSettings.set_docker_option(SCRATCH, "shape", "a")
    assert_eq(SaSettings.get_docker_option(SCRATCH, "shape"), "a", "and what was written after that")


func test_an_option_nobody_declared_reads_null() -> void:
    # Null rather than a zero or an empty string, because a caller asking for an
    # option nobody registered has a spelling mistake and a plausible-looking
    # answer would hide it.
    assert_null(SaSettings.get_docker_option(SCRATCH, "there_is_no_such_option"), "nothing declared it")


func test_registering_the_same_key_twice_is_refused() -> void:
    var first := SaSettings.register_docker_option(SCRATCH, "lines", {"title": "Lines", "default": 1})

    var second := SaSettings.register_docker_option(SCRATCH, "lines", {"title": "Lines again", "default": 4})

    assert_true(first, "the first registration takes")
    assert_false(second, "and the second is refused, so a docker rebuilt draws one row rather than two")
    assert_eq(SaSettings.get_docker_option(SCRATCH, "lines"), 1, "with the first spec's default")


func test_an_option_is_not_an_element_of_the_list() -> void:
    # The third claim. The two are different registries on purpose: an
    # element row answers whether a part of the docker is drawn, and these
    # answer how the docker lays itself out.
    var order := SaSettings.get_layout_order(SaToolBoxGrid.CATEGORY)

    assert_false(order.has(SaToolBoxGrid.ORIENTATION), "Orientation is no row in the toolbox's element list")
    assert_false(order.has(SaToolBoxGrid.MAX_LINES), "and neither is the line cap")


# --- The toolbox's two --------------------------------------------------------


func test_the_toolbox_ships_following_its_own_shape() -> void:
    # The following-its-own-shape answer is the default, so a painter who never
    # opens Preferences sees the toolbox as it always was.
    SaSettings.layout_docker_options[SaToolBoxGrid.CATEGORY] = {}

    assert_eq(SaToolBoxGrid.orientation(), SaToolBoxGrid.FOLLOW_SHAPE, "Follow the shape")
    assert_eq(SaToolBoxGrid.max_lines(), 1, "and a cap of one, which that branch ignores")


func test_following_the_shape_is_a_row_or_a_column() -> void:
    _set_toolbox(SaToolBoxGrid.FOLLOW_SHAPE, 1)

    # Six buttons 32 wide, in a docker 80 tall. One 40 wide affords no row, one
    # 500 wide affords them all, and one 120, which was once two rows of
    # three, is the column now: the grid is off the drag.
    assert_eq(SaToolBoxGrid.columns_for(6, 40.0, 80.0, 32.0), 1, "a narrow docker is one column")
    assert_eq(SaToolBoxGrid.columns_for(6, 500.0, 80.0, 32.0), 6, "a wide one is a single row")
    assert_eq(SaToolBoxGrid.columns_for(6, 120.0, 80.0, 32.0), 1, "and one between is a column too")


func test_horizontal_wraps_into_at_most_the_rows_asked_for() -> void:
    _set_toolbox(SaToolBoxGrid.HORIZONTAL, 2)

    # The reported case and what the scenario shows: five buttons over two
    # rows is three across, whatever the docker's width says.
    assert_eq(SaToolBoxGrid.columns_for(5, 40.0, 80.0, 32.0), 3, "narrow, and still three across")
    assert_eq(SaToolBoxGrid.columns_for(5, 900.0, 80.0, 32.0), 3, "wide, and still three across")


func test_horizontal_at_one_row_is_one_row() -> void:
    _set_toolbox(SaToolBoxGrid.HORIZONTAL, 1)

    assert_eq(SaToolBoxGrid.columns_for(5, 40.0, 80.0, 32.0), 5, "every button across, however narrow the docker is")


func test_vertical_is_the_columns_asked_for_and_never_more_than_the_buttons() -> void:
    _set_toolbox(SaToolBoxGrid.VERTICAL, 2)
    assert_eq(SaToolBoxGrid.columns_for(5, 900.0, 80.0, 32.0), 2, "two columns, however wide the docker is")

    _set_toolbox(SaToolBoxGrid.VERTICAL, 9)
    assert_eq(SaToolBoxGrid.columns_for(5, 900.0, 80.0, 32.0), 5, "and never more columns than there are buttons")


func test_the_cap_is_at_least_one_whatever_is_stored() -> void:
    # A stored zero would be a division by nothing, and a profile can carry one:
    # the row is a SpinBox now and need not be tomorrow.
    _set_toolbox(SaToolBoxGrid.HORIZONTAL, 0)

    assert_eq(SaToolBoxGrid.max_lines(), 1, "clamped to one")
    assert_eq(SaToolBoxGrid.columns_for(5, 40.0, 80.0, 32.0), 5, "so the layout is a single row rather than an error")


func test_the_shape_word_matches_what_the_grid_did() -> void:
    assert_eq(SaToolBoxGrid.shape_of(1, 6), "column", "one column of six")
    assert_eq(SaToolBoxGrid.shape_of(6, 6), "row", "six across")
    assert_eq(SaToolBoxGrid.shape_of(3, 6), "grid", "and anything between")


# --- A forced orientation shows every tool --------------------------------
#
# A forced orientation once lost tools off the docker's end
# with nothing to scroll and nothing to say so. The arithmetic is graded alone
# first, then a docker opened on a screen of a known size, because "every tool is
# inside the docker" is a claim about drawn rectangles.


func test_lines_that_fit_counts_the_gaps_and_never_answers_less_than_one() -> void:
    assert_eq(SaToolBoxGrid.lines_that_fit(100.0, 40.0, 4.0, 5), 2, "two buttons and the gap between them are 84, three are 128")
    assert_eq(SaToolBoxGrid.lines_that_fit(128.0, 40.0, 4.0, 5), 3, "three fit exactly")
    assert_eq(SaToolBoxGrid.lines_that_fit(10.0, 40.0, 4.0, 5), 1, "a room under one button still draws one")
    assert_eq(SaToolBoxGrid.lines_that_fit(900.0, 40.0, 4.0, 5), 5, "and never more lines than there are buttons")
    assert_eq(SaToolBoxGrid.lines_that_fit(INF, 40.0, 4.0, 5), 5, "no limit is every button")


func test_a_forced_row_that_is_wider_than_the_room_wraps_into_more_rows() -> void:
    _set_toolbox(SaToolBoxGrid.HORIZONTAL, 1)
    var room := Vector2(130.0, INF)
    var gap := Vector2(4.0, 4.0)

    var columns := SaToolBoxGrid.columns_for(5, 60.0, 200.0, 40.0, room, gap)

    assert_eq(columns, 3, "three buttons and their gaps are 128, so the row is cut at three")
    assert_eq(int(ceil(5.0 / float(columns))), 2, "and the other two are a second row")
    assert_eq(SaToolBoxGrid.columns_for(5, 60.0, 200.0, 40.0, Vector2(900.0, INF), gap), 5, "a room that holds them is the row")


func test_a_forced_column_that_is_taller_than_the_room_wraps_into_more_columns() -> void:
    _set_toolbox(SaToolBoxGrid.VERTICAL, 1)
    var gap := Vector2(4.0, 4.0)

    assert_eq(
        SaToolBoxGrid.columns_for(5, 60.0, 200.0, 40.0, Vector2(INF, 100.0), gap),
        3,
        "two rows fit, so five buttons are three columns"
    )
    assert_eq(
        SaToolBoxGrid.columns_for(5, 60.0, 200.0, 40.0, Vector2(INF, 900.0), gap), 1, "a room that holds them is the column"
    )

    _set_toolbox(SaToolBoxGrid.VERTICAL, 2)
    assert_eq(
        SaToolBoxGrid.columns_for(5, 60.0, 200.0, 40.0, Vector2(INF, 900.0), gap),
        2,
        "and the painter's cap is kept where it fits"
    )


func test_a_forced_horizontal_toolbox_holds_every_tool_in_its_docker() -> void:
    _set_toolbox(SaToolBoxGrid.HORIZONTAL, 1)

    var docker := _opened_on(Vector2i(1200, 800))

    var count := int(docker.toolbox_report()["visible_buttons"])
    assert_true(count > 2, "the fixture registry draws a toolbox with several buttons")
    assert_eq(docker.grid_container.columns, count, "one row of every tool")
    _assert_every_tool_inside(docker)
    assert_true(docker.size.x > 60, "so the docker grew along its width from the 60 it opened at: %d" % docker.size.x)


func test_a_forced_vertical_toolbox_holds_every_tool_in_its_docker() -> void:
    _set_toolbox(SaToolBoxGrid.VERTICAL, 1)

    var docker := _opened_on(Vector2i(1200, 800))

    assert_eq(docker.grid_container.columns, 1, "one column of every tool")
    _assert_every_tool_inside(docker)
    assert_true(docker.size.y > 120, "so the docker grew along its height from the 120 it opened at: %d" % docker.size.y)


func test_a_host_too_short_for_the_column_wraps_it_instead_of_cutting_it() -> void:
    _set_toolbox(SaToolBoxGrid.VERTICAL, 1)

    var docker := _opened_on(Vector2i(1200, 190))

    assert_true(docker.grid_container.columns > 1, "the tools wrapped into a second column: %d" % docker.grid_container.columns)
    _assert_every_tool_inside(docker)
    assert_true(
        docker.position.y + docker.size.y <= 190,
        "and the docker is inside its host: %d to %d" % [docker.position.y, docker.position.y + docker.size.y]
    )


func test_a_host_too_narrow_for_the_row_wraps_it_instead_of_cutting_it() -> void:
    _set_toolbox(SaToolBoxGrid.HORIZONTAL, 1)

    var docker := _opened_on(Vector2i(150, 800))

    var count := int(docker.toolbox_report()["visible_buttons"])
    assert_true(
        docker.grid_container.columns < count,
        "the row wrapped into a second row: %d columns of %d" % [docker.grid_container.columns, count]
    )
    _assert_every_tool_inside(docker)
    assert_true(docker.position.x + docker.size.x <= 150, "and the docker is inside its host")


func test_the_floor_follows_the_orientation_both_ways() -> void:
    _set_toolbox(SaToolBoxGrid.HORIZONTAL, 1)
    var docker := _opened_on(Vector2i(1200, 800))
    var row_floor := docker.min_size.x
    assert_true(row_floor > int(docker.logical_min_size.x), "a forced row cannot be dragged under its own width: %d" % row_floor)

    _set_toolbox(SaToolBoxGrid.FOLLOW_SHAPE, 1)
    # Taller than wide, so the shape followed is a column. A rectangle still a
    # row keeps a row's floor, which only the scroll's bar told apart from the
    # forced one until the bar stopped taking room in a docker as narrow.
    docker.size = Vector2i(docker.size.x, 800)
    docker.apply_layout_settings()

    assert_true(docker.min_size.x < row_floor, "and following the shape lets it go back: %d" % docker.min_size.x)


func test_the_docker_grows_once_for_a_layout_and_then_leaves_its_size_alone() -> void:
    _set_toolbox(SaToolBoxGrid.VERTICAL, 1)
    var docker := _opened_on(Vector2i(1200, 800))
    docker.size = Vector2i(docker.size.x, 90)

    docker.apply_layout_settings()

    assert_eq(docker.size.y, 90, "a setting written elsewhere does not undo a docker the painter made shorter")


## A docker 60 by 120 on a screen of *host*, the tools of the fixture registry in
## it, its orientation as the test set it, and laid out.
func _opened_on(host: Vector2i) -> ToolBoxDocker:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0
    _screen = SubViewport.new()
    _screen.size = host
    _screen.gui_embed_subwindows = true
    EventBus.add_child(_screen)
    var docker := ToolBoxDocker.new()
    _screen.add_child(docker)
    # Hidden until shown, and a grid in a hidden window sorts none of its buttons.
    docker.visible = true
    docker.position = Vector2i(0, 0)
    docker.size = Vector2i(60, 120)
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    _lay_out(docker)
    return docker


## Every visible tool button lies inside the docker and inside the scroll that
## shows them, which is the rectangle a painter sees.
func _assert_every_tool_inside(docker: ToolBoxDocker) -> void:
    var scroll := docker.get_node("Control/VBoxContainer/Scroll") as ScrollContainer
    var shown := Rect2(scroll.global_position, scroll.size)
    var frame := Rect2(Vector2.ZERO, Vector2(docker.size))
    var seen := 0
    for child in docker.grid_container.get_children():
        var button := child as Control
        if button == null or not button.visible or button.is_queued_for_deletion():
            continue
        seen += 1
        var rect := button.get_global_rect()
        assert_true(frame.encloses(rect), "%s at %s is inside the docker %s" % [button.name, rect, frame])
        assert_true(shown.encloses(rect), "%s at %s is inside what the scroll shows %s" % [button.name, rect, shown])
    assert_eq(seen, int(docker.toolbox_report()["visible_buttons"]), "and every visible tool was read")


## The sorts a frame would have run, outside in, since a suite is one call and a
## container sorts its children on a frame that never comes.
func _lay_out(node: Node) -> void:
    for _pass in 3:
        _sort_under(node)


func _sort_under(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort_under(child)


# --- The page -----------------------------------------------------------------


func test_the_page_draws_a_row_for_each_option_and_dims_the_cap() -> void:
    _set_toolbox(SaToolBoxGrid.FOLLOW_SHAPE, 1)
    var page := SaLayoutPage.new(SaToolBoxGrid.CATEGORY, SaLayoutPage.OPTIONS)

    var titles: Array[String] = []
    for line in page.below_rows():
        titles.append(String(line.get_meta(SaSettingsRows.TITLE_META, "")))

    assert_true(titles.has("Orientation"), "the orientation row is on the page")
    assert_true(titles.has("Maximum rows or columns"), "and the cap row with it")
    var cap := page.below_control("Maximum rows or columns") as SpinBox
    assert_not_null(cap, "the cap row carries a control")
    # Dimmed and disabled are one state.
    assert_false(cap.editable, "and it is disabled while the docker follows its own shape")
    assert_true((cap.get_parent() as Control).modulate.a < 1.0, "and dimmed, the whole line, so the two say the same thing")
    page.free()


func test_the_cap_comes_alive_once_an_orientation_is_chosen() -> void:
    _set_toolbox(SaToolBoxGrid.HORIZONTAL, 2)
    var page := SaLayoutPage.new(SaToolBoxGrid.CATEGORY, SaLayoutPage.OPTIONS)

    var cap := page.below_control("Maximum rows or columns") as SpinBox

    assert_true(cap.editable, "the cap is live once the orientation is not the shape")
    assert_almost_eq(cap.value, 2.0, 0.001, "and reads what is stored")
    page.free()


func test_the_orientation_row_stores_its_key_rather_than_its_index() -> void:
    # A value added to the middle of the list later would renumber every value
    # after it, and a stored profile would quietly mean something else.
    _set_toolbox(SaToolBoxGrid.FOLLOW_SHAPE, 1)
    var page := SaLayoutPage.new(SaToolBoxGrid.CATEGORY, SaLayoutPage.OPTIONS)

    page.drive_gesture(null, Vector2.ZERO, {"option": SaToolBoxGrid.ORIENTATION, "value": SaToolBoxGrid.VERTICAL})

    assert_eq(
        SaSettings.get_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGrid.ORIENTATION),
        SaToolBoxGrid.VERTICAL,
        "the key is what is stored"
    )
    page.free()


func test_the_capture_door_refuses_a_dimmed_row_rather_than_writing_it() -> void:
    # The failure this door exists to avoid: a step that reports a clean write
    # onto a control a painter could not have touched.
    _set_toolbox(SaToolBoxGrid.FOLLOW_SHAPE, 1)
    var page := SaLayoutPage.new(SaToolBoxGrid.CATEGORY, SaLayoutPage.OPTIONS)

    var said := page.drive_gesture(null, Vector2.ZERO, {"option": SaToolBoxGrid.MAX_LINES, "value": 3})

    assert_true(said.contains("dimmed and disabled"), "the step says why it did nothing: %s" % said)
    assert_eq(SaToolBoxGrid.max_lines(), 1, "and the setting is where it was")
    page.free()


func _set_toolbox(mode: String, lines: int) -> void:
    SaSettings.layout_docker_options[SaToolBoxGrid.CATEGORY] = {
        SaToolBoxGrid.ORIENTATION: mode,
        SaToolBoxGrid.MAX_LINES: lines,
    }
