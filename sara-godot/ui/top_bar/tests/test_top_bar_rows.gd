## The top bar's second row: one sentinel in the stored order, the
## controls after it on the second row when it is on and in the middle of the
## first when it is off, sliders that grow into a row's spare width, a width
## readout that can be asked before layout, and a theme pass that leaves a
## caller's separation alone.
##
## Built detached and `_ready()`ed by hand, the way `test_top_menu_bar.gd`
## does, because a PopupMenu is a Window and nothing here needs a tree.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, and
## a machine with the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

var _saved_path: String = ""
var _saved_row: bool = false
var _row_saved: bool = false
var _elements_registered: bool = false
var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    # The person's own switch is saved once, on the first test, because
    # `after_each` puts it back and a per-test save would only record what the
    # test before left. Every test then starts from the row off, rather than
    # from whatever the one before it happened to leave, which is what made
    # four of these pass on the luck of their order.
    if not _row_saved:
        _saved_row = SaSettings.second_row
        _row_saved = true
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_top_bar_rows.cfg"))
    _remove_profile()
    SaSettings.load_settings()
    SaSettings.second_row = false
    # The controls a tool owns reach the order through `ToolOptionsBar`, which
    # registers every spec marked for the bar when it is built. The checks
    # below ask settings for the order rather than building a bar first, so
    # without this the suite read whatever bars other suites had built: it
    # passed in a full run, failed on its own, and its cost grew with the
    # registry every suite before it had filled. One bar, built through the
    # same door the app uses and freed again, registers this suite's own set.
    # The registered elements outlive a settings reload, so once is enough.
    if not _elements_registered:
        _elements_registered = true
        _bar().free()


func after_each() -> void:
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row
    if _machine != null:
        Fixtures.teardown(_surface, _machine)
        _surface = null
        _machine = null


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(SaDataRoot.path("test_top_bar_rows.cfg")) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## A bar with its tool options, the way main builds them, detached, over a
## machine holding the built-in tools so the brush's controls exist.
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


## Only the menus sit before the sentinel, so a fresh profile's second row
## holds every tool option, the rotation pair among them.
func test_the_default_order_puts_only_the_menus_before_the_sentinel() -> void:
    var order := SaSettings.get_layout_order("TopMenuBar")
    var at := order.find(SaSettings.ROW_SENTINEL)
    assert_eq(order.slice(0, at), TopMenuBar.MENU_NAMES, "The menus, and nothing else, come before the sentinel")
    for element: String in ["Brush Presets", "blend_mode", "radius", "opacity", "Rotation", "Stabilizer Toggle"]:
        assert_true(order.find(element) > at, "%s follows it" % element)


## A profile written before this phase has no sentinel and reads as one with
## the sentinel at the end, and a profile missing a newer control gets it
## appended after the sentinel.
func test_a_profile_without_the_sentinel_reads_as_one_row() -> void:
    SaSettings.set_layout_order("TopMenuBar", ["File", "radius", "Edit"])
    var order := SaSettings.get_layout_order("TopMenuBar")
    assert_eq(order.slice(0, 3), ["File", "radius", "Edit"], "What was stored comes first, as stored")
    assert_true(order.has(SaSettings.ROW_SENTINEL), "and the sentinel is there")
    assert_true(order.has("flow"), "with every default the profile lacked")
    var bar := _bar()
    for child in bar.rows.second_options_row.get_children():
        assert_true(false, "Nothing is on the second row for a one-row profile: %s" % child.name)
    bar.free()


## The order above is this suite's fixture, and it stays in this suite's
## file: loading another profile afterwards reads that profile alone, rather
## than the union `ConfigFile.load` makes, which the save at the end of every
## load then wrote into the run's shared profile.
func test_a_stored_order_stays_in_the_profile_that_stored_it() -> void:
    SaSettings.set_layout_order("TopMenuBar", ["File", "radius", "Edit"])
    var other := ProjectSettings.globalize_path(SaDataRoot.path("test_top_bar_rows_other.cfg"))
    var empty := ConfigFile.new()
    empty.set_value("meta", "version", SaSettingsFile.SETTINGS_VERSION)
    empty.save(other)
    SaSettings.settings_path = other
    SaSettings.load_settings()
    assert_false(SaSettings.config.has_section("profile_order"), "The other profile holds no order it never stored")
    assert_false(
        SaSettings.get_layout_order("TopMenuBar").slice(0, 3) == ["File", "radius", "Edit"], "and the bar reads its default"
    )
    var written := ConfigFile.new()
    written.load(other)
    assert_false(written.has_section("profile_order"), "nor does the file the load saved back")
    for suffix: String in ["", ".bak"]:
        if FileAccess.file_exists(other + suffix):
            DirAccess.remove_absolute(other + suffix)


