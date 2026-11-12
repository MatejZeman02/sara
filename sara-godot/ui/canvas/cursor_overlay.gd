## Software cursor drawn on top of a single Window.
##
## Why this exists
## ---------------
## GNOME/Wayland does not move the hardware cursor for tablet pen input, so the
## pointer appears frozen while painting. Drawing the cursor ourselves fixes that,
## but only where we actually draw it.
##
## The invariant
## -------------
## The OS cursor is hidden ONLY while a replacement is guaranteed to be drawn.
## Everywhere else the OS cursor stays visible. Hiding it process-wide and
## relying on one overlay that reparents itself into whatever Window is under
## the pointer leaves no pointer at all once a transient window closes, because
## a FileDialog frees itself on close and takes the overlay with it.
##
## A replacement is guaranteed in two cases: the pointer is inside a canvas
## whose tool wants a brush ring, **or** a tablet tool is what is moving the
## pointer, in which case an arrow is drawn wherever the pointer is inside a
## window that has an overlay. Godot's Wayland driver sets the mouse pointer's
## cursor and not the tablet tool's, so without the arrow a pen has no cursor
## anywhere over the UI.
##
## `SaCursorPolicy.wants_software_pointer` and `resolve_cursor` are the same
## question asked twice in the same tick, and the policy answers no over any
## embedded window with no overlay in it. There the OS cursor stays, and under
## Wayland a pen has none, which is better than hiding a pointer with nothing in
## its place. `SaCursorPolicy.pointer_is_over_embedded_window` counts a window's
## internal children, because a `PopupMenu` is an internal child of its owner,
## and a menu opening across the canvas would otherwise read as the canvas and
## lose the pointer under a ring drawn beneath the menu.
##
## Few windows go without an overlay. An open `SaChoicePopup` attaches one of
## its own and takes it off when it closes, and `WindowWatch` below attaches one
## to every window that enters the tree and takes the pointer, the engine's
## menus and Sara's bare popups alike. What is left is a window opened ahead of
## Main.
##
## One overlay is attached per Window, because a Control cannot draw outside its
## own viewport. Overlays never move between windows.
extends Control

class_name CursorOverlay

## Half-length of the centre crosshair arms, in logical pixels.
const CROSS_LEN: float = 4.0
const RING_MIN_RADIUS: float = 2.0

## How many draws the reported cost is averaged over.
##
## One `_draw` offscreen is a handful of microseconds and the noise between two
## of them is larger than the difference being measured, so the dump reports
## a mean. Sixty is one second at the frame rate the pacer aims for, which is
## long enough to be steady and short enough that a radius change is in the
## number by the time the next `wait` ends.
const DRAW_SAMPLES: int = 60
const COLOR_INK: Color = Color(1.0, 1.0, 1.0, 1.0)

## The arrow's outline, in logical pixels from the hot point at its tip.
##
## The shape every desktop draws, seven points: straight down the left edge, in
## to the notch, out along the tail, back up the other side of the tail, and
## across the shoulder. Written out rather than computed from a width and a
## height, because the tail is what makes it read as a pointer and no two of its
## numbers are a ratio of the others.
static var _arrow_outline := PackedVector2Array(
    [
        Vector2(0.0, 0.0),
        Vector2(0.0, 14.5),
        Vector2(3.6, 11.0),
        Vector2(6.2, 16.4),
        Vector2(8.4, 15.4),
        Vector2(5.7, 10.2),
        Vector2(10.2, 10.2),
    ]
)
const COLOR_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.5)

var _last_pos: Vector2 = Vector2(-1.0, -1.0)
var _last_ring: float = -1.0
var _state_valid: bool = false
## Whether the last draw put the ring anywhere but on the pointer, which is the
## lead a pointer coming to rest still owes one more draw to take back.
var _ring_led: bool = false

## The process frames of the ring's journey from an event to the screen: the
## frame the last motion arrived in, the frame whose step asked for a redraw of
## a moved pointer, and the frame the ring was last drawn in, with where.
##
## They answer whether the ring falls behind the system pointer by a frame of
## Sara's: the three are the
## same number when the ring is drawn in the frame its event arrives, which is
## what a suite holds and the scenario reads from the running app. -1 before the
## first of each.
var _event_frame: int = -1
var _redraw_frame: int = -1
var _drawn_frame: int = -1
var _drawn_at: Vector2 = Vector2(-1.0, -1.0)

## Whether the motion an overlay is pushing to let the pen go is in flight, so
## no overlay's `_input` reads it as the pen's. Static, because it goes to the
## window that embeds the overlay's own, whose overlay hears it as well.
static var _letting_go: bool = false

