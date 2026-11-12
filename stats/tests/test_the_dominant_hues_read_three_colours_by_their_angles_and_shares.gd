## The Stats docker's dominant hues read three colours by their angles and
## shares.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row's Done lines: three flat colours of one lightness and chroma inside
## sRGB, at hues 120 degrees apart over equal thirds, read three hues 120
## degrees apart within 2 degrees, each a third within one per cent. Two colours
## 30 degrees apart read two hues 30 degrees apart, and a document of greys
## reads none. A Display P3 document painted in the same Oklab colours reads the
## same hues. So the suite paints the colours a chunk at a time on a real easel,
## and the part's reduction runs through a service of its own when a real idle
## clock fires, read back at once so an assertion can follow it. Then a hue
## across 0 degrees, the rules that tell hues apart, and the rows the docker
## shows.
extends "res://tests/test_framework.gd"

## Real composites and the real kernel over them.
const REQUIRES_GPU := true

const DominantHues := preload("../dominant_hues.gd")

## Three chunks in a row, so a colour over a third is one chunk.
const SIZE := Vector2i(768, 256)

## One lightness and chroma, inside sRGB at every hue the suite paints.
const LIGHTNESS := 0.7
const CHROMA := 0.1

## How near an angle reads, in degrees, and a share, of the canvas.
const ANGLE_SLACK := 2.0
const SHARE_SLACK := 0.01

var _easel: SaEasel = null
var _clock: SaIdleClock = null
var _service: SaReductionService = null
var _part: DominantHues = null


func before_each() -> void:
    _build(SaColorSpace.srgb())


func after_each() -> void:
    _drop()


func _build(space: SaColorSpace) -> void:
    _easel = SaEasel.create_default(SIZE, null, space)
    _easel.process_pending_composite()
    _clock = SaIdleClock.new()
    _clock.follow_settings = false
    _clock.follow_main = false
    _clock.idle_seconds = 1.0
    _clock.attach(_easel.document)
    _service = SaReductionService.new()
    _service.watch(_easel)
    _service.listen(_clock)
    _part = DominantHues.new()
    _numbers().read_at_once = true


func _drop() -> void:
    _numbers().let_go()
    _part = null
    _service.free()
    _clock.free()
    _easel.free()


## The suite's own document again, in *space*.
func _rebuild(space: SaColorSpace) -> void:
    _drop()
    _build(space)


func _numbers() -> SaReductionService.OverDocument:
    return _part.reduction as SaReductionService.OverDocument


## The colour at Oklab *lightness*, *chroma* and *hue* in degrees, as the
## document stores it, whatever its colour space.
func _oklch(hue: float, chroma: float = CHROMA, lightness: float = LIGHTNESS) -> Color:
    var lab := SaOklab.from_polar(Vector3(lightness, chroma, deg_to_rad(hue)))
    var linear := SaOklab.to_linear_srgb(lab)
    var inside := linear.x >= 0.0 and linear.y >= 0.0 and linear.z >= 0.0
    inside = inside and linear.x <= 1.0 and linear.y <= 1.0 and linear.z <= 1.0
    assert_true(inside, "Hue %.0f at L %.2f and C %.2f is inside sRGB" % [hue, lightness, chroma])
    return SaColorSpace.oklab().carried_to(_easel.document.color_space, Color(lab.x, lab.y, lab.z))


## Paints the chunk at *grid_pos* of the paint layer one colour and tells the
## document, the way a dab inside one chunk does.
func _paint_chunk(grid_pos: Vector2i, colour: Color) -> void:
    var document := _easel.document
    document.active_layer.get_or_create_chunk(grid_pos).clear(colour)
    document.invalidate_chunk_regions({grid_pos: Rect2i(Vector2i.ZERO, Vector2i.ONE * SaLayer.CHUNK_SIZE)})


## The painter stops, and the service runs what is registered.
func _stop() -> bool:
    _clock.note_edit()
    return _clock.tick(_clock.idle_seconds)


## The hues the part finds now, after a stop.
func _hues() -> Array:
    _service.add(_part.reduction)
    assert_true(_stop(), "The clock fires")
    return _part.hues_of(_easel.document)


## How far *one* is from *other* round the wheel, in degrees from 0 to 180.
static func _apart(one: float, other: float) -> float:
    return absf(wrapf(one - other, -180.0, 180.0))


## The found hue nearest *angle*, or null.
static func _nearest(hues: Array, angle: float) -> DominantHues.Hue:
    var best: DominantHues.Hue = null
    for hue: DominantHues.Hue in hues:
        if best == null or _apart(hue.angle, angle) < _apart(best.angle, angle):
            best = hue
    return best