func test_the_switch_round_trips_through_the_profile() -> void:
    SaSettings.second_row = true
    SaSettings.load_settings()
    assert_true(SaSettings.second_row, "Saved and read back")
    SaSettings.second_row = false
    SaSettings.load_settings()
    assert_false(SaSettings.second_row, "and back off")


## The elements after the sentinel change row with the switch, and keep their
## owner and their signals while they do: the bar still reaches its sliders.
func test_elements_after_the_sentinel_move_to_the_second_row_when_it_is_on() -> void:
    var order := SaSettings.get_layout_order("TopMenuBar")
    order.erase(SaSettings.ROW_SENTINEL)
    var at := order.find("radius")
    order.insert(at, SaSettings.ROW_SENTINEL)
    SaSettings.set_layout_order("TopMenuBar", order)

    var bar := _bar()
    var options: ToolOptionsBar = bar.rows._options
    var size_slider := options.control_for(&"radius") as FactorSlider
    var blend_mode_opt := options.control_for(&"blend_mode")
    assert_false(bar.rows.second_row.visible, "Off by default")
    assert_eq(size_slider.get_parent(), options, "so the slider sits on the first row")

    SaSettings.second_row = true
    assert_true(bar.rows.second_row.visible, "The switch shows the row")
    assert_eq(size_slider.get_parent(), bar.rows.second_options_row, "and the slider after the sentinel moves onto it")
    assert_eq(blend_mode_opt.get_parent(), options, "while the one before it stays")
    assert_eq(bar.rows.row_container(2).get_child(0), size_slider, "in the stored order")
    assert_true(size_slider.value_changed.is_connected(options.options._on_slider_changed), "with its signal intact")

    SaSettings.second_row = false
    assert_eq(size_slider.get_parent(), options, "Off again, it comes back to the first row")
    assert_false(bar.rows.second_row.visible, "which is the only one shown")
    bar.free()


## **This measures a fixture bar, not the running app**, and the name says so.
##
## A bar built detached is roomier than the one main builds by 296 logical
## pixels, so this check stays green even when the app overruns its first row.
## See the test below for the numbers.
##
## It stays because the arithmetic itself is worth pinning: `row_spent` counting
## separations, `row_budget` subtracting the pinned children, and neither going
## negative. The claim about the app is in `scenarios/top-row-guard.json`.
func test_the_fixture_bars_first_row_fits_its_own_budget_at_1920() -> void:
    var bar := _bar()
    var spent := bar.rows.row_spent(1)
    var budget := bar.rows.row_budget(1, 1920.0)
    assert_true(spent > 0.0, "The row holds something to measure: %d" % int(spent))
    assert_true(spent <= budget, "and it fits the fixture's own budget: %d of %d" % [int(spent), int(budget)])
    assert_almost_eq(bar.rows.row_spent(2), 0.0, 0.01, "The second row holds nothing by default")
    bar.free()


## What the running app reads, captured by `scenarios/top-row-overruns.json`.
## Constants rather than prose so the tests below can be arithmetic.
##
## **Read off a capture at each width rather than computed from the other.**
## The scenario takes its four dumps at two widths in one run, so the 2560 pair
## is a photograph and not arithmetic over a 1920 capture.
const APP_ROW_1_BUDGET: float = 1030.0

## What the first row spends at 1920, with the second row carrying the group
## after the sentinel.
const APP_ROW_1_SPENT: float = 927.0

## What the first row would spend at 1920 with everything on it, which is what
## the painter asks for by turning the second row off, and what it costs: 149
## more than the row has. That is `second_row_forced_by` in
## `f39-02-second-row-off-1920.json`, added to the budget.
const APP_ROW_1_SPENT_ONE_ROW: float = 1179.0

## What the app's first row has at 2560, read off `row_budget` in
## `f39-04-second-row-off-2560.json` rather than off `row_budget_2560` in a 1920
## dump, which is the same number arrived at by measurement instead of by the
## bar's own arithmetic.
const APP_ROW_1_BUDGET_2560: float = 1670.0

