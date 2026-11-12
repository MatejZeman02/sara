## The gamut as the volume it actually is, drawn in Oklab.
##
## The CIE diagram above is a slice: it shows which *chromaticities* a space
## reaches and says nothing about how much of each it reaches at which lightness.
## Two spaces with the same triangle can hold very different amounts of colour.
##
## Oklab rather than the RGB cube or xyY, because Oklab is perceptually uniform:
## equal distances in it look like equal differences, so the shape reads as the
## amount of colour there actually is. An RGB cube plot draws every gamut as the
## same cube, which is the one plot guaranteed to say nothing.
##
## The wireframe is the RGB cube's twelve edges, subdivided, each vertex taken
## through the gamut's own matrix into linear sRGB and then into Oklab. The edges
## bend, and how they bend is the whole picture: a wide gamut bows further out.
##
## Cut out of `ui/color_space/color_space_browser.gd` when that file passed 900 lines. A
## class that owns something rather than a cut by count: this one owns the volume, where
## it is looked at from, and every gesture that moves the viewpoint, and the browser above
## it owns the page the three drawings sit on.
@tool
class_name SaGamutSolid
extends Control

## Subdivisions per cube edge. Twelve edges at this resolution is a few
## hundred segments, redrawn only when the space changes.
const SEGMENTS: int = 16

## How much of the shorter side one Oklab unit is drawn across. A rate of the
## shorter side, so the solid keeps its proportions whatever the control's
## shape.
const SPREAD: float = 0.868

## Where the solid is looked at from when nothing has turned it, in radians. The
## angle the drawing shipped with, so the picture a page opens on is the one it
## always was and only the gestures over it are new.
const YAW := 0.6
const PITCH := 0.35

## How far the pitch may go before the projection degenerates into a line and
## there is nothing left to read. The Graph docker's clouds clamp at the same
## place and for the same reason, `SaGraphPlot.CLOUD_PITCH_LIMIT`.
const PITCH_LIMIT: float = 1.3

## What a zoom of one is, and how far either way it may go. The clouds' range,
## so the two controls answer the wheel over the same span.
const ZOOM_MIN: float = 0.25
const ZOOM_MAX: float = 4.0

## What one wheel notch multiplies the zoom by, and how many radians a pixel
## of drag is worth. Both are the Graph docker's numbers.
const WHEEL_STEP: float = 1.1
const TURN_PER_PIXEL: float = 0.01

## The eight corners of the RGB unit cube, and the pairs that are edges.
const CORNERS: Array[Vector3] = [
    Vector3(0, 0, 0),
    Vector3(1, 0, 0),
    Vector3(0, 1, 0),
    Vector3(0, 0, 1),
    Vector3(1, 1, 0),
    Vector3(1, 0, 1),
    Vector3(0, 1, 1),
    Vector3(1, 1, 1),
]
const EDGES: Array[Vector2i] = [
    Vector2i(0, 1),
    Vector2i(0, 2),
    Vector2i(0, 3),
    Vector2i(1, 4),
    Vector2i(1, 5),
    Vector2i(2, 4),
    Vector2i(2, 6),
    Vector2i(3, 5),
    Vector2i(3, 6),
    Vector2i(4, 7),
    Vector2i(5, 7),
    Vector2i(6, 7),
]

var space: SaColorSpace = null

## The larger space to compare against, sharing *space*'s transfer so the two
## shapes differ only by gamut, or null to draw *space* alone the way this first
## looked.
var compare: SaColorSpace = null

## Yaw around the neutral axis, in radians. Dragged, because a fixed
## projection of a solid hides whichever half faces away.
var yaw: float = YAW

## Tilt away from edge-on, positive looking down at the solid. Clamped short
## of the poles, where the projection degenerates into a line and there is
## nothing left to read.
var pitch: float = PITCH

## How far in, one being the whole solid drawn at SPREAD.
var zoom: float = 1.0

