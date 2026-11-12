## The Stats docker's value groups read three greys by their shares and values.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row's Done line: a document of three flat greys at Oklab L 0.2, 0.5 and
## 0.8 over a half, a quarter and a quarter of the canvas reads three groups
## with those shares within one per cent and those values within 0.02, and a
## flat fill reads one group of the whole canvas. So the suite paints the greys
## a chunk at a time on a real easel, and the part's reduction runs through a
## service of its own when a real idle clock fires, read back at once so an
## assertion can follow it. Then the canvas nobody painted, the rule that tells
## two peaks apart, and the rows the docker shows.
extends "res://tests/test_framework.gd"

## Real composites and the real kernel over them.
const REQUIRES_GPU := true

const ValueGroups := preload("../value_groups.gd")

## Two chunks by two, so a grey over a half is two chunks and a quarter is one.
const SIZE := Vector2i(512, 512)

var _easel: SaEasel = null
var _clock: SaIdleClock = null
var _service: SaReductionService = null
var _part: ValueGroups = null


func before_each() -> void:
    _open(SaColorSpace.srgb())


func after_each() -> void:
    _close()


## An easel in *space*, a clock and a service of its own, and a fresh part.
func _open(space: SaColorSpace) -> void:
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
    _part = ValueGroups.new()
    _numbers().read_at_once = true


func _close() -> void:
    _numbers().let_go()
    _part = null
    _service.free()
    _clock.free()
    _easel.free()


func _numbers() -> SaReductionService.OverDocument:
    return _part.reduction as SaReductionService.OverDocument


## A neutral grey at Oklab lightness *lightness*, as the document stores it.
func _grey(lightness: float) -> Color:
    var linear := SaOklab.to_linear_srgb(Vector3(lightness, 0.0, 0.0))
    var shown := Color(linear.x, linear.y, linear.z).linear_to_srgb()
    return _easel.document.color_space.from_display(shown)


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


## The groups the part finds now, after a stop.
func _groups() -> Array:
    _service.add(_part.reduction)
    assert_true(_stop(), "The clock fires")
    return _part.groups_of(_easel.document)


## *weights* of the canvas, in whole texels, at the bins they name, as the
## kernel's tally holds them.
static func _bins(weights: Dictionary) -> PackedInt64Array:
    var out := PackedInt64Array()
    out.resize(ValueGroups.BINS)
    for at: int in weights:
        out[at] = int(weights[at]) * ValueGroups.WHOLE
    return out


func test_three_greys_read_three_groups_with_their_shares_and_values() -> void:
    _paint_chunk(Vector2i(0, 0), _grey(0.2))
    _paint_chunk(Vector2i(0, 1), _grey(0.2))
    _paint_chunk(Vector2i(1, 0), _grey(0.5))
    _paint_chunk(Vector2i(1, 1), _grey(0.8))
    var groups := _groups()
    assert_eq(groups.size(), 3, "Three greys are three groups")
    if groups.size() != 3:
        return
    var wanted := [[0.5, 0.2], [0.25, 0.5], [0.25, 0.8]]
    for at in 3:
        var group: ValueGroups.Group = groups[at]
        var share: float = wanted[at][0]
        var value: float = wanted[at][1]
        var said := "group %d holds %.2f of the canvas, read %.4f" % [at + 1, share, group.share]
        assert_true(absf(group.share - share) <= 0.01, said)
        assert_true(absf(group.value - value) <= 0.02, "and sits at L %.2f, read %.4f" % [value, group.value])