## What the first row spends at 2560 with the switch off, and it is **not**
## [constant APP_ROW_1_SPENT_ONE_ROW]. A one-row spend is a function of the
## width: `fit_sliders` lends the row's spare pixels to the four sliders, so the
## same assignment costs 1179 at 1920 and 1366 at 2560.
const APP_ROW_1_SPENT_ONE_ROW_2560: float = 1366.0

## What the **fixture's** first row spends with everything on it, which is the
## only one of these numbers a headless test can read for itself.
##
## It is not the app's 1179 and is not meant to be. It is here so that a control
## added to the bar moves a number the gate looks at: the app's four constants
## are a photograph and this is the thing photographed, measured at Godot's
## default font on a detached bar. The guard allows two pixels of it so a font
## metric that rounds the other way does not fail a run rather than reporting
## one. The number moves with every control added to the first row, so it is
## re-measured on the fixture and never subtracted by hand. It includes the
## Focus Mode button after Redo in a group of its own.
const FIXTURE_ROW_1_SPENT_ONE_ROW: float = 1313.0


## The fixture is roomier than the app, so a guard on the fixture alone could
## not fail.
##
## A detached bar never gets `SaUI.apply_to_window` or the recursive theme pass,
## so every width in it is measured at Godot's default font rather than Sara's.
## The fixture's budget is 1190 against the app's 1030, and its one-row spend is
## 1043 against the app's 1179. 160 pixels of budget the row does not have and
## 136 pixels of controls it does, 296 of slack against an overrun of 149. The
## 160 sits in the pinned children `row_budget` subtracts, and `HBoxMenuBar` at
## 786 in the app's own dump is much the largest of the three, but the split
## between them is not measured and is not claimed.
##
## **When this test starts failing, the fixture has become faithful.** Delete it
## and rename the guard above back, because the guard will then be a guard.
func test_the_fixture_is_roomier_than_the_running_app() -> void:
    var bar := _bar()
    var budget := bar.rows.row_budget(1, 1920.0)
    var spent := bar.rows.row_spent(1)
    assert_true(
        budget > APP_ROW_1_BUDGET, "The fixture gives the row %d where the app gives %d" % [int(budget), int(APP_ROW_1_BUDGET)]
    )
    assert_true(
        spent < APP_ROW_1_SPENT_ONE_ROW,
        "and puts %d in it where the app on one row puts %d" % [int(spent), int(APP_ROW_1_SPENT_ONE_ROW)]
    )
    bar.free()


## The first row does not overrun, in either state of the switch.
##
## Whenever a painter turns the second row off, everything after the sentinel
## joins the first row and the default assignment needs 1179 of the 1030 a 1920
## bar has for it. The slot scrolls, so nothing is unreachable, but reaching
## Mirror V would mean dragging the bar, which is not what the switch is for.
##
## The bar keeps the second row when the first cannot hold what the switch would
## put on it, and `second_row_forced_by` in the state dump says it did and by how
## much. **The numbers here are the app's rather than the fixture's**, because
## the fixture is 296 pixels roomier than the app and cannot see the overrun at
## 1920 at all, which is what the test above pins.
##
## The rule itself is driven on a bar at widths the bar works out, so nothing
## here can pass without something laying a row out. Comparing constants with
## each other would assert that 1179 is more than 1030 and nothing about the
## bar. The constants stay as the photograph the scenario quotes and as what
## [method test_the_capture_the_constants_came_from_is_still_current] guards.
func test_the_bar_brings_the_second_row_back_when_one_row_would_overrun() -> void:
    SaSettings.second_row = false
    # The second row comes back only with the overflow off, and
    # on it is the default, where the tail goes into the overflow list instead.
    SaSettings.set_docker_option("TopMenuBar", TopMenuBar.OVERFLOW_OPTION, false)
    var bar := _bar()

    # What the pinned children cost, which is the same at any width, and what
    # one row needs when it is wide enough to hold everything. Both read off
    # this bar rather than written down, because the fixture's widths are not
    # the app's and the rule is the same either way.
    const ROOMY := 4000.0
    bar.size.x = ROOMY
    bar.apply_layout_settings()
    var pinned := ROOMY - bar.rows.row_budget(1, ROOMY)
    var one_row := bar.rows.row_spent(1)
    assert_true(one_row > 0.0, "One row holds something to measure: %d" % int(one_row))
    assert_almost_eq(bar.rows._second_row_forced_by, 0.0, 0.01, "A bar with room to spare forces nothing")
    assert_false(bar.rows.second_row.visible, "and shows the one row the switch asked for")

    # One pixel more than one row needs, which is as tight as the rule gets.
    bar.size.x = pinned + one_row + 1.0
    bar.apply_layout_settings()
    assert_almost_eq(
        bar.rows._second_row_forced_by,
        0.0,
        0.01,
        "A budget of %d for a row that needs %d is still enough" % [int(bar.rows.row_budget(1)), int(one_row)]
    )
    assert_false(bar.rows.second_row.visible, "so the switch is still honoured")

    # A hundred short of it, and the row comes back by no more than the
    # shortfall: `fit_sliders` lends a narrower row less, so the overrun the bar
    # measures can only be smaller than the gap, never larger.
    const SHORT := 100.0
    bar.size.x = pinned + one_row - SHORT
    bar.apply_layout_settings()
    assert_true(bar.rows.second_row.visible, "A budget short of what one row needs brings the second row back")
    assert_true(bar.rows._second_row_forced_by > 0.0, "and says so: %d" % int(bar.rows._second_row_forced_by))
    assert_true(
        bar.rows._second_row_forced_by <= SHORT + 0.5,
        "by the shortfall and no more: %d of %d" % [int(bar.rows._second_row_forced_by), int(SHORT)]
    )
    bar.free()


