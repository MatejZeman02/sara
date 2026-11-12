## Turning the top bar's Overflow off neither hangs nor crashes Sara.
##
## Overflow turned off on Preferences > Top Menu Bar, on a fresh profile with
## nothing else moved, could leave Sara unanswering, printing
## `Object was deleted while awaiting a callback.` until the message queue ran
## out of memory, and dying with signal 11. One row does not hold the controls at
## 1920, so the bar with the overflow off brings the second row back, and the
## pass that did it hid the row, showed it again while it was empty and only
## then filled it. Godot reads a control's minimum size when it is shown and
## emits `minimum_size_changed` when its deferred check finds another, so each
## refit left the next one queued, all inside one flush.
##
## A suite cannot wait for a frame, so this keeps the record Godot keeps and
## makes its deferred check by hand: the size each control the rows listen to
## had when it was last shown or reported, and a round that sends the signal for
## every one whose size now differs. A round that never goes quiet is the bug.
## The switch is turned the way a painter turns it, through the page's own row,
## and `scenarios/turning-the-top-bars-overflow-off-no-longer-hangs-and-crashes-sara.json`
## does the same in the running app with a perf window round each switch.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, which need a machine, a
## surface and therefore a device.
const REQUIRES_GPU := true

## Wide enough that one row holds everything, at any theme scale.
const ROOMY := 4000.0

## How far one row falls short of the controls. The running app at
## 1920 wanted 70 logical pixels more than the row had, and the suite's font is
## not the app's, so the width is found rather than named.
const SHORT := 70.0

## A common screen, where one row falls far short.
const NARROW := 1280.0

## How many rounds of Godot's check the relayout may take before it has to be
## quiet: the switch's own refit, and the one echo of it a hidden row may send.
const ROUNDS_ALLOWED: int = 2

## Where the round stops counting, well past the rounds allowed, so a loop
## fails the suite rather than hanging the run.
const ROUNDS_LIMIT: int = 50

static var scratch_profile: String = SaDataRoot.path("test_d1_overflow_settles.cfg")

var _saved_path: String = ""
var _saved_row: bool = false
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Control = null
var _page: SaTopBarPage = null
var _kept_embedding: bool = true

## Every control the rows listen to -> the minimum size Godot last reported for
## it, which its deferred check compares against.
var _reported: Dictionary = {}


func before_each() -> void:
    _saved_row = SaSettings.second_row
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    # A fresh profile has the second row on, so the switch is put at one row.
    SaSettings.second_row = false
    _reported = {}


func after_each() -> void:
    if _page != null:
        _page.free()
        _page = null
    if _host != null:
        _host.free()
        _host = null
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
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


## The bar in the tree, under an autoload, the way the 1280 suite puts it: a
## control that is not in the tree is never shown, and being shown is where the
## loop began. Laid out at *width* with the overflow on, a fresh profile's bar,
## or, with no width, where one row falls `SHORT` of what it holds.
func _bar_in_tree(width: float = 0.0) -> TopMenuBar:
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
    # The bar's menus are windows, and one added without embedding maps a real
    # one, so the root embeds for as long as the host stands, the way
    # `test_the_top_bar_refits_only_when_its_controls_change.gd` holds it.
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    _host = Control.new()
    _host.name = "D1TestHost"
    EventBus.add_child(_host)
    _host.add_child(bar)
    bar.size.x = width if width > 0.0 else _short_of_one_row(bar)
    bar.apply_layout_settings()
    _page = SaTopBarPage.new()
    return bar


## The width at which one row holds everything but `SHORT` logical pixels of it,
## read off *bar* at a roomy width with its sliders at their least, because
## there they have grown into the spare room.
func _short_of_one_row(bar: TopMenuBar) -> float:
    bar.size.x = ROOMY
    bar.apply_layout_settings()
    var rows := bar.rows
    var spent := rows.row_spent(1)
    var base := float(DockerUtils.px(ToolOptionsBar.SLIDER_MIN_WIDTH))
    for slider: FactorSlider in rows._options.sliders():
        if slider.visible and slider.get_parent() == rows.row_container(1):
            spent -= slider.custom_minimum_size.x - base
    return ROOMY - rows.row_budget(1, ROOMY) + spent - SHORT


