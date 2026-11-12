## With Keep chroma on, a turn of the ring or of the HSL square's hue bar
## leaves the hue exactly under the pointer on every shape that has one, and
## the kept Oklab lightness and chroma move only the point in the area. On a
## classic shape that point is the one of the pointer's HSV hue nearest the
## kept lightness and chroma, which this suite checks against a search of its
## own over the whole area.
extends "res://tests/test_framework.gd"

const OkhslConversionsScript = preload("res://utils/okhsl_conversions.gd")

const SIDE := 200.0
## A full turn and a little more, in steps of a two hundredth of a turn.
const STEPS := 210
const STEP := 1.0 / 200.0
## The shapes with a ring, and the HSL square with its hue bar. The OKHSL disc
## turns its hue in the area itself, so Keep chroma has nothing to do there.
const RINGED: Array[int] = [
    SaPickerShape.Kind.WHEEL,
    SaPickerShape.Kind.TRIANGLE,
    SaPickerShape.Kind.TRIANGLE_UP,
    SaPickerShape.Kind.HSV_SQUARE,
    SaPickerShape.Kind.HSV_TRIANGLE,
]
## Three starting colours: a saturated warm one, a pale one and a dark one, so
## the turn runs both inside and against the gamut's edge.
const STARTS: Array[Color] = [Color(0.8, 0.3, 0.2), Color(0.75, 0.8, 0.9), Color(0.1, 0.25, 0.12)]

var _holder: Control


func before_each() -> void:
    _holder = Control.new()
    var root := (Engine.get_main_loop() as SceneTree).root
    root.get_child(root.get_child_count() - 1).add_child(_holder)


func after_each() -> void:
    if is_instance_valid(_holder):
        _holder.free()


func _shape(kind: int, col: Color) -> SaPickerShape:
    var shape := SaPickerShape.new()
    _holder.add_child(shape)
    shape.set_kind(kind)
    shape.keep_chroma = true
    shape.frame.size = Vector2(SIDE, SIDE)
    shape._on_frame_resized()
    shape.hue_bar.size = Vector2(18.0, SIDE)
    shape.set_from_color(col)
    return shape


func _lc(col: Color) -> Vector2:
    var lch := OkhslConversionsScript.srgb_to_oklch(col)
    return Vector2(lch.z, lch.y)


static func _turn_gap(a: float, b: float) -> float:
    var d := fposmod(a - b, 1.0)
    return minf(d, 1.0 - d)


## How near the HSV hue *hue*, the plane every classic shape shows, comes to
## *kept* in Oklab lightness and chroma, by the shape's own measure, through a
## plain search of a grid, which is the slow way the shape must agree with.
func _nearest_classic(hue: float, kept: Vector2) -> float:
    var best := INF
    var at := Vector2.ZERO
    var n := 40
    for i in range(n + 1):
        for j in range(n + 1):
            var axes := Vector2(float(i) / n, float(j) / n)
            var miss := SaPickerClassic.lc_miss(hue, axes, kept)
            if miss < best:
                best = miss
                at = axes
    # Then a grid twenty times finer round the best cell, which makes it a
    # reference in steps of an eight hundredth of the side, not a fortieth.
    var around := at
    for i in range(-20, 21):
        for j in range(-20, 21):
            var axes := (around + Vector2(i, j) / (20.0 * n)).clamp(Vector2.ZERO, Vector2.ONE)
            best = minf(best, SaPickerClassic.lc_miss(hue, axes, kept))
    return best


## Whether the Oklab gamut holds *kept* at Oklab hue *oklab_hue*.
func _gamut_holds(oklab_hue: float, kept: Vector2) -> bool:
    var angle := TAU * oklab_hue
    return kept.y <= OkhslConversionsScript.gamut_chroma(cos(angle), sin(angle), kept.x) - 0.002