## Where the ring goes against where the pointer is.
##
## Fed once a frame from `_process` and read by `_draw_body`, so the point that
## is drawn and the point the dump reports are the same reading. The arithmetic
## is `SaCursorPrediction`'s, in its own file, because none of it is about
## drawing and a suite has to be able to feed it a known speed: Wayland will not
## let a capture move the pointer, so the only way to prove a lead is to hand
## the predictor the samples a moving pointer would have produced.
var prediction: SaCursorPrediction = SaCursorPrediction.new()


## Adds an overlay to `window` unless it already has one. Safe to call repeatedly.
static func attach_to(window: Window) -> CursorOverlay:
    if window == null:
        return null
    var existing := window.get_node_or_null("CursorOverlay") as CursorOverlay
    if existing != null:
        return existing
    var overlay := CursorOverlay.new()
    overlay.name = "CursorOverlay"
    window.add_child(overlay)
    # The tool's own picture is sized by the policy under `render`, which
    # cannot ask `SaUI`, so the overlay that stands beside it says the edge.
    SaCursorPolicy.tool_cursor_edge = SaUI.px(SaCursorPolicy.TOOL_CURSOR_EDGE)
    return overlay


## Whether *window* is one the pointer can be over, which every window is but
## one the pointer passes through. The engine's tooltip is such a window, and an
## arrow drawn in it would be drawn over the arrow of the window beneath it.
static func takes_pointer(window: Window) -> bool:
    return window != null and not window.mouse_passthrough


## Hears every `Window` enter the tree and attaches an overlay to one that takes
## the pointer and has none.
##
## A popup is a window of its own, so the overlay of the dialog it opens over
## stops hearing motions the moment the pointer enters it, and a bare popup
## would leave the pen's arrow frozen on the swatch that opened it. The modules
## may not name this file, so `ui` hears them come in
## rather than each window asking.
##
## A node Main holds, so the watch ends with Main and a suite that builds one
## leaves no watch running behind it. Deferred to the frame's end, because a
## window entering the tree refuses a child and its flags may still be being
## set, the engine's own tooltip among them. By instance id, so a window freed
## before then is passed over.
class WindowWatch:
    extends Node

    var _pending: Array[int] = []

    func _enter_tree() -> void:
        if not get_tree().node_added.is_connected(_on_node_added):
            get_tree().node_added.connect(_on_node_added)

    func _exit_tree() -> void:
        if get_tree().node_added.is_connected(_on_node_added):
            get_tree().node_added.disconnect(_on_node_added)

    func _on_node_added(node: Node) -> void:
        if not node is Window or Engine.is_editor_hint():
            return
        if _pending.is_empty():
            settle.call_deferred()
        _pending.append(node.get_instance_id())

    ## Attaches the overlays the windows that came in since the last call are
    ## owed. The frame's end calls it, and a suite, which cannot reach one.
    func settle() -> void:
        var ids := _pending.duplicate()
        _pending.clear()
        for id: int in ids:
            var window := instance_from_id(id) as Window
            if window != null and window.is_inside_tree() and CursorOverlay.takes_pointer(window):
                CursorOverlay.attach_to(window)


## Pure decision function, kept free of node state so it can be unit tested.
##
## Returns one of: "ring" - draw the brush circle and crosshair. The OS cursor
## must be hidden "pointer" - draw an arrow. The OS cursor must be hidden "system"
## - draw nothing. The OS cursor is the pointer
##
## There is still no outcome for "draw nothing and hide the OS cursor". That is
## the state that made the pointer disappear for a whole session, and it stays
## unrepresentable: both of the first two draw.
##
## *tablet* is whether a pen rather than a mouse is moving the pointer, and
## *software_pointer_allowed* is the caller's answer to everything geometric and
## every setting, which is `SaCursorPolicy.arrow_drawn_in`. The ring
## ignores both, because it was never about the device and because
## `software_cursor` set to "never" has always drawn the ring and kept the OS
## cursor as well.
static func resolve_cursor(ring_radius: float, tablet: bool = false, software_pointer_allowed: bool = false) -> StringName:
    if ring_radius >= 0.0:
        return &"ring"
    return &"pointer" if tablet and software_pointer_allowed else &"system"


