## The hue ring and whatever the painter picks inside it: the colour docker's
## whole gesture area, in one of three shapes.
##
## Apart from `sa_color_picker.gd` because the shapes are many times the
## geometry one is.
## The picker keeps the colour, the swatches and the rows around it. This keeps
## the ring, the area inside it and the model each shape reads that area with.
##
## The three shapes:
##
## - **Wheel**, OKHSV. A ring for the hue, and inside it saturation across and
##   value up.
## - **OKHSL**, Sara's own, defined in [OkhslConversions]. A disc filling the
##   frame with the hue around it and saturation out from the middle, and a
##   lightness bar beside it. No ring, because the disc's own rim is one: an
##   inner disc under an outer ring would be two controls for one hue. The rim
##   is saturation 1 at every hue, so the circle is round rather than the shape
##   of the gamut, a circle of one size at every hue.
## - **Triangle**, OKLCh. A ring for the hue, and inside it chroma across and
##   Oklab lightness up, so the region a hue can actually reach is the triangle
##   between black, white and its cusp. The width is that hue's own cusp chroma
##   rather than one constant for every hue, so every triangle fills its frame.
## - **Triangle, saturation up**, the same slice turned a quarter turn.
##   Lightness runs along the bottom edge, black at the left and white at the
##   right, and chroma runs up from that edge to the hue's cusp at the top. A
##   shape of its own rather than a change to the third, so a painter who
##   knows either keeps it.
##
## - **The three classic shapes**, because some painters know them so well
##   that they cannot work without them. Plain
##   RGB hue, saturation and value or lightness in the sRGB encoding, the maths
##   every other painting program draws with, in
##   `shaders/ui/hsv_picker.gdshader`. The **HSV square** sits in a hue ring,
##   saturation across and value up. The **HSV triangle** sits in the same ring,
##   the hue at the top corner and white and black at the two bottom ones, read
##   in barycentric weights. The **HSL square** has a hue bar beside it instead
##   of a ring, saturation across and lightness up, the way a dialog picker
##   draws it. A shortcut profile does not choose among them: a profile writes
##   chords and nothing else.
##
## Every shape holds the same three numbers, a hue and two axes from 0 to 1, so
## switching shape keeps the gesture the painter is in the middle of rather than
## resetting it. What the two axes mean is the shape's business and nobody
## else's: outside this file a colour goes in and a colour comes out.
extends Control

class_name SaPickerShape

## The colour under the cursor changed, at any point during a gesture.
signal color_changed(color: Color)
## A gesture ended, so this colour was chosen rather than passed over.
signal color_committed(color: Color)

enum Kind { WHEEL, OKHSL, TRIANGLE, TRIANGLE_UP, HSV_SQUARE, HSV_TRIANGLE, HSL_SQUARE }

const OkhslConversionsScript = preload("res://utils/okhsl_conversions.gd")
const OkhsvConversionsScript = preload("res://utils/okhsv_conversions.gd")
## Paths loaded where a material wants them, not preloaded. The boot compiles
## this script on a worker thread, and a preload of a resource that is not a
## script is a nested threaded load there. Godot 4.7 leaves that load's token
## behind as an object leaked at exit whenever the worker ran the load itself
## before the pool got to it, which it did for both of these. A `load` on
## the main thread takes the cache and makes no second task.
const OKHSV_SHADER_PATH := "res://shaders/ui/okhsv_picker.gdshader"
const HSV_SHADER_PATH := "res://shaders/ui/hsv_picker.gdshader"

## What each shape is called in the settings file and in the docker's dropdown.
## The stored name is the key, so a profile is readable and a shape added later
## does not renumber the ones before it.
const KIND_KEYS: Array[String] = ["wheel", "okhsl", "triangle", "triangle_up", "hsv_square", "hsv_triangle", "hsl_square"]

## **The colour model first, the arrangement second, over all seven**.
##
## HSV is named square and okHSV is named wheel while both are the same shape.
## The wheel and the
## HSV square are one geometry to the texel, the same ring, the same 0.552
## inset, the same across-and-up read of the area, the same shader mode. What
## separates them is the colour model, OKHSV against sRGB HSV, so that is what
## leads every label. The arrangement follows it, because it is the only thing
## that tells the two OKLCh entries apart and the two HSV ones, and a list
## where some entries carry the second clause and some do not reads as two
## lists. The keys above do not move: a painter's stored choice is one of them.
const KIND_LABELS: Array[String] = [
    "OKHSV, square",
    "OKHSL, disc",
    "OKLCh, triangle",
    "OKLCh, triangle, saturation up",
    "HSV, square",
    "HSV, triangle",
    "HSL, square",
]

## The shapes drawn by the classic shader rather than the Oklab one. The
## families share the ring and the area, and `set_kind` swaps the shader
## under both when a switch crosses between them.
const CLASSIC_KINDS: Array[int] = [Kind.HSV_SQUARE, Kind.HSV_TRIANGLE, Kind.HSL_SQUARE]

## The ring's band, as a fraction of the frame's half-size, and the two radii
## the gesture reads it at. The inner one is under the band so a press just
## short of the ring still turns the hue rather than doing nothing.
const RING_INNER: float = 0.83
const RING_OUTER: float = 0.98
const RING_GRAB_INNER: float = 0.78
const RING_GRAB_OUTER: float = 1.06

## The inner area's side, as a fraction of the frame. Under the ring's inner
## radius over root two, so the corners of the square clear the band.
const AREA_FRACTION: float = 0.552

