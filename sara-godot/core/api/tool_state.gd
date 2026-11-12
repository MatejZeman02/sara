## Base class for every tool.
##
## A tool holds a SaSurface, a document and a view, rather than a `SaCanvas`,
## which is a TextureRect, so the tool base class in core/ does not depend on
## render/, a tool is testable headless, and one tool class serves the main
## canvas and the info docker's scratchpad.
##
## SaTool is an alias of `ToolState`.
class_name ToolState extends RefCounted

## The surface this instance paints on. One instance per surface.
var surface: SaSurface = null

## The machine's door back to the tool that was active before this one, set
## when the machine registers the instance. A tool that has finished a job
## the painter came to it for, the transform's Enter, calls
## [method request_hand_back] rather than naming a tool, because which tool
## that was is the machine's to know. Empty in a test that builds a tool
## alone, and then the request is a no-op.
var hand_back: Callable = Callable()

## The engines the skeleton constructs, by role, set by the machine beside
## `surface`. A tool that builds a crop, a transform or a gradient asks
## here first, so a module's subclass registered under the role is what the
## tool uses. Null in a test that builds a tool alone or a machine bound
## without registries, and then the tool builds the class it names.
var roles: SaRoleRegistry = null

## The seed every stroke of this instance starts its random streams from, or
## zero for a seed drawn off the wall clock at each press, which is what a
## painter wants: two strokes side by side do not lay the same grain.
##
## A picture that has to come out the same on every launch sets it, which is
## the preset thumbnail. A tool with no randomness ignores it.
var stroke_seed: int = 0

## The pen's raw pressure at the last sample, written by a tool whose descriptor sets `reads_pressure`.
var last_pressure: float = 0.0

## Where [method get_document_mouse_position] answers while
## [method straight_line_to] runs its stroke, and whether one is running.
var _line_at: Vector2 = Vector2.ZERO
var _on_line: bool = false

## Whether a press of this tool is held to a guide while snapping is on, which
## the machine sets for a tool that paints under a brush ring: the brush, the
## eraser and every brush engine, and not a fill, a gradient or a selection.
var takes_holds: bool = false

## The hold the stroke in hand keeps its pointer to, `SaStrokeHold.held_at`'s
## answer at its press, or empty for a free stroke.
var _stroke_hold: Callable = Callable()


## The document this instance paints on, or null when it has no surface yet or
## its surface shows none. Every tool asks here rather than guarding the
## surface itself.
func document() -> SaDocument:
    return SaSurface.document_of(surface)


## Asks the machine for the tool that was active before this one.
func request_hand_back() -> void:
    if hand_back.is_valid():
        hand_back.call()


## The machine's way in: *event* to [method handle_input], with a press of a
## tool that [member takes_holds] choosing the guide its stroke is held to
## first, and the release letting it go after. A tool learns of no guide, since
## it reads the held position where it reads every position.
func take_input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    var left := button != null and button.button_index == MOUSE_BUTTON_LEFT
    if left and button.pressed:
        _stroke_hold = Callable()
        if takes_holds:
            _stroke_hold = SaStrokeHold.held_at(document(), get_document_mouse_position())
    handle_input(event)
    if left and not button.pressed:
        _stroke_hold = Callable()


## Called when input reaches this tool.
func handle_input(_event: InputEvent) -> void:
    pass


## Whether a bare press of *keycode* is this tool's own just now, so the tool
## machine hands it to [method handle_input] and no shortcut answers it. The
## Magnetic Lasso keeps Backspace while a trace is under way, which otherwise
## clears the layer. Asked each press, so a tool keeps a key only while it
## has a use for it. Enter and Escape reach every tool without asking.
func keeps_key(_keycode: Key) -> bool:
    return false


## Whether *event*, a key press, is typed into something the tool is editing
## now, a text block above all, so the shortcut router hands it to
## [method handle_input] before any chord or quick tool answers it. Shifted
## letters and Space included, which [method keeps_key] never sees.
func takes_typing(_event: InputEventKey) -> bool:
    return false


## Called once a frame while this tool is the active one, with the frame's own
## delta in seconds.
##
## A no-op for every tool but the brush, which needs a clock: an airbrush
## deposits paint on a pointer that is not moving, so there is no input event to
## hang the work on. Added here rather than as a Timer inside the tool because a
## tool is a `RefCounted` with no tree to put one in, and because the smudge and
## a rotation that follows direction will want the same hook.
func tick(_delta: float) -> void:
    pass


## Called when switching away from this tool, or when the document is rebuilt.
func reset() -> void:
    pass


## Writes a session the tool holds open across presses as the history step
## it would be at Enter. True when there was one to write.
##
## Asked by every undo and redo before the history moves, through
## [method ToolMachine.close_session]. A liquify or a transform session holds
## originals of the layer it took at its first press, and an undo under it
## would change that layer behind its back, so the next press would draw from a
## picture no longer there. Closed first, the session is the step the undo
## takes back.
## Nothing, for a tool whose every press is its own step.
func close_session() -> bool:
    return false


