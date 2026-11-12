## The toolbox flyout is the app's one menu, `SaChoicePopup`, and still a place
## a tool is dragged out of.
##
## The engine's own menu is not used here, for a reason of its own. The flyout
## once had a second column of Buttons beside `SaChoicePopup`'s, and the
## popup's list has the icon cap, the keyboard, the scroll and the scale, so
## this suite is what stops the flyout drifting back out of it: the rows are
## the list's rows, the drag the flyout wrote is
## still on them, and every door the docker and the capture step open is where
## it was.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

var _saved_override: float = -1.0
var _saved_user: float = 1.0


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale


func after_each() -> void:
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


func _toolbox() -> ToolBoxDocker:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = "ToolBoxDocker"
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    return docker


func _open_fills(docker: ToolBoxDocker) -> SaToolFlyout:
    assert_true(docker.open_flyout(&"fill"), "the fills' flyout opens")
    return docker._flyouts[&"fill"]


## The unit's claim. A subclass that declares `_init` takes the base's over, so
## the first version built no panel, no scroll and no column at all and every
## `clear()` was a null: the scroll count is the assertion that catches that,
## because one scroll means the base ran and two would mean it ran twice.
##
## Counted over the whole subtree rather than over the popup's own children,
## because the popup puts a `ChoiceBody` column between the panel and the scroll to
## carry the search field. Where the base hangs its scroll is the base's
## business, and a test of this file that reads it as a direct child breaks
## every time the menu grows a part.
func test_the_flyout_is_the_apps_menu_built_once() -> void:
    var docker := _toolbox()
    var flyout := _open_fills(docker)

    assert_true(flyout is SaChoicePopup, "the flyout is a SaChoicePopup and not a second list of rows")
    assert_eq(_scrolls_under(flyout), 1, "with exactly one scroll under it, so the base's `_init` ran once")
    docker.free()


## Every `ScrollContainer` anywhere under *node*.
func _scrolls_under(node: Node) -> int:
    var found := 1 if node is ScrollContainer else 0
    for child in node.get_children():
        found += _scrolls_under(child)
    return found


## The rows are the list's rows, addressed by tool id, and `ids` is still the
## row order the docker copies into `_flyout_ids` and the capture step indexes.
func test_the_rows_are_the_visible_members_in_order() -> void:
    var docker := _toolbox()
    var flyout := _open_fills(docker)

    var wanted: Array[String] = []
    for descriptor: SaToolDescriptor in docker._visible_members(&"fill"):
        wanted.append(String(descriptor.id))
    assert_eq(flyout.ids, wanted, "one row per visible member, in the order the docker handed over")
    assert_eq(docker._flyout_ids, wanted, "and the docker's copy says the same")

    var by_id: Array[String] = []
    for id: StringName in flyout.row_ids():
        by_id.append(String(id))
    assert_eq(by_id, wanted, "the list's own ids are the tool ids, so a row can be found without an index")
    docker.free()


## The Done-when's number: a row of tools is as tall as the buttons it came out
## of. `ROW_HEIGHT` is 24 and a toolbox button is 40, and a list of 24-tall rows
## beside a column of 40-pixel squares reads as a different control.
func test_a_row_is_a_toolbox_buttons_height_at_the_dockers_scale() -> void:
    for factor: float in [1.0, 1.5, 2.0]:
        SaUI.os_scale_override = factor
        SaUI.user_scale = 1.0
        var docker := _toolbox()
        docker.apply_window_scale()
        var flyout := _open_fills(docker)

        var button := docker.button_for_tool("bucket_fill")
        var row := flyout.row_control(0)
        assert_not_null(row, "the first row has a control at %s" % factor)
        assert_almost_eq(
            row.custom_minimum_size.y,
            button.custom_minimum_size.y,
            0.0001,
            "a row is a button's height at a scale of %s, which is what the flyout is beside" % factor
        )
        assert_almost_eq(
            row.custom_minimum_size.y,
            float(SaUI.px(SaUI.BASE_TOOL_BTN)),
            0.0001,
            "the height being the one SaUI answers for, not a number this file chose"
        )
        docker.free()


## Every row is the same height whatever it carries, which is the screenshot the
## whole U group came from: Duplicate and Clear towering over Merge Down because
## a `PopupMenu` draws an icon at the texture's own size.
##
## Read in the tree, because a row's icon is capped rather
## than expanded and so counts in the row's minimum. A button out of the tree
## never takes the `icon_max_width` written on it into the cache that minimum is
## measured from, so detached the brush's 64-pixel texture counted whole and its
## row asked for 72 beside the gradient's 40, a height no running flyout draws.
## Opened before it joins the tree, so the rows are built and no window shows.
func test_an_icon_row_is_no_taller_than_a_plain_one() -> void:
    var docker := _toolbox()
    var flyout := _open_fills(docker)
    var host := Node.new()
    EventBus.add_child(host)
    host.add_child(docker)

    var heights: Array[float] = []
    for i in flyout.ids.size():
        var row := flyout.row_control(i)
        assert_not_null(row, "row %d has a control" % i)
        heights.append(row.get_combined_minimum_size().y)
    assert_true(heights.size() > 1, "the fills' group is more than one row, or this proves nothing")
    for height: float in heights:
        assert_almost_eq(height, heights[0], 0.0001, "every row wants the same height, icon or none")
    host.free()


