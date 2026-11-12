## How a tool sees the canvas: coordinates, zoom and pan. No Control involved.
##
## A tool holds this rather than a SaCanvas, which is a TextureRect, so the tool
## base class in core/ does not depend on render/ and a tool can be tested
## without a Control tree.
##
## The concrete implementation over SaCanvas lives in render/sa_canvas_view.gd,
## which is the only place that knows a view is a Control.
class_name SaView
extends RefCounted

## Emitted after zoom or pan changes, so a tool never polls and never reaches
## into a sibling node to find out.
##
## Declared on the base and emitted by the concrete views, which is exactly what
## the unused-signal warning cannot see.
@warning_ignore("unused_signal")
signal transform_changed

## The zoom range every route into the zoom shares: the wheel, the gestures, the
## zoom tool and the chords. Here rather than on the zoom tool, so no route
## zooms past what another allows.
const ZOOM_MIN: float = 0.01
const ZOOM_MAX: float = 100.0

## One wheel notch, one chord press, in Krita's step.
const ZOOM_STEP: float = 1.25

## With integer zoom on, the last multiple of actual pixels a notch reaches one
## at a time. Past it a notch doubles, see `Steps.next_zoom`.
const INTEGER_ZOOM_COUNTED: int = 4

## What Ctrl+0 shows, the two answers `SaSettings.reset_zoom` may hold: the
## whole picture fitted between the bars and the dockers at the Size below, or
## actual pixels, one texel on one device pixel. Both are centred. The first is
## the default, and the settings hold the choice.
const RESET_WHOLE: String = "whole"
const RESET_PIXELS: String = "pixels"
const RESETS: Array[String] = [RESET_WHOLE, RESET_PIXELS]

## The Zoom figure the whole picture is shown at, in per cent, and its bounds.
## Ninety is a bit zoomed out, and a value past a hundred is a bit zoomed in,
## which a painter may choose instead.
const RESET_SIZE: int = 90
const RESET_SIZE_MIN: int = 25
const RESET_SIZE_MAX: int = 200

## One rotate chord, in Krita's step, in radians.
const ROTATION_STEP: float = PI / 12.0

## Whether the last move was a Fit, so a change of interface scale can fit
## again rather than keep a zoom the painter never chose. Set by `fit_into` and
## cleared by any other move, read by the canvas.
var _fitted: bool = false

## The share of the fit that last move took, one for Fit to View and the Size
## over a hundred for Ctrl+0, so the fit taken again after a scale change lands
## at the same Zoom figure. Set by `fit_into`, read by the canvas when it fits
## again a frame after the scale moved.
var _fit_share: float = 1.0

## True while `fit_into` moves the view, so its own moves do not clear the above.
var _fitting: bool = false

## The view Ctrl+0 left, so a second press goes back to it: the zoom, the pan,
## the rotation, the mirror and whether it was a fit, at which share, and the
## free rectangle the press reset into, which forgets it once it changes. Empty when
## there is nothing to go back to. Set by `reset` on a toggle and cleared by
## any other move, read by the next toggle. A look from a distance and then
## quickly back to the same level of detail, as Shift+Z is in DaVinci Resolve.
var _left: Dictionary = {}

## True while a toggle moves the view, so its own moves keep the above.
var _toggling: bool = false

## A drag that comes within this of a right angle snaps to it, so a painter can
## find straight-on and the three quarter turns without a ruler.
const ROTATION_SNAP_TOLERANCE: float = deg_to_rad(4.0)


func _init() -> void:
    transform_changed.connect(_on_transform_changed)


func _on_transform_changed() -> void:
    if not _fitting:
        _fitted = false
    if not _toggling:
        _left = {}


## Pointer position in document pixels. Stays correct outside the document
## bounds, returning coordinates beyond it, because painting out of bounds is
## legal - chunks are sparse.
func get_document_mouse_position() -> Vector2:
    return Vector2.ZERO


## Document pixels per screen pixel.
func get_zoom() -> float:
    return 1.0


func set_zoom(_value: float) -> void:
    pass


func get_pan() -> Vector2:
    return Vector2.ZERO


func set_pan(_value: Vector2) -> void:
    pass


## The view's rotation in radians, positive clockwise on screen, about the
## document's origin. Every anchored operation below keeps a chosen point fixed
## by moving the pan, so the pivot never has to move.
func get_rotation() -> float:
    return 0.0