## Whether [method close_session] would write a step now, asked without
## writing it. The Edit menu's Undo row asks, through
## [method ToolMachine.holds_session], because a liquify push or a transform
## move left open is a change the history does not hold yet. On a document
## whose only change was that one the row stood dimmed, though a press on it
## would have taken the change back. False for a tool whose every press is its
## own step.
func holds_session() -> bool:
    return false


## Radius in document pixels for a software brush ring. Non-painting tools
## return a negative value and get an OS cursor shape instead.
func get_cursor_radius() -> float:
    return -1.0


## The OS pointer shape the tool wants where the pointer is now, a
## `Control.CURSOR_*`, or -1 for its descriptor's `cursor_shape`. The machine
## asks every frame, so a tool whose pointer says what a press there would do,
## the marquee's move over a selection, needs no signal of its own.
func cursor_shape() -> int:
    return -1


## A picture of the tool's own for the pointer where it is now, standing in the
## slot of the shape [method cursor_shape] answers, or null for none. Asked
## every frame beside that shape, so the Transform's rotate arrow by a corner
## needs no signal either. Where it answers it wins over the descriptor's
## `cursor_texture`, the one picture a tool shows everywhere.
func cursor_picture() -> SaCursorPicture:
    return null


## The values a key held now shows on the tool's option rows in place of the
## ones it keeps, option key to value, and empty while no key changes a row. A
## selection tool answers `selection_mode` while Shift or Alt is down, the mode
## a press would make. Shown, never written: the option keeps
## the painter's choice, and the row goes back to it when the key is let go.
## Asked every frame by the Tool Options docker, so a held key needs no signal.
func held_options() -> Dictionary:
    return {}


## What the canvas says, translated, when the pointer rests where it is now, or
## empty for nothing. Asked every frame beside [method cursor_picture], so the
## Transform's mode strip, which the overlay draws and no Control holds, names
## the mode of the cell under the pointer with no signal of its own.
func tooltip() -> String:
    return ""


## A size the tool keeps as its own value rather than in a brush's settings, in
## document pixels, which the bracket keys and a shift-drag change the way they
## change a brush's radius. Negative for a tool with none.
##
## A brush answers through its settings' `radius` and never here, because that
## radius is a fraction of the canvas and the gestures already speak it. This is
## the door for a tool whose size is plain pixels, the patch tool's circle first,
## so the gestures reach it without naming a module.
func own_size() -> float:
    return -1.0


## Sets the size [method own_size] answers, clamped to whatever range the tool's
## own row offers. Nothing, for a tool with no size.
func resize_own(_size: float) -> void:
    pass


## Pointer position in document pixels, in the frame the stroke in hand was
## pressed in, which an infinite canvas that grew on the left or at the top
## under the stroke has moved, `SaInfiniteCanvas.stroke_point`, and held to
## the guide the stroke's press chose while one did, [method take_input].
func get_document_mouse_position() -> Vector2:
    if _on_line:
        return _line_at
    if surface == null or surface.view == null:
        return Vector2.ZERO
    var at := SaInfiniteCanvas.stroke_point(surface.get_document(), surface.view.get_document_mouse_position())
    return _stroke_hold.call(at) if _stroke_hold.is_valid() else at


## Runs one stroke straight from *from* to *to*, both in document pixels,
## through [method handle_input] as a press, *motion* and a release, with the
## pointer read at *from* for the press and at *to* after it. The machine asks
## it of a painting tool for a Shift click.
##
## **The tool's own stroke, so nothing is drawn twice**. The press, the walk
## and the release are the code a drag runs, so the line is one undo step and
## the spacing, the symmetry, the lock and the dirty rectangles hold as they
## hold for any stroke, and an engine that reads the pointer through this class
## draws lines with no code of its own. *motion* carries the pressure, the tilt
## and the eraser end the line is walked at, read as any motion is.
func straight_line_to(from: Vector2, to: Vector2, motion: InputEventMouseMotion) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    var release := press.duplicate() as InputEventMouseButton
    release.pressed = false
    _on_line = true
    _line_at = from
    handle_input(press)
    _line_at = surface.view.line_towards(from, to) if surface != null and surface.view != null else to
    handle_input(motion)
    handle_input(release)
    _on_line = false


## What this tool tells a capture's state dump about itself, keyed by the blocks
## it writes. Nothing, unless the tool has something a screenshot cannot show.
##
## Built-ins and modules share one door here too: the state report walks the
## machine's registered
## tools and merges what each answers, so a third-party tool puts a block in a
## capture exactly the way a built-in does and `sara-godot/ui/` names no module
## class to photograph one, rather than reaching into a tool by method name.
##
## *tool_name* is the name the machine registered this tool under, because a tool
## does not carry its own. *active* says whether it is the tool the machine is on,
## so a block about the stroke in progress can be empty when there is none.
func capture_report(_tool_name: StringName, _active: bool) -> Dictionary:
    return {}