func test_a_flat_fill_reads_one_group_of_the_whole_canvas() -> void:
    _easel.document.fill_layer(Color(0.3, 0.6, 0.2))
    var groups := _groups()
    assert_eq(groups.size(), 1, "A flat fill is one group")
    if groups.is_empty():
        return
    var group: ValueGroups.Group = groups[0]
    assert_true(is_equal_approx(group.share, 1.0), "of the whole canvas, read %.4f" % group.share)
    var linear := Color(0.3, 0.6, 0.2).srgb_to_linear()
    var lightness := SaOklab.from_linear_srgb(Vector3(linear.r, linear.g, linear.b)).x
    assert_true(absf(group.value - lightness) <= 0.02, "at the fill's own L %.3f, read %.4f" % [lightness, group.value])


## The value is Oklab L taken through the document's own space: a green past
## sRGB's gamut in a Rec. 2020 document reads its own lightness, which the same
## numbers read as sRGB would miss.
func test_a_wide_gamut_document_reads_its_own_lightness() -> void:
    _close()
    _open(SaColorSpace.rec2020())
    var stored := Vector3(0.05, 0.6, 0.05)
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
        _paint_chunk(grid_pos, Color(stored.x, stored.y, stored.z))
    var groups := _groups()
    assert_eq(groups.size(), 1, "A canvas of one stored colour in Rec. 2020 is one group")
    if groups.is_empty():
        return
    var linear := SaColorSpace.rec2020().to_linear_srgb_matrix() * stored
    assert_true(linear.x < 0.0, "The green is past sRGB's gamut")
    var lightness := SaOklab.from_linear_srgb(linear).x
    var as_srgb := SaOklab.from_linear_srgb(stored).x
    var value: float = (groups[0] as ValueGroups.Group).value
    assert_true(absf(value - lightness) <= 0.02, "at its own L %.3f, read %.4f" % [lightness, value])
    assert_true(absf(value - as_srgb) > 0.02, "and not at the L %.3f its numbers have as sRGB" % as_srgb)


## A transparent document of four chunks with paint in two: black over one,
## and white at half alpha over the other. Two chunks are dispatched over and
## the other two are added as the checkerboard they show.
func test_the_canvas_nobody_painted_counts_as_the_background_it_shows() -> void:
    var background := SaDocumentBackground.default_choice()
    background[SaDocumentBackground.KIND] = SaDocumentBackground.TRANSPARENT
    _easel.document.reset_to_default(SIZE, SaColorSpace.srgb(), SaDocument.DEFAULT_DPI, background)
    assert_not_null(_easel.resize_output(SIZE), "the output is the canvas's size")
    assert_true(_easel.document.active_layer.chunks.is_empty(), "The transparent document holds no chunk")
    _paint_chunk(Vector2i(0, 0), Color.BLACK)
    _paint_chunk(Vector2i(1, 1), Color(1.0, 1.0, 1.0, 0.5))
    var groups := _groups()
    var read := _numbers().dispatched.duplicate()
    read.sort()
    assert_eq(read, [Vector2i(0, 0), Vector2i(1, 1)] as Array[Vector2i], "The two painted chunks are all it read")
    assert_eq(groups.size(), 3, "Black, the checkerboard and white are three groups")
    if groups.size() != 3:
        return
    var black: ValueGroups.Group = groups[0]
    var ground: ValueGroups.Group = groups[1]
    var white: ValueGroups.Group = groups[2]
    assert_true(absf(black.share - 0.25) <= 0.01, "Black covers a quarter, read %.4f" % black.share)
    assert_true(absf(white.share - 0.125) <= 0.01, "white at half alpha half a quarter, read %.4f" % white.share)
    assert_true(absf(ground.share - 0.625) <= 0.01, "and the checkerboard the rest, read %.4f" % ground.share)
    var checker := ValueGroups.background_lightness()
    assert_true(absf(ground.value - checker) <= 0.001, "at the checkerboard's L %.3f, read %.4f" % [checker, ground.value])
    assert_true(checker > 0.5 and checker < 0.7, "which is between its two greys, read %.3f" % checker)