## Where the picture sits, in unit coordinates of the shorter side, so half a
## pan moves it by half that side whatever the page's width. The Graph docker's
## clouds hold their pan in the same units.
var pan: Vector2 = Vector2.ZERO

var _dragging: bool = false
var _panning: bool = false


## Taller than it was. The volume is drawn about the shorter side, so in a page
## 815 pixels wide and a control 200 tall the whole picture was a fifth of the
## width with the rest black, and the gap between a gamut and the wider one it
## is being compared against came to a few pixels. The page scrolls, so height
## here costs nothing but scrolling.
func _init() -> void:
    custom_minimum_size = Vector2(float(SaUI.px(240)), float(SaUI.px(340)))
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # The wireframe is `draw_line` calls and nothing stops a line at the
    # control's edge, so a solid zoomed or panned past its frame drew over the
    # page around its black rectangle. The frame is the picture's window, and
    # the clip is what makes it one.
    clip_contents = true
    # Passed on rather than stopped, so a wheel `apply_gesture` leaves alone
    # reaches the page scrolling around the volume. Everything the volume takes
    # it accepts, so nothing else leaks through.
    mouse_filter = Control.MOUSE_FILTER_PASS
    # The gestures first, so a painter who reads no further has the whole set.
    tooltip_text = tr("Drag to turn, Shift+drag or middle-drag to pan, Ctrl+wheel to zoom, double-click to reset.")
    tooltip_text += "\n"
    tooltip_text += tr("The wireframe is the RGB cube in Oklab, where distance is perceived difference.")


## Oklab to screen. L runs up the middle, chroma spreads around it, and the
## yaw and pitch turn that solid rather than the picture of it.
func project(lab: Vector3) -> Vector2:
    var x := lab.y * cos(yaw) - lab.z * sin(yaw)
    var depth := lab.y * sin(yaw) + lab.z * cos(yaw)
    var y := lab.x - 0.5
    var screen_y := y * cos(pitch) - depth * sin(pitch)
    # One span for both axes, so the solid keeps its shape in a control of any
    # proportion. A per-axis span was tried and rejected: it fills a wide
    # control by squashing the volume to a quarter of its height, and a picture
    # of the amount of colour a space holds cannot be read off a shape whose
    # proportions are the panel's.
    var side := shorter_side()
    var span := side * SPREAD * zoom
    return Vector2(size.x * 0.5 + x * span, size.y * 0.5 - screen_y * span) + pan * side


## The side the picture is drawn about, never zero: a control asked to
## project before it has been laid out has no size, and a division by it is
## the pan coming back as a NaN that no later gesture can clear.
func shorter_side() -> float:
    return maxf(minf(size.x, size.y), 1.0)


## One RGB triple as Oklab, through this space's own gamut and curve. A
## document's numbers are not linear sRGB, so the matrix is not optional: it
## is the whole reason two spaces draw different shapes.
func to_oklab(rgb: Vector3) -> Vector3:
    return to_oklab_for(rgb, space)


## As `to_oklab`, but through whichever space is named, so the compare volume
## can be projected without disturbing this method's own single-argument shape a
## caller may already depend on.
func to_oklab_for(rgb: Vector3, for_space: SaColorSpace) -> Vector3:
    if for_space == null:
        return SaOklab.from_linear_srgb(rgb)
    var decoded := Vector3(for_space.transfer.decode(rgb.x), for_space.transfer.decode(rgb.y), for_space.transfer.decode(rgb.z))
    return SaOklab.from_linear_srgb(for_space.to_linear_srgb_matrix() * decoded)


func _gui_input(event: InputEvent) -> void:
    if apply_gesture(event):
        accept_event()