## The HSV triangle's area, the same fraction: its corners sit on the circle
## of the area's half-side, so a triangle in a square that clears the ring
## clears it too, and the drawing is what the cursor maths is measured in.
const TRIANGLE_FRACTION: float = 0.7

## The smallest the frame is allowed to get, logical units, so a docker dragged
## down to nothing still shows a ring rather than a dot.
const FRAME_MIN: int = 64

## The lightness bar beside the OKHSL disc, and the hue bar beside the
## HSL square: their width and the gap between them and the frame, logical
## units.
const SLIDER_W: int = 18
const SLIDER_GAP: int = 6

## Which `picker_mode` in the shape's own shader draws its inner area, the
## Oklab shader's for the first four and the classic shader's for the rest. A
## table rather than a chain of conditionals, because a fourth shape turned
## the chain into something no one could read in one pass.
const AREA_MODES: Array[int] = [1, 2, 3, 4, 1, 2, 3]
const RING_MODE: int = 0
const HUE_BAR_MODE: int = 4
## The Oklab shader's mode for the disc's lightness bar.
const LIGHTNESS_BAR_MODE: int = 5
## How much one wheel notch over the lightness bar moves the lightness.
const LIGHTNESS_WHEEL_STEP: float = 0.02

## **Where a colour sits on the ring**, one angle for one colour whichever
## family draws it, so switching between an HSV and an OKHSV shape does not
## move yellow round the ring. Both families lay their ring out by Oklab hue, the angle the colour itself
## has, turned so that yellow is straight down. An Oklab hue is the ring's
## angle as it stands. An sRGB HSV hue is carried there piecewise: each of the
## six primaries goes to its own Oklab hue and the hues between them are
## spread evenly across that span, so red, yellow, green, cyan, blue and
## magenta sit at one angle in either family and the HSV ring still turns the
## same way at an even pace inside each sixth. The two shaders hold the same
## numbers, and `test_the_hue_rings_agree.gd` holds all three to each other.
##
## Angles are in turns, clockwise on screen from the right, the way `atan2`
## reads a pointer offset whose y grows downwards.
const RING_YELLOW_HUE: float = 0.30494
const RING_YELLOW_ANGLE: float = 0.25
## The Oklab hue of sRGB red, yellow, green, cyan, blue and magenta, in turns,
## which is where the HSV ring's sixths begin.
const HSV_PRIMARY_HUES: Array[float] = [0.08121, 0.30494, 0.39582, 0.54102, 0.73348, 0.91212]

var kind: int = Kind.WHEEL
## The hue the ring is showing, in turns. A grey does not say what this is, so
## it is worth reading on its own rather than through the colour.
var hue: float = 0.0
## The two axes of the inner area, left to right and bottom to top. What they
## mean depends on `kind`, which is why they are not called s and v.
var _across: float = 0.0
var _up: float = 0.0
var _dragging: int = 0  # 0 = none, 1 = the ring, 2 = the area
## **Keep chroma**, the colour docker's switch: while it is on, a turn of the
## ring holds the colour's Oklab lightness and its distance from the grey axis
## rather than the two numbers the area is in. Written by the docker from its
## option, off unless the painter turns it on.
var keep_chroma: bool = false
## The Oklab lightness and chroma a ring gesture started from, held for the
## whole gesture so a hue with less room does not wear the chroma down. x below
## zero means no gesture has read it yet.
var _kept := Vector2(-1.0, 0.0)

var _ring_mat: ShaderMaterial
var _area_mat: ShaderMaterial

var frame: Control
var ring_rect: ColorRect
var area_rect: ColorRect
var cursors_overlay: Control

## The OKHSL disc's third axis, which the disc itself has no room for. A bar
## beside the disc, shown for that shape alone, drawn the way the hue bar is:
## black at the foot to white at the head through every lightness of the
## colour's own hue and saturation. It writes the same `_up` the square's Y
## axis did.
var lightness_bar: ColorRect
var _lightness_bar_mat: ShaderMaterial
var _lightness_bar_cursor: Control
var _dragging_lightness: bool = false

## The HSL square's hue, which that shape has no ring for: a bar beside the
## square, red at the top and round to red again, dragged like the ring is.
var hue_bar: ColorRect
var _hue_bar_mat: ShaderMaterial
var _hue_bar_cursor: Control
var _dragging_bar: bool = false

## True while a motion of a drag is being followed, so the colour it reaches
## waits for the frame's end rather than going out at once.
var _moving: bool = false
## True while a motion's colour waits to be sent at the frame's end.
var _held_back: bool = false
## What a drag's sends cost and where its handle was drawn, for the dump.
var _ledger := SaPickerDragLedger.new()

var _center: Control


