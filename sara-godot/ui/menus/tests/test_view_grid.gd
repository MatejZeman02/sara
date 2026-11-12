## The grid over the canvas and the View menu's mirror rows.
##
## The grid is a hairline every so many document pixels, and the only thing
## about it worth asserting away from a screen is the step: a hairline is one
## pixel by construction, and what a grid can still get wrong is drawing lines
## closer together than they are wide.
##
## The bar is built detached and `_ready()`ed by hand, the way
## `test_top_menu_bar.gd` does, because a PopupMenu is a Window and nothing
## here needs it in a tree.
extends "res://tests/test_framework.gd"

var _saved_grid: bool = false
var _saved_size: int = 0


func before_each() -> void:
    _saved_grid = SaSettings.show_grid
    _saved_size = SaSettings.grid_size
    SaSettings.show_grid = false


func after_each() -> void:
    SaSettings.show_grid = _saved_grid
    SaSettings.grid_size = _saved_size


func _make_bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    return bar


## The step doubles until it is worth drawing. Without this a grid at one per
## cent zoom is 64 document pixels apart and 0.64 screen pixels apart, which is
## a grey fill rather than a grid.
func test_the_step_doubles_until_it_is_worth_drawing() -> void:
    assert_almost_eq(SaGridOverlay.step_for_zoom(1.0), 64.0, 0.001, "At 100 per cent the base step needs no help")
    assert_almost_eq(SaGridOverlay.step_for_zoom(4.0), 64.0, 0.001, "and zooming in never makes it coarser")
    assert_almost_eq(SaGridOverlay.step_for_zoom(0.05), 256.0, 0.001, "At five per cent it has doubled twice")
    assert_almost_eq(SaGridOverlay.step_for_zoom(0.125), 64.0, 0.001, "and at an eighth 64 is still eight pixels")
    assert_almost_eq(SaGridOverlay.step_for_zoom(0.0), 0.0, 0.001, "A zoom of zero draws nothing rather than looping")

    for zoom: float in [1.0, 0.5, 0.1, 0.05, 0.01, SaView.ZOOM_MIN]:
        var step: float = SaGridOverlay.step_for_zoom(zoom)
        if step > 0.0:
            var on_screen := step * zoom
            assert_true(
                on_screen >= SaGridOverlay.MIN_SCREEN_STEP,
                "the step is never tighter than the minimum at zoom %f: %f" % [zoom, on_screen]
            )


## Additive and with no SETTINGS_VERSION bump, so an older profile has no key
## and gets the ungridded canvas it already had.
func test_the_grid_switch_round_trips_through_the_profile() -> void:
    SaSettings.show_grid = true
    SaSettings.load_settings()
    assert_true(SaSettings.show_grid, "Saved and read back")
    SaSettings.show_grid = false
    SaSettings.load_settings()
    assert_false(SaSettings.show_grid, "and back off")


## The three rows the menu carries, and the grid tick reading the setting rather than
## whatever the menu was built with.
func test_the_view_menu_carries_the_mirror_and_grid_rows() -> void:
    var bar := _make_bar()
    var popup: SaChoicePopup = bar.menus.get("View")
    assert_not_null(popup, "The View menu exists")
    for id: int in [SaViewMenu.ID_MIRROR_H, SaViewMenu.ID_MIRROR_V, SaViewMenu.ID_GRID]:
        assert_not_null(SaMenu.list_holding(popup, SaMenu.key(id)), "and carries item %d" % id)

    var grid_idx := SaMenu.key(SaViewMenu.ID_GRID)
    popup = SaMenu.list_holding(popup, grid_idx)
    assert_false(popup.is_checked(grid_idx), "The grid row is unticked for a profile with the grid off")

    SaSettings.show_grid = true
    (bar.menu("View") as SaViewMenu).sync_ticks()
    assert_true(popup.is_checked(grid_idx), "and follows the setting rather than the last click")

    # A press writes the setting and the tick follows it, so the row cannot end
    # up toggling from a state the setting is not in, which is the failure this
    # suite's older half exists for.
    (bar.menu("View") as SaViewMenu).on_id_pressed(SaViewMenu.ID_GRID)
    assert_false(SaSettings.show_grid, "Pressing the row writes the setting")
    assert_false(popup.is_checked(grid_idx), "and the tick is what the setting says")
    bar.free()


## The mirror rows read the view rather than their own last state, so a flip
## from the Minimap docker shows here too. With no canvas to ask, both read
## unmirrored rather than raising.
func test_the_mirror_rows_read_the_view_and_survive_having_none() -> void:
    var bar := _make_bar()
    var menu := bar.menu("View") as SaViewMenu
    var popup: SaChoicePopup = bar.menus.get("View")
    menu.sync_ticks()
    assert_false(popup.is_checked(SaMenu.key(SaViewMenu.ID_MIRROR_H)), "No canvas reads as unmirrored")
    assert_false(popup.is_checked(SaMenu.key(SaViewMenu.ID_MIRROR_V)), "on both axes")
    menu.on_id_pressed(SaViewMenu.ID_MIRROR_H)
    assert_false(popup.is_checked(SaMenu.key(SaViewMenu.ID_MIRROR_H)), "and a press with no view flips nothing")
    bar.free()