## Where every overlay in the tree is drawing its ring, for the capture harness.
##
## The claim to prove is that the ring did not move while the hand did, and the
## only thing that can answer it is the overlay itself: the state dump's pointer
## is the OS one, which is exactly the reading the pin overrides.
static func state_of(root: Window) -> Array:
    var out: Array = []
    if root == null:
        return out
    for node in root.find_children("*", "CursorOverlay", true, false):
        var overlay := node as CursorOverlay
        if overlay == null or not overlay.is_inside_tree():
            continue
        var window := overlay.get_window()
        var centre := overlay._pointer_position()
        var ring := SaCursorPolicy.cursor_ring_radius_at(window, centre)
        var drawn := overlay.drawn_centre(centre)
        var outline := overlay.cursor_outline_at(centre)
        var extent := Vector2.ZERO
        for point: Vector2 in outline:
            extent = Vector2(maxf(extent.x, absf(point.x)), maxf(extent.y, absf(point.y)))
        var allowed := SaCursorPolicy.arrow_drawn_in(window, centre)
        var drawn_as := resolve_cursor(ring, SaCursorPolicy.pointer_is_tablet, allowed)
        var worn := SaCursorPolicy.pen_picture_at(window, centre) if drawn_as == &"pointer" else null
        (
            out
            . append(
                {
                    "window": window.title if window != null else "<none>",
                    "centre": {"x": centre.x, "y": centre.y},
                    # Where the ring actually goes, and what put it there. The
                    # pointer's own point is `centre` above, so the lead is the
                    # difference and a scenario reads both rather than inferring
                    # one from the other.
                    "drawn_centre": {"x": drawn.x, "y": drawn.y},
                    "lead": {"x": drawn.x - centre.x, "y": drawn.y - centre.y},
                    "speed": overlay.prediction.speed(),
                    "predict_ms": SaCursorPrediction.latency_seconds() * 1000.0,
                    "moving": overlay.prediction.is_moving(),
                    # Whether the ring leads at all and why: the setting and
                    # what it resolves to on this machine.
                    "lead_mode": SaSettings.cursor_lead,
                    "lead_on": SaCursorPrediction.lead_enabled(),
                    "ring": ring,
                    # The shape the ring is drawn as, asked of the canvas rather
                    # than of the policy: `ring` above folds in the hovered
                    # Control and reads -1.0 for every point the real pointer is
                    # not at, which offscreen is every point. The count is zero
                    # for a circle and the extent says which way the tip is
                    # turned.
                    "outline_points": outline.size(),
                    "outline_extent": {"x": extent.x, "y": extent.y},
                    "drawn": String(drawn_as),
                    "tablet": SaCursorPolicy.pointer_is_tablet,
                    # The tool's picture a drawn pen pointer wears in place of
                    # the arrow, the Transform's `rotate`, empty for the arrow.
                    "picture": _picture_name(worn),
                    "pinned": SaCursorPolicy.pointer_is_pinned(),
                    # What the last draw cost and what it drew. The segments are
                    # the claim and the microseconds are the evidence for it: a
                    # ring past the window draws no segments, so it cannot cost
                    # what one inside it costs.
                    "ring_segments": overlay._last_segments,
                    "ring_spans": overlay._last_spans,
                    "overlay_size": {"x": overlay.size.x, "y": overlay.size.y},
                    "spans_now": visible_ring_spans(centre, ring, Rect2(Vector2.ZERO, overlay.size)).size(),
                    "draw_usec": overlay._mean_draw_usec(),
                    "draw_samples": overlay._draw_samples.size(),
                    # Whether the overlay steps at all, which is off while
                    # its window is hidden.
                    "window_shown": window.visible if window != null else false,
                    "stepping": overlay.is_processing(),
                    # The frame the last motion arrived in, the frame the
                    # ring was last drawn in and where. Equal frames are a ring
                    # drawn in the frame its event arrived.
                    "event_frame": overlay._event_frame,
                    "redraw_frame": overlay._redraw_frame,
                    "drawn_frame": overlay._drawn_frame,
                    "ring_drawn_at": {"x": overlay._drawn_at.x, "y": overlay._drawn_at.y},
                }
            )
        )
    return out