func _init() -> void:
    name = "PickerShape"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL

    _center = Control.new()
    _center.name = "ShapeCenter"
    _center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_center)

    frame = Control.new()
    frame.name = "ShapeFrame"
    frame.custom_minimum_size = Vector2(SaUI.px(FRAME_MIN), SaUI.px(FRAME_MIN))
    _center.add_child(frame)

    _ring_mat = ShaderMaterial.new()
    _ring_mat.shader = load(OKHSV_SHADER_PATH) as Shader
    _ring_mat.set_shader_parameter("picker_mode", 0)
    _ring_mat.set_shader_parameter("inner_radius", RING_INNER)
    _ring_mat.set_shader_parameter("outer_radius", RING_OUTER)
    _ring_mat.set_shader_parameter("mark_angles", mark_angles())
    # The ring has no parameters of its own beyond its two radii. The two hue
    # anchors and their two lightness factors are gone, because the ring rides
    # each hue's cusp and the cusp is not something a caller can be wrong about:
    # yellow is light and blue is dark because that is where the sRGB gamut puts
    # them, not because this file said so.

    ring_rect = ColorRect.new()
    ring_rect.name = "RingRect"
    ring_rect.material = _ring_mat
    ring_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    ring_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    frame.add_child(ring_rect)

    _area_mat = ShaderMaterial.new()
    _area_mat.shader = load(OKHSV_SHADER_PATH) as Shader
    _area_mat.set_shader_parameter("picker_mode", 1)
    _area_mat.set_shader_parameter("current_hue", 0.0)
    # The disc's rim is its ring, so it carries the marks too.
    _area_mat.set_shader_parameter("mark_angles", mark_angles())

    area_rect = ColorRect.new()
    area_rect.name = "AreaRect"
    area_rect.material = _area_mat
    area_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
    area_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    frame.add_child(area_rect)

    cursors_overlay = Control.new()
    cursors_overlay.name = "CursorsOverlay"
    cursors_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    cursors_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    cursors_overlay.draw.connect(_on_cursors_draw)
    frame.add_child(cursors_overlay)

    _lightness_bar_mat = ShaderMaterial.new()
    _lightness_bar_mat.shader = load(OKHSV_SHADER_PATH) as Shader
    _lightness_bar_mat.set_shader_parameter("picker_mode", LIGHTNESS_BAR_MODE)
    lightness_bar = ColorRect.new()
    lightness_bar.name = "DiscLightness"
    lightness_bar.material = _lightness_bar_mat
    lightness_bar.visible = false
    lightness_bar.tooltip_text = tr("Set the lightness, which the disc has no axis for.")
    lightness_bar.gui_input.connect(_on_lightness_bar_gui_input)
    add_child(lightness_bar)
    _lightness_bar_cursor = Control.new()
    _lightness_bar_cursor.name = "DiscLightnessCursor"
    _lightness_bar_cursor.set_anchors_preset(Control.PRESET_FULL_RECT)
    _lightness_bar_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _lightness_bar_cursor.draw.connect(_on_lightness_bar_draw)
    lightness_bar.add_child(_lightness_bar_cursor)

    _hue_bar_mat = ShaderMaterial.new()
    _hue_bar_mat.shader = load(HSV_SHADER_PATH) as Shader
    _hue_bar_mat.set_shader_parameter("picker_mode", HUE_BAR_MODE)
    _hue_bar_mat.set_shader_parameter("mark_angles", mark_angles())
    hue_bar = ColorRect.new()
    hue_bar.name = "HueBar"
    hue_bar.material = _hue_bar_mat
    hue_bar.visible = false
    hue_bar.tooltip_text = tr("Set the hue, which the square has no ring for.")
    hue_bar.gui_input.connect(_on_hue_bar_gui_input)
    add_child(hue_bar)
    _hue_bar_cursor = Control.new()
    _hue_bar_cursor.name = "HueBarCursor"
    _hue_bar_cursor.set_anchors_preset(Control.PRESET_FULL_RECT)
    _hue_bar_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hue_bar_cursor.draw.connect(_on_hue_bar_draw)
    hue_bar.add_child(_hue_bar_cursor)

    _center.resized.connect(_on_center_resized)
    frame.resized.connect(_on_frame_resized)
    frame.gui_input.connect(_on_frame_gui_input)
    # Grey while a mask is the paint target, here as well as over the docker's
    # whole picker, so the palette's ring shows no hue then either.
    add_child(SaGreyVeil.new())


func _ready() -> void:
    _apply_layout()


## A shape that is hidden or leaves the tree mid drag will never hear the
## release, so the drag ends there as if the button had come up.
func _notification(what: int) -> void:
    if what == NOTIFICATION_EXIT_TREE or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
        _end_drag()


## The end of every drag, the ring's, the area's and both bars': the first
## event that shows the left button up, wherever it was let go. A release let
## go outside the window reaches no control here, so a motion whose mask has
## lost the left button ends the drag as well, and moves nothing. The colour
## the drag reached is committed once.
func _end_drag() -> void:
    if _dragging == 0 and not _dragging_bar and not _dragging_lightness:
        return
    _dragging = 0
    _dragging_bar = false
    _dragging_lightness = false
    _send_held_back()
    color_committed.emit(color())