func test_two_peaks_close_together_are_one_group_and_far_apart_two() -> void:
    var texels := 1000
    var close := ValueGroups.find(_bins({30: 500, 33: 500}), texels, 0.5)
    assert_eq(close.size(), 1, "Three bins apart, the smoothed histogram never dips between them")
    var apart := ValueGroups.find(_bins({20: 500, 40: 500}), texels, 0.5)
    assert_eq(apart.size(), 2, "Twenty bins apart, they are two")
    var ridge := ValueGroups.find(_bins({20: 375, 26: 375, 23: 250}), texels, 0.5)
    assert_eq(ridge.size(), 1, "A valley above half the lower peak joins the two")
    var dip := ValueGroups.find(_bins({20: 450, 26: 450, 23: 100}), texels, 0.5)
    assert_eq(dip.size(), 2, "and one below it keeps them apart")


func test_a_group_under_one_per_cent_joins_its_neighbour() -> void:
    var groups := ValueGroups.find(_bins({10: 5, 40: 995}), 1000, 0.5)
    assert_eq(groups.size(), 1, "Half a per cent of the canvas is no group of its own")
    if groups.size() == 1:
        assert_true(is_equal_approx((groups[0] as ValueGroups.Group).share, 1.0), "and its share goes to the one left")
    var kept := ValueGroups.find(_bins({10: 20, 40: 980}), 1000, 0.5)
    assert_eq(kept.size(), 2, "Two per cent is one")


func test_past_eight_groups_the_closest_are_joined() -> void:
    var weights := {}
    for at in 10:
        weights[3 + at * 6] = 100
    var groups := ValueGroups.find(_bins(weights), 1000, 0.5)
    assert_eq(groups.size(), ValueGroups.MOST, "Ten even peaks are named as eight")
    var whole := 0.0
    for group: ValueGroups.Group in groups:
        whole += group.share
    assert_true(is_equal_approx(whole, 1.0), "and the shares still add up to the canvas, read %.4f" % whole)


func test_the_rows_show_the_count_and_each_groups_share_and_value() -> void:
    var page := SaPage.new(_part.declare)
    page.declare_rows()
    var box := VBoxContainer.new()
    page.realize(box)
    var count := page.row(&"value_groups")
    assert_eq(count.value, 0, "Before a run there is no group")
    assert_false(page.row(&"value_group_1").line.visible, "and no group row is on the page")

    _paint_chunk(Vector2i(0, 0), _grey(0.2))
    _paint_chunk(Vector2i(0, 1), _grey(0.2))
    _paint_chunk(Vector2i(1, 0), _grey(0.5))
    _paint_chunk(Vector2i(1, 1), _grey(0.8))
    _service.add(_part.reduction)
    assert_true(_stop(), "The clock fires")
    _part.follow(_easel.document)
    assert_eq(count.value, 3, "The count row reads three")
    assert_eq((count.control as Label).text, "3", "and shows it")
    for at in ValueGroups.MOST:
        var row := page.row(StringName("value_group_%d" % (at + 1)))
        assert_eq(row.line.visible, at < 3, "group row %d is on the page while there is a group for it" % (at + 1))
    var first := page.row(&"value_group_1")
    assert_eq(first.label, "Value 0.20", "The darkest row is titled by its middle value")
    assert_eq(first.value, "50 %", "and says its share")
    assert_eq((first.control as Label).text, "50 %", "on screen")
    assert_false((count.control as Label).tooltip_text.is_empty(), "The rule that tells two peaks apart is on hover")
    box.free()


func test_the_count_asks_for_frames_while_the_tally_is_on_its_way() -> void:
    var page := SaPage.new(_part.declare)
    page.declare_rows()
    var box := VBoxContainer.new()
    page.realize(box)
    var count := page.row(&"value_groups")
    var words := count.control as ValueGroups.Readout
    _numbers().read_at_once = false
    _paint_chunk(Vector2i(0, 0), _grey(0.2))
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
    assert_true(count.value >= 1, "Then the rows show what came back")
    box.free()