func _ready() -> void:
    name = "CursorOverlay"
    mouse_filter = MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_FULL_RECT)
    top_level = true
    z_as_relative = false
    z_index = 4096
    # The cursor state is *checked* every frame and *redrawn* only when it
    # changed. Those are very different costs: the check is a couple of rect
    # tests, while a redraw invalidates this full-window control.
    #
    # Driving it from motion events alone was wrong in both directions. The OS
    # cursor is hidden by whoever changes tool or brush size, but the ring was
    # only drawn on the next motion event, so between the two the pointer was
    # invisible, and a brush-size change did not resize the ring until the
    # mouse moved. Worse, a decision to hide taken while the pointer was over the
    # canvas was never revisited if the pointer then left the window or the
    # window resized underneath it, which left the pointer hidden process-wide
    # for the rest of the session.
    #
    # Checked only while the window is shown, as measured: the Filter
    # dialogs, the Message box and every closed docker keep an overlay, and each
    # hidden one asked for its ring every step at up to 120 microseconds for a
    # window nobody can see. `_follow_window` turns the step on as the window
    # shows and off as it hides.
    var window := get_window()
    if window != null:
        window.visibility_changed.connect(_follow_window)
    _follow_window()
    # On, and only to read: a motion event is what says whether a pen or a mouse
    # is moving the pointer, and this is the one node that sees every motion in a
    # window whether or not it is over a canvas. Nothing here marks an event
    # handled.
    set_process_input(true)
    SaCursorPolicy.register_overlay(self)


## Steps while the window is shown and not while it is hidden, and draws afresh
## on the first step after it shows, because the pointer and the ring it last
## saw belong to before the window went away.
func _follow_window() -> void:
    var window := get_window()
    var shown := window == null or window.visible
    if shown and not is_processing():
        _state_valid = false
    set_process(shown)


## Registers again on every entry, since `_ready` runs once and a window taken
## out of the tree and put back takes its overlay with it, and the policy asks
## the register which windows have one.
func _enter_tree() -> void:
    if is_node_ready():
        SaCursorPolicy.register_overlay(self)


func _exit_tree() -> void:
    SaCursorPolicy.unregister_overlay(self)


func _input(event: InputEvent) -> void:
    if _letting_go:
        return
    SaCursorPolicy.note_pointer_device(event, get_window())
    if event is InputEventMouseMotion:
        _event_frame = Engine.get_process_frames()
        prediction.note_pen(event as InputEventMouseMotion)


## Passes on the display server's word that the pointer left this window or came
## over it, which under Windows Ink is all a pen crossing onto a let-out docker
## that does not have the focus leaves behind. The engine sends both to every
## node of a window of its own and to no embedded one, and this is the node
## every window has. Sara losing the focus to another program and getting it
## back is passed on as well, for the pointer the policy hides.
func _notification(what: int) -> void:
    if not is_inside_tree():
        return
    if what == NOTIFICATION_WM_MOUSE_EXIT:
        SaCursorPolicy.note_pointer_left(get_window())
    elif what == NOTIFICATION_WM_MOUSE_ENTER:
        SaCursorPolicy.note_pointer_entered(get_window())
    elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        SaCursorPolicy.note_focus_out()
    elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
        SaCursorPolicy.note_focus_in()


## Lets the window's hover go once the pen has gone quiet out of range, which on
## Android is all its leaving says. The ring goes by itself, since the
## pen's place reads as nowhere, but the engine still believes the pointer is
## over the last Control the pen hovered, and a tooltip it opened stays over the
## canvas until a motion says otherwise. So a motion outside the window is
## pushed into it, which drops the hovered Control and the tooltip with it the
## way a mouse leaving does. No overlay reads it as the pen's, and the pen's
## next real motion hovers again.
##
## Into the window that embeds this one, when it is embedded, as every docker
## is on Android: an embedded window's hover is its embedder's to give and take,
## and a motion pushed into the docker itself leaves its row hovered. The
## engine keeps `get_embedder` to itself, so the walk is up the parents'
## viewports to the first window of its own.
func _let_the_pen_go() -> void:
    var host: Viewport = get_window()
    while host is Window and (host as Window).is_embedded() and host.get_parent() != null:
        host = host.get_parent().get_viewport()
    var gone := InputEventMouseMotion.new()
    gone.position = SaCursorPolicy.NOWHERE
    gone.global_position = SaCursorPolicy.NOWHERE
    _letting_go = true
    host.push_input(gone, true)
    _letting_go = false