## The doors the flyout's drag and the capture step use, in the shape their callers open them in: the
## capture step aims a pointer at `row_control`, `SaToolBoxGroups.release_target`
## asks `row_at`, and the drag data is what the docker's `is_tool_drag` reads.
func test_the_drag_doors_are_where_their_callers_open_them() -> void:
    var docker := _toolbox()
    var flyout := _open_fills(docker)

    var row := flyout.row_control(0) as Button
    assert_not_null(row, "a row is a Button, which is what carries a drag")
    assert_eq(row.text, flyout.row_labels()[0], "and the label the docker handed over is on it")
    assert_null(flyout.row_control(-1), "a row before the first is nothing")
    assert_null(flyout.row_control(flyout.ids.size()), "and so is one past the last")

    var data: Variant = flyout._drag_from(Vector2.ZERO, 0)
    assert_true(SaToolFlyout.is_tool_drag(data), "a drag out of a row carries the flyout's key")
    assert_eq(String((data as Dictionary)[SaToolFlyout.DRAG_KEY]), flyout.ids[0], "and the tool id of the row it left")
    assert_false(SaToolFlyout.is_tool_drag({"file": "cat.png"}), "somebody else's drag is refused")
    assert_true(flyout._can_drop_on(Vector2.ZERO, data), "a tool may land on a row")
    assert_false(flyout._can_drop_on(Vector2.ZERO, {"file": "cat.png"}), "a file may not")

    # Detached, so no row has a screen rectangle to be inside: the answer for a
    # point on nothing is the one `release_target` reads as "not a row of this
    # flyout" and falls through to the buttons on.
    assert_eq(flyout.row_at(Vector2(-9999.0, -9999.0)), [-1, false], "a point on no row is [-1, false]")
    docker.free()


## Picking closes the list, the way every menu in Sara does on a choice, and the
## docker still hears the row **number** it addresses a row by.
func test_picking_a_row_closes_the_list_and_names_the_row_by_number() -> void:
    var docker := _toolbox()
    var flyout := _open_fills(docker)

    var wanted := flyout.ids.find("gradient")
    assert_true(wanted >= 0, "the gradient is one of the fills' rows")
    var heard: Array[int] = []
    flyout.row_picked.connect(func(row: int) -> void: heard.append(row))

    assert_true(flyout.press_row(StringName("gradient")), "the row presses")
    assert_eq(heard, [wanted], "the docker hears the row's number and not its id")
    assert_false(flyout.visible, "and the list is shut, which is what a menu does on a choice")

    var faces := {}
    for entry: Dictionary in docker.toolbox_report()["buttons"]:
        if entry.has("category"):
            faces[entry["category"]] = entry["face"]
    assert_eq(faces.get("fill"), "gradient", "the button showing the tool that was picked")
    docker.free()


## What the popup's list gives reaches the flyout too, which is the whole reason the flyout
## stopped being a column of its own: the keyboard was never going to be written
## twice.
func test_the_keyboard_reaches_the_flyout() -> void:
    var docker := _toolbox()
    var flyout := _open_fills(docker)

    assert_eq(String(flyout.highlighted()), "", "an opened list has the keyboard nowhere")
    assert_true(flyout.move_highlight(1), "down lands somewhere")
    assert_eq(String(flyout.highlighted()), flyout.ids[0], "on the first row")
    assert_true(flyout.move_highlight(-1), "and up from there wraps")
    assert_eq(String(flyout.highlighted()), flyout.ids[flyout.ids.size() - 1], "onto the last")
    docker.free()


## The report the flyout scenario grades on, unchanged in its keys and its counts,
## because a dump whose words move is a scenario that has to be rewritten.
func test_the_report_still_says_what_x2_reads() -> void:
    SaUI.os_scale_override = 2.0
    SaUI.user_scale = 1.0
    var docker := _toolbox()
    docker.apply_window_scale()
    var flyout := _open_fills(docker)

    var report := flyout.report()
    for key: String in ["content_scale_factor", "rows", "row_height", "row_height_drawn", "size"]:
        assert_true(report.has(key), "the report still carries '%s'" % key)
    assert_eq(int(report["rows"]), flyout.ids.size(), "the row count is the members'")
    assert_almost_eq(float(report["content_scale_factor"]), 2.0, 0.0001, "at the factor the docker renders at")
    docker.free()