## The constants above are a photograph, and this is what makes them one.
##
## They are read off a capture taken by
## `scenarios/top-bar-guard-asserts-its-own-constants.json` and by a rerun of
## `scenarios/top-row-overruns.json`. A photograph goes stale the moment the
## thing it is of moves, so this pins what the app's numbers are a function of,
## on a bar rather than in prose: which controls the first row carries with the
## switch off, and what they cost each other on the fixture. Either moving means
## a control was added, removed, widened or sent across the sentinel, and the
## capture has to be taken again. The fixture's own widths are not the app's and
## are not claimed to be. What is claimed is that they move together, because
## both rows are built from one order and one set of descriptors.
##
## **When this fails, rerun the scenario and write its four numbers in above.**
## The failure is not a bug in the bar.
func test_the_capture_the_constants_came_from_is_still_current() -> void:
    SaSettings.second_row = false
    var bar := _bar()
    bar.size.x = 4000.0
    bar.apply_layout_settings()

    var names: Array[String] = []
    for child in bar.rows.row_container(1).get_children():
        var control := child as Control
        if control != null and control.visible:
            names.append(String(control.name))
    # Radial and the stabiliser's toggle are built without names of their own, so
    # they are counted rather than listed: an anonymous node's name carries its
    # instance id and changes between runs. The symmetry pair has names since it
    # took its icons.
    var named: Array[String] = []
    var anonymous := 0
    for name in names:
        if name.begins_with("@"):
            anonymous += 1
        else:
            named.append(name)
    assert_eq(
        named,
        [
            "PresetBox",
            "BlendModeOpt",
            "KeepBlendChk",
            "EraserToggledBtn",
            # Opacity first and Radius on its right.
            "OpacitySlider",
            "RadiusSlider",
            # Breaks between the groups, the brush's and the view's, the view's
            # and the stroke's before the symmetry buttons, and the stroke's
            # and the brush's before Edit Brush. The view's group opens on
            # Rotation and the stroke's holds one mirror, a fresh bar showing
            # neither the Flat or Environment button nor Mirror V.
            "GroupBreak0",
            # The document's Double Resolution toggle, heading the view's group.
            "DoubleResolutionToggle",
            "RotationSlider",
            "ResetRotationBtn",
            "GroupBreak1",
            "SymmetryHorizontal",
            # Undo and Redo, in the history's group.
            "GroupBreak2",
            "UndoBtn",
            "RedoBtn",
            # Focus Mode after Redo, in the window's group.
            "GroupBreak3",
            "FocusModeBtn",
            "GroupBreak4",
            "EditBrushButton",
        ],
        "One row carries what it carried when the capture was taken. Rerun the scenario if it does not"
    )
    assert_eq(anonymous, 2, "with Radial and the stabiliser's toggle among them")
    assert_almost_eq(
        bar.rows.row_spent(1),
        FIXTURE_ROW_1_SPENT_ONE_ROW,
        2.0,
        (
            "and costs what it cost then: %d against %d. Rerun the scenario and write its numbers in"
            % [int(bar.rows.row_spent(1)), int(FIXTURE_ROW_1_SPENT_ONE_ROW)]
        )
    )
    bar.free()


