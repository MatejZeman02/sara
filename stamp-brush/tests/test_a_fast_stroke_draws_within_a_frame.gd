## A fast stroke draws within a frame under either pen driver.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A quick scribble with a 2 px Pencil froze the canvas for up to seconds
## under Windows Ink or WinTab,
## because a frame walked every motion that had queued before it could draw.
## [SaWalkBudget] walks until the frame's share is spent and carries the rest,
## stopping inside a span if it has to. What these hold is that the carried
## stroke is the same stroke, dab for dab, that a brush nobody ticks still
## walks everything at once, which is what every other suite relies on, and
## that the pen's lift waits for the walk. The frames themselves are measured
## with `Sara stroke:` lines.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

static var scratch_dir: String = SaDataRoot.path("test_w1_fast_stroke_presets")

## A scribble's samples, far apart as a late frame's are.
const SAMPLES: Array[Vector2] = [
    Vector2(20, 20),
    Vector2(220, 60),
    Vector2(120, 200),
    Vector2(30, 120),
    Vector2(230, 230),
    Vector2(60, 40),
]
## Long enough per dab that a few spans run past the frame's share.
const DAB_USEC: int = 300

var _surface: SaSurface = null
var _machine: ToolMachine = null


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    if DirAccess.dir_exists_absolute(scratch_dir):
        for file_name: String in DirAccess.get_files_at(scratch_dir):
            DirAccess.remove_absolute(scratch_dir.path_join(file_name))
        DirAccess.remove_absolute(scratch_dir)


## The places a walk of [constant SAMPLES] lays its dabs at, through a budget
## ticked once before each take when *framed*, and never otherwise.
func _walked(framed: bool) -> Dictionary:
    var budget := SaWalkBudget.new()
    var curve := SaStrokeCurve.new()
    var distance := SaStrokeDistance.new()
    var spacing := SaStrokeDistance.Spacing.new()
    var laid: Array[Vector2] = []
    var stamp := func(at: Vector2, _pressure: float, _tilt: Vector2) -> void:
        laid.append(at)
        distance.register_dab(at, spacing)
        OS.delay_usec(DAB_USEC)
    var sample := func(at: Vector2, pressure: float, tilt: Vector2) -> SaStrokeCurve.Span:
        if curve.is_empty():
            curve.begin(at, pressure, tilt)
            return null
        return curve.feed(at, pressure, tilt, 0.0)
    var takes := 0
    var short_takes := 0
    if framed:
        budget.frame()
    for at in SAMPLES:
        budget.push(at, 0.8, Vector2.ZERO)
        if not budget.take(sample, distance, stamp):
            short_takes += 1
    takes += 1
    while framed and not budget.take(sample, distance, stamp):
        budget.frame()
        takes += 1
    SaWalkBudget.walk(curve.finish(0.0), distance, stamp)
    return {"laid": laid, "takes": takes, "short": short_takes}


func test_a_carried_stroke_lays_every_dab_where_a_whole_walk_does() -> void:
    var whole := _walked(false)
    var carried := _walked(true)
    assert_eq(whole["short"], 0, "A budget never ticked walks every sample when it comes")
    assert_true(carried["takes"] > 2, "The ticked budget carried the stroke over %d frames" % carried["takes"])
    var laid_whole: Array[Vector2] = whole["laid"]
    var laid_carried: Array[Vector2] = carried["laid"]
    assert_true(laid_whole.size() > 300, "The scribble lays hundreds of dabs, %d here" % laid_whole.size())
    assert_eq(laid_carried.size(), laid_whole.size(), "Carried, the stroke lays as many dabs")
    var same := true
    for i in mini(laid_whole.size(), laid_carried.size()):
        same = same and laid_whole[i].is_equal_approx(laid_carried[i])
    assert_true(same, "and every one at the place the whole walk laid it")


func test_a_frame_stops_inside_a_span_near_its_share() -> void:
    var budget := SaWalkBudget.new()
    var distance := SaStrokeDistance.new()
    var spacing := SaStrokeDistance.Spacing.new()
    # The count and the longest dab, because a sleep is as long as the system's
    # timer makes it and not as long as it is asked to be.
    var seen: Array[int] = [0, 0]
    var stamp := func(at: Vector2, _pressure: float, _tilt: Vector2) -> void:
        var dab_started := Time.get_ticks_usec()
        distance.register_dab(at, spacing)
        OS.delay_usec(DAB_USEC)
        seen[0] += 1
        seen[1] = maxi(seen[1], Time.get_ticks_usec() - dab_started)
    var curve := SaStrokeCurve.new()
    curve.begin(Vector2(0, 0), 1.0, Vector2.ZERO)
    curve.feed(Vector2(1000, 0), 1.0, Vector2.ZERO, 0.0)
    var sample := func(at: Vector2, pressure: float, tilt: Vector2) -> SaStrokeCurve.Span:
        return curve.feed(at, pressure, tilt, 0.0)
    budget.frame()
    budget.push(Vector2(1000, 10), 1.0, Vector2.ZERO)
    var started := Time.get_ticks_usec()
    assert_false(budget.take(sample, distance, stamp), "One span of a thousand pixels does not fit a frame")
    var spent := Time.get_ticks_usec() - started
    assert_true(seen[0] >= 1, "The frame laid what fitted, %d dabs" % seen[0])
    assert_true(spent >= SaWalkBudget.FRAME_USEC, "and walked until its share was spent, %d us" % spent)
    assert_true(spent < SaWalkBudget.FRAME_USEC + seen[1] + 1000, "and no longer than one dab past it, %d us" % spent)
    var first := seen[0]
    assert_false(budget.take(sample, distance, stamp), "The same frame has no share left")
    assert_eq(seen[0], first, "and lays nothing more")
    budget.frame()
    budget.take(sample, distance, stamp)
    assert_true(seen[0] > first, "The next frame goes on inside the span")