## The spacing the doubling starts from is a setting, and one document pixel is
## a legal value, so the case worth asserting is a size of one giving a line per document pixel wherever the zoom affords it.
func test_a_one_pixel_grid_draws_a_line_per_document_pixel_where_the_zoom_affords_it() -> void:
    assert_almost_eq(SaGridOverlay.step_for_zoom(8.0, 1), 1.0, 0.001, "At eight times one pixel is eight on screen")
    assert_almost_eq(SaGridOverlay.step_for_zoom(16.0, 1), 1.0, 0.001, "and further in it stays one")
    assert_almost_eq(SaGridOverlay.step_for_zoom(4.0, 1), 2.0, 0.001, "At four times it doubles once to clear the floor")
    assert_almost_eq(SaGridOverlay.step_for_zoom(1.0, 1), 8.0, 0.001, "and at 100 per cent three times")
    assert_almost_eq(SaGridOverlay.step_for_zoom(0.05, 1), 256.0, 0.001, "Zoomed out it is the coarse grid 64 gets")
    assert_almost_eq(
        SaGridOverlay.step_for_zoom(SaView.ZOOM_MIN, 1),
        1024.0,
        0.001,
        "and at the lowest zoom Sara allows it still has a step rather than giving up"
    )


## The doubling is the readability floor at every size, not only at 64: a size
## the zoom cannot afford draws a coarser grid rather than a grey field.
func test_no_size_ever_draws_lines_closer_together_than_the_floor() -> void:
    for grid_size: int in [1, 2, 5, 16, 64, 256, SaSettings.MAX_GRID_SIZE]:
        for zoom: float in [16.0, 8.0, 1.0, 0.5, 0.1, 0.05, SaView.ZOOM_MIN]:
            var step: float = SaGridOverlay.step_for_zoom(zoom, grid_size)
            assert_true(step > 0.0, "size %d at zoom %f still has a step" % [grid_size, zoom])
            assert_true(
                step * zoom >= SaGridOverlay.MIN_SCREEN_STEP,
                "size %d at zoom %f is not tighter than the floor: %f" % [grid_size, zoom, step * zoom]
            )
            assert_true(step >= float(grid_size), "and a size is never made finer than it was asked for")


## The default is the grid a painter already had, so a painter who has not touched the row sees
## the grid they already had, and a zoom of zero still draws nothing.
func test_the_default_size_leaves_the_old_grid_exactly_where_it_was() -> void:
    assert_eq(SaSettings.DEFAULT_GRID_SIZE, 64, "The default is a quarter of a chunk")
    assert_eq(SaGridOverlay.BASE_STEP, SaSettings.DEFAULT_GRID_SIZE, "and the overlay's own default is that one")
    for zoom: float in [4.0, 1.0, 0.125, 0.05]:
        assert_almost_eq(
            SaGridOverlay.step_for_zoom(zoom, SaSettings.DEFAULT_GRID_SIZE),
            SaGridOverlay.step_for_zoom(zoom),
            0.001,
            "and asking for it answers what the bare call does at zoom %f" % zoom
        )
    assert_almost_eq(SaGridOverlay.step_for_zoom(0.0, 1), 0.0, 0.001, "A zoom of zero draws nothing rather than looping")


## Additive and with no SETTINGS_VERSION bump, and clamped at both ends, so a
## profile carrying nonsense cannot ask for a step of zero or one per texel of a
## document that has none.
func test_the_size_round_trips_through_the_profile_and_clamps() -> void:
    SaSettings.grid_size = 1
    SaSettings.load_settings()
    assert_eq(SaSettings.grid_size, 1, "One is a legal value and survives a reload")
    SaSettings.grid_size = 0
    assert_eq(SaSettings.grid_size, SaSettings.MIN_GRID_SIZE, "Below one clamps to one")
    SaSettings.grid_size = 999999
    assert_eq(SaSettings.grid_size, SaSettings.MAX_GRID_SIZE, "and past the cap clamps to the cap")
    SaSettings.grid_size = SaSettings.DEFAULT_GRID_SIZE
    SaSettings.load_settings()
    assert_eq(SaSettings.grid_size, SaSettings.DEFAULT_GRID_SIZE, "and the default round trips too")


## The row exists on the Display page and writes the setting. Without this the
## setting is reachable only from a scenario's `prefs` step, which is not a door
## a painter has.
func test_the_display_page_carries_the_grid_size_row() -> void:
    var page := SaDisplayPage.new()
    var found := page.find_children("GridSizeSpin", "SpinBox", true, false)
    assert_eq(found.size(), 1, "Preferences > Display carries one grid size row")
    var spin := found[0] as SpinBox
    assert_eq(int(spin.value), SaSettings.grid_size, "built at the setting rather than at a literal")
    assert_eq(int(spin.min_value), SaSettings.MIN_GRID_SIZE, "one is reachable from the row")
    assert_eq(int(spin.max_value), SaSettings.MAX_GRID_SIZE, "and the cap is the setting's own")
    # Set silently and then emitted, because writing `value` delivers nothing to
    # `value_changed` in this engine, in the tree or out of it, and a test that
    # only assigns proves that Godot stores numbers
    # (a Godot trap: writing `Range.value` does not deliver `value_changed`).
    spin.set_value_no_signal(1)
    spin.value_changed.emit(1.0)
    assert_eq(SaSettings.grid_size, 1, "and moving it writes the setting")
    page.free()