## The switch is honoured wherever it can be, and 2560 is wide enough.
##
## The rule is measured rather than a width written down: the second row comes
## back only when `row_spent` would pass `row_budget`, and `row_budget` grows
## with the bar. At 2560 the app's first row has 1670 for the 1366 the one-row
## assignment costs there, so a painter on a wide screen gets the one row they
## asked for and the same painter at 1920 does not. A one-row spend grows with
## the room the sliders are lent, so both numbers come from a capture at that
## width.
##
## The verdict itself is the scenario's, because `assert_true(1670 > 1366)`
## reads the file it is written in. The claim about the app is
## `scenarios/top-bar-guard-asserts-its-own-constants.json`, whose two dumps are
## the switch off at each width. What is left here is the half a headless test
## can honestly make: that the bar's budget grows with the bar, which is what
## the whole rule rests on.
func test_a_wide_enough_bar_honours_the_one_row_switch() -> void:
    var bar := _bar()
    assert_true(
        bar.rows.row_budget(1, 2560.0) > bar.rows.row_budget(1, 1920.0), "A wider bar gives the first row a bigger budget"
    )
    assert_almost_eq(
        bar.rows.row_budget(1, 2560.0) - bar.rows.row_budget(1, 1920.0),
        640.0,
        0.5,
        "and every pixel of the extra width reaches it, because the pinned children do not grow"
    )
    bar.free()


## A slider on a row with room grows into it, and never below its minimum.
func test_sliders_grow_into_a_row_with_room_and_never_shrink() -> void:
    var order := SaSettings.get_layout_order("TopMenuBar")
    order.erase(SaSettings.ROW_SENTINEL)
    order.insert(order.find("radius"), SaSettings.ROW_SENTINEL)
    SaSettings.set_layout_order("TopMenuBar", order)
    SaSettings.second_row = true

    var bar := _bar()
    var options: ToolOptionsBar = bar.rows._options
    var size_slider := options.control_for(&"radius") as FactorSlider
    var minimum := float(DockerUtils.px(ToolOptionsBar.SLIDER_MIN_WIDTH))
    assert_true(size_slider.custom_minimum_size.x > minimum, "A slider alone on the second row is wider than the minimum")
    assert_true(
        size_slider.custom_minimum_size.x <= minimum + float(DockerUtils.px(ToolOptionsBar.SLIDER_EXTRA_WIDTH)),
        "but no wider than the extra allows"
    )
    for slider: Control in options.sliders():
        assert_true(slider.custom_minimum_size.x >= minimum, "%s never goes below the minimum" % slider.name)
    bar.free()


## The theme pass records what it wrote, so a container whose caller
## set its own separation keeps it through every pass, and a container the
## pass set follows the pass.
func test_the_theme_pass_keeps_a_separation_a_caller_set() -> void:
    var own := HBoxContainer.new()
    own.add_theme_constant_override("separation", 3)
    var plain := HBoxContainer.new()
    var root := Control.new()
    root.add_child(own)
    root.add_child(plain)

    SaUI.apply_ui_theme(root)
    SaUI.apply_ui_theme(root)
    assert_eq(int(own.get_theme_constant("separation")), 3, "The caller's separation survives two passes")
    assert_eq(
        int(plain.get_theme_constant("separation")), SaUI.px(SaUI.BASE_SEPARATOR), "and a plain container gets the global one"
    )

    plain.add_theme_constant_override("separation", 5)
    SaUI.apply_ui_theme(root)
    assert_eq(int(plain.get_theme_constant("separation")), 5, "A value set after a pass is a caller's too")
    root.free()