## The five the rows connect `refit_if_moved` to.
func _listened(rows: SaTopBarRows) -> Array[Control]:
    return [
        rows.row_container(1),
        rows.second_options_row,
        rows.main_row.get_node(^"HBoxMenuBar") as Control,
        rows.main_row.get_node(^"HBoxWindowControls") as Control,
        rows.color_pair,
    ]


## Starts keeping Godot's record for each control the rows listen to. Heard on
## the control and on both rows, because a row shown shows what it holds.
func _watch(rows: SaTopBarRows) -> void:
    for control in _listened(rows):
        _reported[control] = control.get_combined_minimum_size()
        control.visibility_changed.connect(_shown)
    rows.second_row.visibility_changed.connect(_shown)
    rows.main_row.visibility_changed.connect(_shown)


## What Godot does when a control is shown: it reads the minimum size there and
## then, and says so when that is news.
func _shown() -> void:
    for control: Control in _reported:
        if control.is_visible_in_tree():
            _report(control)


func _report(control: Control) -> bool:
    var now := control.get_combined_minimum_size()
    if now == _reported[control]:
        return false
    _reported[control] = now
    control.minimum_size_changed.emit()
    return true


## Godot's deferred check, round after round: every control whose size differs
## from the one last reported says so, and whatever that starts is checked in
## the next round, the way a deferred call queued inside a flush runs in that
## same flush. Answers the rounds that sent a signal, or `ROUNDS_LIMIT` when
## they never stopped.
func _flush() -> int:
    for round_index in ROUNDS_LIMIT:
        var any := false
        for control: Control in _reported:
            any = _report(control) or any
        if not any:
            return round_index
    return ROUNDS_LIMIT


## Turns the page's Overflow row to *on* the way a painter's click does, lets
## Godot's checks run until they are quiet, and answers how long that took.
func _switch(rows: SaTopBarRows, on: bool, tag: String) -> int:
    var refits_before := rows._refits
    var began := Time.get_ticks_msec()
    _page.page.row(&"overflow").drive(on)
    var rounds := _flush()
    var took := Time.get_ticks_msec() - began
    assert_eq(SaTopBarOverflow.enabled(), on, "%s: the page's switch wrote the bar's option" % tag)
    assert_true(rounds <= ROUNDS_ALLOWED, "%s: the relayout is quiet after %d rounds, not %d" % [tag, ROUNDS_ALLOWED, rounds])
    assert_eq(rows._refits, refits_before + 1, "%s: in one relayout" % tag)
    assert_true(took < 1000, "%s: and it answered within a second, %d ms" % [tag, took])
    # Quiet means a round that follows moves nothing either.
    var refits := rows._refits
    _flush()
    assert_eq(rows._refits, refits, "%s: a round after it runs no refit" % tag)
    return took


## Every element the profile and the tool show sits on a row or in the list,
## and nowhere else, and the list's button is shown exactly when it holds one.
func _assert_every_element_placed(rows: SaTopBarRows, tag: String) -> void:
    var elements := rows.elements()
    var placed := 0
    for element: String in elements:
        var node: Control = elements[element]
        if node == null or not node.visible:
            continue
        var parent := node.get_parent()
        var on_row := parent == rows.row_container(1) or parent == rows.row_container(2)
        assert_true(on_row or parent == rows.overflow.box, "%s: %s is on a row or in the list" % [tag, element])
        if parent == rows.row_container(2):
            assert_true(rows.second_row.visible, "%s: %s is on the second row, which is shown" % [tag, element])
        placed += 1
    assert_true(placed > 0, "%s: the bar has elements to place" % tag)
    assert_eq(rows.overflow.visible, not _listed(rows).is_empty(), "%s: the button shows while the list holds one" % tag)


