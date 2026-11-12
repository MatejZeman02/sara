## A colour ramp: an ordered list of stops, each a position, a colour and an
## alpha of its own.
##
## Alpha is part of a stop rather than a property of the ramp, because a
## one-sided gradient is a stop at alpha zero.
##
## The colours are display colours, the ones a picker shows, as a gradient's
## two ends are. The walk between them is Oklab, so the middle of a red to blue
## ramp is the perceptual middle, between every neighbouring pair of stops.
##
## In `core/` rather than beside the gradient tool, because the kernel that draws
## a ramp, the control that edits one and the store that will save one are three
## different layers and none of them owns the others, and because other tools
## and filters may use a ramp too, so nothing here knows which tool built one.
class_name SaColorRamp
extends RefCounted

## Emitted whenever a stop is added, moved, recoloured or removed, so a control
## and a live preview both follow one edit.
signal changed

## The fewest stops a ramp can hold. Blender's is two as well: one stop is a
## fill, and the control has no way back from it.
const MIN_STOPS: int = 2

## How wide the texture the kernel samples is. A ramp laid across a 4K canvas is
## read at about four texels per screen pixel, so a stop lands within half a
## pixel of where it was put. 256 was the first choice and put a stop up to eight
## pixels out on that canvas, which is visible against a hard pair of stops.
const TEXELS: int = 1024

## `{"position": float in 0..1, "color": Color}`, kept sorted by position.
var stops: Array[Dictionary] = []


## The two-stop ramp *near* at the press end and *far* at the release end, with
## the colours exactly as given.
##
## Pure, and it has to stay that way. One tool's remembered alphas were read
## here once, and every other suite that built a ramp then depended on what the
## last suite to fade an end had left in the profile. A tool's own habits live
## beside the tool, never on a type other tools share.
static func from_pair(near: Color, far: Color) -> SaColorRamp:
    var ramp := SaColorRamp.new()
    ramp.stops = [{"position": 0.0, "color": near}, {"position": 1.0, "color": far}]
    return ramp


## A copy nothing else holds a reference into, for a caller that wants to edit a
## ramp without moving the one on screen.
func duplicate_ramp() -> SaColorRamp:
    var copy := SaColorRamp.new()
    for stop: Dictionary in stops:
        copy.stops.append({"position": _position(stop), "color": _color(stop)})
    return copy


func size() -> int:
    return stops.size()


func position_of(index: int) -> float:
    return _position(stops[index]) if index >= 0 and index < stops.size() else 0.0


func color_of(index: int) -> Color:
    return _color(stops[index]) if index >= 0 and index < stops.size() else Color.TRANSPARENT


## Adds a stop at *at*, taking the colour the ramp already has there, and answers
## its index. A click on the bar should not change the picture, only give the
## painter something to drag.
func add_stop(at: float, color: Variant = null) -> int:
    var position := clampf(at, 0.0, 1.0)
    var wanted: Color = color if color is Color else display_at(position)
    stops.append({"position": position, "color": wanted})
    _sort()
    changed.emit()
    return _index_at(position, wanted)


## Removes stop *index*, unless the ramp is already down to its minimum. True
## when one went.
func remove_stop(index: int) -> bool:
    if stops.size() <= MIN_STOPS or index < 0 or index >= stops.size():
        return false
    stops.remove_at(index)
    changed.emit()
    return true


## Moves stop *index* to *at* and answers where it ended up in the list, which
## may not be where it started: dragging one stop past another reorders them.
func move_stop(index: int, at: float) -> int:
    if index < 0 or index >= stops.size():
        return index
    var wanted := clampf(at, 0.0, 1.0)
    var color: Color = stops[index]["color"]
    stops[index]["position"] = wanted
    _sort()
    changed.emit()
    return _index_at(wanted, color)


func set_stop_color(index: int, color: Color) -> void:
    if index < 0 or index >= stops.size():
        return
    stops[index]["color"] = color
    changed.emit()


func set_stop_alpha(index: int, alpha: float) -> void:
    if index < 0 or index >= stops.size():
        return
    var color: Color = stops[index]["color"]
    color.a = clampf(alpha, 0.0, 1.0)
    stops[index]["color"] = color
    changed.emit()