## The drag list keeps the menus among themselves and lets a control cross the
## sentinel, which is how a control changes rows.
##
## Asked of the band a row may land in rather than of a drop target, because the page
## runs its own reorder instead of Godot's drag-and-drop: the row
## moves while the pointer does, so there is no target until it stops.
func test_the_preferences_rows_refuse_a_menu_past_the_sentinel() -> void:
    var page := SaLayoutPage.new("TopMenuBar")
    var sentinel := page.row_for(SaSettings.ROW_SENTINEL)
    var menu_row := page.row_for("File")
    var tool_row := page.row_for("radius")

    assert_true(sentinel.is_sentinel, "The sentinel row knows what it is")
    assert_false(sentinel.can_drag(), "and cannot be dragged")
    assert_true(sentinel.check_button.visible, "and shows the second row's own switch")

    var sentinel_at := sentinel.get_index()
    var menu_band := page.drop_band(menu_row)
    var tool_band := page.drop_band(tool_row)
    assert_eq(menu_band.x, 0, "A menu may lead the bar")
    assert_true(menu_band.y < sentinel_at, "and can never reach the second row")
    assert_true(tool_band.x > menu_band.y, "A control starts after the last menu")
    assert_true(tool_band.y >= sentinel_at, "and may cross the sentinel, which is how it changes rows")

    page.free()


## The sentinel's own switch is the second row's, not a copy of it.
func test_the_sentinel_switch_is_the_second_row_switch() -> void:
    var host := Node.new()
    SaSettings.second_row = false
    var sentinel := SaLayoutPage.DragRow.new("TopMenuBar", SaSettings.ROW_SENTINEL, true, host)
    assert_false(sentinel.check_button.button_pressed, "Starts from the real setting, not the 'true' this test passed")

    sentinel.check_button.button_pressed = true
    sentinel.check_button.toggled.emit(true)
    assert_true(SaSettings.second_row, "Toggling the row toggles the setting")
    sentinel.free()
    host.free()


## Drag Handle and Resizer sit pinned, not merely first by luck of the
## default order. Neither can be picked up, and nothing may land above them.
func test_drag_handle_and_resizer_are_pinned() -> void:
    var page := SaLayoutPage.new("ColorPicker")
    var handle := page.row_for("Drag Handle")
    var resizer := page.row_for("Resizer")
    var wheel := page.row_for("HSV Wheel")

    assert_true(handle.is_locked, "Drag Handle knows it is pinned")
    assert_true(resizer.is_locked, "and so does Resizer")
    assert_false(wheel.is_locked, "a real element is not")
    assert_false(handle.can_drag(), "Pinned rows cannot be picked up")
    assert_eq(handle.get_index(), 0, "The handle leads the list")
    assert_eq(resizer.get_index(), 1, "with the resizer under it")
    assert_eq(page.drop_band(wheel).x, 2, "and a real element cannot land above the pair")
    assert_true(handle.check_button.visible, "but each keeps its own switch")

    page.free()


## The pair is pinned at the left of the second row, before the slot that
## scrolls, so it never scrolls away from the painter.
func test_the_colour_pair_is_pinned_at_the_left_of_the_second_row() -> void:
    var bar := _bar()
    assert_not_null(bar.rows.color_pair, "The bar builds the pair")
    assert_eq(bar.rows.color_pair.get_parent(), bar.rows.second_row, "on the second row")
    var names: Array = []
    for child in bar.rows.second_row.get_children():
        names.append(String(child.name))
    assert_eq(names, ["ColorPair", "ColorPairSeparator", "SecondRowSlot"], "ahead of the slot and its separator")
    bar.free()


## The arrow and the square that is behind swap, and the
## square already in use does not, because clicking the colour you are
## painting with must do nothing.
func test_the_pair_swaps_from_the_arrow_and_from_the_back_square() -> void:
    var pair := SaColorPair.new()
    pair.size = Vector2(90, 57)
    assert_true(pair.swaps_at(pair.swap_rect().get_center()), "The arrow swaps")
    assert_true(pair.swaps_at(pair.background_rect().end - Vector2(2, 2)), "and so does the back square")
    assert_false(pair.swaps_at(pair.foreground_rect().position + Vector2(2, 2)), "the front one does not")
    assert_false(pair.swaps_at(Vector2(0, 0)), "and neither does the padding round them")

    # An Array rather than an int, because a lambda captures a plain value by
    # copy and the count would stay at zero however often it ran.
    var asked: Array = []
    pair.swap_requested.connect(func() -> void: asked.append(true))
    for point: Vector2 in [pair.swap_rect().get_center(), pair.foreground_rect().position + Vector2(2, 2)]:
        var press := InputEventMouseButton.new()
        press.button_index = MOUSE_BUTTON_LEFT
        press.pressed = true
        press.position = point
        pair._gui_input(press)
    assert_eq(asked.size(), 1, "One press on the arrow asks once, and the one on the front square asks nothing")
    pair.free()