## The names of the shown controls the list holds.
func _listed(rows: SaTopBarRows) -> Array:
    return rows.overflow.report()["held"]


## Overflow off on a fresh profile, and then on again. Both settle,
## and every element is somewhere a painter reaches it.
func _off_and_on_again(width: float) -> void:
    var bar := _bar_in_tree(width)
    var rows := bar.rows
    var tag := "at %d" % int(bar.size.x)
    assert_false(SaSettings.second_row, "%s: a fresh profile asks for one row" % tag)
    assert_true(SaTopBarOverflow.enabled(), "%s: and overflows" % tag)
    _watch(rows)

    _switch(rows, false, tag + ", off")
    assert_true(rows._second_row_forced_by > 0.0, "%s: one row does not hold the controls, the case that overflowed" % tag)
    assert_true(rows.second_row.visible, "%s: so the second row is back" % tag)
    assert_true(rows.overflow.held().is_empty(), "%s: and nothing is in the list" % tag)
    _assert_every_element_placed(rows, tag + ", off")

    _switch(rows, true, tag + ", on again")
    assert_false(rows.second_row.visible, "%s: on again, one row as the profile asks" % tag)
    assert_false(_listed(rows).is_empty(), "%s: with what does not fit in the list" % tag)
    _assert_every_element_placed(rows, tag + ", on again")


func test_off_and_on_again_settle_when_one_row_is_a_little_short() -> void:
    _off_and_on_again(0.0)


func test_off_and_on_again_settle_at_1280() -> void:
    _off_and_on_again(NARROW)


## The cause itself: the switch's relayout shows the second row once, and
## already holding what it will hold, so the size Godot reads when it is shown is
## the one it keeps.
func test_the_second_row_is_shown_once_and_already_filled() -> void:
    var bar := _bar_in_tree()
    var rows := bar.rows
    var seen: Array[Vector2] = []
    var changes := [0]
    rows.second_row.visibility_changed.connect(
        func() -> void:
            changes[0] += 1
            if rows.second_row.visible:
                seen.append(rows.second_options_row.get_combined_minimum_size())
    )
    _page.page.row(&"overflow").drive(false)
    assert_eq(changes[0], 1, "The row is shown once, not hidden and shown again")
    assert_eq(seen.size(), 1, "and shown")
    if seen.size() == 1:
        assert_eq(seen[0], rows.second_options_row.get_combined_minimum_size(), "holding what it holds after")
        assert_true(seen[0].x > 0.0, "which is not an empty row")


## The rows hear a width signal as news only when what the split is made from
## moved, so the echo of their own refit runs none, and a control that really
## grew still gets one.
func test_an_echo_runs_no_refit_and_a_real_change_does() -> void:
    var bar := _bar_in_tree()
    var rows := bar.rows
    _page.page.row(&"overflow").drive(false)
    var refits := rows._refits
    for control in _listened(rows):
        control.minimum_size_changed.emit()
    assert_eq(rows._refits, refits, "A signal that only echoes the last refit runs none")
    rows._options.keep_blend_chk.text += " when a preset is loaded"
    rows._options.minimum_size_changed.emit()
    assert_eq(rows._refits, refits + 1, "A control that grew is news, and the split is made again")


## The same for the bar's own resize. The second row the switch brings back
## makes the bar taller and no row wider, and in the running app that resize ran
## a second pass after every switch. A new width still refits.
func test_a_resize_refits_only_when_the_width_moved() -> void:
    var bar := _bar_in_tree()
    var rows := bar.rows
    _page.page.row(&"overflow").drive(false)
    var refits := rows._refits
    bar.size.y += 20.0
    bar.resized.emit()
    assert_eq(rows._refits, refits, "A taller bar runs no refit")
    bar.size.x = NARROW
    bar.resized.emit()
    assert_eq(rows._refits, refits + 1, "and a narrower one does")