func _process(_delta: float) -> void:
    if SaCursorPolicy.note_pen_silence(get_window(), Time.get_ticks_usec()):
        _let_the_pen_go()
    var pos := _pointer_position()
    # Once a frame and before anything reads the velocity, because the ring is
    # drawn per frame and the speed it is drawn with has to be measured over the
    # same clock. The pen's clock and not the wall's, for the reason
    # `SaPenClock` gives: a replay lays one move a frame, so how long a frame
    # took is how busy the machine was and not how fast the hand moved. Filmed
    # twice by `modules/sara-tutorials/lesson_videos.py`, a lesson read off the
    # wall drew its ring a pixel or two out over the 43 frames of a lesson's
    # longest stroke and the two films were not the same video. Outside a
    # capture the clock is the engine's, so a painter's ring is unchanged.
    prediction.sample(pos, SaPenClock.now_usec())
    var ring := SaCursorPolicy.cursor_ring_radius_at(get_window(), pos)

    # Re-evaluated every frame so a stale "hidden" cannot outlive the conditions
    # that justified it. This is the only thing that hides the OS cursor, and it
    # runs in the same tick as the redraw below, so the two cannot disagree. The
    # first overlay to step in a frame runs it for all of them, since the answer
    # is the same for every window.
    SaCursorPolicy.sync_os_cursor_visibility_this_frame()

    # A run of draws the capture step asked for, so a cost can be a mean rather
    # than one reading. Zero in the app, where a still pointer redraws nothing
    # and should not.
    if _forced_draws > 0:
        _forced_draws -= 1
        queue_redraw()
        return

    # A moving pointer redraws because `pos` moved. A pointer that has stopped
    # redraws once more, because the lead is falling to nothing and the ring has
    # to arrive on the pointer rather than staying where it was predicted to go.
    # That once more is `_ring_led`: without it, the frame the speed falls
    # under the rest threshold asks for nothing, and the ring stays a fraction
    # of a pixel along the stroke, by however far the last moving frame's clock
    # carried it, so two runs end a stroke with its edge a texel apart.
    var still := _state_valid and pos == _last_pos and is_equal_approx(ring, _last_ring)
    if not needs_redraw(still, prediction.is_moving(), _ring_led):
        return
    _last_pos = pos
    _last_ring = ring
    _state_valid = true
    _redraw_frame = Engine.get_process_frames()
    queue_redraw()


## Whether a step redraws: a pointer that moved or a ring that changed does,
## *still* false, and so does a pointer the prediction still calls *moving*.
## A pointer at rest whose last ring was drawn off it, *ring_led*, does once
## more, to take the lead back. Static, so the suite grades the rule without a
## frame to draw in.
static func needs_redraw(still: bool, moving: bool, ring_led: bool) -> bool:
    return not still or moving or ring_led


## Segments and spans the last draw put on screen, and what it cost, for the
## dump `state_of` builds. Not settings and not state: a reading.
var _last_segments: int = 0
var _last_spans: int = 0
var _draw_samples: PackedInt64Array = PackedInt64Array()

## Frames left in which to redraw whatever else happens, which only the capture
## step sets.
##
## `_process` queues a redraw when the pointer or the radius moves and not
## otherwise, which is the whole point of it: a still pointer costs nothing. A
## cost measured over one draw is noise, so the step that asks for a cost asks
## for a run of draws to average, and this is the counter it sets. Zero in the
## app, always.
var _forced_draws: int = 0


## Clears the samples and asks for *draws* more, which is what the capture
## step's ring cost measures over.
##
## A method rather than two writes from outside, because a class writes its own
## members only, and an overlay already in the tree has no constructor left to
## take them through.
func force_samples(draws: int) -> void:
    _draw_samples = PackedInt64Array()
    _forced_draws = draws
    queue_redraw()


## The mean of the last [constant DRAW_SAMPLES] draws, in microseconds, or -1
## while nothing has been drawn.
func _mean_draw_usec() -> float:
    if _draw_samples.is_empty():
        return -1.0
    var total: int = 0
    for sample: int in _draw_samples:
        total += sample
    return float(total) / float(_draw_samples.size())


func _draw() -> void:
    var started := Time.get_ticks_usec()
    _last_segments = 0
    _last_spans = 0
    _draw_body()
    _draw_samples.append(Time.get_ticks_usec() - started)
    if _draw_samples.size() > DRAW_SAMPLES:
        _draw_samples = _draw_samples.slice(_draw_samples.size() - DRAW_SAMPLES)


## Everything the draw actually does, so the timing above wraps one call rather
## than being threaded through three early returns.
func _draw_body() -> void:
    var pos := _pointer_position()
    var ring := SaCursorPolicy.cursor_ring_radius_at(get_window(), pos)
    var allowed := SaCursorPolicy.arrow_drawn_in(get_window(), pos)
    match resolve_cursor(ring, SaCursorPolicy.pointer_is_tablet, allowed):
        &"ring":
            # The ring leads and the arrow does not. The ring is what a painter
            # watches while the hand moves, and the arrow is what they look at
            # while they aim at a control, where a lead would put it past
            # whatever they are aiming for.
            _drawn_at = drawn_centre(pos)
            _drawn_frame = Engine.get_process_frames()
            _ring_led = _drawn_at != pos
            _draw_brush_cursor(_drawn_at, ring)
        &"pointer":
            _ring_led = false
            var picture := SaCursorPolicy.pen_picture_at(get_window(), pos)
            if picture != null and picture.texture != null:
                _draw_tool_picture(pos, picture)
            else:
                _draw_arrow_cursor(pos)
        _:
            _ring_led = false


