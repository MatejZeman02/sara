## Drags a let-out docker by its title bar with a pen the way Windows Ink hands
## one to Godot 4.7, so a pen drag that flickers can be run without a tablet.
##
## Under Ink the pen's own messages are answered as handled, so the system
## pointer stays where it was while the docker moves under it, and Windows
## tells the moved window that the pointer moved. Each pen motion here is
## pushed into the docker's window at the pen's place carried into where the
## docker is now, with a pressure and a tilt, and each is followed, unless the
## spec says otherwise, by that motion of Windows' making, at the place the press
## landed on the desktop and with neither, a motion that is not the pen and that
## pulls the drag back to the system pointer wherever it is read as the pen.
##
## Pushed into the window rather than parsed, the way `pen_in` does, so the
## docker's own `CursorOverlay` notes each motion and its title bar's
## `gui_input` follows it, in the order the engine runs the two, and no warp of
## the system pointer is asked for that Wayland would refuse.
extends RefCounted

## Where a docker named by its id is asked for, through the registry.
const CaptureRun := preload("res://harness/sa_capture_run.gd")


## Drags a docker with a pen: a let-out one, by its title bar, with a pen whose
## motions come with a plain one after each, as Windows Ink delivers them, and
## answers where the docker went and how often it went back, `{"pen_drag":
## {"window": "LayersDocker", "by": [360, 140], "steps": 24, "plain": true,
## "pressure": 0.5}}`.
##
## *by* is in desktop pixels, the space a window of its own is placed in.
## `plain` false drags with the pen's motions alone, which is WinTab's way. A
## docker that went back towards the press, on any of the motions, is the
## fault, and a line carrying `failed` says why nothing was dragged.
static func drag(tree: SceneTree, spec: Dictionary) -> String:
    var name := String(spec.get("window", ""))
    var window := CaptureRun.DockerLookup.named(tree.root, name) as Window
    if window == null:
        return "SaCapture: pen_drag failed, no window called '%s'" % name
    if window.is_embedded():
        return "SaCapture: pen_drag failed, %s is embedded and the drag is a let-out docker's" % name
    var title_bar := window.find_child("DragHandle", true, false) as Control
    if title_bar == null:
        return "SaCapture: pen_drag failed, %s has no title bar to drag by" % name
    var by_raw := spec.get("by", [0, 0]) as Array
    if by_raw == null or by_raw.size() < 2:
        return "SaCapture: pen_drag failed, it needs a 'by' of two numbers"
    var by := Vector2(float(by_raw[0]), float(by_raw[1]))
    var steps := maxi(int(spec.get("steps", 24)), 1)
    var plain := bool(spec.get("plain", true))
    var pressure := float(spec.get("pressure", 0.5))

    var start := title_bar.get_global_rect().get_center()
    var pressed_at := _to_desktop(window) * start
    var before := window.position
    window.push_input(_pen(start, 0.0), true)
    window.push_input(_tip(start, true), true)
    var last := window.position
    var changes := 0
    var went_back := 0
    var at := start
    for i in steps:
        var pen := pressed_at + by * float(i + 1) / float(steps)
        at = _to_desktop(window).affine_inverse() * pen
        var motions: Array[InputEventMouseMotion] = [_pen(at, pressure)]
        if plain:
            motions.append(_plain(_to_desktop(window).affine_inverse() * pressed_at))
        for motion: InputEventMouseMotion in motions:
            window.push_input(motion, true)
            if window.position != last:
                changes += 1
                if Vector2(window.position - last).dot(by) < 0.0:
                    went_back += 1
            last = window.position
    window.push_input(_tip(at, false), true)

    return (
        (
            "SaCapture: pen_drag %s by (%d, %d) in %d pen motions%s: (%d, %d) -> (%d, %d), moved (%d, %d),"
            + " went back %d times in %d changes of place"
        )
        % [
            name,
            by.x,
            by.y,
            steps,
            " with a plain one after each" if plain else "",
            before.x,
            before.y,
            window.position.x,
            window.position.y,
            window.position.x - before.x,
            window.position.y - before.y,
            went_back,
            changes,
        ]
    )


## From *window*'s viewport space to desktop pixels, for a window of its own,
## which is the transform the cursor package keeps the pen's desktop place by.
static func _to_desktop(window: Window) -> Transform2D:
    return Transform2D(0.0, Vector2(window.position)) * window.get_screen_transform()


## A pen motion at *at*, as `WM_POINTERUPDATE` builds one: a pressure, a tilt,
## and the left button down while the tip is.
static func _pen(at: Vector2, pressure: float) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.global_position = at
    motion.pressure = pressure
    motion.tilt = Vector2(0.2, -0.1)
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT if pressure > 0.0 else 0
    return motion


## The motion Windows makes for a window that moved under the system pointer,
## as `WM_MOUSEMOVE` builds it under Ink: no button the system knows of, so no
## pressure, and no tilt.
static func _plain(at: Vector2) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.global_position = at
    return motion


## The pen's tip coming down or lifting at *at*, as `WM_POINTERDOWN` and
## `WM_POINTERUP` build it.
static func _tip(at: Vector2, down: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = down
    button.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
    button.position = at
    button.global_position = at
    return button
