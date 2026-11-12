## Paint behind the pen of a noise stroke does not change after it is laid.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Each update of a noise stroke paints its body up to a point held behind the
## pen and lays a front, the round end, under the pen, which the next update
## puts back before its own body paints there (`dab_list/noise_front.gd`).
## Where the front laid something the body then lays otherwise, the painter
## sees paint change behind the tip after it was drawn.
##
## **What is measured.** Thick Impasto, Bristle Flat and Grain Round are each
## dragged along one row, a sample every few pixels, over an empty layer and
## over a layer of old paint with a height. After every update the stroke
## buffer's colour and the layer's colour, and the layer's height, are read
## over the row's band. Two things are kept for each: the farthest distance
## behind the pen's newest sample at which any texel differs from the update
## before, and how much paint the stroke had laid already changes again more
## than a tip's radius behind the pen, summed over the stroke. The same stroke
## is painted by a list that lays no front, whose farthest change is the body's
## own catch up, and which never changes paint it has laid.
##
## **The front changes nothing behind the pen the body does not.** Its
## farthest change is no more than the body's, in colour and in height, for
## all three brushes over both layers.
##
## **Laid paint stays.** More than a radius behind the pen nothing the front
## laid changes again, but for the push of a brush that lays height over old
## paint: the next stretch's loads fold in what it finds, which no front can
## know, so there the front is close rather than the same. That change is held
## to a share of what it was while the front laid no push. Within a radius of
## the pen the front's round end is drawn over as the path moves on, a round
## rim becoming a straight edge, which is the round tip under the pen moving
## with it.
##
## **What is left.** After the lift the layer holds what the stroke with no
## front leaves, within [constant LEFT_WITHIN] a channel.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseHeightCarryScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_height_carry.gd")

## Wide enough that each preset's radius, a share of the smaller side, is ten
## pixels or more, and the drag runs some thirty radii.
const CANVAS := Vector2i(1024, 512)
## The drag along the middle of the top row of chunks, a sample every
## [constant STEP] pixels, at a working press.
const ROW := 128.0
const FROM := Vector2(96.0, ROW)
const TO := Vector2(900.0, ROW)
const STEP := 3.0
const PRESS := 0.9
## The updates at the start left unread, while the body has not caught up.
const SETTLE := 8
## The old paint, upright strokes of Thick Impasto across the row, so a push
## carries colour and height along the drag.
const OLD_EVERY := 48.0
const OLD_COLOUR := Color(0.72, 0.46, 0.22)
const DRAG_COLOUR := Color(0.2, 0.36, 0.75)
const BRUSHES: Array[String] = ["Thick Impasto", "Bristle Flat", "Grain Round"]
## The brushes of the three that lay height and so push old paint.
const PUSHING: Array[String] = ["Thick Impasto", "Bristle Flat"]
const FIELDS: Array[String] = ["albedo", "height"]
## How far a change behind the pen may lie past the body's own and still count
## as the body's, in pixels: the samples fall on whole steps of the path, so
## the farthest texel either list changes moves by up to a texel.
const SLACK := 1.0
## The share of the change a front that lays no push makes to laid paint more
## than a radius behind the pen that the front may still make, by field.
## Measured at 0.22 for the colour and 0.59 for the height.
const PUSHED_SHARE := {"albedo": 0.5, "height": 0.8}
## How far apart a channel of the layer left with the front and without it may
## be after the lift.
const LEFT_WITHIN := 0.0005


## A dab list that lays no front, the stroke as the body alone paints it.
class NoFrontList:
    extends "res://modules/sara-noise-brush-engine/dab_list/noise_dab_list.gd"

    func lay_front(
        _doc: SaDocument,
        _compute: SaCompute,
        _values: Dictionary,
        _carry: SaTexture,
        _pressure: float,
        _heights: SaStrokeHeights = null
    ) -> void:
        pass


## A front that lays no push, as it was before it read the stroke's loads.
class NoPushFront:
    extends "res://modules/sara-noise-brush-engine/dab_list/noise_front.gd"

    func push(
        _pushed: NoiseHeightCarryScript, compute: SaCompute, values: Dictionary, _radius: float
    ) -> Array[SaCompute.Recorded]:
        values["push_reach"] = 0.0
        values["push_length"] = 0.0
        NoiseHeightCarryScript.bind_none(compute)
        return []


## The drags measured so far, by brush, layer and list, since two tests read
## the same ones.
static var _measured: Dictionary = {}

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