## Whether *event* is a motion made with the left button up, which ends a drag.
static func _left_is_up(event: InputEventMouseMotion) -> bool:
    return (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0


## The shape shown, one of [enum Kind]. The colour on screen is kept across a
## switch: the axes are re-read from it in the new shape's own model, which is
## the only thing that makes the three interchangeable mid-gesture.
func set_kind(wanted: int) -> void:
    if wanted == kind or wanted < 0 or wanted >= KIND_KEYS.size():
        return
    var held := color()
    kind = wanted
    var shader := load(HSV_SHADER_PATH if is_classic(wanted) else OKHSV_SHADER_PATH) as Shader
    _area_mat.shader = shader
    _ring_mat.shader = shader
    _area_mat.set_shader_parameter("picker_mode", AREA_MODES[wanted])
    _ring_mat.set_shader_parameter("picker_mode", RING_MODE)
    # Set again after the swap rather than trusted to outlive it, so a shape
    # never shows a ring without its marks.
    _ring_mat.set_shader_parameter("mark_angles", mark_angles())
    _area_mat.set_shader_parameter("mark_angles", mark_angles())
    _read_axes(held)
    _apply_layout()
    _refresh()


## Whether *which* is one of the three classic shapes.
static func is_classic(which: int) -> bool:
    return CLASSIC_KINDS.has(which)


## What the chosen shape does to the frame: the disc and the HSL square take
## the whole of it, the disc putting the ring's job on its own rim and the
## square putting it on the bar beside it, and the rest keep the ring and the
## area inside it.
func _apply_layout() -> void:
    var disc := kind == Kind.OKHSL
    var hsl := kind == Kind.HSL_SQUARE
    if ring_rect:
        ring_rect.visible = not disc and not hsl
    if lightness_bar:
        lightness_bar.visible = disc
    if hue_bar:
        hue_bar.visible = hsl
    if area_rect:
        area_rect.visible = true
    _on_center_resized()


## The [enum Kind] the settings string *key* names, or the wheel for anything
## a newer build might have written.
static func kind_of(key: String) -> int:
    var at := KIND_KEYS.find(key)
    return at if at != -1 else Kind.WHEEL


## The part a gesture in progress holds, as the usage tally names it: the ring
## or the hue bar, the area, or the lightness slider.
func part_moving() -> StringName:
    if _dragging == 1 or _dragging_bar:
        return SaUsageTally.RING
    return SaUsageTally.SQUARE if _dragging == 2 else SaUsageTally.SLIDER


func kind_key() -> String:
    return KIND_KEYS[kind]


## Shows *col* without emitting anything.
##
## A grey has no hue, so taking the zero the conversion reports would drag the
## ring back to red every time a painter samples the background and leave them
## painting red when they move into the area. Stepping the ring's current hue
## by the golden angle instead means the colour under the area cursor is a
## different one after every such pick, deliberately rather than by rounding
## noise.
func set_from_color(col: Color) -> void:
    var shown := hue
    _kept.x = -1.0
    _read_axes(col)
    if OkhsvConversionsScript.is_achromatic(col):
        # From the hue the ring was on, not from the zero `_read_axes` just
        # wrote: stepping from zero every time lands on the same hue twice.
        hue = OkhsvConversionsScript.step_hue(shown)
    _refresh()


## The colour the three numbers stand for in the shape now shown.
func color() -> Color:
    match kind:
        Kind.OKHSL:
            return OkhslConversionsScript.okhsl_to_srgb(hue, _across, _up)
        Kind.TRIANGLE:
            return OkhslConversionsScript.oklch_to_srgb(hue, _across * OkhslConversionsScript.cusp_chroma(hue), _up)
        Kind.TRIANGLE_UP:
            # The same two numbers as the triangle above, read the other way
            # round: chroma is the vertical axis and lightness the horizontal.
            return OkhslConversionsScript.oklch_to_srgb(hue, _up * OkhslConversionsScript.cusp_chroma(hue), _across)
        Kind.HSV_SQUARE, Kind.HSV_TRIANGLE:
            return Color.from_hsv(hue, _across, _up)
        Kind.HSL_SQUARE:
            return SaPickerClassic.hsl_to_srgb(hue, _across, _up)
        _:
            return OkhsvConversionsScript.okhsv_to_srgb(hue, _across, _up)


## What a capture reads to say which shape is up and where its two cursors
## are, neither of which a screenshot names.
func report() -> Dictionary:
    return {
        "kind": kind_key(),
        "kinds": KIND_KEYS.duplicate(),
        "hue": hue,
        "keep_chroma": keep_chroma,
        "across": _across,
        "up": _up,
        "color": color().to_html(false),
        "area_mode": int(_area_mat.get_shader_parameter("picker_mode")),
        "ring_visible": ring_rect != null and ring_rect.visible,
        "classic": is_classic(kind),
        "lightness_slider_visible": lightness_bar != null and lightness_bar.visible,
        "hue_bar_visible": hue_bar != null and hue_bar.visible,
        "hue_bar_rect": _rect(hue_bar.get_global_rect()) if hue_bar != null else {},
        "lightness_bar_rect": _rect(lightness_bar.get_global_rect()) if lightness_bar != null else {},
        "lightness_slider": _up if lightness_bar != null else 0.0,
        # What the horizontal axis is worth at this hue. One constant for every
        # hue is what made the triangle small, so the number the stretch turns
        # on belongs in the dump.
        "cusp_chroma": OkhslConversionsScript.cusp_chroma(hue),
        "triangle_reach": _triangle_reach(),
        "area_rect": {"x": area_rect.position.x, "y": area_rect.position.y, "w": area_rect.size.x, "h": area_rect.size.y},
        # Where the gesture area actually is on screen, so a scenario can press
        # the ring or the disc rather than guess at the docker's insides.
        "frame_rect": _rect(frame.get_global_rect()),
        "ring_radius": minf(frame.size.x, frame.size.y) * 0.5 * (RING_INNER + RING_OUTER) * 0.5,
        # Where the hue sits round the ring, in turns clockwise from the right,
        # which is the same number for one colour in either family.
        "ring_angle": ring_angle(hue, is_classic(kind)),
        "sends": _ledger.report()["sends"],
        "drawn": _ledger.report()["drawn"],
        # Where the pointer was last heard over the frame, in its own pixels,
        # which is how a scenario finds a let-out picker on a seat.
        "pointer": {"x": frame.get_local_mouse_position().x, "y": frame.get_local_mouse_position().y},
        "hovered": _hovered(),
    }


## Whether the pointer is over the frame in the frame's own window, which a
## reading of the pointer alone cannot say: every window answers one.
func _hovered() -> bool:
    var under := frame.get_viewport().gui_get_hovered_control() if frame.is_inside_tree() else null
    return under != null and (under == frame or frame.is_ancestor_of(under))


static func _rect(r: Rect2) -> Dictionary:
    return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}


