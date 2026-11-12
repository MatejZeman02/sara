## A tool dropped before a later tool of its own group lands before it.
##
## `SaToolBoxGroups.row_drop_target` counts a row's position with the dragged
## tool still in the group, and `moved` erases the tool before it inserts, so a
## tool moved down its own group landed one row past the row it was dropped
## before. A capture dragged lasso onto the upper half of the Patch row in
## `[marquee, lasso, wand, patch]` and read `[marquee, wand, patch, lasso]`, the
## same order the lower half gives. What a painter sees is
## `scenarios/a-tool-dropped-before-a-later-tool-of-its-own-group-lands-after-it.json`.
extends "res://tests/test_framework.gd"

const SELECT := ["marquee", "lasso", "wand", "patch"]


## The groups as the toolbox holds them, the select group second, so a group
## index above zero is exercised rather than only the first.
func _groups() -> Array:
    return [["brush", "eraser"], SELECT.duplicate()]


## A drop through the row the flyout reports, the way a release is turned into a
## move, so the test grades the two together rather than `moved` alone.
func _drop_on_row(groups: Array, tool_id: String, row_id: String, before: bool) -> Array:
    var target := SaToolBoxGroups.row_drop_target(groups, 1, row_id, before)
    return SaToolBoxGroups.moved(groups, tool_id, target[0], target[1], target[2])


func test_lasso_dropped_before_patch_lands_between_wand_and_patch() -> void:
    var out := _drop_on_row(_groups(), "lasso", "patch", true)
    assert_eq(out[1], ["marquee", "wand", "lasso", "patch"], "the upper half of the Patch row puts lasso before patch")


func test_lasso_dropped_after_patch_lands_at_the_end() -> void:
    var out := _drop_on_row(_groups(), "lasso", "patch", false)
    assert_eq(out[1], ["marquee", "wand", "patch", "lasso"], "the lower half of the Patch row puts lasso after patch")


func test_lasso_dropped_before_marquee_lands_first() -> void:
    var out := _drop_on_row(_groups(), "lasso", "marquee", true)
    assert_eq(out[1], ["lasso", "marquee", "wand", "patch"], "a row above lasso's own takes it before, as it always did")


func test_the_two_halves_of_one_row_no_longer_give_the_same_order() -> void:
    var upper := _drop_on_row(_groups(), "lasso", "patch", true)
    var lower := _drop_on_row(_groups(), "lasso", "patch", false)
    assert_true(upper[1] != lower[1], "the upper and lower half of the Patch row put lasso in two different places")


## Dropped on its own row, either half, the tool stays where it was rather than
## hopping a place, which the correction must not introduce.
func test_a_tool_dropped_on_its_own_row_stays_put() -> void:
    assert_eq(_drop_on_row(_groups(), "lasso", "lasso", true)[1], SELECT, "the upper half of its own row leaves the order alone")
    assert_eq(_drop_on_row(_groups(), "lasso", "lasso", false)[1], SELECT, "and so does the lower half")


## The same position from a tool of another group is not corrected, because that
## tool left no place above the target in this one.
func test_a_tool_from_another_group_is_inserted_where_the_row_says() -> void:
    var out := SaToolBoxGroups.moved(_groups(), "brush", 1, 3, false)
    assert_eq(out[1], ["marquee", "lasso", "wand", "brush", "patch"], "the brush lands before patch, at the row's own index")
    assert_eq(out[0], ["eraser"], "and leaves its own group")