func set_rotation(_value: float) -> void:
    pass


## Which way round the view shows the picture, as a sign per axis: Vector2.ONE
## for neither, (-1, 1) mirrored left to right, (1, -1) top to bottom. A mirror
## is a view property like the zoom and the pan, so nothing here reaches a
## chunk, and the zoom stays the single positive number every caller expects.
func get_flip() -> Vector2:
    return Vector2.ONE


func set_flip(_value: Vector2) -> void:
    pass


## Size of the area the document is displayed in, in screen pixels.
func get_viewport_size() -> Vector2:
    return Vector2.ZERO


## The part of the area nothing is drawn over, in the pan's space. The whole
## area here, because a view with no window has nothing on top of it.
##
## Not the same as the size above. The main canvas reaches under the top bar,
## so a fit measured on the whole area would put the document's top rows under
## the menus. Fit to Window asks for this, and every zoom anchor keeps to the
## middle of the whole area.
func get_visible_rect() -> Rect2:
    return Rect2(Vector2.ZERO, get_viewport_size())


## The part of the visible rectangle nothing stands beside either, the room
## between the docker columns, in the pan's space. The visible rectangle here,
## because a view with no window has no dockers.
##
## A fit and a centre ask for this. Four sweeps found the default dockers over
## the painting's subject, and hiding them to see it took the dockers away as
## well.
func get_free_rect() -> Rect2:
    return get_visible_rect()


## Radius in screen pixels for a document-space radius. The cursor ring needs it.
func document_to_screen_length(length: float) -> float:
    return length * get_zoom()


## Zooms to *zoom*, keeping the document point under *anchor* where it is.
##
## *anchor* is in the same space as the pan: the view's own parent, which for the
## canvas is the full-rect control that receives input, so an event's `position`
## is the anchor as it comes. The one helper every route into the zoom shares,
## rather than each pinning the screen centre, which zooms away from what the
## pointer is over.
func zoom_at(zoom: float, anchor: Vector2) -> void:
    var clamped := clampf(zoom, ZOOM_MIN, ZOOM_MAX)
    var current := get_zoom()
    if current <= 0.0 or is_equal_approx(clamped, current):
        return
    var document_point := screen_to_document(anchor)
    set_zoom(clamped)
    set_pan(anchor - view_offset(document_point))


## Where a straight line from *from* to *to*, both in document pixels, ends:
## *to* itself on a flat view, and the copy of it the short way round the seam
## on a view that shows the document as a sphere. A Shift click's line asks.
func line_towards(_from: Vector2, to: Vector2) -> Vector2:
    return to


## How many times wider in the document's x a dab centred at *pixel* is drawn,
## so that it is round where this view shows it: nought on a view that shows
## the document flat, whose dab is the flat one, and on one that shows it as a
## sphere the kind's stretch there, infinite at a pole. `SaDabParams.stretch`
## holds the answer for the dab.
func dab_stretch(_pixel: Vector2) -> float:
    return 0.0


## The document point under *screen* (in the view's parent space), through the
## whole transform: screen = pan + rotate(flip * document * zoom).
func screen_to_document(screen: Vector2) -> Vector2:
    var zoom := get_zoom()
    if zoom <= 0.0:
        return Vector2.ZERO
    # The flip is its own inverse, both components being 1 or -1, so the way
    # back multiplies by the same signs the way out did.
    return (screen - get_pan()).rotated(-get_rotation()) / zoom * get_flip()


## Where a document point lands on screen, the inverse of screen_to_document.
func document_to_screen(document_point: Vector2) -> Vector2:
    return get_pan() + view_offset(document_point)


## A document point as an offset from the pan: the mirror, the zoom and the
## rotation in the order a Control applies them, which is why the flip is a
## scale sign rather than a step of its own. Written down once because three
## anchored operations below and the minimap all have to agree with it.
func view_offset(document_point: Vector2) -> Vector2:
    return (document_point * get_flip() * get_zoom()).rotated(get_rotation())


## Rotates to *rotation*, keeping the document point under *anchor* where it is.
## The "rotate about the cursor" behaviour, by the same trick as zoom_at: the pivot
## stays at the origin and the pan absorbs the difference.
func rotate_at(rotation: float, anchor: Vector2) -> void:
    var wrapped := wrapf(rotation, -PI, PI)
    if is_equal_approx(wrapped, get_rotation()):
        return
    var document_point := screen_to_document(anchor)
    set_rotation(wrapped)
    set_pan(anchor - view_offset(document_point))


