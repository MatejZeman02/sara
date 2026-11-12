## Shared drag behaviour for floating docker windows and similar handles.
##
## A Node rather than a plain helper object, because the ALT-drag has to consume
## the press *before* the docker's own controls see it. The `window_input` signal
## looks like the place for that, but `Viewport.push_input` clears the handled
## flag right after emitting it, so `set_input_as_handled()` from a `window_input`
## handler is advisory at best, ALT-clicking a tool button both moved the docker
## and switched the tool. A node's `_input` runs inside `push_input`, ahead of GUI
## dispatch, which is where the flag actually holds.
extends Node

class_name DockerDragHandle

const DockerUtilsScript = preload("res://ui/dockers/docker_utils.gd")

var _window: Window
var _is_dragging: bool = false
var _is_alt_dragging: bool = false
var _is_alt_resizing: bool = false

## Set by the ALT double click that opens a docker's Preferences page, and read
## only by the release that follows it. A Button acts on release rather than on
## press, so a release the gesture does not consume still fires whatever control
## the second click landed on, which is the same reason the two drags consume
## theirs.
var _is_alt_opening: bool = false

## Set when ALT's release ends a move or resize with the button still down, and
## read by that button's release, which is consumed for the reason the drags'
## own releases are.
var _is_release_owed: bool = false

## Window rectangle and pointer position when an ALT-right drag began. Absolute
## for the same reason the move is: accumulating deltas loses the fraction on
## every event, and at 2x scale most deltas round to zero. The position is kept
## as well as the size because a resize about the centre moves both. The anchor
## is also the press point `resize_rect` reads to decide which way each axis
## grows, because it is where the drag began and nowhere else is.
var _resize_start_size: Vector2i
var _resize_start_position: Vector2i
var _resize_anchor: Vector2

## Pointer offset from the window's top-left, captured when the drag begins and
## measured in the same space `Window.position` is written in.
var _drag_offset: Vector2

## Whether a release that moved or sized the window tells the app the painter
## changed the layout. A dialog passes false, because a dialog is not part of the
## layout and dragging Preferences aside must not fork the preset.
var _is_part_of_layout: bool = true

## The window's rectangle when the press began, which the release compares with
## the rectangle it finds. Only a release that changed it is a layout edit, so
## a click on a title bar with nothing moved forks no "default (custom)" and
## adds no row to Window › Layouts.
var _press_rect: Rect2i

## What every line of a drag's trail opens with.
const DRAG_TRAIL := "Sara drag:"
## The command line flag and the environment variable that turn the trail on.
const TRAIL_FLAG := "--trail-drag"
const TRAIL_ENV := "SARA_TRAIL_DRAG"

## Whether a drag prints a line for every motion it follows, off unless the run
## was started with `--trail-drag` or with `SARA_TRAIL_DRAG=1`.
##
## **For a sitting that drags a let-out docker with the pen**, where the
## drivers of Windows can move it in ways a plain log does not show. A line
## here says which
## window the motion reached, where in it, with what pressure and tilt, where
## the docker was and where the drag put it, and on which frame after how long a
## frame, which is what tells a motion that was not the pen's from one that was,
## and a step a frame from a step a motion. Through `print`, so it reaches the
## log a painter sends.
static var trail: bool = (
    OS.get_cmdline_args().has(TRAIL_FLAG) or OS.get_cmdline_user_args().has(TRAIL_FLAG) or OS.get_environment(TRAIL_ENV) == "1"
)

## The motions the drag in progress has followed, and the clock and the frame
## it began on, for the trail's last line.
var _trail_motions: int = 0
var _trail_began_usec: int = 0
var _trail_began_frame: int = 0


func _init(is_part_of_layout: bool = true) -> void:
    _is_part_of_layout = is_part_of_layout


func bind(window: Window, drag_handle: Control) -> void:
    _window = window
    assert(_window != null, "Target window is missing")
    assert(drag_handle != null, "Drag handle node is missing")
    drag_handle.mouse_filter = Control.MOUSE_FILTER_PASS
    drag_handle.gui_input.connect(_on_drag_handle_input)
    _window.focus_exited.connect(_end_alt_gesture)


## Where `Window.position` must go for the point grabbed at drag start to stay
## under the pointer.
##
## Absolute, not accumulated. Adding each `event.relative` and rounding it to an
## integer threw away the fraction on every motion event, and with the pointer
## delivered in logical units at 2x scale most of them round to zero, the docker
## fell behind the cursor and lurched forward whenever one big delta arrived.
static func drag_position(pointer_in_parent: Vector2, grab_offset: Vector2) -> Vector2i:
    return Vector2i((pointer_in_parent - grab_offset).round())