func _read_axes(col: Color) -> void:
    match kind:
        Kind.OKHSL:
            var hsl := OkhslConversionsScript.srgb_to_okhsl(col)
            hue = hsl.x
            _across = hsl.y
            _up = hsl.z
        Kind.TRIANGLE, Kind.TRIANGLE_UP:
            var lch := OkhslConversionsScript.srgb_to_oklch(col)
            hue = lch.x
            # Through the same cusp the drawing uses, or a colour set from the
            # hex box lands somewhere else than the colour under the cursor.
            var widest := OkhslConversionsScript.cusp_chroma(lch.x)
            var chroma := clampf(lch.y / widest, 0.0, 1.0) if widest > 0.0 else 0.0
            var lightness := clampf(lch.z, 0.0, 1.0)
            _across = lightness if kind == Kind.TRIANGLE_UP else chroma
            _up = chroma if kind == Kind.TRIANGLE_UP else lightness
        Kind.HSV_SQUARE, Kind.HSV_TRIANGLE:
            # A grey has no hue and the engine reports zero for it, so the ring
            # stays where it was rather than swinging back to red.
            if col.s > 0.0:
                hue = col.h
            _across = col.s
            _up = col.v
        Kind.HSL_SQUARE:
            var hsl := SaPickerClassic.srgb_to_hsl(col)
            if hsl.y > 0.0:
                hue = hsl.x
            _across = hsl.y
            _up = hsl.z
        _:
            var hsv := OkhsvConversionsScript.srgb_to_okhsv(col)
            hue = hsv.x
            _across = hsv.y
            _up = hsv.z


## What the lightness bar or the hue bar takes of the control's width beside
## the frame, the gap included, and nothing for a shape that carries neither.
## The colour picker docker reads it to know how much of its width the frame
## can have.
func bar_width() -> float:
    var beside := (lightness_bar != null and lightness_bar.visible) or (hue_bar != null and hue_bar.visible)
    if not beside:
        return 0.0
    return float(SaUI.px(SLIDER_W) + SaUI.px(SLIDER_GAP))


## The frame is the largest square the control can hold, less whatever the
## lightness bar takes when it is showing.
func _on_center_resized() -> void:
    if _center == null or frame == null:
        return
    var room := _center.size
    room.x = maxf(room.x - bar_width(), 0.0)
    var side := maxf(minf(room.x, room.y), float(SaUI.px(FRAME_MIN)))
    frame.size = Vector2(side, side)
    frame.position = Vector2((room.x - side) * 0.5, (room.y - side) * 0.5)
    var beside_size := Vector2(float(SaUI.px(SLIDER_W)), side)
    var beside_at := Vector2(frame.position.x + side + float(SaUI.px(SLIDER_GAP)), frame.position.y)
    if lightness_bar != null and lightness_bar.visible:
        lightness_bar.size = beside_size
        lightness_bar.position = beside_at
    if hue_bar != null and hue_bar.visible:
        hue_bar.size = beside_size
        hue_bar.position = beside_at
    _on_frame_resized()


## The area inside the ring, or the whole frame for the disc, which has no ring
## around it to clear.
func _on_frame_resized() -> void:
    if frame and area_rect:
        var fraction := AREA_FRACTION
        if kind == Kind.OKHSL or kind == Kind.HSL_SQUARE:
            fraction = 1.0
        elif kind == Kind.HSV_TRIANGLE:
            fraction = TRIANGLE_FRACTION
        var side := roundf(minf(frame.size.x, frame.size.y) * fraction)
        area_rect.custom_minimum_size = Vector2(side, side)
        area_rect.size = Vector2(side, side)
        area_rect.position = (frame.size - area_rect.size) * 0.5
    if cursors_overlay:
        cursors_overlay.queue_redraw()


func _on_frame_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        var mb := event as InputEventMouseButton
        if mb.pressed:
            _begin_drag(mb.position)
        elif _dragging != 0:
            # The gesture ended on a colour, the one under the release, which
            # is the one the recent list should remember, rather than every
            # colour the drag passed over.
            _follow_frame(mb.position)
            _end_drag()
    elif event is InputEventMouseMotion and _dragging != 0:
        var mm := event as InputEventMouseMotion
        if _left_is_up(mm):
            _end_drag()
        else:
            _moving = true
            _follow_frame(mm.position)
            _moving = false


## The ring or the area, whichever the gesture under way began on, moved to *at*.
func _follow_frame(at: Vector2) -> void:
    if _dragging == 1:
        _drag_ring(at - frame.size * 0.5)
    else:
        _drag_area(at)


func _begin_drag(at: Vector2) -> void:
    _kept.x = -1.0
    if kind == Kind.OKHSL or kind == Kind.HSL_SQUARE:
        # The disc and the HSL square are the whole frame and there is no ring
        # to miss, so every press in it is the one gesture.
        _dragging = 2
        if kind == Kind.OKHSL:
            _lift(0.0)
        _drag_area(at)
        return
    var offset := at - frame.size * 0.5
    var half := minf(frame.size.x, frame.size.y) * 0.5
    var norm := offset.length() / half if half > 0.0 else 0.0
    # The triangle's area is a square whose corners reach into the ring, so
    # only the distance from the centre says which of the two was pressed.
    var in_area := norm < RING_GRAB_INNER
    if kind != Kind.HSV_TRIANGLE:
        in_area = in_area or area_rect.get_rect().grow(SaUI.px(6)).has_point(at)
    if in_area:
        _dragging = 2
        _drag_area(at)
    elif norm <= RING_GRAB_OUTER:
        _dragging = 1
        _lift(ring_hue(fposmod(atan2(offset.y, offset.x) / TAU, 1.0), is_classic(kind)))
        _drag_ring(offset)
    else:
        _dragging = 0