## *rotation* pulled onto the nearest right angle when it is within
## ROTATION_SNAP_TOLERANCE of one, and left alone otherwise.
static func snap_rotation(rotation: float) -> float:
    var quarter := PI / 2.0
    var nearest := roundf(rotation / quarter) * quarter
    if absf(wrapf(rotation - nearest, -PI, PI)) <= ROTATION_SNAP_TOLERANCE:
        return wrapf(nearest, -PI, PI)
    return rotation


## Mirrors the view across the axis *horizontal* names, keeping the document
## point under *anchor* where it is.
##
## The rotation is negated with it, because a mirror on the screen is what the
## painter asked for and a mirror in document space is not the same thing once
## the view is turned: reflecting a turn reverses it, M * R(t) = R(-t) * M. So a
## turned view mirrors to exactly its own reflection, and flipping twice comes
## back to where it started.
func flip_at(horizontal: bool, anchor: Vector2) -> void:
    var document_point := screen_to_document(anchor)
    var flip := get_flip()
    if horizontal:
        flip.x = -flip.x
    else:
        flip.y = -flip.y
    set_flip(flip)
    set_rotation(wrapf(-get_rotation(), -PI, PI))
    set_pan(anchor - view_offset(document_point))


## Mirrors about the middle of the free rectangle, which is what a button with
## no pointer behind it means by "flip", and the middle a centred picture has.
## The window's middle once, which `SaShortcutCommands._zoom_view` says the cost
## of.
func flip_view(horizontal: bool) -> void:
    flip_at(horizontal, get_free_rect().get_center())


## Multiplies the zoom by *factor* about *anchor*. A notch in is ZOOM_STEP, a
## notch out is one over it.
func zoom_by(factor: float, anchor: Vector2) -> void:
    if factor > 0.0:
        zoom_at(get_zoom() * factor, anchor)


## Device pixels per logical pixel on the surface the view is drawn on.
##
## One here, because a view with no window behind it has no interface scale to
## divide out. The concrete view over a Control reads it off the window, where
## `SaUI.apply_to_window` is the one writer of it.
func get_content_scale() -> float:
    return 1.0


## The zoom at which one document texel covers exactly one device pixel.
##
## A hundred per cent is a promise about the screen and not about a logical
## unit. At an interface scale of 1.25 a zoom of one puts 1.25 device pixels on
## a texel, and the canvas then samples nearest at a fractional ratio, so one
## texel in four is drawn two pixels wide and the rest one: Measured, 420 runs
## of one pixel against 140 of two across a one-texel checkerboard. Below one it
## is worse, because the sampler is linear there and a scale of 0.9 turned the
## same checkerboard into ten shades of grey. Dividing the interface scale out
## is what makes the squares square again.
func actual_pixel_zoom() -> float:
    var content := get_content_scale()
    return 1.0 / content if content > 0.0 else 1.0


## Zooms to one document texel per device pixel, keeping *anchor* where it is.
## What reads Pixels 100%, on any interface scale, the scale pixel work wants.
func zoom_to_actual_pixels(anchor: Vector2) -> void:
    zoom_at(actual_pixel_zoom(), anchor)


## The zoom at which a document of *document_size* fits the free rectangle edge
## to edge, which is what reads Zoom 100%. Zero for an empty document or an
## empty view.
##
## The rotated document's bounding box, the same fit Fit to View makes, so F
## reads 100% however the view is turned. Measured against the free rectangle,
## so the figure moves when a docker column opens or closes while the picture
## stays where it is.
func _fit_zoom(document_size: Vector2i) -> float:
    var area := get_free_rect()
    if document_size.x <= 0 or document_size.y <= 0 or area.size.x <= 0.0 or area.size.y <= 0.0:
        return 0.0
    var extent := rotated_extent(Vector2(document_size), get_rotation())
    return minf(area.size.x / extent.x, area.size.y / extent.y)


