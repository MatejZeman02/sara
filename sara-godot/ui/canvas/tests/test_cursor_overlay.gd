## Tests for the software cursor policy.
##
## The invariant under test: the OS cursor is hidden only where a replacement is
## actually drawn. The previous design hid it process-wide and relied on a single
## overlay that reparented into whatever Window was under the pointer, so closing
## a transient window (a FileDialog frees itself) destroyed the overlay and left
## no pointer at all for the rest of the session.
extends "res://tests/test_framework.gd"


## "draw nothing and hide the OS cursor" must stay unrepresentable, and the
## arrow outcome for a pen does not change that: every radius, including nonsense ones and
## with a tablet either side of the pointer, resolves to something that draws or
## to the system cursor.
func test_every_radius_resolves_to_a_visible_pointer() -> void:
    var radii: Array[float] = [-1.0, -0.001, 0.0, 0.5, 1.0, 12.0, 4096.0, INF, -INF, NAN]
    for radius in radii:
        for tablet: bool in [false, true]:
            for allowed: bool in [false, true]:
                var kind := CursorOverlay.resolve_cursor(radius, tablet, allowed)
                assert_true(
                    kind == &"ring" or kind == &"pointer" or kind == &"system",
                    "radius %s tablet %s resolved to '%s', which draws no pointer" % [radius, tablet, kind]
                )


func test_negative_radius_means_the_os_cursor_is_used() -> void:
    assert_eq(CursorOverlay.resolve_cursor(-1.0), &"system", "No ring requested should leave the OS cursor")
    assert_eq(CursorOverlay.resolve_cursor(10.0), &"ring", "A requested ring should be drawn")


## NAN fails every comparison, so it must fall through to the OS cursor rather
## than claiming a ring will be drawn.
func test_nan_radius_falls_back_to_the_os_cursor() -> void:
    assert_eq(CursorOverlay.resolve_cursor(NAN), &"system", "A NAN radius must not claim a ring")


## attach_to must be idempotent: it runs from Main._ready and from every docker's
## setup, and windows are re-entered as dockers are shown and hidden.
##
## The Window is deliberately never added to the scene tree, adding one maps a
## real OS window, which stalls a headless run.
func test_attach_to_is_idempotent() -> void:
    var window := Window.new()

    var first := CursorOverlay.attach_to(window)
    var second := CursorOverlay.attach_to(window)
    assert_not_null(first, "attach_to should create an overlay")
    assert_eq(first, second, "attach_to should reuse the existing overlay")

    var overlays := 0
    for child in window.get_children():
        if child is CursorOverlay:
            overlays += 1
    assert_eq(overlays, 1, "A window should never accumulate overlays")

    window.free()


func test_attach_to_null_window_is_safe() -> void:
    assert_null(CursorOverlay.attach_to(null), "attach_to(null) should not crash or create a node")


## The hide decision and the draw decision must read the pointer from one place.
##
## They used not to: sync_os_cursor_visibility() asked the viewport while the
## overlay asked the display server, and the two could disagree about which
## canvas the pointer was over, one hiding the cursor while the other drew
## nothing.
func test_pointer_in_window_is_safe_without_a_window() -> void:
    var pos := SaCursorPolicy.pointer_in_window(null)
    assert_true(pos.x < 0.0 and pos.y < 0.0, "No window must yield an off-canvas pointer, never a plausible one")


## The escape hatch must always end with a usable pointer, whatever else is true.
func test_never_setting_always_restores_the_os_cursor() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var previous: String = SaSettings.software_cursor
    var previous_mode := Input.get_mouse_mode()

    SaSettings.software_cursor = "never"
    Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
    SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(Input.get_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "software_cursor=never must restore the OS pointer")

    SaSettings.software_cursor = previous
    Input.set_mouse_mode(previous_mode)


## A gesture that moves the mouse without meaning to move the cursor pins
## where the application thinks the pointer is, and everything that asks reads
## the same frozen answer.
func test_a_pinned_pointer_is_what_every_reader_gets() -> void:
    var window := Window.new()
    var owner := Node.new()

    SaCursorPolicy.pin_pointer(owner, window, Vector2(320.0, 240.0))
    assert_true(SaCursorPolicy.pointer_is_pinned(), "The pin is on")
    assert_eq(SaCursorPolicy.pointer_in_window(window), Vector2(320.0, 240.0), "and the window reads the pinned point")

    SaCursorPolicy.unpin_pointer(owner)
    assert_false(SaCursorPolicy.pointer_is_pinned(), "Dropping it puts the OS pointer back in charge")
    owner.free()
    window.free()