## *picture*'s name for a dump, empty for none.
static func _picture_name(picture: SaCursorPicture) -> String:
    return String(picture.name) if picture != null else ""


## Where the ring is drawn for a pointer at *at*.
##
## The one place the prediction enters the drawing, so the dump and the frame
## cannot disagree about it: `state_of` calls this rather than adding the lead a
## second time. The lead is the learned one, and only while
## `SaSettings.cursor_lead` resolves to on: off, the ring sits on the pointer,
## which is what a hardware cursor beside it wants.
func drawn_centre(at: Vector2) -> Vector2:
    if not SaCursorPrediction.lead_enabled():
        return at
    return prediction.predicted_learned(at, SaCursorPrediction.latency_seconds(), SaCursorPrediction.view_at(get_window(), at))


## The OS pointer position mapped into this control's local space.
##
## DisplayServer.mouse_get_position() is sampled when the draw list is built,
## which is fresher than get_local_mouse_position(), the latter is frozen at
## the last input batch processed at frame start.
func _pointer_position() -> Vector2:
    var window := get_window()
    if window == null:
        return get_local_mouse_position()
    return SaCursorPolicy.pointer_in_window(window)


func _draw_brush_cursor(center: Vector2, radius: float) -> void:
    # Logical units: the window's content_scale_factor already scales this.
    var arm := CROSS_LEN
    var halo := arm + 1.0

    # Drawn as geometry rather than from a texture, so this path cannot fail the
    # way a missing icon file can.
    draw_line(center + Vector2(-halo, 0.0), center + Vector2(halo, 0.0), COLOR_SHADOW, 2.5)
    draw_line(center + Vector2(0.0, -halo), center + Vector2(0.0, halo), COLOR_SHADOW, 2.5)
    draw_line(center + Vector2(-arm, 0.0), center + Vector2(arm, 0.0), COLOR_INK, 1.0)
    draw_line(center + Vector2(0.0, -arm), center + Vector2(0.0, arm), COLOR_INK, 1.0)

    if radius <= RING_MIN_RADIUS:
        return

    # An image tip draws its own shape instead of the circle. The points come
    # from whatever the active tool published and are numbers in units of this
    # radius, so nothing here knows what a brush is: the file that knows what
    # they mean is the module's.
    var outline := cursor_outline_at(center)
    if outline.size() >= 3:
        _draw_outline(center, radius, outline)
        return

    # Only the arc inside the window, at a smoothness the radius earns.
    # `draw_arc` walks the whole circle at a fixed count whatever is on screen,
    # which is what made a ring past the window cost the same as one inside it.
    for span: Vector2 in visible_ring_spans(center, radius, _window_rect()):
        var points := SaRingClip.arc_points(center, radius, span.x, span.y)
        if points.size() < 2:
            continue
        _last_spans += 1
        _last_segments += points.size() - 1
        draw_polyline(points, COLOR_SHADOW, 2.0)
        draw_polyline(points, COLOR_INK, 1.0)


## The published outline placed at *center* and scaled to *radius*, closed by
## repeating its first point.
##
## Static and separate from the draw, because a `_draw` only runs inside a
## frame and this is the arithmetic worth asserting: a silhouette with a gap in
## it reads as a tip with a bite out of it.
static func outline_points(center: Vector2, radius: float, outline: PackedVector2Array) -> PackedVector2Array:
    if outline.size() < 3:
        return PackedVector2Array()
    var points := PackedVector2Array()
    points.resize(outline.size() + 1)
    for i in outline.size():
        points[i] = center + outline[i] * radius
    points[outline.size()] = points[0]
    return points


## The published outline scaled to *radius* and closed, or nothing when it falls
## entirely outside the window.
##
## Not clipped span by span the way the circle is: an outline is bounded by the
## same radius, so a shape far past the window is caught by one rectangle test
## rather than by the arc arithmetic needed for a ring of twenty thousand
## pixels. What a huge outline costs is its own point count, which is fixed.
func _draw_outline(center: Vector2, radius: float, outline: PackedVector2Array) -> void:
    if not _window_rect().intersects(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)):
        return
    var points := outline_points(center, radius, outline)
    _last_spans = 1
    _last_segments = points.size() - 1
    draw_polyline(points, COLOR_SHADOW, 2.0)
    draw_polyline(points, COLOR_INK, 1.0)