## The Zoom figure in per cent: the picture's size on screen against the whole
## picture fitted into the free rectangle, whatever its resolution. Zero where
## there is nothing to fit.
func zoom_per_cent(document_size: Vector2i) -> float:
    var whole := _fit_zoom(document_size)
    return get_zoom() / whole * 100.0 if whole > 0.0 else 0.0


## Fits a document of *document_size* into the free part of the view, between
## the dockers, and centres it there. What Fit to View asks for, Zoom 100%.
func fit(document_size: Vector2i) -> void:
    fit_into(document_size, get_free_rect())


## Shows a document of *document_size* the way Ctrl+0 does and a new or opened
## document opens: what `SaSettings.reset_zoom` names, the whole picture at
## `SaSettings.reset_zoom_size` per cent of the fit or actual pixels, centred
## in the free rectangle either way.
##
## *toggle* is Ctrl+0's press: a second press while the view still stands where
## the first left it puts back the view the first press left. Any other move in
## between, a wheel step, a drag of the pan, a fit or a turn, forgets that view,
## so the press after it resets again. A view already standing where the reset
## puts it has nothing to go back to, and the press remembers nothing, so a
## second press does not move a painter who never left. A flag rather than a
## method of its own, because the view stands at gdlint's limit of public ones.
##
## A change of the free rectangle forgets that view too, though the view itself
## does not move: Tab into or out of focus mode, a docker opened, closed or
## dragged, the window resized. The press remembers the rectangle it reset into
## and compares it here, at the next press, rather than listening for each of
## those, since `core` never names the dockers. So the press after a Tab resets
## into the room as it now stands.
func reset(document_size: Vector2i, toggle: bool = false) -> void:
    if toggle and not _left.is_empty() and _left.free != get_free_rect():
        _left = {}
    if toggle and not _left.is_empty():
        _go_back()
        return
    var before := {
        "zoom": get_zoom(),
        "pan": get_pan(),
        "rotation": get_rotation(),
        "flip": get_flip(),
        "fitted": _fitted,
        "share": _fit_share,
        "free": get_free_rect(),
    }
    _toggling = toggle
    if SaSettings.reset_zoom == RESET_PIXELS:
        zoom_to_actual_pixels(get_free_rect().get_center())
        center(document_size)
    else:
        fit_into(document_size, get_free_rect(), SaSettings.reset_zoom_size / 100.0)
    _toggling = false
    if not toggle:
        return
    var moved: bool = (
        get_zoom() != before.zoom or get_pan() != before.pan or get_rotation() != before.rotation or get_flip() != before.flip
    )
    _left = before if moved else {}


## Puts back the view Ctrl+0 left, which `reset` remembered, and forgets it, so
## a third press resets again.
func _go_back() -> void:
    var back := _left
    var flip_back: Vector2 = back.flip
    var pan_back: Vector2 = back.pan
    _toggling = true
    set_flip(flip_back)
    set_rotation(SaTyped.real(back.rotation))
    set_zoom(SaTyped.real(back.zoom))
    set_pan(pan_back)
    _toggling = false
    _fitted = back.fitted
    _fit_share = back.share
    _left = {}


## Keeps the painting its size in device pixels when the interface scale moves
## from *before* to *now*. The zoom is in logical units, and a logical unit is
## the scale's worth of device pixels, so a zoom kept across scale 1 to 2 would
## double the picture on screen and asking for bigger buttons would take the
## picture away. The zoom is multiplied by the old scale over the new
## about the middle, which the resize the same change sent has already kept in
## place, so actual pixels stay actual. A view whose last move was a fit is
## fitted again instead, at the share it was fitted at.
func follow_scale(document_size: Vector2i, before: float, now: float) -> void:
    if now <= 0.0 or before <= 0.0 or is_equal_approx(before, now):
        return
    if _fitted:
        fit_into(document_size, get_free_rect(), _fit_share)
    else:
        zoom_at(get_zoom() * before / now, get_viewport_size() * 0.5)


## Centres a document of *document_size* in the free part of the view at the
## current zoom and rotation. The pan half of a reset, so a painter who zoomed
## into a corner has a way back.
func center(document_size: Vector2i) -> void:
    _center_in(document_size, get_free_rect())