## Sara runs one ToolMachine per paintable surface, and each drops a pin it does
## not hold every frame. Without the owner check the idle one unpinned the
## gesture the other was in the middle of, on the very next frame.
func test_only_the_holder_can_drop_the_pin() -> void:
    var window := Window.new()
    var holder := Node.new()
    var bystander := Node.new()

    SaCursorPolicy.pin_pointer(holder, window, Vector2(10.0, 10.0))
    SaCursorPolicy.unpin_pointer(bystander)
    assert_true(SaCursorPolicy.pointer_is_pinned(), "Somebody else's unpin is not this one's")
    SaCursorPolicy.unpin_pointer(holder)
    assert_false(SaCursorPolicy.pointer_is_pinned(), "The holder's is")

    SaCursorPolicy.unpin_pointer(holder)
    assert_false(SaCursorPolicy.pointer_is_pinned(), "and dropping it twice is harmless")
    holder.free()
    bystander.free()
    window.free()


## A pin cannot outlive what it belongs to, or a freed gesture leaves a cursor
## frozen for the rest of the session.
func test_a_pin_dies_with_its_holder() -> void:
    var window := Window.new()
    var holder := Node.new()
    SaCursorPolicy.pin_pointer(holder, window, Vector2(10.0, 10.0))
    holder.free()
    assert_false(SaCursorPolicy.pointer_is_pinned(), "The holder is gone, so the pin is")
    window.free()


## The arrow outcome, and the two conditions it is under. A pen over the UI
## gets an arrow, a mouse over the UI gets the OS cursor, and the ring is decided
## before either because it was never about the device.
func test_a_tablet_over_the_ui_draws_an_arrow_and_a_mouse_does_not() -> void:
    assert_eq(CursorOverlay.resolve_cursor(-1.0, true, true), &"pointer", "A pen over the UI is drawn")
    assert_eq(CursorOverlay.resolve_cursor(-1.0, false, true), &"system", "A mouse over the UI is the OS cursor")
    assert_eq(CursorOverlay.resolve_cursor(-1.0, true, false), &"system", "and so is a pen the policy said no to")
    assert_eq(CursorOverlay.resolve_cursor(12.0, true, true), &"ring", "Over a canvas the ring wins, pen or not")
    assert_eq(CursorOverlay.resolve_cursor(12.0, false, false), &"ring", "whatever else is true")


## The heuristic that tells a pen from a mouse, which is the same one
## `state_brush.gd` has used since F5 because Godot's Wayland driver reports
## every pointer as device 0 and there is nothing else to ask.
func test_pressure_tilt_or_the_eraser_end_means_a_tablet() -> void:
    for field: String in ["pressure", "tilt", "inverted"]:
        SaCursorPolicy.forget_pointer_device()
        assert_false(SaCursorPolicy.pointer_is_tablet, "Nothing seen yet is not a tablet")
        var motion := InputEventMouseMotion.new()
        match field:
            "pressure":
                motion.pressure = 0.4
            "tilt":
                motion.tilt = Vector2(0.2, -0.3)
            _:
                motion.pen_inverted = true
        SaCursorPolicy.note_pointer_device(motion)
        assert_true(SaCursorPolicy.pointer_is_tablet, "%s says a pen is on the tablet" % field)
    SaCursorPolicy.forget_pointer_device()


## One plain motion is not a mouse: a pen hovering reports nothing either. It
## takes a streak, which is why the number is a constant with a name.
func test_a_streak_of_plain_motions_is_what_makes_it_a_mouse_again() -> void:
    SaCursorPolicy.forget_pointer_device()
    var pen := InputEventMouseMotion.new()
    pen.pressure = 0.9
    SaCursorPolicy.note_pointer_device(pen)

    var plain := InputEventMouseMotion.new()
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK:
        SaCursorPolicy.note_pointer_device(plain)
        assert_true(SaCursorPolicy.pointer_is_tablet, "Still a pen after %d quiet motions" % (i + 1))
    SaCursorPolicy.note_pointer_device(plain)
    assert_false(SaCursorPolicy.pointer_is_tablet, "and a mouse one motion past the streak")
    SaCursorPolicy.forget_pointer_device()