## Where a window of *size* asked to stand at *position* stands so all of it is
## inside a host of *host*, moved as little as possible. A window larger than
## the host keeps its top-left on the host's, so its bar stays in reach, and an
## empty *host* is no clamp.
##
## **The reopen's rule, and the drag's in a window of its own.** A drag that
## wrote the pointer's place with no limit could leave a docker below the
## status bar with its buttons and grip off screen. An embedded docker's drag
## keeps its title strip in reach instead, [method drag_place], and the Window
## menu's show opens it whole through here, because a docker that appears half
## hidden reads as a fault.
static func clamp_to_host(position: Vector2i, size: Vector2i, host: Vector2i) -> Vector2i:
    if host == Vector2i():
        return position
    return position.clamp(Vector2i(), (host - size).max(Vector2i()))


## The size a drag of *drag* asks for, never below what the docker can show.
##
## Separate from the window so a test can check the arithmetic without putting a
## Window in the scene tree, which maps a real OS window and hangs the run.
static func resize_size(start_size: Vector2i, drag: Vector2, minimum: Vector2i) -> Vector2i:
    var wanted := start_size + Vector2i(drag.round())
    return Vector2i(maxi(minimum.x, wanted.x), maxi(minimum.y, wanted.y))


## The whole rectangle the ALT-right drag asks for: grown about the centre it
## started at, so sideways movement stretches both sides and vertical movement
## both ends, and pulling away from the centre grows while pulling towards it
## shrinks, whichever quadrant the drag began in. The corner grip does not come
## here, `grip_rect` below is its own.
##
## *press* is where the pointer was when the drag began, in the same space as
## *start_position*. Which side of the centre each of its coordinates falls on
## gives that axis its sign, so a drag started in any corner, or anywhere else
## in the window, pulls its own way rather than only the way the corner grip's
## own corner happens to. A press exactly on the centre line defaults to the
## positive side, which is the corner grip's own quadrant and gives its
## arithmetic with no *press* at all.
##
## The size takes twice the signed drag, which is what keeps the centre still
## *and* the corner nearest the press under the pointer at the same time. With
## the centre fixed and the size up by 2d, that corner has moved by d, which is
## exactly how far the pointer went.
##
## The position is derived from the size after it has been clamped, so a docker
## that has hit its minimum stops growing without its centre sliding away.
## *host* is `resize_host_of`'s rectangle, the bar already off its top, and an
## empty one is no clamp.
static func resize_rect(
    start_position: Vector2i, start_size: Vector2i, drag: Vector2, press: Vector2, minimum: Vector2i, host: Rect2i = Rect2i()
) -> Rect2i:
    var centre := Vector2(start_position) + Vector2(start_size) * 0.5
    var signed_drag := Vector2(drag.x if press.x >= centre.x else -drag.x, drag.y if press.y >= centre.y else -drag.y)
    var wanted := resize_size(start_size, signed_drag * 2.0, minimum)
    if host.has_area():
        wanted = fit_about_centre(wanted, centre, minimum, host)
    return Rect2i(Vector2i((centre - Vector2(wanted) * 0.5).round()), wanted)


## The rectangle the corner grip asks for: the corner opposite the grip held
## still and the grip's own corner under the pointer, so a drag down moves the
## bottom edge down and nothing else.
##
## **Not about the centre, which the ALT-right drag keeps.** A grip grown about
## the centre moves the top by as much as the bottom: pulled down 260 it lifted
## the Brush Presets docker's top 130 over the menu bar, and the shrink after it
## took the top down with the bottom until the grid was gone. A grip is a
## corner a painter holds, and the edges they did not hold are expected to stay.
##
## The size is the start plus the drag, floored at *minimum*. The height is
## capped where the grip's corner would cross *host*'s foot, and the top is never
## written, so it cannot rise over the bar. The width is capped at the host's,
## and once the right edge stands on the host's, the left edge gives the rest,
## `SaDockerEdges.widened`. The minimum wins over the edge, for
## `fit_about_centre`'s reason.
static func grip_rect(
    start_position: Vector2i, start_size: Vector2i, drag: Vector2, minimum: Vector2i, host: Rect2i = Rect2i()
) -> Rect2i:
    var wanted := resize_size(start_size, drag, minimum)
    if not host.has_area():
        return Rect2i(start_position, wanted)
    var room_y := host.end.y - start_position.y
    var across := SaDockerEdges.widened(start_position.x, start_position.x + start_size.x, wanted.x, minimum.x, host, true)
    return Rect2i(across.x, start_position.y, across.y, clampi(wanted.y, minimum.y, maxi(room_y, minimum.y)))


## The largest *wanted* may be while a rectangle centred on *centre* stays inside
## *host*, and never below *minimum*.
##
## **Growth about a held centre stops when the nearer edge reaches the host's**,
## or a docker grown near an edge would draw its far column off the window,
## and neither the gesture nor the window refuses. The centre is what the gesture
## holds, so the only thing left to give is the size. *host* starts below the
## bar, so the top stops there too.
##
## The minimum wins over the edge when the two disagree, because a docker
## squeezed under its own minimum is unusable and one whose corner poked out is
## untidy. That needs a centre closer to an edge than half the minimum size,
## which is a restored layout rather than a gesture.
static func fit_about_centre(wanted: Vector2i, centre: Vector2, minimum: Vector2i, host: Rect2i) -> Vector2i:
    var near := centre - Vector2(host.position)
    var far := Vector2(host.end) - centre
    var room := Vector2i(int(floor(minf(near.x, far.x) * 2.0)), int(floor(minf(near.y, far.y) * 2.0)))
    return Vector2i(clampi(wanted.x, minimum.x, maxi(room.x, minimum.x)), clampi(wanted.y, minimum.y, maxi(room.y, minimum.y)))