## The outline the canvas under *at* published, or empty for the circle.
##
## Asked of the canvas the same way the radius is, so a shape and the radius it
## is scaled by come from one place and cannot be read a frame apart.
func cursor_outline_at(at: Vector2) -> PackedVector2Array:
    return SaCursorPolicy.cursor_outline_at(get_window(), at)


## The arrow drawn for a tablet tool over the UI.
##
## Geometry rather than a texture, for the reason the ring is: this path cannot
## fail the way a missing icon file can, and it is the path that runs when the
## OS cursor is hidden. Shaped like the arrow every desktop draws, hot point at
## the top left corner where the pointer actually is, with the same dark halo the
## ring uses so it is readable over a light panel as well as a dark one.
func _draw_arrow_cursor(tip: Vector2) -> void:
    var body := PackedVector2Array()
    var ink := PackedColorArray()
    for point: Vector2 in _arrow_outline:
        body.append(tip + point)
        ink.append(COLOR_INK)
    var outline := PackedVector2Array(body)
    outline.append(body[0])
    draw_polygon(body, ink)
    # The same dark halo the ring carries, so the arrow is readable over a light
    # panel as well as over the canvas.
    draw_polyline(outline, COLOR_SHADOW, 1.5)


## The tool's own picture drawn for a pen in place of the arrow, the
## Transform's rotate arrow by a corner, its point on the pointer. The edge is
## the policy's logical one, because the window's content scale already turns
## this control's units into pixels, the way it does for the ring.
func _draw_tool_picture(tip: Vector2, picture: SaCursorPicture) -> void:
    var edge := Vector2.ONE * SaCursorPolicy.TOOL_CURSOR_EDGE
    draw_texture_rect(picture.texture, Rect2(tip - picture.hotspot * edge, edge), false)


## The rectangle the ring is clipped to, which is the window's and not this
## control's.
##
## **A `top_level` Control has a size of nothing.** This overlay sets
## `top_level = true` so it draws in window space rather than under its parent's
## transform, and the anchors it also sets are then never applied: `size` stays
## `(0, 0)` for the whole life of the node. `draw_arc` never asked, so nothing
## noticed until the clip did, and a ring drawn without it vanished
## entirely while the dump said `drawn: ring`. The window's own visible rect is both
## the right answer and the one `SaCursorPolicy.cursor_ring_radius_at` already
## measures the pointer against.
func _window_rect() -> Rect2:
    var window := get_window()
    if window == null:
        return Rect2(Vector2.ZERO, size)
    return Rect2(Vector2.ZERO, window.get_visible_rect().size)


## The angular spans of the ring inside *rect*, as `[from, to]` pairs in
## radians. `SaRingClip` owns the arithmetic, and it is kept here under the name
## every test and every reader already knows.
static func visible_ring_spans(center: Vector2, radius: float, rect: Rect2) -> Array[Vector2]:
    return SaRingClip.visible_ring_spans(center, radius, rect)


## Predicts each overlay's ring: it feeds every overlay the samples a pointer
## travelling a line in a time would have produced, then reports what each one
## would draw, `{"ring_predict": {"from": [x, y], "to": [x, y], "seconds": 0.2,
## "samples": 12}}`.
##
## The step exists because Wayland will not let a capture move the pointer, so
## the only reading of a lead available offscreen is the one the predictor
## itself gives when it is handed a known speed. What that proves is exactly the
## lead's claim, arithmetic included: the reported speed is the distance over
## the time, and the lead is that speed times the latency.
##
## `{"ring_predict": "rest"}` clears the gesture, so the next report is the
## still pointer's, which is the other half of the claim.
static func capture_ring_predict(tree: SceneTree, raw: Variant) -> String:
    if tree == null or tree.root == null:
        return "SaCapture: no tree to predict a ring in"
    var root := tree.root
    var overlays: Array[CursorOverlay] = []
    for node in root.find_children("*", "CursorOverlay", true, false):
        var overlay := node as CursorOverlay
        if overlay != null and overlay.is_inside_tree():
            overlays.append(overlay)
    if overlays.is_empty():
        return "SaCapture: no overlay to predict a ring in"

    if typeof(raw) != TYPE_DICTIONARY:
        for overlay in overlays:
            overlay.prediction.reset()
        return "SaCapture: ring_predict at rest"

    var spec := raw as Dictionary
    var from_raw := spec.get("from", [0, 0]) as Array
    var to_raw := spec.get("to", [0, 0]) as Array
    if from_raw == null or from_raw.size() < 2 or to_raw == null or to_raw.size() < 2:
        return "SaCapture: a ring_predict needs a 'from' and a 'to' of two numbers each"
    var from := Vector2(float(from_raw[0]), float(from_raw[1]))
    var to := Vector2(float(to_raw[0]), float(to_raw[1]))
    var seconds := maxf(float(spec.get("seconds", 0.2)), 0.001)
    var samples := maxi(int(spec.get("samples", 12)), 2)

    # The clock is the step's own rather than the wall's, because a capture
    # running a frame behind would otherwise measure the harness and not the
    # arithmetic. It starts far enough back that the first interval is the
    # step's own and not a gap since whatever moved the pointer last.
    var step_usec := int(seconds / float(samples - 1) * 1_000_000.0)
    for overlay in overlays:
        overlay.prediction.reset()
        var usec := Time.get_ticks_usec()
        for i in samples:
            overlay.prediction.sample(from.lerp(to, float(i) / float(samples - 1)), usec + step_usec * i)

    var asked := from.distance_to(to) / seconds
    var lines: Array[String] = []
    for entry: Dictionary in state_of(root):
        var lead: Dictionary = entry["lead"]
        (
            lines
            . append(
                (
                    (
                        "SaCapture: ring_predict window='%s' asked=%.1f speed=%.1f predict_ms=%.2f"
                        + " lead=(%.2f, %.2f) |lead|=%.2f moving=%s"
                    )
                    % [
                        entry["window"],
                        asked,
                        float(entry["speed"]),
                        float(entry["predict_ms"]),
                        float(lead["x"]),
                        float(lead["y"]),
                        Vector2(float(lead["x"]), float(lead["y"])).length(),
                        str(entry["moving"]),
                    ]
                )
            )
        )
    return "\n".join(lines)