## Anything that is not a motion is not evidence either way. A click carries no
## pressure field, and reading one as a plain motion would count a pen's own
## clicks towards calling it a mouse.
func test_only_a_motion_says_anything_about_the_device() -> void:
    SaCursorPolicy.forget_pointer_device()
    var pen := InputEventMouseMotion.new()
    pen.pressure = 0.9
    SaCursorPolicy.note_pointer_device(pen)
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK + 5:
        SaCursorPolicy.note_pointer_device(InputEventMouseButton.new())
        SaCursorPolicy.note_pointer_device(InputEventKey.new())
    assert_true(SaCursorPolicy.pointer_is_tablet, "Clicks and keys leave the answer alone")
    SaCursorPolicy.forget_pointer_device()


## The escape hatch covers the new outcome too, or "never" would keep the OS
## cursor and draw an arrow beside it.
func test_the_never_setting_refuses_the_software_pointer() -> void:
    var previous: String = SaSettings.software_cursor
    var pen := InputEventMouseMotion.new()
    pen.pressure = 0.7
    SaCursorPolicy.note_pointer_device(pen)
    var window := Window.new()
    window.size = Vector2i(400, 300)

    SaSettings.software_cursor = "never"
    assert_false(SaCursorPolicy.wants_software_pointer(window, Vector2(10, 10)), "never means never")

    SaSettings.software_cursor = previous
    SaCursorPolicy.forget_pointer_device()
    window.free()


## A window nobody is pointing at draws nothing, or every overlay in the process
## would claim the pointer and the OS cursor would be hidden for a window on the
## other side of the screen.
func test_a_pointer_outside_the_window_wants_nothing() -> void:
    var pen := InputEventMouseMotion.new()
    pen.pressure = 0.7
    SaCursorPolicy.note_pointer_device(pen)
    var window := Window.new()
    window.size = Vector2i(400, 300)
    assert_false(SaCursorPolicy.wants_software_pointer(window, Vector2(-40, 10)), "Left of it is not in it")
    assert_false(SaCursorPolicy.wants_software_pointer(window, Vector2(10, 900)), "Below it is not in it")
    assert_false(SaCursorPolicy.wants_software_pointer(null, Vector2(10, 10)), "and no window is not a crash")
    SaCursorPolicy.forget_pointer_device()
    window.free()


## The window rectangle every case below measures against: a 1920 by 1048
## viewport with the pointer in the middle of it, which is what the scenario
## shoots.
const WINDOW := Rect2(Vector2.ZERO, Vector2(1920.0, 1048.0))
const MIDDLE := Vector2(960.0, 524.0)

## What a span's end may exceed TAU by and still be inside one turn.
##
## **A `Vector2` holds two float32s and TAU is a float64.** A span built as
## `Vector2(lo, TAU)` reads back as 6.2831855, which is larger than the TAU it
## was given, so `span.y <= TAU` is false for a span that ends exactly on the
## turn. It costs the drawing nothing, the last point of the arc landing a
## millionth of a pixel from the first, and it costs a test that compares to TAU
## an epsilon. Written down because the number looks like a bug.
const TURN_EPSILON: float = 1e-5


## A ring smaller than the distance to the nearest edge is whole, and is one
## span of a full turn.
func test_a_small_ring_is_one_whole_turn() -> void:
    var spans := CursorOverlay.visible_ring_spans(MIDDLE, 20.0, WINDOW)
    assert_eq(spans.size(), 1, "One span")
    assert_almost_eq(spans[0].x, 0.0, 1e-6, "from zero")
    assert_almost_eq(spans[0].y, TAU, 1e-4, "to a full turn")


## A ring past every corner is not visible at all, which is the case that used
## to cost forty-eight segments of nothing.
##
## **The geometry, not a cap.** With the pointer in the middle of a 1920 by 1048
## window the farthest corner is 1093.7 pixels away, so a circle of radius 20000
## centred there passes nowhere near the window.
func test_a_ring_past_the_window_has_no_visible_arc() -> void:
    assert_eq(CursorOverlay.visible_ring_spans(MIDDLE, 20000.0, WINDOW).size(), 0, "Twenty thousand is off screen")
    assert_eq(CursorOverlay.visible_ring_spans(MIDDLE, 3000.0, WINDOW).size(), 0, "and so is three thousand")

    var corner := MIDDLE.distance_to(Vector2.ZERO)
    assert_almost_eq(corner, 1093.7, 0.1, "The farthest corner is %.1f away" % corner)
    assert_eq(CursorOverlay.visible_ring_spans(MIDDLE, corner + 1.0, WINDOW).size(), 0, "One pixel past it shows nothing")
    assert_eq(
        CursorOverlay.visible_ring_spans(MIDDLE, corner - 1.0, WINDOW).size(),
        4,
        "and one pixel inside it shows four corner slivers"
    )