## The rectangle a resize of *window* is kept in, in the space its `position` is
## written in: `SaDockerMaximise.host_rect` less the main window's bar, by the
## rule `SaDialogWindow.below_the_bar_of` holds for every dialog. Empty for a
## window outside the tree, which has no host to ask and whose `is_embedded`
## refuses with an error, and the two gestures read empty as no clamp.
##
## A docker the painter put over the bar keeps its own top as the host's, so a
## resize grows it about where it stands rather than squeezing it to its
## minimum, and still never lifts an edge over the bar it was not already over.
static func resize_host_of(window: Window) -> Rect2i:
    if window == null or not window.is_inside_tree():
        return Rect2i()
    var host := SaDialogWindow.below_the_bar_of(window, SaDockerMaximise.host_rect(window))
    if not window.is_embedded() or window.position.y >= host.position.y or not host.has_area():
        return host
    var top := maxi(window.position.y, 0)
    return Rect2i(host.position.x, top, host.size.x, host.end.y - top)


## The space *window* has to sit in: its host viewport when embedded, the screen
## otherwise, and `Vector2i()` when neither can be asked.
##
## Static and here rather than in `docker_layout_store.gd`, which had the only
## copy, because the resize needs the same rule and two copies of it would drift.
## The store delegates to this one.
static func host_size_of(window: Window) -> Vector2i:
    if window == null:
        return Vector2i()
    if not window.is_embedded():
        return DisplayServer.screen_get_usable_rect(window.current_screen if window.is_inside_tree() else -1).size
    var parent_node := window.get_parent()
    if parent_node == null or not parent_node.is_inside_tree():
        return Vector2i()
    var host_vp := parent_node.get_viewport()
    return Vector2i(host_vp.get_visible_rect().size) if host_vp != null else Vector2i()


## The rectangle a drag of *window* keeps it in, in the space its `position` is
## written in, and empty for no clamp.
##
## Embedded, it is `host_size_of` from the host's corner. A window of its own
## takes the usable rect of the screen under *pointer* rather than of the one
## the window stands on, so a drag still carries it to another screen, and with
## that rect's corner, which a panel along the top or left moves off the origin.
## A window outside the tree is never embedded, and its `is_embedded` refuses,
## so it is asked as a window of its own, which is what `host_size_of` gives it.
static func drag_host_of(window: Window, pointer: Vector2) -> Rect2i:
    if window == null:
        return Rect2i()
    if window.is_inside_tree() and window.is_embedded():
        return Rect2i(Vector2i(), host_size_of(window))
    return DisplayServer.screen_get_usable_rect(DisplayServer.get_screen_from_rect(Rect2(pointer, Vector2.ONE)))


## *at* moved as little as possible so all of *window* stands inside
## `drag_host_of`'s rectangle, the screen being the one under *pointer*.
## `MainDockers.toggle_docker` calls this with the window's own centre for the
## pointer, and the drag of a window of its own through [method drag_place].
static func fit_inside(window: Window, at: Vector2i, pointer: Vector2) -> Vector2i:
    var host := drag_host_of(window, pointer)
    return clamp_to_host(at - host.position, window.size, host.size) + host.position


## Where a drag puts *window* when the pointer asks for *at*, the pointer at
## *pointer*.
##
## **An embedded docker keeps its title strip in reach, not its whole
## frame.** It may go past every edge of the window as far as [method
## SaDockerLayoutFit.reached] leaves a part of the strip a hand can take, and
## stops there, and it may stand over the top bar and the status line as over
## the canvas, so a docker goes anywhere in the window. The top stops at
## the window's own top row, where the whole strip is still in. A window of
## its own, with embedding off, keeps the screen rule of [method fit_inside].
static func drag_place(window: Window, at: Vector2i, pointer: Vector2) -> Vector2i:
    if window == null:
        return at
    if not window.is_inside_tree() or not window.is_embedded():
        return fit_inside(window, at, pointer)
    return SaDockerLayoutFit.reached(at, window.size, drag_host_of(window, pointer))


## The pointer in whatever space this window's `position` is measured in: the host
## viewport's logical space when embedded, physical screen pixels when it is a
## real OS window.
func pointer_in_parent_space() -> Vector2:
    return pointer_in_parent_space_of(_window)