## One step: the ring to *angle* turns, or the hue bar to that fraction of its
## height on the HSL square. Returns where the pointer asked the hue to be, as
## a ring angle or a bar fraction.
func _step(shape: SaPickerShape, at: float) -> float:
    if shape.kind == SaPickerShape.Kind.HSL_SQUARE:
        var y := clampf(fposmod(at, 1.0), 0.0, 1.0)
        shape._drag_bar(Vector2(9.0, y * SIDE))
        return y
    shape._drag_ring(Vector2.from_angle(TAU * at) * SIDE * 0.45)
    return fposmod(at, 1.0)


func _where(shape: SaPickerShape) -> float:
    if shape.kind == SaPickerShape.Kind.HSL_SQUARE:
        return shape.hue
    return SaPickerShape.ring_angle(shape.hue, SaPickerShape.is_classic(shape.kind))


func _kinds() -> Array[int]:
    var out: Array[int] = RINGED.duplicate()
    out.append(SaPickerShape.Kind.HSL_SQUARE)
    return out


func test_the_ring_s_cursor_stays_under_the_pointer_on_every_shape() -> void:
    var began := Time.get_ticks_usec()
    var turns := 0
    for kind: int in _kinds():
        for start: Color in STARTS:
            var shape := _shape(kind, start)
            var from := _where(shape)
            var worst := 0.0
            for k in range(1, STEPS + 1):
                var asked := _step(shape, from + k * STEP)
                worst = maxf(worst, _turn_gap(_where(shape), asked))
                turns += 1
            var name := "%s from %s" % [SaPickerShape.KIND_KEYS[kind], start.to_html(false)]
            var said := "%s: the cursor sits under the pointer at every step, worst %.5f of a turn"
            assert_true(worst < 0.001, said % [name, worst])
            shape.free()
    print("one turn of the ring takes %.0f microseconds" % (float(Time.get_ticks_usec() - began) / turns))


func test_the_kept_lightness_and_chroma_move_only_the_point() -> void:
    for kind: int in _kinds():
        var classic := SaPickerShape.is_classic(kind)
        for start: Color in STARTS:
            var shape := _shape(kind, start)
            var kept := _lc(shape.color())
            var from := _where(shape)
            var worst := 0.0
            var worse_than_best := 0.0
            for k in range(1, STEPS + 1, 13):
                _step(shape, from + k * STEP)
                var miss := _lc(shape.color()).distance_to(kept)
                if classic:
                    # The pointer's HSV hue may not reach the kept pair at all,
                    # so the point is held to the nearest the area offers.
                    var best := _nearest_classic(shape.hue, kept)
                    var shown := shape.color()
                    var found := SaPickerClassic.lc_miss(shape.hue, Vector2(shown.s, shown.v), kept)
                    worse_than_best = maxf(worse_than_best, found - best)
                    if best < 0.001:
                        worst = maxf(worst, miss)
                elif _gamut_holds(OkhslConversionsScript.srgb_to_oklch(shape.color()).x, kept):
                    worst = maxf(worst, miss)
            var name := "%s from %s" % [SaPickerShape.KIND_KEYS[kind], start.to_html(false)]
            var said := "%s: lightness and chroma are the kept ones where the hue reaches them, worst %.4f"
            assert_true(worst < 0.003, said % [name, worst])
            if classic:
                said = "%s: and nowhere farther than the nearest point of the hue, worst %.4f"
                assert_true(worse_than_best < 0.0005, said % [name, worse_than_best])
            shape.free()


func test_a_turn_back_to_the_first_hue_gives_the_first_colour() -> void:
    for kind: int in _kinds():
        for start: Color in STARTS:
            var shape := _shape(kind, start)
            var first := shape.color()
            var from := _where(shape)
            # Out a third of a turn and back the same way, in one gesture.
            for k in range(1, 67):
                _step(shape, from + k * STEP)
            for k in range(65, -1, -1):
                _step(shape, from + k * STEP)
            var back := shape.color()
            var name := "%s from %s" % [SaPickerShape.KIND_KEYS[kind], start.to_html(false)]
            var gap := maxf(absf(back.r - first.r), maxf(absf(back.g - first.g), absf(back.b - first.b)))
            assert_true(gap < 0.004, "%s: back at the first hue the colour is the first one, off by %.4f" % [name, gap])
            shape.free()