func _drag_ring(offset: Vector2) -> void:
    _turn_to(ring_hue(fposmod(atan2(offset.y, offset.x) / TAU, 1.0), is_classic(kind)))
    _emit()


## A gesture that turns the hue on a colour too dark to show one starts from
## the mid colour of *to_hue* [SaRingLift] gives, once, as it starts. The disc
## turns its hue with its own press, so there the lift is its lightness alone.
func _lift(to_hue: float) -> void:
    if not SaRingLift.is_dark(color()):
        return
    if kind == Kind.OKHSL:
        _up = SaRingLift.DISC_LIGHTNESS
        return
    var classic_hue := OkhslConversionsScript.srgb_to_oklch(Color.from_hsv(to_hue, 1.0, 1.0)).x
    _read_axes(SaRingLift.colour(classic_hue if is_classic(kind) else to_hue))


## Puts the ring on *to_hue*, and with [member keep_chroma] on moves the point
## in the area to where the colour of the same Oklab lightness and chroma sits
## at that hue. The hue is the pointer's on every shape, so the ring's cursor
## stays under it and only the point in the area moves.
##
## The chroma is the one the gesture started with, not the one the last event
## left, so a hue whose gamut is narrower at this lightness stops the point on
## its edge and turning back to the first hue gives the first colour again. On
## the classic shapes the hue is an sRGB one, so the point is the one of that
## hue nearest the kept pair, found in the shape's own model by
## [method SaPickerClassic.nearest_to_lc] from where the colour of the pure
## colour's Oklab hue sits, in saturation and value.
func _turn_to(to_hue: float) -> void:
    if not keep_chroma:
        hue = to_hue
        return
    if _kept.x < 0.0:
        var start := OkhslConversionsScript.srgb_to_oklch(color())
        _kept = Vector2(start.z, start.y)
    var classic := is_classic(kind)
    var oklab_hue := OkhslConversionsScript.srgb_to_oklch(Color.from_hsv(to_hue, 1.0, 1.0)).x if classic else to_hue
    var target := OkhslConversionsScript.oklch_to_srgb(oklab_hue, _kept.y, _kept.x)
    _read_axes(target)
    hue = to_hue
    if classic:
        var sv := SaPickerClassic.nearest_to_lc(to_hue, _kept, Vector2(target.s, target.v))
        if kind == Kind.HSL_SQUARE:
            var hsl := SaPickerClassic.srgb_to_hsl(Color.from_hsv(to_hue, sv.x, sv.y))
            sv = Vector2(hsl.y, hsl.z)
        _across = sv.x
        _up = sv.y


## The ring's angle in turns for *at_hue*, an sRGB HSV hue when *classic* and
## an Oklab hue otherwise.
static func ring_angle(at_hue: float, classic: bool) -> float:
    var oklab_hue := at_hue
    if classic:
        var sixths := fposmod(at_hue, 1.0) * 6.0
        var i := mini(int(sixths), 5)
        var from := HSV_PRIMARY_HUES[i]
        var to := HSV_PRIMARY_HUES[(i + 1) % 6] + (1.0 if i == 5 else 0.0)
        oklab_hue = lerpf(from, to, sixths - float(i))
    return fposmod(oklab_hue - RING_YELLOW_HUE + RING_YELLOW_ANGLE, 1.0)


## The hue at *angle* turns round the ring, the inverse of [method ring_angle].
static func ring_hue(angle: float, classic: bool) -> float:
    var oklab_hue := fposmod(angle - RING_YELLOW_ANGLE + RING_YELLOW_HUE, 1.0)
    if not classic:
        return oklab_hue
    # Below red's own Oklab hue is the last sixth, magenta back round to red.
    var i := 5
    for k in range(5, -1, -1):
        if oklab_hue >= HSV_PRIMARY_HUES[k]:
            i = k
            break
    var from := HSV_PRIMARY_HUES[i]
    var to := HSV_PRIMARY_HUES[(i + 1) % 6] + (1.0 if i == 5 else 0.0)
    var along := oklab_hue if oklab_hue >= from else oklab_hue + 1.0
    return fposmod((float(i) + (along - from) / (to - from)) / 6.0, 1.0)


## **The six marks on the ring**, one at each of pure sRGB red, yellow, green,
## cyan, blue and magenta, in turns clockwise from the right. Each is the
## angle [method ring_angle] gives that colour's Oklab hue, which both families
## share, so the mark says where the colour is rather than where a sixth of
## the circle is. Both shaders take this as `mark_angles`, and the HSL
## square's hue bar reads its marks from the same list through the classic
## shader's own `hue_at_angle`.
static func mark_angles() -> PackedFloat32Array:
    var out := PackedFloat32Array()
    for oklab_hue: float in HSV_PRIMARY_HUES:
        out.append(ring_angle(oklab_hue, false))
    return out