## Where a capture scenario says the pointer is, or null when the real one is
## the answer, which is every run that is not a capture.
##
## Wayland will not let a client place the pointer, and every dump on this
## machine reports `pointer_warp_works` false, so an injected motion carries a
## position that the two gestures below never read: they ask the live pointer.
## Without this seam the ALT-drag and the grip are undrivable from a scenario and
## the centred resize could only ever have been argued from the code.
static var capture_pointer: Variant = null

## The system pointer on the desktop when a let-out docker's move follows it,
## null when it follows the pen's place. A suite hands its own. **WinTab's moves
## follow the system pointer**, which its driver carries with the pen, because a
## motion is placed against where its window was when Windows made it, and
## WinTab's packets and Windows' mouse moves interleave either side of the
## docker's last move, so a drag that followed the pen would swing.
## Under Windows Ink the system pointer can stay behind the pen.
static var system_pointer: Callable = func() -> Variant:
    if DisplayServer.tablet_get_current_driver() == "wintab":
        return SaCursorPolicy.system_pointer()
    return null


## The same question for a window this handle does not own, which is what lets
## `docker_resizer.gd` measure its drag in the units its window's `position` is
## written in without keeping a second copy of the rule.
static func pointer_in_parent_space_of(window: Window) -> Vector2:
    if capture_pointer is Vector2:
        return capture_pointer
    if window == null:
        return Vector2.ZERO
    if window.is_embedded():
        var parent := window.get_parent()
        var host := parent.get_viewport() if parent != null else null
        if host != null:
            return SaCursorPolicy.pointer_in(host)
    return SaCursorPolicy.pointer_in(null)


## The smallest this window may be drawn: its own minimum when it declares one,
## and the docker floor otherwise, raised to the width the column inside it
## insists on.
##
## **`min_size` is a snapshot and the column keeps growing after it is taken.**
## `DockerWindow.enforce_column_minimum` raises `min_size.x` to the column's want
## and runs twice, both times during the window's own setup. The Minimap's column
## reaches its width only once its picture and its Proof Mode row have laid out,
## which is after both calls, so its floor stays at what `apply_window_scale`
## wrote from the logical minimum. A drag clamped against that floor walks
## straight through the column and leaves the hide button outside the window.
##
## Reading the column here rather than raising `min_size` is deliberate, and it is
## the shape `SaDockerStoredEntry.floored` uses for the stored sizes. Raising
## `min_size` when the column grows would make a window
## grow under the hand that is holding it, which is a worse thing than a drag that
## stops early.
##
## **The width for every docker, the height for one that asks.** Driving all ten
## dockers inward and reading `size` against `column_wants` on both axes leaves
## nothing shorter than its column in either state, because `apply_window_scale`
## already reserves the corner on the y axis. Flooring every height would stop
## the Recorder shrinking below the height its column wants, far taller than it
## opens. Brush Presets
## asks, through `DockerWindow.column_height_floor`, because its grid has no
## floor of its own and a shrink left it the search box and no presets.
static func minimum_size_of(window: Window) -> Vector2i:
    var minimum: Vector2i = window.min_size
    if minimum == Vector2i():
        minimum = DockerUtilsScript.get_min_docker_size(window)
    var column := DockerWindow.column_min_width(window)
    if column > 0:
        minimum.x = maxi(minimum.x, column)
    if window.has_method("column_height_floor"):
        minimum.y = maxi(minimum.y, int(window.call("column_height_floor")))
    return minimum


## The title of the Preferences page *window*'s own settings live on, or "" for
## none, which `SaDockersPage.page_of` answers for the key the window gives.
##
## Two hops rather than one, and neither is a table kept by hand. The docker
## answers `settings_category`, the `SaSettings` key its element list and its
## options are stored under, and `SaSettings` answers whether that key was
## registered, as a module's docker is through `register_layout_category`.
##
## A `SaDialogWindow` shares this handle and answers nothing, so Preferences,
## About and the filter dialogs have no page and the gesture over their title
## bars is dead. The Brush Editor is not one of them: it drags itself and has no
## `DragHandleInput` at all, so the gesture never reaches this.
static func settings_page_of(window: Window) -> String:
    return SaDockersPage.page_of(_category_of(window))


## The row on that page the gesture lands on, a docker's line, or empty.
static func settings_row_of(window: Window) -> StringName:
    return SaDockersPage.line_of(_category_of(window))


static func _category_of(window: Window) -> String:
    return String(window.call("settings_category")) if window != null and window.has_method("settings_category") else ""


## Asks for Preferences on this docker's line, and says whether there was one
## to ask for. An empty row is the top bar's page, opened at its top.
##
## Deferred for the reason `SaAppCommands._open_preferences` gives one file over:
## this runs inside `Viewport.push_input`, and a window taking focus from inside
## that re-entrancy desynchronises the engine's popup bookkeeping.
func _open_settings_page() -> bool:
    var page := settings_page_of(_window)
    if page.is_empty():
        return false
    if EventBus:
        EventBus.settings_row_requested.emit.call_deferred(page, settings_row_of(_window))
    return true