## That *hues* are the painted *angles*, each within `ANGLE_SLACK`, holding
## *share* of the canvas each, said for a document *said*.
func _reads(hues: Array, angles: Array, share: float, said: String) -> void:
    assert_eq(hues.size(), angles.size(), "%s: %d hues" % [said, angles.size()])
    for angle: float in angles:
        var hue := _nearest(hues, angle)
        if hue == null:
            continue
        var off := _apart(hue.angle, angle)
        assert_true(off <= ANGLE_SLACK, "%s: hue %.0f reads %.2f" % [said, angle, hue.angle])
        var holds := absf(hue.share - share) <= SHARE_SLACK
        assert_true(holds, "%s: hue %.0f holds %.3f of the canvas, read %.4f" % [said, angle, share, hue.share])


## The three hues 120 degrees apart, a chunk each, and what the part reads.
func _paint_three() -> Array:
    _paint_chunk(Vector2i(0, 0), _oklch(30.0))
    _paint_chunk(Vector2i(1, 0), _oklch(150.0))
    _paint_chunk(Vector2i(2, 0), _oklch(270.0))
    return _hues()


## The gaps between neighbouring *hues* round the wheel, sorted.
static func _gaps(hues: Array) -> Array[float]:
    var angles: Array[float] = []
    for hue: DominantHues.Hue in hues:
        angles.append(hue.angle)
    angles.sort()
    var gaps: Array[float] = []
    for at in angles.size():
        gaps.append(fposmod(angles[(at + 1) % angles.size()] - angles[at], 360.0))
    gaps.sort()
    return gaps


## *cells* as the kernel's tally holds them, from bins of whole texels at a
## place in each bin, *weights* bin to texels.
static func _cells(weights: Dictionary, place: float = 0.5) -> PackedInt64Array:
    var out := PackedInt64Array()
    out.resize(DominantHues.CELLS)
    for at: int in weights:
        var weight := int(weights[at]) * DominantHues.WHOLE
        out[at * 2] = weight
        out[at * 2 + 1] = int(round(weight * place * DominantHues.STEPS))
    return out


func test_three_hues_120_degrees_apart_read_three_with_their_angles_and_thirds() -> void:
    var hues := _paint_three()
    _reads(hues, [30.0, 150.0, 270.0], 1.0 / 3.0, "sRGB")
    if hues.size() != 3:
        return
    for gap: float in _gaps(hues):
        assert_true(absf(gap - 120.0) <= ANGLE_SLACK, "Neighbours are 120 degrees apart, read %.2f" % gap)
    var widest := DominantHues.gap_of(hues)
    assert_true(absf(widest - 120.0) <= ANGLE_SLACK, "and the widest gap is 120, read %.2f" % widest)


func test_two_hues_30_degrees_apart_read_two_and_a_grey_adds_none() -> void:
    _paint_chunk(Vector2i(0, 0), _oklch(40.0))
    _paint_chunk(Vector2i(1, 0), _oklch(70.0))
    var grey := SaOklab.to_linear_srgb(Vector3(LIGHTNESS, 0.0, 0.0))
    _paint_chunk(Vector2i(2, 0), _easel.document.color_space.from_display(Color(grey.x, grey.y, grey.z).linear_to_srgb()))
    var hues := _hues()
    _reads(hues, [40.0, 70.0], 1.0 / 3.0, "Two hues beside a grey")
    if hues.size() != 2:
        return
    var apart := _apart((hues[0] as DominantHues.Hue).angle, (hues[1] as DominantHues.Hue).angle)
    assert_true(absf(apart - 30.0) <= ANGLE_SLACK, "They are 30 degrees apart, read %.2f" % apart)
    var widest := DominantHues.gap_of(hues)
    assert_true(absf(widest - 330.0) <= ANGLE_SLACK, "and the widest gap is the rest of the wheel, read %.2f" % widest)