func test_the_front_changes_nothing_behind_the_pen_the_body_does_not() -> void:
    for old: bool in [false, true]:
        for name: String in BRUSHES:
            var shown := _measure(name, old, "front")
            var plain := _measure(name, old, "none")
            var r: float = shown["radius"]
            var what := "%s over %s" % [name, "old paint" if old else "an empty layer"]
            for field: String in FIELDS:
                var with_front: float = shown["behind"][field]
                var without: float = plain["behind"][field]
                print(
                    (
                        "  %s, %s: changes up to %.2f radii behind the pen with the front and %.2f with none"
                        % [what, field, with_front / r, without / r]
                    )
                )
                assert_true(
                    with_front <= without + SLACK,
                    (
                        "%s: with the front its %s changes %.2f radii behind the pen, the body alone %.2f"
                        % [what, field, with_front / r, without / r]
                    )
                )


func test_paint_laid_more_than_a_radius_behind_the_pen_stays_but_for_a_push() -> void:
    for old: bool in [false, true]:
        for name: String in BRUSHES:
            var shown := _measure(name, old, "front")
            var plain := _measure(name, old, "none")
            var what := "%s over %s" % [name, "old paint" if old else "an empty layer"]
            for field: String in FIELDS:
                var changed: Vector2 = shown["relaid"][field]
                print(
                    (
                        "  %s, %s: laid paint changes again past a radius by up to %.4f, %.1f summed"
                        % [what, field, changed.x, changed.y]
                    )
                )
                assert_eq(
                    plain["relaid"][field], Vector2.ZERO, "%s: the body alone never changes its %s once laid" % [what, field]
                )
                if old and name in PUSHING:
                    var unpushed: Vector2 = _measure(name, old, "unpushed")["relaid"][field]
                    print("    and %.4f, %.1f summed, while the front laid no push" % [unpushed.x, unpushed.y])
                    assert_true(unpushed.y > 0.0, "%s: a front that lays no push changes the %s laid behind it" % [what, field])
                    assert_true(
                        changed.y <= PUSHED_SHARE[field] * unpushed.y,
                        (
                            # gdlint:ignore=max-line-length
                            "%s: the front's push changes the laid %s by %.1f, no more than %.2f of the %.1f a front with none does"
                            % [what, field, changed.y, PUSHED_SHARE[field], unpushed.y]
                        )
                    )
                else:
                    assert_eq(
                        changed,
                        Vector2.ZERO,
                        "%s: nothing the front laid more than a radius behind the pen changes in its %s" % [what, field]
                    )


func test_the_front_leaves_nothing_after_the_lift() -> void:
    for old: bool in [false, true]:
        for name: String in BRUSHES:
            var shown: Dictionary = _measure(name, old, "front")["left"]
            var plain: Dictionary = _measure(name, old, "none")["left"]
            var what := "%s over %s" % [name, "old paint" if old else "an empty layer"]
            assert_eq(shown.keys(), plain.keys(), "%s: the front leaves the same chunks and fields" % what)
            var most := 0.0
            for key: String in plain:
                if shown.has(key):
                    most = maxf(most, _largest_difference(shown[key], plain[key]))
            assert_true(
                most <= LEFT_WITHIN,
                "%s: the layer left with the front is the one left without, within %.4f, %.6f" % [what, LEFT_WITHIN, most]
            )


## The drag of [method _drag], measured once a run.
func _measure(name: String, old: bool, list: String) -> Dictionary:
    var key := "%s %s %s" % [name, old, list]
    if not _measured.has(key):
        _measured[key] = _drag(name, old, list)
    return _measured[key]