## Where the window was when a gesture's press arrived.
func _note_press_rect() -> void:
    _press_rect = Rect2i(_window.position, _window.size)


## Tells the app the painter changed the layout, when this handle belongs to a
## layout and the gesture that just ended moved or sized its window.
func _announce_if_changed() -> void:
    if not _is_part_of_layout or Rect2i(_window.position, _window.size) == _press_rect:
        return
    if EventBus:
        EventBus.docker_layout_changed.emit()


func _begin_drag() -> void:
    _note_press_rect()
    var pointer := _drag_pointer()
    _drag_offset = pointer - Vector2(_window.position)
    if not trail:
        return
    _trail_motions = 0
    _trail_began_usec = Time.get_ticks_usec()
    _trail_began_frame = Engine.get_process_frames()
    print(
        (
            "%s %s begins, pointer %s, docker %s, offset %s, pen %s"
            % [
                DRAG_TRAIL,
                _window.title,
                _point_text(pointer),
                _point_text(Vector2(_window.position)),
                _point_text(_drag_offset),
                SaCursorPolicy.pointer_is_tablet,
            ]
        )
    )


## The pointer a move follows, [member system_pointer] when it answers one.
func _drag_pointer() -> Vector2:
    if capture_pointer == null and not _window.is_embedded():
        var system: Variant = system_pointer.call()
        if system is Vector2:
            return system
    return pointer_in_parent_space()


## Follows one motion of a move, *event* being the motion for the trail.
func _apply_drag(event: InputEvent) -> void:
    var was := _window.position
    var pointer := _drag_pointer()
    var at := drag_position(pointer, _drag_offset)
    # A dialog is not part of the layout and stays whole, as it opens.
    _window.position = drag_place(_window, at, pointer) if _is_part_of_layout else fit_inside(_window, at, pointer)
    if trail:
        _trail_motions += 1
        print("%s %s" % [DRAG_TRAIL, _trail_line(event, was, pointer)])


## The trail's line for one motion: the window it reached and its place there,
## its pressure and tilt, the pointer the drag read, the docker's place before
## and after, and the frame with how long the last one took.
##
## The window is named by the id the display server sent the motion to beside
## the docker's own, because under Windows Ink Godot gives a mouse motion to
## the focused window whichever window it was over. The place is in the
## viewport the motion reached, never local to the title bar.
func _trail_line(event: InputEvent, was: Vector2i, pointer: Vector2) -> String:
    var reached := "window %d, the docker's %d," % [_sent_to(event), _window.get_window_id()]
    var mouse := event as InputEventMouse
    var at := _point_text(mouse.global_position) if mouse != null else "nowhere"
    var motion := event as InputEventMouseMotion
    # Three places for the tilt as for the pressure, because a tilt that is not
    # zero is the pen's whatever its size, and to one place 0.04 reads as none.
    var pen := (
        "pressure %.3f, tilt (%.3f, %.3f)" % [motion.pressure, motion.tilt.x, motion.tilt.y] if motion != null else "no motion"
    )
    return (
        "%s motion %d in %s at %s, %s, pointer %s, docker %s -> %s, frame %d after %.1f ms, %.1f ms in"
        % [
            _window.title,
            _trail_motions,
            reached,
            at,
            pen,
            _point_text(pointer),
            _point_text(Vector2(was)),
            _point_text(Vector2(_window.position)),
            Engine.get_process_frames(),
            get_process_delta_time() * 1000.0,
            (Time.get_ticks_usec() - _trail_began_usec) / 1000.0,
        ]
    )


## The window id the display server addressed *event* to, -1 for an event that
## carries none.
static func _sent_to(event: InputEvent) -> int:
    var from_window := event as InputEventFromWindow
    return from_window.window_id if from_window != null else -1


## The trail's last line for a move, with how many frames it took and how long
## each was on average, which is the number that says whether a step a frame is
## what held a drag to thirty moves a second.
func _end_trail() -> void:
    if not trail:
        return
    var spent_ms := (Time.get_ticks_usec() - _trail_began_usec) / 1000.0
    var frames := Engine.get_process_frames() - _trail_began_frame
    print(
        (
            "%s %s ends at %s after %d motions in %.1f ms over %d frames, %.1f ms a frame"
            % [
                DRAG_TRAIL,
                _window.title,
                _point_text(Vector2(_window.position)),
                _trail_motions,
                spent_ms,
                frames,
                spent_ms / maxf(float(frames), 1.0),
            ]
        )
    )


func _begin_resize() -> void:
    _note_press_rect()
    _resize_start_size = _window.size
    _resize_start_position = _window.position
    _resize_anchor = pointer_in_parent_space()