func test_a_document_of_greys_reads_no_hue() -> void:
    for at in 3:
        var lightness := 0.25 + 0.25 * at
        var linear := SaOklab.to_linear_srgb(Vector3(lightness, 0.0, 0.0))
        var shown := Color(linear.x, linear.y, linear.z).linear_to_srgb()
        _paint_chunk(Vector2i(at, 0), _easel.document.color_space.from_display(shown))
    assert_eq(_hues().size(), 0, "Three greys are no hue")
    assert_eq(_numbers().dispatched.size(), 3, "though all three chunks were read")
    _paint_chunk(Vector2i(1, 0), _oklch(200.0, DominantHues.CHROMA_FLOOR * 0.5))
    assert_eq(_hues().size(), 0, "Paint under the chroma floor is grey too")
    _paint_chunk(Vector2i(1, 0), _oklch(200.0, DominantHues.CHROMA_FLOOR * 2.0))
    assert_eq(_hues().size(), 1, "and twice the floor is a hue")


func test_a_display_p3_document_in_the_same_oklab_colours_reads_the_same_hues() -> void:
    var srgb := _paint_three()
    _rebuild(SaColorSpace.display_p3())
    assert_true(_easel.document.color_space.matches(SaColorSpace.display_p3()), "The document is Display P3")
    var stored := _oklch(30.0)
    var p3 := _paint_three()
    _reads(p3, [30.0, 150.0, 270.0], 1.0 / 3.0, "Display P3")
    assert_false(stored.is_equal_approx(_srgb_stored(30.0)), "Its stored triples are not sRGB's")
    for hue: DominantHues.Hue in srgb:
        var same := _nearest(p3, hue.angle)
        if same != null:
            var off := _apart(same.angle, hue.angle)
            assert_true(off <= ANGLE_SLACK, "P3 reads sRGB's hue %.2f as %.2f" % [hue.angle, same.angle])
    _rebuild(SaColorSpace.oklab())
    _reads(_paint_three(), [30.0, 150.0, 270.0], 1.0 / 3.0, "An Oklab document")


## The triple an sRGB document stores for the suite's colour at *hue*.
func _srgb_stored(hue: float) -> Color:
    var lab := SaOklab.from_polar(Vector3(LIGHTNESS, CHROMA, deg_to_rad(hue)))
    return SaColorSpace.oklab().carried_to(SaColorSpace.srgb(), Color(lab.x, lab.y, lab.z))


func test_a_hue_across_0_degrees_counts_once() -> void:
    _paint_chunk(Vector2i(0, 0), _oklch(357.0))
    _paint_chunk(Vector2i(1, 0), _oklch(3.0))
    var hues := _hues()
    assert_eq(hues.size(), 1, "357 and 3 degrees are one hue")
    if hues.size() != 1:
        return
    var hue: DominantHues.Hue = hues[0]
    assert_true(_apart(hue.angle, 0.0) <= ANGLE_SLACK, "at 0 degrees and not 180, read %.2f" % hue.angle)
    assert_true(absf(hue.share - 2.0 / 3.0) <= SHARE_SLACK, "holding both, read %.4f" % hue.share)
    assert_eq(DominantHues.gap_of(hues), 0.0, "One hue has no gap")


func test_peaks_far_apart_are_two_hues_and_close_ones_one() -> void:
    var close := DominantHues.find(_cells({10: 500, 13: 500}), 1000)
    assert_eq(close.size(), 1, "Three bins apart, the smoothed histogram never dips between them")
    var apart := DominantHues.find(_cells({10: 500, 16: 500}), 1000)
    assert_eq(apart.size(), 2, "Six bins apart, they are two")
    var ridge := DominantHues.find(_cells({20: 375, 26: 375, 23: 250}), 1000)
    assert_eq(ridge.size(), 1, "A valley above half the lower peak joins the two")
    var dip := DominantHues.find(_cells({20: 450, 26: 450, 23: 100}), 1000)
    assert_eq(dip.size(), 2, "and one below it keeps them apart")
    var wrapped := DominantHues.find(_cells({71: 300, 0: 300, 1: 300}), 1000)
    assert_eq(wrapped.size(), 1, "Bins either side of 0 degrees are one hue")
    var placed := DominantHues.find(_cells({24: 500}, 0.25), 1000)
    assert_eq(placed.size(), 1, "One bin is one hue")
    if placed.size() == 1:
        var angle := (placed[0] as DominantHues.Hue).angle
        var said := "at its place in the bin, a quarter of five degrees past 120, read %.3f" % angle
        assert_true(absf(angle - 121.25) <= 0.05, said)


