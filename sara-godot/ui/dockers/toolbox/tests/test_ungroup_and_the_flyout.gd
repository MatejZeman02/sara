## A tool dragged out of a flyout can leave every group, and the flyout it came
## out of is still standing afterwards.
##
## Reordering by dragging should be able to un-group the tool out of the
## current group as well, not only change the order in the list. And the flying
## dropdown should not close when the dragged tool is released.
##
## Two halves, and this suite grades the arithmetic and the doors under both.
## The gesture itself is `scenarios/a-dragged-tool-can-leave-its-group.json`,
## because a release on empty space is a place on a screen and a suite has none:
## a docker built here is detached, its `drop_area_screen_rect` is empty on purpose,
## and every geometric case is written against a rectangle handed in.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

## A stand-in for the docker's button area, in the screen units the buttons and
## the release both answer in.
const GRID := Rect2(700.0, 240.0, 220.0, 380.0)

var _order: Array = []
var _groups_raw: Variant = null


func before_each() -> void:
    _order = SaSettings.get_layout_order(SaToolBoxGrid.CATEGORY)
    _groups_raw = SaSettings.get_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY)


## The profile is the run's own and a move writes it, so every case puts the
## order and the groups back where it found them.
func after_each() -> void:
    SaSettings.set_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY, _groups_raw)
    SaSettings.set_layout_order(SaToolBoxGrid.CATEGORY, _order)


func _toolbox() -> ToolBoxDocker:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = "ToolBoxDocker"
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    return docker


func _groups_of(docker: ToolBoxDocker) -> Array:
    return docker.toolbox_report()["groups"]


## The gesture this unit chose, on a rectangle alone: inside the docker and on
## nothing means a group of its own at the end, outside it means nothing.
func test_empty_toolbox_space_is_a_group_of_its_own_and_outside_is_not() -> void:
    var groups := [["brush", "eraser"], ["marquee", "lasso"]]

    assert_eq(
        SaToolBoxGroups.empty_drop_target(groups, Vector2(810.0, 600.0), GRID),
        [2, 0, true],
        "the space under the last button opens a group at the end"
    )
    assert_eq(
        SaToolBoxGroups.empty_drop_target(groups, Vector2(810.0, 239.0), GRID),
        [],
        "a point above the button area is outside the docker"
    )
    assert_eq(
        SaToolBoxGroups.empty_drop_target(groups, Vector2(1400.0, 400.0), GRID), [], "and so is one on the canvas beside it"
    )
    assert_eq(
        SaToolBoxGroups.empty_drop_target(groups, Vector2.ZERO, Rect2()),
        [],
        "a docker with no screen to be on has no empty space either, rather than one around the origin"
    )


## The index that target carries, through the arithmetic it is for: the tool
## leaves whatever group it was in and ends alone at the end of the list.
func test_the_target_ungroups_the_tool_through_moved() -> void:
    var groups := [["brush", "eraser"], ["marquee", "lasso", "wand"]]
    var target := SaToolBoxGroups.empty_drop_target(groups, Vector2(810.0, 600.0), GRID)

    var out := SaToolBoxGroups.moved(groups, "lasso", target[0], target[1], target[2])
    assert_eq(out, [["brush", "eraser"], ["marquee", "wand"], ["lasso"]], "the lasso ends in a group of its own at the end")

    var last := SaToolBoxGroups.moved([["brush"], ["lasso"]], "lasso", 2, 0, true)
    assert_eq(last, [["brush"], ["lasso"]], "and a tool already alone is put back where it was rather than duplicated")


## `release_target` asks the rows, then the buttons, then the space. With no
## flyout up and no button under the point, the space is what answers.
func test_release_target_falls_through_the_rows_and_the_buttons_to_the_space() -> void:
    var groups := [["brush", "eraser"], ["marquee", "lasso"]]
    var names := ["paint", "select"]

    assert_eq(
        SaToolBoxGroups.release_target(Vector2(810.0, 600.0), groups, names, {}, {}, 1, GRID),
        [2, 0, true],
        "a release on nothing inside the docker un-groups"
    )
    assert_eq(
        SaToolBoxGroups.release_target(Vector2(1400.0, 400.0), groups, names, {}, {}, 1, GRID),
        [],
        "and one outside it still means put the tool back"
    )