func _apply_resize() -> void:
    # Read from where the drag began, which is `_resize_anchor` doing double
    # duty as `resize_rect`'s press point, rather than flipped by a fixed rule.
    # A fixed flip would always grow towards the top right, wherever the press
    # fell, so `resize_rect` asks the press itself which way is away from the
    # centre, on both axes.
    var drag := pointer_in_parent_space() - _resize_anchor
    var rect := resize_rect(
        _resize_start_position, _resize_start_size, drag, _resize_anchor, minimum_size_of(_window), resize_host_of(_window)
    )
    # The size first. A window whose position is written while it is still the
    # old size can be pushed against its host's edge and clamped there, and a
    # clamped position is not a chosen one.
    _window.size = rect.size
    _window.position = rect.position


## Ends an ALT move or resize where the docker stands, which a release of the
## button, of ALT, a focus lost or a motion with no button down all do.
func _end_alt_gesture() -> void:
    if not (_is_alt_dragging or _is_alt_resizing):
        return
    if _is_alt_dragging:
        _end_trail()
    _is_alt_dragging = false
    _is_alt_resizing = false
    _announce_if_changed()


## The application losing focus reaches every node, and the window's own
## `focus_exited` covers a focus that moves to another of Sara's windows. Either
## way the release of ALT or of the button goes somewhere this handle never hears.
func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        _end_alt_gesture()


func _on_drag_handle_input(event: InputEvent) -> void:
    if _window == null:
        return

    if event is InputEventMouseButton or event is InputEventScreenTouch:
        # The left button only, because a right press is the docker's menu.
        if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
            return
        if event.is_pressed():
            _is_dragging = true
            _begin_drag()
        else:
            if _is_dragging:
                _is_dragging = false
                _end_trail()
                _announce_if_changed()

    elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and _is_dragging:
        _apply_drag(event)


func _input(event: InputEvent) -> void:
    if handle_input(event):
        var vp := get_viewport()
        if vp != null:
            vp.set_input_as_handled()


## The ALT-drag state machine. Returns true when the event belongs to the drag and
## must not reach the docker's controls. Separate from `_input` so it can be
## driven directly by a test, which cannot put a Window in the tree.
func handle_input(event: InputEvent) -> bool:
    if _window == null:
        return false

    if event is InputEventMouseButton or event is InputEventScreenTouch:
        var is_left: bool = event is not InputEventMouseButton or event.button_index == MOUSE_BUTTON_LEFT
        var is_right: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT
        # A touch carries no modifiers, and reading one off it was a script
        # error that ended this branch on every touch of a title. A
        # touch is never an ALT gesture, so it falls through to the title's
        # own left-press drag.
        var is_alt: bool = event is InputEventWithModifiers and event.alt_pressed
        if event.is_pressed():
            _is_release_owed = false
            # Before the move, because a double click arrives as press, release,
            # press-with-`double_click`, release: the first pair has already run
            # the move and ended it, and this is the second press. Testing the
            # flag after the move would start a drag nobody asked for and never
            # reach the page.
            if is_alt and is_left and event is InputEventMouseButton and event.double_click:
                _is_alt_opening = _open_settings_page()
                # Consumed either way. A gesture that found no page must do
                # nothing at all, and letting the press through to the docker's
                # own controls is not nothing.
                return true
            # Not with Ctrl as well, which is a subtract on a layer's thumbnail.
            if is_alt and is_left and not (event is InputEventMouseButton and event.ctrl_pressed):
                _is_alt_dragging = true
                _begin_drag()
                return true
            # The corner grip is 24 logical units in one corner, which is the
            # only way to resize a docker and is unreachable once the window is
            # against a screen edge. ALT-right drags from anywhere in it.
            if is_alt and is_right:
                _is_alt_resizing = true
                _begin_resize()
                return true
        elif _is_alt_opening:
            _is_alt_opening = false
            return true
        elif _is_release_owed:
            _is_release_owed = false
            return true
        elif _is_alt_dragging or _is_alt_resizing:
            # Consumed on release too, or the button that never saw the press
            # still fires: a Button acts on release, not on press. A right
            # release that is not consumed opens a context menu instead.
            _end_alt_gesture()
            return true
        return false

    # ALT let go ends the gesture where the docker stands. The key itself is
    # not consumed, because the shortcuts and the menus' ALT read it as well.
    # The button's release still to come is, as the gesture's own would be.
    if event is InputEventKey and not event.pressed and (event.keycode == KEY_ALT or event.physical_keycode == KEY_ALT):
        if _is_alt_dragging or _is_alt_resizing:
            _is_release_owed = true
        _end_alt_gesture()
        return false

    # A motion with no button down means the release went to another window
    # or was never sent, and one without ALT means ALT's release did, and
    # following either is the docker that would not stop.
    if (
        event is InputEventMouseMotion
        and (_is_alt_dragging or _is_alt_resizing)
        and (event.button_mask == 0 or not event.alt_pressed)
    ):
        _end_alt_gesture()
        return false

    if event is InputEventMouseMotion or event is InputEventScreenDrag:
        if _is_alt_dragging:
            _apply_drag(event)
            return true
        if _is_alt_resizing:
            _apply_resize()
            return true

    return false