## Reads one gesture onto the solid and answers whether it was taken.
##
## Split from `_gui_input` for the reason the Graph docker's `apply_gesture`
## gives: an injected motion never reaches a `gui_input`, and `accept_event()`
## off an input pass is an error, so the part worth driving from a scenario
## or a test is the part without it.
##
## The gesture set is the clouds': left drag turns, shift or the middle button
## pans, the wheel zooms, and a double click puts the view back.
##
## **Inside a page that scrolls, only Ctrl+wheel zooms**. Every place
## the volume sits today is the tail of a long scrolling page, and a wheel that
## zoomed whenever the pointer crossed it stopped the page halfway down, on
## Preferences and on both dialogs' previews. A plain wheel there is left
## untaken, and the page scrolls. A volume standing alone keeps the plain wheel.
func apply_gesture(event: InputEvent) -> bool:
    # The wheel and a touchpad's scroll zoom by as much as they moved, up in.
    var moved := SaStep.notches(event).y
    if moved != 0.0:
        if not _wheel_zooms(event):
            return false
        zoom_at(pow(WHEEL_STEP, -moved), SaStep.where(event, size / 2.0))
        return true
    var button := event as InputEventMouseButton
    if button != null:
        if button.button_index == MOUSE_BUTTON_LEFT:
            if button.pressed and button.double_click:
                reset_view()
                return true
            _dragging = button.pressed and not button.shift_pressed
            _panning = button.pressed and button.shift_pressed
            return true
        if button.button_index == MOUSE_BUTTON_MIDDLE:
            _panning = button.pressed
            return true
        return false
    var motion := event as InputEventMouseMotion
    if motion == null:
        return false
    if _dragging:
        turn_by(motion.relative * TURN_PER_PIXEL)
        return true
    if _panning:
        pan_by(motion.relative / shorter_side())
        return true
    return false


## Whether *event*, a wheel or a touchpad scroll, is a zoom here: always when
## no ancestor scrolls vertically, and only with Ctrl held when one does.
func _wheel_zooms(event: InputEvent) -> bool:
    var keys := event as InputEventWithModifiers
    if keys != null and keys.ctrl_pressed:
        return true
    return scrolling_page() == null


## The nearest ancestor that scrolls up and down, or null when the volume
## stands alone.
func scrolling_page() -> ScrollContainer:
    var node := get_parent()
    while node != null:
        var scroll := node as ScrollContainer
        if scroll != null and scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
            return scroll
        node = node.get_parent()
    return null


## Turns the solid by *by* radians, yaw then pitch.
##
## The pitch is subtracted, which is the convention. Every orbit control in the trade
## lowers the eye when the pointer goes down, so a drag down tips the top of the
## solid towards the painter and eventually shows its underside. Adding was the
## sign the drawing shipped with, and it carried the far side downwards instead.
func turn_by(by: Vector2) -> void:
    yaw += by.x
    pitch = clampf(pitch - by.y, -PITCH_LIMIT, PITCH_LIMIT)
    queue_redraw()


## Moves the picture by *by*, in unit coordinates of the shorter side.
func pan_by(by: Vector2) -> void:
    pan += by
    queue_redraw()


## Zooms by *factor* about *at*, a point in this control, so whatever the
## pointer sits on stays under the pointer.
##
## The clouds zoom about the middle of their square instead, which is where
## the two controls differ and why: the cloud's zoom is a push constant the
## binning kernel reads, so zooming about a point would have to move the pan
## the same pass and re-bin, while here the projection is read back per
## frame and the correction is two lines.
func zoom_at(factor: float, at: Vector2) -> void:
    var next := clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
    if is_equal_approx(next, zoom):
        return
    var side := shorter_side()
    var pan_pixels := pan * side
    var from_middle := at - size * 0.5 - pan_pixels
    pan = (pan_pixels - from_middle * (next / zoom - 1.0)) / side
    zoom = next
    queue_redraw()