## Drags the preset *name* along the row on a fresh surface, over old paint
## when *old*, with a front that is *list*'s: the shipped one, "none" or
## "unpushed". Answers the radius, by field the farthest distance in pixels
## behind the newest sample at which a texel changed between two updates and
## the largest and summed change of laid paint more than a radius behind it,
## and the layer's fields after the lift.
func _drag(name: String, old: bool, list: String) -> Dictionary:
    _fresh()
    if old:
        _preset("Thick Impasto", OLD_COLOUR)
        var x := FROM.x
        while x < TO.x:
            _stroke(Vector2(x, ROW - 60.0), Vector2(x, ROW + 60.0))
            x += OLD_EVERY
    _preset(name, DRAG_COLOUR)
    if list == "none":
        _brush.dab_list = NoFrontList.new(StateNoiseBrushScript.KERNEL)
    elif list == "unpushed":
        _brush.dab_list.front = NoPushFront.new()
    var r := _radius()
    var band := Rect2i(0, int(ROW - 2.0 * r), CANVAS.x, int(4.0 * r) + 1)
    var behind := {"albedo": 0.0, "height": 0.0}
    var relaid := {"albedo": Vector2.ZERO, "height": Vector2.ZERO}
    var steps := ceili(FROM.distance_to(TO) / STEP)
    var start := _read(band)
    var before := start
    _brush.begin_stroke(FROM, PRESS)
    for i in range(1, steps + 1):
        var at := FROM.lerp(TO, float(i) / steps)
        _brush.add_sample(at, PRESS)
        var now := _read(band)
        if i > SETTLE:
            for field: String in FIELDS:
                var was := _only(before, field)
                var is_now := _only(now, field)
                var first := _first_change(was, is_now, band)
                if first >= 0:
                    behind[field] = maxf(behind[field], at.x - float(first))
                var here := _relaid(_only(start, field), was, is_now, band, int(at.x - r))
                relaid[field] = Vector2(maxf(relaid[field].x, here.x), relaid[field].y + here.y)
        before = now
    _brush.end_stroke()
    return {"radius": r, "behind": behind, "relaid": relaid, "left": _layer_fields()}


## The readings of *reading* whose field is *field*.
static func _only(reading: Dictionary, field: String) -> Dictionary:
    var out := {}
    for key: String in reading:
        if key.ends_with(field):
            out[key] = reading[key]
    return out


func _fresh() -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7


## The preset called *name* on the brush in *colour*, as it ships.
func _preset(name: String, colour: Color) -> void:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == name:
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    _brush.settings.color = colour


func _radius() -> float:
    return _brush.settings.radius * mini(CANVAS.x, CANVAS.y)


func _stroke(from: Vector2, to: Vector2) -> void:
    _brush.begin_stroke(from, 1.0)
    var steps := ceili(from.distance_to(to) / 4.0)
    for i in range(1, steps + 1):
        _brush.add_sample(from.lerp(to, float(i) / steps), 1.0)
    _brush.end_stroke()


func _document() -> SaDocument:
    return _surface.easel.document


## The bytes the card holds for the stroke buffer's colour and the active
## layer's colour and height, on every chunk that crosses *band*, by grid
## position and field.
func _read(band: Rect2i) -> Dictionary:
    var rd := GlobalShaderCompiler.get_rd()
    var out := {}
    var doc := _document()
    var sources := {"buffer": doc.stroke_layer, "layer": doc.active_layer}
    for source: String in sources:
        var layer: SaLayer = sources[source]
        if layer == null:
            continue
        for grid: Vector2i in layer.chunks:
            var chunk := layer.chunks[grid] as SaChunk
            var side := chunk.pixel_size()
            if not Rect2i(grid * side, Vector2i(side, side)).intersects(band):
                continue
            out["%s %s albedo" % [source, grid]] = rd.texture_get_data(chunk.albedo().rid, 0)
            if source == "layer" and chunk.has_field(SaFieldSpec.HEIGHT):
                out["%s %s height" % [source, grid]] = rd.texture_get_data(layer.get_field(grid, SaFieldSpec.HEIGHT).rid, 0)
    return out


## The smallest document x on *band*'s rows at which *now* differs from
## *before*, -1 where nothing does. A field present in one reading only is read
## as nought in the other, which is what a chunk the layer does not hold shows.
func _first_change(before: Dictionary, now: Dictionary, band: Rect2i) -> int:
    var first := -1
    var keys := before.keys()
    for key: String in now:
        if not keys.has(key):
            keys.append(key)
    for key: String in keys:
        var one: PackedByteArray = before.get(key, PackedByteArray())
        var other: PackedByteArray = now.get(key, PackedByteArray())
        if one == other:
            continue
        var size := maxi(one.size(), other.size())
        if one.is_empty():
            one = _zeros(size)
        if other.is_empty():
            other = _zeros(size)
        var side := _side_of(key)
        var origin := _grid_of(key) * side
        @warning_ignore("integer_division")
        var texel := size / (side * side)
        var row_bytes := side * texel
        for y in range(maxi(band.position.y, origin.y), mini(band.end.y, origin.y + side)):
            var at := (y - origin.y) * row_bytes
            var a := one.slice(at, at + row_bytes)
            var b := other.slice(at, at + row_bytes)
            if a == b:
                continue
            # The longest prefix the two rows share, halved down to a texel:
            # *lo* texels agree and *hi* do not.
            var lo := 0
            var hi := side
            while hi - lo > 1:
                @warning_ignore("integer_division")
                var mid := (lo + hi) / 2
                if a.slice(0, mid * texel) == b.slice(0, mid * texel):
                    lo = mid
                else:
                    hi = mid
            first = origin.x + lo if first < 0 else mini(first, origin.x + lo)
    return first