# --- The capture harness's door ------------------------------------------------
#
# Both gestures read the live pointer, and Wayland will not let a capture put it
# anywhere, so a scenario drives them through here: the real window, the real
# state machine and the real arithmetic, with the pointer's position supplied.
# The same reason `probe` and `click` exist.


## Resizes a docker by a drag: a registered docker, dragged *by* logical units
## from the point *from* names, through the ALT and right button gesture, or
## through the corner grip when `grip` is true, `{"docker_resize": {"id":
## "LayersDocker", "by": [60, 40], "grip": false, "from": "bottom_right"}}`.
## Answers the rectangle and the centre either side of it, which is the claim.
##
## *from* is one of `top_left`, `top_right`, `bottom_left`, `bottom_right`, and
## defaults to the last: `resize_rect`'s own default quadrant, and the only one
## the grip can ever start a drag from, because it sits in that corner. `grip`
## ignores *from* for that reason and always presses there. Wayland will not let
## a capture place the pointer at a fraction of the window either, which is why
## a corner is named rather than a point: the press has to fall exactly on the
## rectangle's own edge to land in a quadrant unambiguously.
static func capture_resize(tree: SceneTree, spec: Dictionary) -> String:
    var docker_id := String(spec.get("id", ""))
    var window := tree.root.find_child(docker_id, true, false) as Window
    if window == null:
        return "SaCapture: no docker called '%s' to resize" % docker_id
    var by_raw := spec.get("by", [0, 0]) as Array
    if by_raw == null or by_raw.size() < 2:
        return "SaCapture: docker_resize needs a 'by' of two numbers"
    var by := Vector2(float(by_raw[0]), float(by_raw[1]))
    var is_grip := bool(spec.get("grip", false))
    var from := "bottom_right" if is_grip else String(spec.get("from", "bottom_right"))

    var before := Rect2i(window.position, window.size)
    var start := _quadrant_point(before, from)
    capture_pointer = start
    if is_grip:
        _drive_grip(window, start, by)
    else:
        _drive_alt_drag(window, start, by)
    capture_pointer = null

    var after := Rect2i(window.position, window.size)
    return (
        "SaCapture: docker_resize %s by (%d, %d) %s from %s: %s -> %s, centre %s -> %s"
        % [
            docker_id,
            by.x,
            by.y,
            "grip" if is_grip else "alt-right",
            from,
            _rect_text(before),
            _rect_text(after),
            _point_text(Vector2(before.position) + Vector2(before.size) * 0.5),
            _point_text(Vector2(after.position) + Vector2(after.size) * 0.5),
        ]
    )


## The corner of *rect* that *corner* asks for, `bottom_right` for anything
## else, which keeps `capture_resize` and the grip, which can only ever press
## there, agreeing on a default without either one naming the other.
static func _quadrant_point(rect: Rect2i, corner: String) -> Vector2:
    match corner:
        "top_left":
            return Vector2(rect.position)
        "top_right":
            return Vector2(rect.position.x + rect.size.x, rect.position.y)
        "bottom_left":
            return Vector2(rect.position.x, rect.position.y + rect.size.y)
        _:
            return Vector2(rect.position + rect.size)


## Opens a docker's own page: its Preferences page, by the ALT double click on
## its drag handle, and answers the page and line it resolved to, or that it
## resolved to none, `{"docker_page": {"id": "LayersDocker"}}`. The top bar's
## id, `TopMenuBar`, drives the bar's own gesture, which takes an `on` naming a
## menu title, `SaTopBarPageGesture.capture`.
##
## The same seam as `capture_resize` above and for the same reason: the gesture
## is a modifier held through two clicks on an embedded subwindow, which is
## neither something an injected click routes into nor something Wayland will
## let a capture place the pointer for. The request is deferred, so the scenario
## has to `wait` before it shoots and the dump's `preferences_search.open_page`
## is what says where Preferences landed.
static func capture_page(tree: SceneTree, spec: Dictionary) -> String:
    var docker_id := String(spec.get("id", ""))
    # The bar answers the same gesture and is no Window, so it drives its own.
    if docker_id == SaDockersPage.TOP_BAR:
        return SaTopBarPageGesture.capture(tree, spec)
    var window := tree.root.find_child(docker_id, true, false) as Window
    if window == null:
        return "SaCapture: no docker called '%s' to open a page for" % docker_id
    var handle := window.find_child("DragHandleInput", true, false)
    if handle == null or not handle.has_method("handle_input"):
        return "SaCapture: docker '%s' has no drag handle to double click" % docker_id
    var page := settings_page_of(window)
    _drive_alt_double_click(handle)
    if page.is_empty():
        return "SaCapture: docker_page %s alt-double-click: no page, nothing asked for" % docker_id
    return "SaCapture: docker_page %s alt-double-click: asked for '%s' at '%s'" % [docker_id, page, settings_row_of(window)]