## Puts the viewpoint back where a fresh page has it.
func reset_view() -> void:
    yaw = YAW
    pitch = PITCH
    zoom = 1.0
    pan = Vector2.ZERO
    queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.10, 0.09), true)
    if space == null:
        return

    # The neutral axis, so the solid has something to be read against.
    draw_line(project(Vector3(0.0, 0.0, 0.0)), project(Vector3(1.0, 0.0, 0.0)), Color(1, 1, 1, 0.18), 1.0)

    # The bigger volume first, at full colour, so the selected one draws over it
    # dimmed rather than the other way round.
    if compare != null:
        _draw_wireframe(compare, 0.9)
    _draw_wireframe(space, 0.35 if compare != null else 0.95)


## The box each wireframe is drawn inside, and how far apart the two are.
##
## A screenshot of two nested wireframes is one shape to anybody who did not
## draw it, so the numbers are here rather than in the eye. `spread` is the largest
## distance between the two shapes' projected corners: zero means one shape
## drawn twice.
func report() -> Dictionary:
    var out := {
        "space": String(space.id) if space != null else "",
        "compare": String(compare.id) if compare != null else "",
        "space_box": _rect_of(space),
        "compare_box": _rect_of(compare),
        "size": [size.x, size.y],
        # Where the solid is being looked at from. Four numbers rather than a
        # picture of a turned wireframe, which is the only thing that could say
        # a wheel notch or a pan landed: two zooms a notch apart both draw a
        # wireframe and differ by a few per cent of a span.
        "yaw": yaw,
        "pitch": pitch,
        "zoom": zoom,
        "pan": {"x": pan.x, "y": pan.y},
        # The white corner where it lands on screen, which is the reading a
        # test checks: a drag down has to move it up.
        "white": _white_corner(),
    }
    out["spread"] = _corner_spread()
    out["distinct"] = out["spread"] > 1.0
    # Where the frame is on the window and whether the picture is cut at it. A
    # wireframe box that leaves the frame is a state to avoid,
    # and `clipped` is what keeps it inside.
    var frame := get_global_rect()
    out["frame"] = [frame.position.x, frame.position.y, frame.size.x, frame.size.y]
    # How far the page around the volume is scrolled, so a wheel over it reads as
    # a page that moved or a page that stayed. Minus one standing alone.
    var page := scrolling_page()
    out["page_scroll"] = page.scroll_vertical if page != null else -1
    out["clipped"] = clip_contents
    out["overflows"] = _overflows(out["space_box"]) or _overflows(out["compare_box"])
    return out


## Whether a projected box, as x, y, w, h in this control's own pixels, has a
## corner outside the control's rectangle.
func _overflows(box: Array) -> bool:
    if box.is_empty():
        return false
    var rect := Rect2(float(box[0]), float(box[1]), float(box[2]), float(box[3]))
    return not Rect2(Vector2.ZERO, size).encloses(rect)


## The projected screen position of the cube's white corner, as x and y, or
## nothing while no space is set.
func _white_corner() -> Array:
    if space == null:
        return []
    var at := project(to_oklab(Vector3(1, 1, 1)))
    return [at.x, at.y]


## The projected bounding box of one wireframe's corners, as x, y, w, h.
func _rect_of(for_space: SaColorSpace) -> Array:
    if for_space == null:
        return []
    var box := Rect2(project(to_oklab_for(CORNERS[0], for_space)), Vector2.ZERO)
    for corner: Vector3 in CORNERS:
        box = box.expand(project(to_oklab_for(corner, for_space)))
    return [box.position.x, box.position.y, box.size.x, box.size.y]


## The furthest any corner of one shape sits from the same corner of the
## other, in pixels of this control.
func _corner_spread() -> float:
    if space == null or compare == null:
        return 0.0
    var worst := 0.0
    for corner: Vector3 in CORNERS:
        var a := project(to_oklab_for(corner, space))
        var b := project(to_oklab_for(corner, compare))
        worst = maxf(worst, a.distance_to(b))
    return worst