## The largest change between *before* and *now* of a texel of *band* left of
## document x *behind* that already differed from *start*, paint the stroke had
## laid, and the changes of all such texels summed.
func _relaid(start: Dictionary, before: Dictionary, now: Dictionary, band: Rect2i, behind: int) -> Vector2:
    var most := 0.0
    var sum := 0.0
    for key: String in now:
        var one: PackedByteArray = before.get(key, PackedByteArray())
        var other: PackedByteArray = now[key]
        if one == other or one.is_empty():
            continue
        var origin_bytes: PackedByteArray = start.get(key, _zeros(other.size()))
        var side := _side_of(key)
        var origin := _grid_of(key) * side
        if origin.x >= behind:
            continue
        @warning_ignore("integer_division")
        var texel := other.size() / (side * side)
        var row_bytes := side * texel
        for y in range(maxi(band.position.y, origin.y), mini(band.end.y, origin.y + side)):
            var at := (y - origin.y) * row_bytes
            var a := one.slice(at, at + row_bytes)
            var b := other.slice(at, at + row_bytes)
            if a == b:
                continue
            var o := origin_bytes.slice(at, at + row_bytes)
            for x in range(0, mini(side, behind - origin.x)):
                var t := x * texel
                if _apart(a, o, t, texel) > 0.0:
                    var apart := _apart(a, b, t, texel)
                    most = maxf(most, apart)
                    sum += apart
    return Vector2(most, sum)


## The largest difference of a channel of the texel at byte *t* of two rows
## of half floats, *texel* bytes a texel.
static func _apart(a: PackedByteArray, b: PackedByteArray, t: int, texel: int) -> float:
    var most := 0.0
    for c in range(0, texel, _width(texel)):
        most = maxf(most, absf(_channel(a, t + c, texel) - _channel(b, t + c, texel)))
    return most


## The bytes a channel takes in a texel of *texel* bytes: a float of four in
## the colour's four channels, a half of two in the height's one.
static func _width(texel: int) -> int:
    return 4 if texel >= 16 else 2


static func _channel(a: PackedByteArray, at: int, texel: int) -> float:
    return a.decode_float(at) if _width(texel) == 4 else a.decode_half(at)


static func _zeros(size: int) -> PackedByteArray:
    var out := PackedByteArray()
    out.resize(size)
    out.fill(0)
    return out


func _grid_of(key: String) -> Vector2i:
    var inner := key.get_slice("(", 1).get_slice(")", 0)
    return Vector2i(int(inner.get_slice(",", 0)), int(inner.get_slice(",", 1)))


func _side_of(key: String) -> int:
    var layer: SaLayer = _document().stroke_layer if key.begins_with("buffer") else _document().active_layer
    for grid: Vector2i in layer.chunks:
        return (layer.chunks[grid] as SaChunk).pixel_size()
    return 256


## The active layer's colour and height after the lift, as floats.
func _layer_fields() -> Dictionary:
    var layer := _document().active_layer
    var out := {}
    for grid: Vector2i in layer.chunks:
        @warning_ignore("static_called_on_instance")
        out["%s albedo" % grid] = SaExport.get_texture_image_float(layer.get_field(grid))
        var height := layer.get_field(grid, SaFieldSpec.HEIGHT)
        if height != null:
            out["%s height" % grid] = GlobalShaderCompiler.get_rd().texture_get_data(height.rid, 0)
    return out


## The largest difference of any channel between two readings of one field.
func _largest_difference(one: Variant, other: Variant) -> float:
    var most := 0.0
    if one is Image:
        var a := one as Image
        var b := other as Image
        if a.get_data() == b.get_data():
            return 0.0
        for y in a.get_height():
            for x in a.get_width():
                var c := a.get_pixel(x, y)
                var d := b.get_pixel(x, y)
                most = maxf(most, maxf(maxf(absf(c.r - d.r), absf(c.g - d.g)), maxf(absf(c.b - d.b), absf(c.a - d.a))))
        return most
    var p := one as PackedByteArray
    var q := other as PackedByteArray
    if p == q:
        return 0.0
    @warning_ignore("integer_division")
    for i in p.size() / 2:
        most = maxf(most, absf(p.decode_half(i * 2) - q.decode_half(i * 2)))
    return most