## **The case the clipping has to get right.** A ring taller than the window
## crosses it as two arcs, one at each side, and one span across them both would
## draw a chord over the canvas.
func test_a_ring_taller_than_the_window_crosses_it_as_two_arcs() -> void:
    var spans := CursorOverlay.visible_ring_spans(MIDDLE, 700.0, WINDOW)
    # Three rather than two, because the right-hand arc runs across angle zero
    # and every span here is forwards and inside one turn: it arrives as the
    # piece before the turn and the piece after nought. Two polylines meeting at
    # zero draw as one arc, and the alternative is a span whose end is smaller
    # than its start, which every reader of the pair would have to know about.
    assert_eq(spans.size(), 3, "Three spans, the right-hand arc cut at zero")

    var covered := 0.0
    for span: Vector2 in spans:
        covered += span.y - span.x
        assert_true(span.y > span.x, "each running forwards, %s" % span)
        assert_true(span.x >= 0.0 and span.y <= TAU + TURN_EPSILON, "and inside one turn, %s" % span)
    assert_almost_eq(covered, 3.384, 0.01, "Just over half the circle is on screen, %.3f of it" % covered)

    # A span's middle is inside the window and so is a point just inside each of
    # its ends. That is what says these are the visible set rather than any
    # three arcs of the right total length.
    for span: Vector2 in spans:
        var middle := MIDDLE + Vector2(cos((span.x + span.y) * 0.5), sin((span.x + span.y) * 0.5)) * 700.0
        assert_true(WINDOW.has_point(middle), "The middle of %s is inside the window, at %s" % [span, middle])
        for angle: float in [span.x + 1e-3, span.y - 1e-3]:
            var near_end := MIDDLE + Vector2(cos(angle), sin(angle)) * 700.0
            assert_true(WINDOW.has_point(near_end), "and so is a point just inside its end, at %s" % near_end)

    # And the gaps are outside it, which is the half a chord would have covered.
    for angle: float in [PI * 0.5, PI * 1.5]:
        var gap := MIDDLE + Vector2(cos(angle), sin(angle)) * 700.0
        assert_false(WINDOW.has_point(gap), "The top and the bottom of the ring are off screen, %s" % gap)
        assert_false(_spans_cover(spans, angle), "and no span claims them")


## Off the window's own middle the arcs are not symmetric, which a shortcut
## measuring one edge would get wrong.
func test_a_ring_off_centre_is_clipped_where_it_actually_leaves() -> void:
    var high := Vector2(960.0, 120.0)
    var spans := CursorOverlay.visible_ring_spans(high, 400.0, WINDOW)
    assert_true(spans.size() >= 1, "Something is visible")

    var covered := 0.0
    for span: Vector2 in spans:
        covered += span.y - span.x
    assert_true(covered > 0.0 and covered < TAU, "and it is part of the circle, %.3f of it" % covered)

    # The pointer is 120 from the top edge and 928 from the bottom one, so the
    # arc above it is gone and the one below it is whole.
    assert_true(WINDOW.has_point(high + Vector2(0.0, 400.0)), "The bottom of the ring is on screen")
    assert_false(WINDOW.has_point(high + Vector2(0.0, -400.0)), "and its top is not")
    assert_true(_spans_cover(spans, PI * 0.5), "so the downward point is in a span")
    assert_false(_spans_cover(spans, PI * 1.5), "and the upward one is not")