func _drag_area(at: Vector2) -> void:
    if kind == Kind.OKHSL:
        _drag_disc(at)
        return
    var local := at - area_rect.position
    if kind == Kind.HSV_TRIANGLE:
        _drag_triangle(local)
        return
    _across = clampf(local.x / area_rect.size.x, 0.0, 1.0) if area_rect.size.x > 0.0 else 0.0
    _up = clampf(1.0 - (local.y / area_rect.size.y), 0.0, 1.0) if area_rect.size.y > 0.0 else 0.0
    # A press outside the triangle is a press on its edge, so the cursor rides
    # the gamut rather than sitting in the empty corner beside it. Which of the
    # two axes gets clamped is the whole difference between the two triangles.
    if kind == Kind.TRIANGLE:
        _across = minf(_across, _triangle_reach())
    elif kind == Kind.TRIANGLE_UP:
        _up = minf(_up, _triangle_reach())
    _emit()


## The HSV triangle reads its two axes off the corner weights: value is what
## is not black, saturation the hue's share of the rest. A press outside the
## triangle has a weight below zero, and clamping the two axes puts the
## cursor on the nearest edge the way the Oklab triangles ride their slope.
func _drag_triangle(local: Vector2) -> void:
    if area_rect.size.x <= 0.0 or area_rect.size.y <= 0.0:
        return
    var weights := SaPickerClassic.triangle_weights(local / area_rect.size)
    var v := clampf(1.0 - weights.z, 0.0, 1.0)
    var lit := weights.x + weights.y
    _up = v
    _across = clampf(weights.x / lit, 0.0, 1.0) if lit > 1e-6 and v > 0.0 else 0.0
    _emit()


## The hue bar is the ring's job for the HSL square: a press or a drag along
## it sets the hue by how far down the bar the pointer is, red at the top.
func _on_hue_bar_gui_input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            _dragging_bar = true
            _kept.x = -1.0
            _lift(clampf(button.position.y / hue_bar.size.y, 0.0, 1.0) if hue_bar.size.y > 0.0 else hue)
            _drag_bar(button.position)
        elif _dragging_bar:
            _drag_bar(button.position)
            _end_drag()
        return
    var motion := event as InputEventMouseMotion
    if motion != null and _dragging_bar:
        if _left_is_up(motion):
            _end_drag()
        else:
            _moving = true
            _drag_bar(motion.position)
            _moving = false


func _drag_bar(at: Vector2) -> void:
    if hue_bar.size.y <= 0.0:
        return
    _turn_to(clampf(at.y / hue_bar.size.y, 0.0, 1.0))
    _emit()


## The bar's cursor, a line across it at the hue, in the two rims the other
## cursors wear.
func _on_hue_bar_draw() -> void:
    var y := hue * hue_bar.size.y
    _hue_bar_cursor.draw_line(Vector2(0.0, y), Vector2(hue_bar.size.x, y), Color.BLACK, SaUI.pxf(3.0), true)
    _hue_bar_cursor.draw_line(Vector2(0.0, y), Vector2(hue_bar.size.x, y), Color.WHITE, SaUI.pxf(1.5), true)


## The disc reads hue and saturation from one gesture: the angle round the
## middle and the distance out from it. A press past the rim is a press on the
## rim, the way a press outside the triangle is a press on its slope, so a drag
## that leaves the circle keeps painting the hue it is pointing at.
func _drag_disc(at: Vector2) -> void:
    var half := minf(area_rect.size.x, area_rect.size.y) * 0.5
    var offset := at - area_rect.position - area_rect.size * 0.5
    _across = clampf(offset.length() / half, 0.0, 1.0) if half > 0.0 else 0.0
    if _across > 0.0:
        # A press dead in the middle is a grey, and a grey has no angle to
        # read, so the hue stays where the painter last put it.
        hue = ring_hue(fposmod(atan2(offset.y, offset.x) / TAU, 1.0), false)
    _emit()


## How much of this hue's cusp chroma the gamut still holds at the lightness
## the cursor is on, as the same 0 to 1 fraction the chroma axis is in.
##
## Which axis carries the lightness depends on the shape, so this asks the
## shape rather than reading `_up` outright: on the upright triangle the
## lightness is `_up` and the answer bounds `_across`, and on the transposed one
## it is the other way round.
func _triangle_reach() -> float:
    return _reach_at(hue, _across, _up)


## The same answer for axes handed in rather than for the ones the cursor is
## standing on.
##
## Split off for `ui/dockers/color/tests/test_sa_color_picker.gd`, which probes the reach at a hue
## and a lightness no colour on the wheel has to be moved to first, rather than
## writing `hue`, `_across` and `_up` from outside the class, because a private
## is written by its own class only. The gesture still asks the same question of its own axes one line
## up, so the two cannot answer differently.
func _reach_at(at_hue: float, across: float, up: float) -> float:
    var lightness := across if kind == Kind.TRIANGLE_UP else up
    var angle := 2.0 * PI * at_hue
    var reach := OkhslConversionsScript.gamut_chroma(cos(angle), sin(angle), lightness)
    var widest := OkhslConversionsScript.cusp_chroma(at_hue)
    return clampf(reach / widest, 0.0, 1.0) if widest > 0.0 else 0.0


## The cursors move at once, and the colour goes out at once too unless a
## motion of a drag brought it. A tablet sends a motion every few milliseconds,
## and every listener of the colour, the picker's controls, the store and all
## that hear the foreground, ran for each of them, so the frame fell behind the
## pen. A motion's colour waits for the frame's end instead,
## and the motions of one frame go out as one colour, the last. A press is
## sent at once, so a click with no drag sets the colour then.
func _emit() -> void:
    _refresh()
    if _moving:
        if not _held_back:
            _held_back = true
            _send_held_back.call_deferred()
        return
    _held_back = false
    _send()