func test_the_lift_waits_for_the_walk_and_a_hover_is_not_the_stroke() -> void:
    var budget := SaWalkBudget.new()
    var distance := SaStrokeDistance.new()
    var spacing := SaStrokeDistance.Spacing.new()
    var stamp := func(at: Vector2, _pressure: float, _tilt: Vector2) -> void:
        distance.register_dab(at, spacing)
        OS.delay_usec(DAB_USEC)
    var curve := SaStrokeCurve.new()
    curve.begin(Vector2(0, 0), 1.0, Vector2.ZERO)
    var sample := func(at: Vector2, pressure: float, tilt: Vector2) -> SaStrokeCurve.Span:
        return curve.feed(at, pressure, tilt, 0.0)
    budget.frame()
    budget.push(Vector2(800, 0), 1.0, Vector2.ZERO)
    budget.push(Vector2(800, 800), 1.0, Vector2.ZERO)
    budget.take(sample, distance, stamp)
    assert_true(budget.lift_later(), "A release with a walk carried is kept")
    assert_true(budget.lifting, "and says the pen is up, so a motion now is a hover")
    var frames := 0
    while not budget.take(sample, distance, stamp) and frames < 1000:
        budget.frame()
        frames += 1
    assert_true(budget.lifted(), "Once the walk is done the kept lift is due")
    assert_false(budget.lifted(), "once")
    assert_false(budget.lift_later(), "and a release with nothing carried lifts at once")


func test_a_budget_ticked_long_ago_walks_everything() -> void:
    var budget := SaWalkBudget.new()
    var distance := SaStrokeDistance.new()
    var spacing := SaStrokeDistance.Spacing.new()
    var stamp := func(at: Vector2, _pressure: float, _tilt: Vector2) -> void:
        distance.register_dab(at, spacing)
        OS.delay_usec(DAB_USEC)
    var curve := SaStrokeCurve.new()
    curve.begin(Vector2(0, 0), 1.0, Vector2.ZERO)
    var sample := func(at: Vector2, pressure: float, tilt: Vector2) -> SaStrokeCurve.Span:
        return curve.feed(at, pressure, tilt, 0.0)
    budget.frame()
    OS.delay_usec(SaWalkBudget.STALE_USEC + 10000)
    budget.push(Vector2(300, 0), 1.0, Vector2.ZERO)
    budget.push(Vector2(300, 300), 1.0, Vector2.ZERO)
    assert_true(budget.take(sample, distance, stamp), "No frame came for a quarter of a second, so nothing is carried")


## The brush itself, ticked as the tool machine ticks it: a 2 px Pencil's long
## flick is carried past the release, the stroke stays open until the walk is
## done, and it ends with the dabs and the one history step a brush that is
## never ticked leaves.
func test_a_ticked_brush_commits_the_carried_stroke_whole() -> void:
    var untouched := _flick(false)
    var ticked := _flick(true)
    assert_true(untouched["dabs"] > 1000, "The flick lays over a thousand dabs, %d" % untouched["dabs"])
    assert_true(ticked["open_after_release"], "The ticked brush was still walking after the release")
    assert_true(ticked["ticks"] > 1, "over %d frames" % ticked["ticks"])
    assert_eq(ticked["dabs"], untouched["dabs"], "and laid the same dabs in the end")
    assert_eq(ticked["steps"], untouched["steps"], "with one history step, as the brush never ticked")


func _flick(framed: bool) -> Dictionary:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = Fixtures.make_surface(Vector2i(1024, 1024))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    var brush: Object = _machine.active_tool
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(brush.settings, ShippedPresetsScript)
    assert_true(store.apply_preset("Pencil", brush.settings), "Pencil loads")
    brush.settings.radius = 1.0 / 1024.0
    var doc := _surface.easel.document
    var steps_before: int = doc.history.step_count() if doc.history != null else 0
    var laid_before: int = brush.stroke_info.dab_index
    if framed:
        brush.tick(0.016)
    _surface.view.mouse_position = Vector2(40, 40)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    brush.handle_input(press)
    for at: Vector2 in [Vector2(900, 60), Vector2(500, 900), Vector2(60, 500), Vector2(950, 950)]:
        var motion := InputEventMouseMotion.new()
        motion.pressure = 0.8
        _surface.view.mouse_position = at
        brush.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    brush.handle_input(release)
    var open_after_release: bool = brush.is_drawing
    var ticks := 0
    while brush.is_drawing and ticks < 2000:
        brush.tick(0.016)
        ticks += 1
    var steps: int = doc.history.step_count() - steps_before if doc.history != null else -1
    return {
        "dabs": brush.stroke_info.dab_index - laid_before if not brush.is_drawing else -1,
        "open_after_release": open_after_release,
        "ticks": ticks,
        "steps": steps,
    }