## The press, release, double-click press and release a real double click
## delivers, in that order, with ALT held through all four. The first pair is
## what makes the second press a `double_click`, and leaving it out would test a
## gesture no pointer can make.
static func _drive_alt_double_click(handle: Node) -> void:
    for double_click: bool in [false, true]:
        var press := InputEventMouseButton.new()
        press.button_index = MOUSE_BUTTON_LEFT
        press.pressed = true
        press.alt_pressed = true
        press.double_click = double_click
        handle.call("handle_input", press)
        var release := InputEventMouseButton.new()
        release.button_index = MOUSE_BUTTON_LEFT
        release.pressed = false
        release.alt_pressed = true
        handle.call("handle_input", release)


## Moves a docker, `{"drag": {"window": "Minimap", "by": [-120, 60]}}`, and answers
## with the report line, or an empty string when the spec names nothing this seam can
## move.
##
## `capture_resize`'s sibling, and it exists for the same reason one step further
## in. A docker moves on ALT plus a *left* drag, and `SaCaptureInput.drag_window`
## pushes a plain left drag, so `handle_input` refused it and every move a
## scenario asked for read `moved=(0, 0)`. That is not a bug in `drag_window`:
## nothing there can hold ALT down through a motion, and adding a modifier to the
## `press` step belongs to the capture input rather than to this handle. The
## gesture gets its own seam instead, which is also what `capture_resize` did.
##
## The window is found by title, the way `drag_window` finds it, so the committed
## scenario reaches this without being rewritten. An empty answer means the
## caller should fall back: a note window is dragged by the same step and has no
## `DragHandleInput` behind it, and a `via` of anything but `window` is a
## deliberate test of input routing rather than of the drag arithmetic.
static func capture_move(tree: SceneTree, spec: Dictionary) -> String:
    if String(spec.get("via", "window")) != "window":
        return ""
    var title := String(spec.get("window", ""))
    if title.is_empty():
        return ""
    # Every Window in the tree, not `SaCursorPolicy.embedded_subwindows`, which skips a
    # hidden one and stops recursing at each Window. `drag_window` scans the same
    # way, so the two find the same docker and the fall-through cannot land on a
    # different window from the one this refused.
    var window: Window = null
    for node in tree.root.find_children("*", "Window", true, false):
        var candidate := node as Window
        if candidate != null and candidate.title == title:
            window = candidate
            break
    if window == null:
        return ""
    var handle := window.find_child("DragHandleInput", true, false)
    if handle == null or not handle.has_method("handle_input"):
        return ""
    var by_raw := spec.get("by", [0, 0]) as Array
    if by_raw == null or by_raw.size() < 2:
        return "SaCapture: drag needs a 'by' of two numbers"
    var by := Vector2(float(by_raw[0]), float(by_raw[1]))

    var before := window.position
    var start := Vector2(before) + Vector2(window.size) * 0.5
    capture_pointer = start
    _drive_alt_left_drag(handle, start, by)
    capture_pointer = null

    var moved := window.position - before
    return (
        "SaCapture: drag %s by (%d, %d) alt-left: %s -> %s, moved %s"
        % [title, by.x, by.y, _point_text(Vector2(before)), _point_text(Vector2(window.position)), _point_text(Vector2(moved))]
    )


## The ALT-left press, motion and release, handed straight to the handle, with
## the pointer supplied through `capture_pointer` because the handle reads the
## live one and Wayland will not let a capture place it.
static func _drive_alt_left_drag(handle: Node, start: Vector2, by: Vector2) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.alt_pressed = true
    handle.call("handle_input", press)
    capture_pointer = start + by
    handle.call("handle_input", held_motion(MOUSE_BUTTON_MASK_LEFT))
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.alt_pressed = true
    handle.call("handle_input", release)


## The node untyped and `has_method` rather than a cast: a cast to this script's
## own `class_name` inside a `static func` leaks the script at exit.
static func _drive_alt_drag(window: Window, start: Vector2, by: Vector2) -> void:
    var handle := window.find_child("DragHandleInput", true, false)
    if handle == null or not handle.has_method("handle_input"):
        return
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_RIGHT
    press.pressed = true
    press.alt_pressed = true
    handle.call("handle_input", press)
    capture_pointer = start + by
    handle.call("handle_input", held_motion(MOUSE_BUTTON_MASK_RIGHT))
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_RIGHT
    release.pressed = false
    release.alt_pressed = true
    handle.call("handle_input", release)


## A motion with *mask* held and ALT down, as the drag's own motions arrive,
## for the capture drivers below and for a suite.
static func held_motion(mask: MouseButtonMask) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.button_mask = mask
    motion.alt_pressed = true
    return motion


static func _drive_grip(window: Window, start: Vector2, by: Vector2) -> void:
    var grip := window.find_child("Resizer", true, false)
    if grip == null or not grip.has_method("capture_drag"):
        return
    grip.call("capture_drag", start, by)


static func _rect_text(rect: Rect2i) -> String:
    return "(%d, %d) %dx%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


static func _point_text(point: Vector2) -> String:
    return "(%.1f, %.1f)" % [point.x, point.y]