## The segment count follows the visible arc rather than the radius, so a ring
## ten times the screen costs what its visible sliver costs and no more.
func test_the_cost_follows_the_visible_arc_rather_than_the_radius() -> void:
    assert_eq(_segment_count(MIDDLE, 20.0), 21, "A 20 pixel ring draws 21 segments")
    assert_eq(_segment_count(MIDDLE, 20000.0), 0, "A 20000 pixel one draws none, because none of it is on screen")
    assert_eq(_segment_count(MIDDLE, 3000.0), 0, "and neither does a 3000 pixel one")

    # **The peak, swept rather than argued.** The most expensive ring is the
    # largest one still whole, which is half the window's shorter side, 524
    # here, and its whole circumference over the six pixel chord is 549
    # segments. Every larger ring is partly off screen and draws less. The old
    # fixed count was 48 at every radius, so the largest brush a painter uses
    # costs about eleven times what it did and the largest ring there is costs
    # nothing.
    var worst := 0
    var worst_at := 0
    for radius in range(1, 2400, 7):
        var count := _segment_count(MIDDLE, float(radius))
        if count > worst:
            worst = count
            worst_at = radius
    assert_true(worst <= 560, "The most any radius draws is %d segments, at a radius of %d" % [worst, worst_at])
    assert_true(worst_at < 600, "and the peak is the largest whole ring rather than the largest ring, at %d" % worst_at)


## A radius that is not a number, and a window with no area, draw nothing rather
## than asking the draw loop for a million points.
func test_a_nonsense_radius_or_window_draws_nothing() -> void:
    assert_eq(CursorOverlay.visible_ring_spans(MIDDLE, NAN, WINDOW).size(), 0, "A NaN radius is no arc")
    assert_eq(CursorOverlay.visible_ring_spans(MIDDLE, INF, WINDOW).size(), 0, "nor is an infinite one")
    assert_eq(CursorOverlay.visible_ring_spans(MIDDLE, -5.0, WINDOW).size(), 0, "nor a negative one")
    assert_eq(CursorOverlay.visible_ring_spans(MIDDLE, 0.0, WINDOW).size(), 0, "nor a radius of nothing")
    assert_eq(CursorOverlay.visible_ring_spans(MIDDLE, 20.0, Rect2()).size(), 0, "A window with no area shows no arc")


## Whether *angle* falls inside any of *spans*.
static func _spans_cover(spans: Array[Vector2], angle: float) -> bool:
    for span: Vector2 in spans:
        if angle >= span.x and angle <= span.y:
            return true
    return false


## How many segments the whole visible ring is drawn with, across every span.
static func _segment_count(center: Vector2, radius: float) -> int:
    var total := 0
    for span: Vector2 in CursorOverlay.visible_ring_spans(center, radius, WINDOW):
        total += int(ceil((span.y - span.x) * radius / SaRingClip.RING_SEGMENT_PX))
    return total


## Under XWayland a pen moves the window's events and not the X pointer that
## `DisplayServer.mouse_get_position` reads, so the ring stood still while the
## pen painted and showed only while the shift drag pinned it. While a tablet is what
## moves the pointer, the last motion event in a window is where the pointer is.
func test_a_pens_pointer_is_where_its_last_motion_was() -> void:
    SaCursorPolicy.forget_pointer_device()
    var window := Window.new()
    var owner := Node.new()
    var pressed := InputEventMouseMotion.new()
    pressed.pressure = 0.5
    pressed.position = Vector2(101.5, 83.25)
    SaCursorPolicy.note_pointer_device(pressed, window)
    assert_eq(SaCursorPolicy.pointer_in_window(window), Vector2(101.5, 83.25), "The pointer is the pen's last event")

    # The tip lifts before the pen hovers, since a plain motion while it is down is not the pen's.
    var lift := InputEventMouseButton.new()
    lift.button_index = MOUSE_BUTTON_LEFT
    lift.position = pressed.position
    SaCursorPolicy.note_pointer_device(lift, window)
    var hover := InputEventMouseMotion.new()
    hover.position = Vector2(120.0, 90.0)
    SaCursorPolicy.note_pointer_device(hover, window)
    assert_eq(SaCursorPolicy.pointer_in_window(window), Vector2(120.0, 90.0), "A hover with no pressure moves it too")

    SaCursorPolicy.pin_pointer(owner, window, Vector2(5.0, 5.0))
    assert_eq(SaCursorPolicy.pointer_in_window(window), Vector2(5.0, 5.0), "A pin still outranks the pen")
    SaCursorPolicy.unpin_pointer(owner)
    assert_eq(SaCursorPolicy.pointer_in_window(window), Vector2(120.0, 90.0), "and the pen is back once it is dropped")

    SaCursorPolicy.forget_pointer_device()
    owner.free()
    window.free()