## Times the ring's drawing: in three forms.
##
## `{"ring_cost": {"at": [x, y], "draws": 60}}` pins the pointer there for every
## overlay and asks each for that many timed draws, `{"ring_cost": "unpin"}`
## lets the pointer go, and any other value, `"read"` for one, reports one line
## per window: the ring's radius, the spans and segments it was drawn as, and
## the mean draw time over the samples taken.
##
## **Two calls with a `wait` between them**, because the number is a mean over
## the last [constant DRAW_SAMPLES] draws and a draw happens in `_process`
## rather than when this is called. The first call points the overlay at a place
## and throws the old samples away, the second reads what has accumulated since.
##
## The pointer is *pinned* as well as moved, and both are necessary. The
## position the overlay draws at is `DisplayServer.mouse_get_position`, which
## Wayland will not let a capture write, so the pin is the only way a scenario
## can say where the ring is. The motion is what moves
## `gui_get_hovered_control`, which `pointer_is_over_ui` reads and which decides
## whether the canvas is asked for a ring at all: pinned without the motion, the
## overlay believes the pointer is over whatever the hand last hovered, and
## offscreen that is the menu bar.
##
## The pin is held by the tree, which is what the step is handed and what every
## later step of the same run hands back, so the `unpin` releases the same pin.
static func capture_ring_cost(tree: SceneTree, raw: Variant) -> String:
    if tree == null or tree.root == null:
        return "SaCapture: no tree to read a ring cost from"
    var root := tree.root

    if typeof(raw) == TYPE_DICTIONARY and (raw as Dictionary).has("at"):
        var coords := (raw as Dictionary)["at"] as Array
        if coords == null or coords.size() < 2:
            return "SaCapture: a ring_cost 'at' is [x, y]"
        var at := Vector2(float(coords[0]), float(coords[1]))
        SaCursorPolicy.pin_pointer(tree, root, at)
        for node in root.find_children("*", "CursorOverlay", true, false):
            var overlay := node as CursorOverlay
            if overlay != null:
                overlay.force_samples(int((raw as Dictionary).get("draws", DRAW_SAMPLES)))
        return "SaCapture: ring_cost pinned at %s, samples cleared" % at

    if String(raw) == "unpin":
        SaCursorPolicy.unpin_pointer(tree)
        return "SaCapture: ring_cost unpinned"

    var lines: Array[String] = []
    for entry: Dictionary in state_of(root):
        (
            lines
            . append(
                (
                    "SaCapture: ring_cost window='%s' ring=%.1f spans=%d segments=%d usec=%.2f over=%d"
                    % [
                        entry["window"],
                        float(entry["ring"]),
                        int(entry["ring_spans"]),
                        int(entry["ring_segments"]),
                        float(entry["draw_usec"]),
                        int(entry["draw_samples"]),
                    ]
                )
            )
        )
    return "\n".join(lines) if not lines.is_empty() else "SaCapture: no overlay to read a ring cost from"