## The colour the motions of this frame reached, sent once, or nothing when a
## press or the drag's end has sent it already.
func _send_held_back() -> void:
    if not _held_back:
        return
    _held_back = false
    _send()


func _send() -> void:
    var began := Time.get_ticks_usec()
    color_changed.emit(color())
    _ledger.sent(Time.get_ticks_usec() - began)


func _refresh() -> void:
    if _area_mat:
        _area_mat.set_shader_parameter("current_hue", hue)
        _area_mat.set_shader_parameter("disc_lightness", _up)
    if _lightness_bar_mat:
        _lightness_bar_mat.set_shader_parameter("current_hue", hue)
        _lightness_bar_mat.set_shader_parameter("bar_saturation", _across)
    if _lightness_bar_cursor:
        _lightness_bar_cursor.queue_redraw()
    if cursors_overlay:
        cursors_overlay.queue_redraw()
    if _hue_bar_cursor:
        _hue_bar_cursor.queue_redraw()


## The lightness bar sets the disc's third axis: a press or a drag along it
## puts the lightness where the pointer is, white at the head, and a wheel
## notch nudges it. The end of a drag is a chosen colour, exactly as the end of
## a gesture in the frame is, so the recent list records one entry rather than
## every lightness the drag passed through. A right press is the colour
## picker's, which opens the shape menu from it.
func _on_lightness_bar_gui_input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            _dragging_lightness = true
            _drag_lightness(button.position)
        elif _dragging_lightness:
            _drag_lightness(button.position)
            _end_drag()
        return
    var wheel := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
    if button != null and button.pressed and wheel.has(button.button_index):
        var notch := LIGHTNESS_WHEEL_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else -LIGHTNESS_WHEEL_STEP
        _set_lightness(_up + notch)
        lightness_bar.accept_event()
        return
    var motion := event as InputEventMouseMotion
    if motion != null and _dragging_lightness:
        if _left_is_up(motion):
            _end_drag()
        else:
            _moving = true
            _drag_lightness(motion.position)
            _moving = false


func _drag_lightness(at: Vector2) -> void:
    if lightness_bar.size.y <= 0.0:
        return
    _set_lightness(1.0 - at.y / lightness_bar.size.y)


func _set_lightness(value: float) -> void:
    var wanted := clampf(value, 0.0, 1.0)
    if is_equal_approx(wanted, _up):
        return
    _up = wanted
    _emit()


## The colour the bar shows *at* of the way up it, 0 at the foot and 1 at the
## head: the colour's own hue and saturation at that lightness. The twin of the
## shader's bar mode, which GDScript cannot call into.
func lightness_bar_colour(at: float) -> Color:
    return OkhslConversionsScript.okhsl_to_srgb(hue, _across, at)


## The bar's cursor, a line across it at the lightness, in the two rims the
## other cursors wear.
func _on_lightness_bar_draw() -> void:
    var y := (1.0 - _up) * lightness_bar.size.y
    _lightness_bar_cursor.draw_line(Vector2(0.0, y), Vector2(lightness_bar.size.x, y), Color.BLACK, SaUI.pxf(3.0), true)
    _lightness_bar_cursor.draw_line(Vector2(0.0, y), Vector2(lightness_bar.size.x, y), Color.WHITE, SaUI.pxf(1.5), true)


func _on_cursors_draw() -> void:
    if frame == null or area_rect == null:
        return
    _ledger.drew(_across, _up)

    var center := frame.size * 0.5
    var half := minf(frame.size.x, frame.size.y) * 0.5
    var angle := ring_angle(hue, is_classic(kind)) * TAU

    if kind == Kind.OKHSL:
        # One cursor, because the disc holds hue and saturation together and
        # there is no ring to carry a second.
        var reach := minf(area_rect.size.x, area_rect.size.y) * 0.5
        _draw_cursor(area_rect.position + area_rect.size * 0.5 + Vector2(cos(angle), sin(angle)) * _across * reach)
        return

    if kind == Kind.HSL_SQUARE:
        # The hue is on the bar beside the square, which draws its own line.
        _draw_cursor(area_rect.position + Vector2(_across * area_rect.size.x, (1.0 - _up) * area_rect.size.y))
        return

    var ring_radius := half * (RING_INNER + RING_OUTER) * 0.5
    _draw_cursor(center + Vector2(cos(angle), sin(angle)) * ring_radius)

    if kind == Kind.HSV_TRIANGLE:
        _draw_cursor(area_rect.position + SaPickerClassic.triangle_point(_across, _up) * area_rect.size)
        return

    var across := _across
    var up := _up
    if kind == Kind.TRIANGLE:
        across = minf(across, _triangle_reach())
    elif kind == Kind.TRIANGLE_UP:
        up = minf(up, _triangle_reach())
    _draw_cursor(area_rect.position + Vector2(across * area_rect.size.x, (1.0 - up) * area_rect.size.y))


## Two concentric rims with a hole between them, so the cursor reads against
## whatever colour it is standing on.
func _draw_cursor(at: Vector2) -> void:
    cursors_overlay.draw_circle(at, SaUI.pxf(6.5), Color.BLACK, false, SaUI.pxf(1.5), true)
    cursors_overlay.draw_circle(at, SaUI.pxf(5.0), Color.WHITE, false, SaUI.pxf(1.5), true)