## The pair shows the store and changes nothing itself. The bar is what
## turns the request into a swap.
func test_the_pair_follows_the_store_and_the_bar_does_the_swapping() -> void:
    var was := [SaColors.foreground, SaColors.background]
    SaColors.foreground = Color.RED
    SaColors.background = Color.BLUE

    var bar := _bar()
    assert_eq(bar.rows.color_pair.foreground, Color.RED, "The pair opens on what the store holds")
    assert_eq(bar.rows.color_pair.background, Color.BLUE, "both colours")

    bar.rows.color_pair.swap_requested.emit()
    assert_eq(SaColors.foreground, Color.BLUE, "A request reaches the store")
    assert_eq(SaColors.background, Color.RED, "and the pair changes places")
    assert_eq(bar.rows.color_pair.foreground, Color.BLUE, "The pair follows the bus rather than its own click")
    assert_eq(bar.rows.color_pair.background, Color.RED, "on both colours")

    bar.free()
    SaColors.foreground = was[0]
    SaColors.background = was[1]


## The second row is half again as tall as the first, and
## a control that moves onto it takes the height. Moving back gives the
## control the flags it was built with rather than leaving it stretched.
func test_a_control_on_the_second_row_takes_the_rows_height() -> void:
    var order := SaSettings.get_layout_order("TopMenuBar")
    order.erase(SaSettings.ROW_SENTINEL)
    order.insert(order.find(ToolOptionsBar.ELEMENT_KEEP_BLEND), SaSettings.ROW_SENTINEL)
    SaSettings.set_layout_order("TopMenuBar", order)

    var bar := _bar()
    var keep: Control = bar.rows._options.layout_elements()[ToolOptionsBar.ELEMENT_KEEP_BLEND]
    assert_eq(keep.size_flags_vertical, Control.SIZE_SHRINK_CENTER, "It is built to sit at its own height")

    SaSettings.second_row = true
    assert_eq(keep.get_parent(), bar.rows.second_options_row, "The switch moves it onto the second row")
    assert_eq(keep.size_flags_vertical, Control.SIZE_FILL, "where it fills the height the row already had")
    assert_eq(bar.rows.second_options_row.size_flags_vertical, Control.SIZE_EXPAND_FILL, "because the row fills it too")

    SaSettings.second_row = false
    assert_eq(keep.size_flags_vertical, Control.SIZE_SHRINK_CENTER, "and back on the first it is itself again")
    bar.free()


## The pair and its separator are pinned, so the second row's budget is what
## is left after them rather than the whole bar. A slider that grows into the
## row measures against this, and a row that forgot the pair would push the
## last control off the right-hand edge.
func test_the_second_rows_budget_is_short_of_the_pinned_pair() -> void:
    var bar := _bar()
    SaSettings.second_row = true
    var budget := bar.rows.row_budget(2, 1920.0)
    var pinned := 1920.0 - budget
    var pair_width := bar.rows.color_pair.get_combined_minimum_size().x
    assert_true(pair_width > 0.0, "The pair asks for a width: %d" % int(pair_width))
    assert_true(pinned > pair_width, "and the row loses it and the separator: %d of %d" % [int(pinned), int(pair_width)])
    bar.free()


## The rotation pair is a row element like every other, so a profile can
## order it, move it to the second row and hide it, and the bar owns it rather
## than the tool options builder.
func test_the_rotation_pair_is_a_row_element_the_profile_owns() -> void:
    var bar := _bar()
    var pair := bar.rotation_row
    assert_not_null(pair.slider, "The slider is built once the bar has tool options")
    assert_not_null(pair.reset_button, "and so is the reset button")

    var elements: Dictionary = bar.rows.elements()
    assert_true(elements.has(SaTopBarRotation.ELEMENT_SLIDER), "The slider is an element the profile can order")
    assert_true(elements.has(SaTopBarRotation.ELEMENT_RESET), "and so is the button")
    assert_eq(elements[SaTopBarRotation.ELEMENT_SLIDER], pair.slider, "each standing for its own control")

    SaSettings.second_row = true
    assert_eq(pair.slider.get_parent(), bar.rows.second_options_row, "After the sentinel, the switch moves the slider to row two")
    assert_eq(pair.reset_button.get_parent(), bar.rows.second_options_row, "with the button beside it")

    SaSettings.set_element_visible("TopMenuBar", SaTopBarRotation.ELEMENT_SLIDER, false)
    bar.apply_layout_settings()
    assert_false(pair.slider.visible, "and hiding it from Preferences takes it off the bar")
    bar.free()


