## A docker keeps its column's floor across a scale change.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `apply_window_scale` writes `min_size` from `logical_min_size`, which drops
## whatever `enforce_column_minimum` had raised it to, and raises it again from a
## column measured in that same frame. A column whose want grows after the call
## therefore never reaches the floor, and the window sits narrower than its own
## content until something else notices.
##
## The Toolbox is the one that shows it. Its want is 44 while the docker is 520
## tall, because the content fits and no vertical scroll bar is drawn, and 52
## once the docker is the 264 its own `logical_size` declares, because the bar
## appears and `ScrollContainer` passes its width up. `apply_window_scale` sets
## the size to 264 and reads the column in the same frame, so it reads the 44,
## keeps a declared floor of 50, and the docker draws two logical pixels narrower
## than its column. `DockerLayoutStore` then saves the 50 and its restore clamps
## it back up to 52 through `SaDockerStoredEntry.floored`, which does read the column, so
## the first run after a fresh settings directory is 50 wide and every run after
## it is 52. Any capture with the Toolbox in it is then two pictures, which is
## what made a refactoring's before unreadable.
##
## **This is the third of the three floors.** `test_stored_size_floor.gd`
## asks the store what a stored size comes back as and
## `test_drag_floor_follows_the_column.gd` asks a drag what it may walk
## through. Both read the floor without ever asking the window to mend it, which
## is the half neither covered: the repair itself, and that `apply_window_scale`
## asks for it a second time once the layout has settled.
##
## What the assembled dockers do is
## `scenarios/toolbox-narrow-on-a-fresh-settings-dir.json`.
## `@tool` because the fixture below extends `DockerWindow`, which is a tool
## script, and the LSP warns on a subclass that is not one. The annotation is
## file-wide and reaches the inner class, and no suite is ever a node in a scene,
## so nothing here runs in the editor.
@tool
extends "res://tests/test_framework.gd"


## A docker whose column's want can be moved between two calls, which is the one
## thing the defect needs. Built through `_init_docker` so the logical sizes and
## the floors are the real ones.
##
## **Two columns rather than one that is widened**, because a `Control` caches its
## combined minimum and only invalidates that cache on the deferred pass, so a
## `custom_minimum_size` written here still reads as the old number for the rest
## of the frame. That cache is half of what the defect is made of and a fixture
## that leaned on it would be asserting Godot's timing rather than Sara's floor.
## Switching which column `content_column` answers with says the same thing
## outright: the want the second read sees is not the want the first one did.
class GrowingDocker:
    extends DockerWindow

    var narrow: VBoxContainer = null
    var wide: VBoxContainer = null
    var _wide_now: bool = false

    func _init(logical: Vector2i, floor_size: Vector2i, small: int, large: int) -> void:
        _init_docker("GrowingDocker", "Growing", logical, floor_size)
        # A real docker's content sits inside the window's own Control, and this
        # one's two columns are children of the window itself. `wrap_controls`
        # would then size the window to the wider of them and answer the question
        # this suite is asking, so it is off here. What is under test is the floor
        # arithmetic, not Godot's wrap.
        wrap_controls = false
        narrow = _column(small)
        wide = _column(large)
        drag_handle = PanelContainer.new()
        narrow.add_child(drag_handle)

    func _column(width: int) -> VBoxContainer:
        var column := VBoxContainer.new()
        column.custom_minimum_size = Vector2i(width, 36)
        add_child(column)
        return column

    ## The column the window is laid out against, which is what
    ## `DockerWindow.column_min_width` asks every docker for.
    func content_column() -> Container:
        return wide if _wide_now else narrow

    ## The scroll bar appears: from here on the column wants the wider number.
    func grow() -> void:
        _wide_now = true


func _grown(wants: int = 44) -> GrowingDocker:
    return GrowingDocker.new(Vector2i(50, 264), Vector2i(50, 76), wants, 52)


## The synchronous raise, when the column has already grown. This is the half
## that works, and it is here so a change that drops the call from
## `apply_window_scale` fails something.
func test_a_scale_change_floors_the_window_at_the_column_it_can_see() -> void:
    var docker := _grown(44)
    docker.grow()
    docker.apply_window_scale()
    assert_eq(DockerWindow.column_min_width(docker), 52, "The column says what it wants")
    assert_eq(docker.min_size.x, 52, "and the floor comes back at it rather than at the declared 50")
    assert_eq(docker.size.x, 52, "and the window is at least that wide")
    docker.free()


## The defect, in one assertion. The column grows after the call, which is what a
## scroll bar appearing at the new height is, and the window is left under it.
func test_a_column_that_grows_after_the_call_leaves_the_window_under_it() -> void:
    var docker := _grown(44)
    docker.apply_window_scale()
    assert_eq(docker.min_size.x, 50, "A column wanting less than the floor does not lower it")
    docker.grow()
    assert_eq(DockerWindow.column_min_width(docker), 52, "The column now wants more than the floor")
    assert_true(docker.size.x < 52, "and nothing has moved the window, which is the defect")
    docker.free()


## The repair, which is the pass `apply_window_scale` now asks for a second time
## once the layout has settled. Called here rather than awaited, because the
## runner is synchronous and an awaited assertion is a dropped one.
func test_the_deferred_pass_mends_a_window_left_under_its_column() -> void:
    var docker := _grown(44)
    docker.apply_window_scale()
    docker.grow()
    docker.enforce_column_minimum()
    assert_eq(docker.min_size.x, 52, "The floor follows the column that grew")
    assert_eq(docker.size.x, 52, "and the window with it, so the two runs draw one width")
    docker.free()


## The floor is a floor. A docker wider than its column keeps its width, or a
## scale change would snap every docker to its content.
func test_a_window_wider_than_its_column_is_not_shrunk_by_the_pass() -> void:
    var docker := _grown(44)
    docker.size = Vector2i(200, 264)
    docker.enforce_column_minimum()
    assert_eq(docker.size.x, 200, "A window over both floors is left where it was")
    docker.free()


## That `apply_window_scale` asks for the second pass at all, read off the source.
##
## The effect needs a shown window, a settled layout and a deferred call, and a
## suite that awaits one drops every assertion after the await. So this
## is `test_f95_dialogs_connect_the_visibility_signal_once.gd`'s shape, for the
## same reason it took it: what has to hold is that the call is in the function,
## and the running app answers the rest in
## `scenarios/toolbox-narrow-on-a-fresh-settings-dir.json`.
func test_apply_window_scale_asks_for_the_pass_again_once_the_layout_settles() -> void:
    var source := FileAccess.get_file_as_string("res://ui/dockers/docker_window.gd")
    assert_false(source.is_empty(), "docker_window.gd is readable")
    var body := source.split("func apply_window_scale() -> void:")
    assert_eq(body.size(), 2, "apply_window_scale is declared exactly once")
    if body.size() != 2:
        return
    var till_next := body[1].split("\nfunc ")[0]
    assert_true(
        till_next.contains("enforce_column_minimum()"), "apply_window_scale still floors the window at the column it can see"
    )
    assert_true(
        till_next.contains("enforce_column_minimum.call_deferred()"),
        "and asks again once the layout has settled, or a column that grew is never reached"
    )
    assert_true(
        till_next.contains("reserve_grip_corner.call_deferred()"), "with the other axis going round again for the same reason"
    )