## Fits a document of *document_size* into *area* of the view, in the pan's
## space, and centres it there. Fit to View hands it the free rectangle, and Fit
## to Window the visible one, which leaves the dockers no room. *share* scales
## the fit, below one for a margin round the
## picture and above it for a picture that overflows a little, which is how
## Ctrl+0 lands at its Size.
func fit_into(document_size: Vector2i, area: Rect2, share: float = 1.0) -> void:
    if document_size.x <= 0 or document_size.y <= 0 or area.size.x <= 0.0 or area.size.y <= 0.0 or share <= 0.0:
        return
    # What has to fit is the rotated document's bounding box, or a quarter turn
    # of a wide picture would overflow the view it was just fitted to.
    var extent := rotated_extent(Vector2(document_size), get_rotation())
    var factor := minf(area.size.x / extent.x, area.size.y / extent.y) * share
    _fitting = true
    set_zoom(clampf(factor, ZOOM_MIN, ZOOM_MAX))
    _center_in(document_size, area)
    _fitting = false
    _fitted = true
    _fit_share = share


func _center_in(document_size: Vector2i, area: Rect2) -> void:
    if area.size.x <= 0.0 or area.size.y <= 0.0:
        return
    set_pan(area.get_center() - view_offset(Vector2(document_size) * 0.5))


## The axis-aligned size of a *size* rectangle turned by *rotation*.
static func rotated_extent(size: Vector2, rotation: float) -> Vector2:
    var c := absf(cos(rotation))
    var s := absf(sin(rotation))
    return Vector2(size.x * c + size.y * s, size.x * s + size.y * c)


## The notch every route into the zoom takes, a chord, a zoom tool click and a
## wheel, so they agree on where a notch lands. ZOOM_STEP by default, and with
## `SaSettings.integer_zoom` on the next whole multiple of actual pixels at and
## above 100%, so texels never scale by a fraction for pixel art.
##
## An inner class of statics, because SaView's public methods are at gdlint's
## limit and the rule is one thing, the stops and how a notch finds them.
class Steps:
    ## *notches* of a wheel or a chord in or out about *anchor* on *view*. A
    ## whole notch moves to `next_zoom`, and a smooth wheel's fraction of one
    ## zooms by that fraction of ZOOM_STEP, whole steps or not, because a
    ## touchpad's run of small ticks would otherwise jump a stop on each.
    static func notch(view: SaView, notches: float, inward: bool, anchor: Vector2) -> void:
        if is_equal_approx(notches, 1.0):
            view.zoom_at(next_zoom(view.get_zoom(), view.actual_pixel_zoom(), inward), anchor)
            return
        var step := pow(ZOOM_STEP, notches)
        view.zoom_by(step if inward else 1.0 / step, anchor)

    ## The zoom one notch in or out from *zoom*, where *actual* is the view's
    ## actual pixel zoom, its 100%.
    ##
    ## With integer zoom on, the multiples of actual pixels are counted one at
    ## a time up to INTEGER_ZOOM_COUNTED and doubled past it, so 100%, 200%,
    ## 300%, 400%, 800% and 1600%, the stops a pixel painter names, without a
    ## dozen presses between the last two. A zoom between two stops goes to the
    ## next one, and a step in from under 100% that would pass it stops on it.
    ## Under 100% a step is ZOOM_STEP, because a fraction of a texel per pixel
    ## is a reduction whatever its figure.
    static func next_zoom(zoom: float, actual: float, inward: bool) -> float:
        var plain := zoom * ZOOM_STEP if inward else zoom / ZOOM_STEP
        if not SaSettings.integer_zoom or actual <= 0.0:
            return plain
        var ratio := zoom / actual
        var near := 1e-4
        if inward:
            if ratio < 1.0 - near:
                return minf(plain, actual)
            var whole := floori(ratio + near)
            if whole < INTEGER_ZOOM_COUNTED:
                return actual * (whole + 1)
            return actual * _power_above(ratio + near)
        if ratio <= 1.0 + near:
            return plain
        var under := ceili(ratio - near)
        if under <= INTEGER_ZOOM_COUNTED:
            return actual * (under - 1)
        return actual * maxi(INTEGER_ZOOM_COUNTED, _power_below(ratio - near))

    ## The least power of two above *ratio*.
    static func _power_above(ratio: float) -> int:
        var power := 1
        while power <= ratio:
            power *= 2
        return power

    ## The greatest power of two under *ratio*.
    static func _power_below(ratio: float) -> int:
        var power := 1
        while power * 2 < ratio:
            power *= 2
        return power