## The colour at *t*, as a picker would show it.
##
## The walk is Oklab and the way back out is the display curve, so this is what
## the canvas will hold and what the control's bar should draw. Alpha is coverage
## rather than colour and is interpolated on its own, which is what lets a stop at
## alpha zero fade a ramp out without dragging its hue anywhere.
func display_at(t: float) -> Color:
    var lab := oklab_at(t)
    var linear := SaOklab.to_linear_srgb(Vector3(lab.r, lab.g, lab.b))
    var curve := SaTransferFunction.srgb()
    return Color(curve.encode(linear.x), curve.encode(linear.y), curve.encode(linear.z), lab.a)


## The colour at *t* in Oklab, L in `r`, a in `g`, b in `b` and alpha in `a`.
## What the texture the kernel samples is filled from.
##
## A `Color` rather than a `Vector4` because `lerp` between two of them is the
## whole of the interpolation, and because the texture wants four floats in that
## order anyway. The channel names are wrong for what they carry, which is why
## every use of them says so.
##
## *space* is the document the stops were picked for, since a picked colour
## means that document's gamut. Null reads them as sRGB, which is what a ramp
## with no document to land in has.
func oklab_at(t: float, space: SaColorSpace = null) -> Color:
    return _walk(_stops_in_oklab(space), t)


## A picked colour in Oklab, L, a and b with its alpha carried through.
##
## Oklab is defined against linear sRGB and carries no gamut of its own, so a
## picked colour reaches it through the display curve and then *space*'s gamut,
## the reasoning `SaColorSpace.from_display` spells out for an Oklab document.
## It holds whatever the document stores, because the ramp is walked in Oklab
## either way and only the way out depends on the document. Without the gamut a
## P3 document's ramp from `1, 0, 0` started at sRGB's red while its fill was
## P3's.
static func to_oklab(color: Color, space: SaColorSpace = null) -> Color:
    return _through(color, _gamut_of(space))


## The ramp as the RGBA32F texels the kernel samples: L, a, b and alpha at the
## centre of each texel, so a sample at t reads the ramp at t. *space* is the
## document the stops mean, as [method oklab_at] takes it.
func to_oklab_texels(width: int = TEXELS, space: SaColorSpace = null) -> PackedFloat32Array:
    var data := PackedFloat32Array()
    data.resize(width * 4)
    var labs := _stops_in_oklab(space)
    for i in width:
        var lab := _walk(labs, (float(i) + 0.5) / float(width))
        data[i * 4] = lab.r
        data[i * 4 + 1] = lab.g
        data[i * 4 + 2] = lab.b
        data[i * 4 + 3] = lab.a
    return data


## *count* colours of the ramp in Oklab, as [method oklab_at] gives them, the
## first at the ramp's start and the last at its end, each as L, a, b and alpha.
## The stops are converted once for the whole table: asked of [method oklab_at]
## one sample at a time they were converted 256 times, 13 ms a table, and an
## open of 70 gradient maps spent 0.92 s of one frame on it.
func oklab_samples(count: int, space: SaColorSpace = null) -> PackedFloat32Array:
    var data := PackedFloat32Array()
    data.resize(maxi(count, 0) * 4)
    var labs := _stops_in_oklab(space)
    for i in count:
        var lab := _walk(labs, float(i) / float(maxi(count - 1, 1)))
        data[i * 4] = lab.r
        data[i * 4 + 1] = lab.g
        data[i * 4 + 2] = lab.b
        data[i * 4 + 3] = lab.a
    return data


## The stops as plain data, for a store and for a state dump. Positions and
## colours only: the ramp has no other state.
##
## The colour goes out as four floats rather than as an eight-bit hex string.
## Sara is float throughout on purpose (hard rule 5), and a ramp written as
## `#33cc4d80` comes back a different colour, which would make saved ramps
## lossy for no reason a painter would understand.
func to_array() -> Array:
    var out: Array = []
    for stop: Dictionary in stops:
        var color: Color = stop["color"]
        out.append({"position": _position(stop), "color": [color.r, color.g, color.b, color.a]})
    return out


