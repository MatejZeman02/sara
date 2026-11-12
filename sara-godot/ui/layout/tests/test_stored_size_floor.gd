## A stored docker size is floored by the column inside it.
##
## `DockerLayoutStore` wrote `win.size` straight from the file in four of its
## five paths, and all four run after `DockerWindow.enforce_column_minimum` has
## raised the floor, so the floor was applied and then written over. The Minimap
## opened 300 wide against a column wanting 335 with 31 units of its own hide
## button past the right edge.
##
## The clamp reads the column's want as well as `min_size`, because
## `apply_window_scale` rewrites `min_size` from the logical minimum and raises
## it again from a column that has not always laid out yet. A run reads the
## Minimap's `min_size` at 177 while its column already wants 335.
##
## What the assembled dockers do is
## `scenarios/minimap-hide-button-off-edge.json`.
extends "res://tests/test_framework.gd"

const StoreScript := preload("res://ui/layout/docker_layout_store.gd")


## A window that answers `content_column` the way a `DockerWindow` does, which is
## what `DockerWindow.column_min_width` duck-types for. A real docker builds a
## toolbox or a picker in `_init` and is far more than this test needs.
class ColumnWindow:
    extends Window

    var column: VBoxContainer = null

    func _init(wants: Vector2i) -> void:
        column = VBoxContainer.new()
        column.custom_minimum_size = wants
        add_child(column)

    func content_column() -> Container:
        return column


func test_a_stored_size_under_the_windows_own_minimum_is_raised() -> void:
    var store := StoreScript.new()
    var window := Window.new()
    window.min_size = Vector2i(200, 160)
    var floored: Vector2i = SaDockerStoredEntry.floored(window, Vector2i(80, 40))
    assert_eq(floored, Vector2i(200, 160), "A size under the floor comes back at the floor")
    window.free()
    store.free()


func test_a_size_over_the_minimum_is_left_alone() -> void:
    var store := StoreScript.new()
    var window := Window.new()
    window.min_size = Vector2i(200, 160)
    var kept: Vector2i = SaDockerStoredEntry.floored(window, Vector2i(400, 300))
    assert_eq(kept, Vector2i(400, 300), "A size the window can hold is not touched")
    window.free()
    store.free()


## The defect, in one assertion. `min_size` says 177 and the column wants 335,
## and it is the column a painter sees run off the edge.
func test_the_column_raises_the_floor_above_min_size() -> void:
    var store := StoreScript.new()
    var window := ColumnWindow.new(Vector2i(335, 90))
    window.min_size = Vector2i(177, 144)
    assert_eq(DockerWindow.column_min_width(window), 335, "The column says what it wants")
    var floored: Vector2i = SaDockerStoredEntry.floored(window, Vector2i(300, 220))
    assert_eq(floored.x, 335, "and a stored 300 comes back at it rather than at min_size's 177")
    assert_eq(floored.y, 220, "while the other axis is left where the stored size put it")
    window.free()
    store.free()


## The floor is a floor, not a size: a docker wider than its column keeps its
## width, or every docker would snap to its content on the next launch.
func test_a_window_wider_than_its_column_is_not_shrunk() -> void:
    var store := StoreScript.new()
    var window := ColumnWindow.new(Vector2i(200, 90))
    window.min_size = Vector2i(177, 144)
    var kept: Vector2i = SaDockerStoredEntry.floored(window, Vector2i(600, 480))
    assert_eq(kept, Vector2i(600, 480), "A stored size over both floors is kept")
    window.free()
    store.free()
