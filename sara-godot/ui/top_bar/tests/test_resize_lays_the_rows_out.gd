## The bar lays its rows out again when its width changes, not only its
## sliders.
##
## A sibling of `test_top_bar_rows.gd`, whose one-row spend rule it drives:
## nothing here restates that rule, what is asserted is the half that connects a
## resize to it.
##
## The bar is built the way `test_top_bar_rows.gd` builds one, detached under
## nothing, which is what `test_ui_components` does with every other bar.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The tool options the bar carries come from the brush's descriptor, which
## needs a machine, a surface and therefore a device.
const REQUIRES_GPU := true

## Wide enough that one row holds everything with room over, at any theme scale.
const ROOMY := 4000.0

## How far under its one-row spend the narrow bar sits.
const SHORT := 100.0

var _surface: SaSurface = null
var _machine: ToolMachine = null


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    SaSettings.set_docker_option("TopMenuBar", TopMenuBar.OVERFLOW_OPTION, true)
    _surface = null
    _machine = null


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
    # `TopMenuBar._init` takes `PRESET_TOP_WIDE`, which is a left anchor of
    # 0 and a right anchor of 1, and every `bar.size.x = ...` below then warns
    # that "Nodes with non-equal opposite anchors will have their size overridden
    # after _ready()". The warning is right about a bar in a tree and says
    # nothing about this one: a detached Control has no parent to lay it out, so
    # the width written here is the width that stays, which is the whole reason
    # this fixture exists. The anchors are pinned together so the ten lines a
    # gate run carried are gone and the eleventh is worth reading. Writing the
    # width with `set_deferred`, which the warning suggests, would deliver it
    # after the assertion that reads it.
    bar.set_anchor(SIDE_RIGHT, 0.0)
    return bar


## The same rule when the only thing that moves is the width.
##
## Nothing here calls `apply_layout_settings` after the first pass, which is the
## whole case: a painter who unmaximises, tiles a window or moves Sara back to a
## laptop screen changes no setting, and the bar must not answer a resize by
## fitting the sliders inside a row that has already stopped fitting.
## `scenarios/top-bar-guard-asserts-its-own-constants.json` is the same thing at
## 1920 on the running app.
##
## **`resized` is emitted by hand, and the connection is asserted separately.**
## A bar this fixture builds is never added to a tree, and a detached Control's
## size is written straight into its rect without the layout pass that emits the
## signal. Writing the width and waiting for `resized` here proves nothing at
## all: it passes against a bar that ignores resizes until the widening step
## catches a stale overrun still sitting on it.
func test_narrowing_the_bar_brings_the_second_row_back_with_no_setting_touched() -> void:
    SaSettings.second_row = false
    # The second row comes back only with the overflow off, and
    # on it is the default, where the tail goes into the overflow list instead.
    SaSettings.set_docker_option("TopMenuBar", TopMenuBar.OVERFLOW_OPTION, false)
    var bar := _bar()
    assert_true(bar.resized.is_connected(bar.rows.refit_if_moved), "A resize lays the rows out again, not only the sliders")

    bar.size.x = ROOMY
    bar.apply_layout_settings()
    var narrow := ROOMY - bar.rows.row_budget(1, ROOMY) + bar.rows.row_spent(1) - SHORT

    bar.size.x = narrow
    bar.apply_layout_settings()
    var by_setting := bar.rows._second_row_forced_by
    assert_true(by_setting > 0.0, "A narrow bar laid out by a setting overruns: %d" % int(by_setting))

    bar.size.x = ROOMY
    bar.resized.emit()
    assert_false(bar.rows.second_row.visible, "A resize alone honours the switch when the width allows it")
    assert_almost_eq(bar.rows._second_row_forced_by, 0.0, 0.01, "and reports no overrun")

    bar.size.x = narrow
    bar.resized.emit()
    assert_true(bar.rows.second_row.visible, "and brings the second row back when it does not")
    assert_almost_eq(bar.rows._second_row_forced_by, by_setting, 1.0, "by the overrun a setting would have found")
    bar.free()


## The guard on `_refit_rows`, driven rather than reasoned about.
##
## The second pass reparents controls between the rows, which changes the bar's
## height, which is a resize. A bar in a tree would then re-enter the method it
## is already inside. The flag is what stops it, and a `resized` raised from
## under `_place_tool_options` is the shape of the real one.
func test_a_resize_raised_inside_the_layout_pass_does_not_start_a_second() -> void:
    SaSettings.second_row = false
    # The second row comes back only with the overflow off, and
    # on it is the default, where the tail goes into the overflow list instead.
    SaSettings.set_docker_option("TopMenuBar", TopMenuBar.OVERFLOW_OPTION, false)
    var bar := _bar()
    bar.size.x = ROOMY
    bar.apply_layout_settings()
    var narrow := ROOMY - bar.rows.row_budget(1, ROOMY) + bar.rows.row_spent(1) - SHORT

    bar.size.x = narrow
    # Every reparent inside the pass raises one, which is what a bar in a tree
    # does to itself.
    bar.rows.second_row.child_order_changed.connect(bar.resized.emit)
    bar.resized.emit()
    bar.rows.second_row.child_order_changed.disconnect(bar.resized.emit)

    assert_true(bar.rows.second_row.visible, "The pass still finished its second half")
    assert_true(bar.rows._second_row_forced_by > 0.0, "and still measured the overrun: %d" % int(bar.rows._second_row_forced_by))
    assert_false(bar.rows._refitting, "and left the flag down for the next resize")
    bar.free()