## The inverse of [method to_array]. A ramp with fewer than two readable stops
## falls back to *fallback*, because a control with one stop has no way back.
static func from_array(raw: Array, fallback: SaColorRamp = null) -> SaColorRamp:
    var ramp := SaColorRamp.new()
    for entry: Variant in raw:
        if entry is not Dictionary:
            continue
        var fields: Dictionary = entry
        if not fields.has("position") or not fields.has("color"):
            continue
        # `entry["color"] as Array` cannot be used here. Inference would make
        # this a typed Array, and assigning the null a failed cast gives it is a
        # runtime error rather than a parse one, which aborts the whole read and
        # answers null instead of the fallback.
        var raw_channels: Variant = fields["color"]
        if raw_channels is not Array:
            continue
        var channels: Array = raw_channels
        if channels.size() < 4:
            continue
        var color := Color(
            SaTyped.real(channels[0]), SaTyped.real(channels[1]), SaTyped.real(channels[2]), SaTyped.real(channels[3])
        )
        ramp.stops.append({"position": clampf(SaTyped.real(fields["position"]), 0.0, 1.0), "color": color})
    if ramp.stops.size() < MIN_STOPS:
        return fallback if fallback != null else from_pair(Color.BLACK, Color.WHITE)
    ramp._sort()
    return ramp


## Every stop in Oklab, in stop order, through one gamut matrix.
##
## Once per build rather than once per texel. The texels asked each stop for
## its matrix and its conversion again at every one of 1024 texels, and the
## matrix alone was 16.5 ms of the 26.5 ms a build took on the laptop, all of
## it on the gradient's first move. A stop converts to the
## same colour wherever it is read, so the walk reads the list instead.
func _stops_in_oklab(space: SaColorSpace) -> Array[Color]:
    var gamut: Variant = _gamut_of(space)
    var labs: Array[Color] = []
    for stop in stops:
        labs.append(_through(_color(stop), gamut))
    return labs


## The colour at *t* between the stops *labs* holds in Oklab, [method oklab_at]
## once the stops are converted.
func _walk(labs: Array[Color], t: float) -> Color:
    if labs.is_empty():
        return Color(0.0, 0.0, 0.0, 0.0)
    var position := clampf(t, 0.0, 1.0)
    var lower := 0
    while lower < stops.size() - 1 and _position(stops[lower + 1]) <= position:
        lower += 1
    var near := labs[lower]
    if lower >= labs.size() - 1:
        return near
    var upper := labs[lower + 1]
    var from := _position(stops[lower])
    var to := _position(stops[lower + 1])
    # Two stops in the same place are a hard edge rather than a division by
    # nothing, and the one on the right wins, which is what dragging a stop onto
    # another one looks like it should do.
    if to - from <= 0.0:
        return upper
    return near.lerp(upper, (position - from) / (to - from))


## The matrix that takes *space*'s linear RGB into linear sRGB, or null for a
## ramp with no document, which reads its stops as sRGB.
static func _gamut_of(space: SaColorSpace) -> Variant:
    if space == null:
        return null
    return space.to_linear_srgb_matrix()


## *color* through the display curve, the *gamut* matrix when there is one,
## and into Oklab, its alpha carried through. [method to_oklab] once the matrix
## is known.
static func _through(color: Color, gamut: Variant) -> Color:
    var curve := SaTransferFunction.srgb()
    var linear := Vector3(curve.decode(color.r), curve.decode(color.g), curve.decode(color.b))
    if gamut != null:
        var matrix: Basis = gamut
        linear = matrix * linear
    var lab := SaOklab.from_linear_srgb(linear)
    return Color(lab.x, lab.y, lab.z, color.a)


func _sort() -> void:
    stops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _position(a) < _position(b))


## Which entry is the stop that was just put at *position* with *color*. Sorting
## by position alone cannot say, because two stops may share one, so the colour
## breaks the tie and the first match wins.
func _index_at(position: float, color: Color) -> int:
    for i in stops.size():
        if is_equal_approx(_position(stops[i]), position) and _color(stops[i]) == color:
            return i
    return 0


## Where *stop* sits. Every stop in `stops` is built here with a float, so the
## typed local reads what was written.
static func _position(stop: Dictionary) -> float:
    var at: float = stop["position"]
    return at


## The colour of *stop*, a Color by the same reasoning as `_position`.
static func _color(stop: Dictionary) -> Color:
    var color: Color = stop["color"]
    return color