## The docker's own door, un-grouping through it: the tool leaves the group it
## shared and gets a button of its own, and the layout says so afterwards.
func test_the_docker_ungroups_a_tool_into_a_button_of_its_own() -> void:
    var docker := _toolbox()
    var select := docker._group_names.find("select")
    assert_true(select >= 0, "there is a select group to pull a tool out of")
    assert_true(docker.tools_in_category_of("marquee").has("ellipse_select"), "with the ellipse in it")

    var groups := _groups_of(docker)
    assert_true(docker.move_tool("ellipse_select", groups.size(), 0, true), "the ellipse moves out of every group")

    var after := _groups_of(docker)
    assert_eq(after[after.size() - 1], ["ellipse_select"], "and stands alone at the end of the list")
    assert_false(docker.tools_in_category_of("marquee").has("ellipse_select"), "off the marquee's button")
    assert_true(docker.button_for_tool("ellipse_select") != docker.button_for_tool("marquee"), "and onto one of its own")
    docker.free()


## The second half of the rule. A drop leaves a list standing: the group the
## tool landed in when that group can show one, and the list that was open
## before when it cannot, which is every un-group.
func test_a_drop_leaves_a_flyout_standing() -> void:
    var docker := _toolbox()
    assert_true(docker.open_flyout(&"select"), "the select flyout opens on its tools")

    var select := docker._group_names.find("select")
    assert_true(docker.move_tool("ellipse_select", select, 0, false), "the ellipse moves to the top of its own group")
    assert_eq(docker._open_flyout, &"select", "and the list it was reordered in is still up")
    assert_eq(docker._flyout_ids[0], "ellipse_select", "showing the new order")

    # The lassos' list is the one open, and the ellipse is pulled out of its
    # group. The ellipse's own category is left with the marquee alone, which has
    # no list to show, so the list that was open comes back.
    assert_true(docker.open_flyout(&"lasso"), "with the lassos' flyout open instead")
    var groups := _groups_of(docker)
    assert_true(docker.move_tool("ellipse_select", groups.size(), 0, true), "the ellipse is pulled out of every group")
    assert_eq(
        docker._open_flyout,
        &"lasso",
        "and the list that was open is still up, because a group of one has no list of its own to show"
    )
    assert_false(docker._flyout_ids.has("ellipse_select"), "and it never held the tool that left")
    docker.free()


## A drop into another group shows that group, because a painter who moved a
## tool onto a button is looking at where it landed.
func test_a_drop_into_another_group_shows_that_group() -> void:
    var docker := _toolbox()
    assert_true(docker.open_flyout(&"select"), "the select flyout is up")

    var paint := docker._group_names.find("paint")
    assert_true(docker.move_tool("lasso", paint, 1, false), "the lasso joins the paint group")
    assert_eq(docker._open_flyout, &"paint", "and the paint list is what stands afterwards")
    assert_true(docker._flyout_ids.has("lasso"), "with the tool that just arrived in it")
    docker.free()


## A release that moves nothing leaves the flyout exactly as it was, which is
## the case in question: it once shut it.
func test_a_release_outside_the_docker_leaves_the_flyout_alone() -> void:
    var docker := _toolbox()
    assert_true(docker.open_flyout(&"select"), "the select flyout is up")
    var before := _groups_of(docker)

    # A detached docker's `drop_area_screen_rect` is empty, so every point is outside
    # it, which is the release on the canvas this case is named for.
    assert_eq(docker.drop_area_screen_rect(), Rect2(), "a docker with no screen has no drop area")
    docker._on_tool_released("lasso", Vector2(1400.0, 400.0))

    assert_eq(_groups_of(docker), before, "the groups are untouched")
    assert_eq(docker._open_flyout, &"select", "and the flyout is still up")
    docker.free()