func test_a_speck_is_not_named_and_past_six_the_closest_are_joined() -> void:
    var speck := DominantHues.find(_cells({10: 5, 40: 995}), 1000)
    assert_eq(speck.size(), 1, "Half a per cent of the coloured paint is not named")
    if speck.size() == 1:
        var kept: DominantHues.Hue = speck[0]
        assert_true(_apart(kept.angle, 202.5) <= 0.05, "and does not pull the hue named towards it, read %.3f" % kept.angle)
        assert_true(absf(kept.share - 0.995) <= 0.0001, "whose share is its own, read %.4f" % kept.share)
    var named := DominantHues.find(_cells({10: 20, 40: 980}), 1000)
    assert_eq(named.size(), 2, "Two per cent is named")
    var weights := {}
    for at in 9:
        weights[at * 8] = 100
    var nine := DominantHues.find(_cells(weights), 1000)
    assert_eq(nine.size(), DominantHues.MOST, "Nine even peaks are named as six")
    var whole := 0.0
    for hue: DominantHues.Hue in nine:
        whole += hue.share
    assert_true(absf(whole - 0.9) <= 0.0001, "and the shares still add up to the paint, read %.4f" % whole)
    var none := DominantHues.find(PackedInt64Array(), 1000)
    assert_eq(none.size(), 0, "No coloured paint is no hue")


func test_the_rows_show_the_count_each_hues_angle_and_share_and_the_widest_gap() -> void:
    var page := SaPage.new(_part.declare)
    page.declare_rows()
    var box := VBoxContainer.new()
    page.realize(box)
    var count := page.row(&"hues")
    assert_eq(count.value, 0, "Before a run there is no hue")
    assert_false(page.row(&"hue_1").line.visible, "and no hue row is on the page")
    assert_false(page.row(&"hue_gap").line.visible, "nor the gap")
    assert_false(page.row(&"hue_spread").line.visible, "nor the spread")

    _paint_chunk(Vector2i(0, 0), _oklch(30.0))
    _paint_chunk(Vector2i(1, 0), _oklch(30.0))
    _paint_chunk(Vector2i(2, 0), _oklch(270.0))
    _service.add(_part.reduction)
    assert_true(_stop(), "The clock fires")
    _part.follow(_easel.document)
    assert_eq(count.value, 2, "The count row reads two")
    assert_eq((count.control as Label).text, "2", "and shows it")
    for at in DominantHues.MOST:
        var row := page.row(StringName("hue_%d" % (at + 1)))
        assert_eq(row.line.visible, at < 2, "hue row %d is on the page while there is a hue for it" % (at + 1))
    var first := page.row(&"hue_1")
    assert_eq(first.label, "Hue 30°", "The largest hue's row is titled by its angle")
    assert_eq(first.value, "67 %", "and says its share")
    assert_eq((first.control as Label).text, "67 %", "on screen")
    assert_eq(page.row(&"hue_2").label, "Hue 270°", "The smaller comes second")
    var gap := page.row(&"hue_gap")
    assert_true(gap.line.visible, "With two hues the gap is on the page")
    assert_eq(gap.value, "240°", "and reads the wider way round from 30 to 270")
    var spread := page.row(&"hue_spread")
    assert_true(spread.line.visible, "So is the spread")
    assert_eq(spread.value, "120°", "the arc that holds both, 360 less 240")
    assert_eq((spread.control as Label).text, "120°", "on screen")
    assert_false((count.control as Label).tooltip_text.is_empty(), "The rule and the chroma floor are on hover")
    assert_true((count.control as Label).tooltip_text.contains("0.03"), "the floor by its number")
    box.free()


func test_the_count_asks_for_frames_while_the_tally_is_on_its_way() -> void:
    var page := SaPage.new(_part.declare)
    page.declare_rows()
    var box := VBoxContainer.new()
    page.realize(box)
    var count := page.row(&"hues")
    var words := count.control as DominantHues.Readout
    _numbers().read_at_once = false
    _paint_chunk(Vector2i(0, 0), _oklch(150.0))
    _service.add(_part.reduction)
    assert_true(_stop(), "The clock fires")
    assert_eq(_numbers().waiting, 1, "The run asked the device for its tally")
    _part.follow(_easel.document)
    assert_eq(count.value, 0, "The rows wait for the answer")
    assert_true(words.is_processing(), "and the count's words ask for a frame each frame meanwhile")
    for frame in 8:
        if _numbers().waiting == 0:
            break
        words.notification(Node.NOTIFICATION_PROCESS)
        RenderingServer.force_draw(false, 0.0)
    assert_eq(_numbers().waiting, 0, "The device answered within a few frames")
    words.notification(Node.NOTIFICATION_PROCESS)
    assert_false(words.is_processing(), "and the asking stops once it is in")
    _part.follow(_easel.document)
    assert_eq(count.value, 1, "Then the rows show what came back")
    box.free()