## Every edge of the RGB cube, projected through *for_space*, each segment
## wearing the colour it stands for so the shape is readable without a
## legend, at *alpha* so a compared pair can tell which is which.
func _draw_wireframe(for_space: SaColorSpace, alpha: float) -> void:
    for edge: Vector2i in EDGES:
        var from: Vector3 = CORNERS[edge.x]
        var to: Vector3 = CORNERS[edge.y]
        for i in SEGMENTS:
            var t0 := float(i) / float(SEGMENTS)
            var t1 := float(i + 1) / float(SEGMENTS)
            var rgb0 := from.lerp(to, t0)
            var rgb1 := from.lerp(to, t1)
            var tint := Color(rgb0.x, rgb0.y, rgb0.z, alpha)
            draw_line(project(to_oklab_for(rgb0, for_space)), project(to_oklab_for(rgb1, for_space)), tint, 1.5)


## Moves the gamut solid's view: it turns, pans, zooms or resets the gamut solid
## from a scenario, `{"gamut_solid": {"drag": [0, 40]}}`, and prints what it is
## looking at.
##
## `drag` is a left drag in pixels and `shift` makes it a pan, `wheel` is one
## notch, positive in, `at` is where in the control the wheel turned, defaulting
## to the middle, and `reset` puts the view back. The gestures go through
## `apply_gesture`, the same door the pointer uses, because a scenario that
## called `turn_by` would prove the maths and not the wiring.
##
## Static and finding the control itself, because a scenario names a step and
## the step table has no node to hand it: the solid a gesture means is the one
## on screen, and the last visible browser is the one in front for the reason
## `SaColorSpaceBrowser._front_browser_row` gives.
static func capture_solid(tree: SceneTree, spec: Dictionary) -> String:
    var root := tree.get_root()
    var browser: SaColorSpaceBrowser = null
    for node in root.find_children("*", "VBoxContainer", true, false):
        if node is SaColorSpaceBrowser and node.is_visible_in_tree():
            browser = node as SaColorSpaceBrowser
    if browser == null or browser.solid == null:
        return "SaCapture: no gamut solid on screen"
    var solid: SaGamutSolid = browser.solid
    if bool(spec.get("reset", false)):
        solid.reset_view()
    if spec.has("drag"):
        var by := spec["drag"] as Array
        if by != null and by.size() >= 2:
            _drag_solid(solid, Vector2(float(by[0]), float(by[1])), bool(spec.get("shift", false)))
    if spec.has("wheel"):
        var at := solid.size * 0.5
        # `spec.get("at", null) as Array` is a cast of null, which is a runtime
        # error rather than a null, so the key is asked for before it is read.
        if spec.has("at"):
            var where := spec["at"] as Array
            if where != null and where.size() >= 2:
                at = Vector2(float(where[0]), float(where[1]))
        _wheel_solid(solid, float(spec["wheel"]) > 0.0, at)
    return "SaCapture: gamut solid %s" % JSON.stringify(solid.report())


## One whole left drag of *relative* pixels on *solid*, a pan when *shift*,
## through the handler the pointer uses.
static func _drag_solid(solid: SaGamutSolid, relative: Vector2, shift: bool) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.shift_pressed = shift
    solid.apply_gesture(press)
    var motion := InputEventMouseMotion.new()
    motion.relative = relative
    solid.apply_gesture(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.shift_pressed = shift
    solid.apply_gesture(release)


## One wheel notch on *solid* at *at*, in on *up*.
static func _wheel_solid(solid: SaGamutSolid, up: bool, at: Vector2) -> void:
    var wheel := InputEventMouseButton.new()
    # The step drives the zoom, so it holds the chord a page that scrolls asks
    # for, and a plain wheel over a page is the pointer's to prove.
    wheel.ctrl_pressed = true
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
    wheel.pressed = true
    wheel.position = at
    solid.apply_gesture(wheel)