## The width is written through `preferred_width` and never through
## `custom_minimum_size`, because `FactorSlider._update_display` rewrites the
## minimum from `preferred_width` on every value change. A width set the other
## way survives exactly until the first drag, which measures a 96-wide
## slider as 170 on the running bar.
##
## The text, the word and the widest angle at the theme
## font's size, asks for more than that width, so what is held is that the
## slider never asks for less and that a value change does not move it.
func test_the_rotation_slider_keeps_its_width_after_a_value_change() -> void:
    var bar := _bar()
    var slider := bar.rotation_row.slider
    var least := float(DockerUtils.px(SaTopBarRotation.SLIDER_WIDTH))
    var asked := slider.get_combined_minimum_size().x
    assert_true(asked >= least, "The slider asks for its own width at least: %d of %d" % [int(asked), int(least)])
    slider.set_value_no_signal(-180.0)
    assert_almost_eq(slider.get_combined_minimum_size().x, asked, 0.5, "and still asks for the same at the end of its range")
    bar.free()


## A slider that read "0 °" alone was taken for a progress bar,
## so the word goes ahead of the angle. "Rotate" is the shorter word.
func test_the_rotation_slider_says_rotate_ahead_of_its_angle() -> void:
    var bar := _bar()
    var slider := bar.rotation_row.slider
    assert_eq(slider.prefix, "Rotate: ", "The slider's label opens on the word")
    assert_eq(slider._label.text, "Rotate: 0 °", "and reads it ahead of the angle")
    bar.free()


## At 1280 Size and Opacity stand on the bar at their full width while the
## rarely used controls are in the overflow. A cut from the row's end would do
## the opposite, since the two sliders stand in the middle of the row and the rarely used controls at
## its start and its end.
##
## On the fixture, whose budget at 1280 is roomier than the app's. The running
## app at 1280 is `scenarios/size-and-opacity-are-full-size-on-the-bar-and-the-last-to-leave-it.json`.
func test_at_1280_size_and_opacity_stay_whole_and_the_rarely_used_leave() -> void:
    var bar := _bar()
    bar.size.x = 1280.0
    bar.apply_layout_settings()
    var rows := bar.rows
    var options: ToolOptionsBar = rows._options
    var full := float(DockerUtils.px(ToolOptionsBar.SLIDER_MIN_WIDTH))
    for key: StringName in [&"radius", &"opacity"]:
        var slider := options.control_for(key) as FactorSlider
        assert_eq(slider.get_parent(), rows.row_container(1), "%s stands on the first row at 1280" % key)
        assert_true(slider.visible, "and shows")
        assert_true(
            slider.get_combined_minimum_size().x >= full,
            "at its full width: %d of %d" % [int(slider.get_combined_minimum_size().x), int(full)]
        )
        assert_eq(slider.text_size(), SaUI.get_font_size(), "with its text at the size the overflow's list draws it")
    var elements := rows.elements()
    for element: String in SaTopBarRows.LEAVE_FIRST:
        # The eraser leaves among the first but was reached for, so it is not
        # one of the seven that leave first.
        if element == "eraser_toggled":
            continue
        # Off a fresh bar altogether, Mirror V and the Flat or Environment
        # button among them, so in neither the row nor the list.
        if not SaSettings.get_element_visible("TopMenuBar", element):
            continue
        var node: Control = elements.get(element)
        assert_not_null(node, "%s is a row element" % element)
        if node != null:
            assert_eq(node.get_parent(), rows.overflow.box, "%s is in the overflow at 1280" % element)
    assert_true(rows.overflow.visible, "whose button shows")
    assert_true(
        rows.row_spent(1) <= rows.row_budget(1) + 0.5,
        "and the row holds what it shows whole: %d of %d" % [int(rows.row_spent(1)), int(rows.row_budget(1))]
    )
    bar.free()
