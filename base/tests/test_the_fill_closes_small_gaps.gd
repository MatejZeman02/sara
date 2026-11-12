## The fill closes small gaps.
##
## A ring with a gap of about 20 pixels lets the fill leak through over the
## whole layer unless a setting stops it. Close gaps is that setting: `close` in `wand.gmacs` grows the
## lines by half the
## setting before the flood, so a gap up to the setting is shut, and `contest`
## and `grow` take the settled flood back to the lines, so what is filled
## reaches them, and share a gap out between the two sides.
##
## The ring is written through the harness's `write_pixels` step, ink with a
## one texel soft edge, and it is centred on the corner where four chunks
## meet, so its gap at the top straddles a seam and the wall it closes against
## lies in two chunks. The canvas is nine chunks, so a leak reaches chunks the
## layer never held.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const StateBucketFillScript = preload("res://modules/sara-base-modules/base/tools/state_bucket_fill.gd")
const SaWandScript = preload("res://modules/sara-base-modules/base/wand/sa_wand.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The Inked Pen's near-black and the fill's blue, display colours.
const INK := Color(0.04, 0.04, 0.05, 1.0)
const BLUE := Color(0.1, 0.4, 0.9, 1.0)

const CENTRE := Vector2(256.0, 256.0)
const INNER := 90.0
const OUTER := 100.0
## The setting under test, and the gaps either side of it.
const SETTING := 24
const NARROW_GAP := 20.0
const WIDE_GAP := 30.0
## Dents round the ragged ring's inner edge, one every three texels or so, and
## how far in and out the edge moves.
const RAGGED_WAVES := 180.0
const RAGGED := 0.9

const WRITTEN := Rect2i(0, 0, 512, 512)
const CANVAS := Vector2i(768, 768)

## Texels the assertions read: the middle, two texels clear of the inner wall on
## the right, the one beside the wall, which the antialias feather softens,
## just inside the gap's mouth, just outside the gap, beside the ring outside,
## and the ground in a chunk the layer never held.
const MIDDLE := Vector2i(256, 256)
const BY_THE_WALL := Vector2i(344, 256)
const AGAINST_THE_WALL := Vector2i(345, 256)
const IN_THE_MOUTH := Vector2i(256, 168)
const PAST_THE_GAP := Vector2i(256, 140)
const BESIDE_THE_RING := Vector2i(370, 256)
const FAR_GROUND := Vector2i(650, 650)
## In the gap, nearer the inside than the outside, and the other way round.
const IN_THE_GAP := Vector2i(256, 164)
const OUT_IN_THE_GAP := Vector2i(256, 158)
## A click five texels from the inner wall, inside the half of the setting
## that `close` takes off every line.
const NEAR_THE_LINE := Vector2i(341, 256)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _folder: String = ""


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _doc = _surface.get_document()
    _folder = OS.get_temp_dir().path_join("sara-s36-close-gaps-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)


func after_each() -> void:
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)
    _doc.free()
    _surface.easel.free()
    _surface = null
    _doc = null


## The ring's alpha at *at*, solid with a one texel ramp on both edges, cut
## by a straight channel *gap* texels wide at the top, 0 for a closed ring.
## *ragged* moves the inner edge in and out by that many texels every three
## texels round, the dents a brush's dabs leave along a stroke's edge.
static func _coverage_at(at: Vector2, gap: float, ragged: float = 0.0) -> float:
    if gap > 0.0 and at.y < CENTRE.y and absf(at.x - CENTRE.x) < gap / 2.0:
        return 0.0
    var d := at.distance_to(CENTRE)
    var inner := INNER + ragged * sin((at - CENTRE).angle() * RAGGED_WAVES)
    return clampf(OUTER + 0.5 - d, 0.0, 1.0) * clampf(d - inner + 0.5, 0.0, 1.0)


## A new layer holding the ring, written through the harness's `write_pixels`
## the way the fill suites write their line art, and the merged picture brought up
## to date the way a frame would.
func _ring(gap: float, name: String = "Ring", ragged: float = 0.0) -> SaLayer:
    var stored := _doc.color_space.from_display(INK)
    var floats := PackedFloat32Array()
    floats.resize(WRITTEN.size.x * WRITTEN.size.y * 4)
    for y in WRITTEN.size.y:
        for x in WRITTEN.size.x:
            var alpha := _coverage_at(Vector2(x, y) + Vector2(0.5, 0.5), gap, ragged)
            if alpha <= 0.0:
                continue
            var at := (y * WRITTEN.size.x + x) * 4
            floats[at] = stored.r
            floats[at + 1] = stored.g
            floats[at + 2] = stored.b
            floats[at + 3] = alpha
    var file := FileAccess.open(_folder.path_join("ring.npy"), FileAccess.WRITE)
    file.store_buffer(PixelDriver.Npy.header(WRITTEN.size))
    file.store_buffer(floats.to_byte_array())
    file.close()
    var rect := [WRITTEN.position.x, WRITTEN.position.y, WRITTEN.size.x, WRITTEN.size.y]
    var answer := PixelDriver.write_from(_doc, {"new_layer": name, "rect": rect, "file": "ring.npy"}, _folder)
    assert_false(answer.has("error"), "The harness wrote the ring: %s" % answer)
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    return _doc.active_layer


func _fill(gap: int) -> Object:
    var fill := StateBucketFillScript.new()
    fill.surface = _surface
    fill.gap_close = gap
    SaColors.foreground = BLUE
    return fill


func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var grid := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var chunk: SaChunk = layer.chunks.get(grid, null)
    if chunk == null:
        return Color(0, 0, 0, 0)
    var texture: SaTexture = chunk.field(chunk.fields.keys()[0])
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := at - grid * SaChunk.SIZE
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x)


func _is_blue(layer: SaLayer, at: Vector2i) -> bool:
    var stored := _doc.color_space.from_display(BLUE)
    var texel := _texel(layer, at)
    var off := maxf(absf(texel.r - stored.r), maxf(absf(texel.g - stored.g), absf(texel.b - stored.b)))
    return texel.a > 0.9 and off < 0.01


## Texels of the four chunks the ring sits in where *a* and *b* differ.
func _differing(a: SaLayer, b: SaLayer) -> int:
    var rd := GlobalShaderCompiler.get_rd()
    var count := 0
    for grid_y in 2:
        for grid_x in 2:
            var grid := Vector2i(grid_x, grid_y)
            var mine: SaTexture = (a.chunks[grid] as SaChunk).field((a.chunks[grid] as SaChunk).fields.keys()[0])
            var theirs: SaTexture = (b.chunks[grid] as SaChunk).field((b.chunks[grid] as SaChunk).fields.keys()[0])
            var left := rd.texture_get_data(mine.rid, 0)
            var right := rd.texture_get_data(theirs.rid, 0)
            for texel in mine.size.x * mine.size.y:
                var one := SaFieldSpec.decode_texel(left, mine.format, texel)
                var other := SaFieldSpec.decode_texel(right, theirs.format, texel)
                if absf(one.a - other.a) > 0.0001 or absf(one.b - other.b) > 0.0001:
                    count += 1
    return count


## Texels inside the ring's inner edge, clear of the fill's own one texel
## feather along it, that *layer* holds no blue at, the four chunks read once.
func _unfilled_inside(layer: SaLayer) -> int:
    var rd := GlobalShaderCompiler.get_rd()
    var stored := _doc.color_space.from_display(BLUE)
    var count := 0
    for grid_y in 2:
        for grid_x in 2:
            var grid := Vector2i(grid_x, grid_y)
            var chunk := layer.chunks[grid] as SaChunk
            var texture: SaTexture = chunk.field(chunk.fields.keys()[0])
            var bytes := rd.texture_get_data(texture.rid, 0)
            for y in texture.size.y:
                for x in texture.size.x:
                    var at := grid * SaChunk.SIZE + Vector2i(x, y)
                    if (Vector2(at) + Vector2(0.5, 0.5)).distance_to(CENTRE) >= INNER - 2.5:
                        continue
                    var texel := SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)
                    if texel.a < 0.9 or absf(texel.b - stored.b) > 0.01:
                        count += 1
    return count


## The setting left at nothing: the fill pours out of the ring and over the
## whole layer.
func test_a_ring_with_a_20_px_gap_leaks_with_gaps_left_open() -> void:
    var layer := _ring(NARROW_GAP)
    _fill(0).fill_at(MIDDLE)
    assert_true(_is_blue(layer, MIDDLE), "The middle is filled")
    assert_true(_is_blue(layer, PAST_THE_GAP), "and the fill went out through the gap")
    assert_true(_is_blue(layer, FAR_GROUND), "and over the ground in a chunk the layer never held")


## At Close gaps 24 the same ring fills inside alone, right up to its line,
## and the layer gains no chunk.
func test_at_24_a_ring_with_a_20_px_gap_fills_only_inside() -> void:
    var layer := _ring(NARROW_GAP)
    var chunks := layer.chunks.size()
    var touched: int = _fill(SETTING).fill_at(MIDDLE)

    assert_true(touched > 0, "The click painted, %d chunk(s)" % touched)
    assert_true(_is_blue(layer, MIDDLE), "The middle is filled")
    assert_true(_is_blue(layer, BY_THE_WALL), "and so are the texels by the inner wall, which close took away")
    assert_true(_texel(layer, AGAINST_THE_WALL).a > 0.5, "up to the one against it, under the feather")
    assert_true(_is_blue(layer, IN_THE_MOUTH), "and the inside of the gap's mouth")
    assert_almost_eq(_texel(layer, PAST_THE_GAP).a, 0.0, 0.001, "Past the gap the ground is still empty")
    assert_almost_eq(_texel(layer, BESIDE_THE_RING).a, 0.0, 0.001, "and beside the ring outside")
    assert_almost_eq(_texel(layer, FAR_GROUND).a, 0.0, 0.001, "and far from it")
    assert_eq(layer.chunks.size(), chunks, "The fill made no chunk outside the ring")


## At 24 the gap is shared out down its middle: the fill reaches into it on the
## inside half and stops there, and leaves no dent round the gap's mouth where
## the ground outside comes nearer than the far wall.
func test_at_24_the_fill_meets_the_ground_in_the_middle_of_the_gap() -> void:
    var layer := _ring(NARROW_GAP)
    _fill(SETTING).fill_at(MIDDLE)
    assert_true(_is_blue(layer, IN_THE_GAP), "The fill reaches into the gap")
    assert_almost_eq(_texel(layer, OUT_IN_THE_GAP).a, 0.0, 0.001, "and stops before its outer half")
    assert_eq(_unfilled_inside(layer), 0, "and every texel inside the ring is filled, round the gap's mouth too")


## A gap wider than the setting is not one it closes, and the tooltip says the
## setting is the widest gap closed.
func test_at_24_a_ring_with_a_30_px_gap_still_leaks() -> void:
    var layer := _ring(WIDE_GAP)
    _fill(SETTING).fill_at(MIDDLE)
    assert_true(_is_blue(layer, MIDDLE), "The middle is filled")
    assert_true(_is_blue(layer, PAST_THE_GAP), "and the fill went out through the wider gap")
    assert_true(_is_blue(layer, FAR_GROUND), "and over the layer")


## A closed ring fills the same texels, to the same coverage, at 0 and at 24.
## Two layers hold the same ring, each filled at one setting.
func test_a_closed_ring_fills_exactly_as_before_at_0_and_at_24() -> void:
    var open_layer := _ring(0.0, "Ring at 0")
    _fill(0).fill_at(MIDDLE)
    var closed_layer := _ring(0.0, "Ring at 24")
    _fill(SETTING).fill_at(MIDDLE)

    assert_true(_is_blue(open_layer, MIDDLE), "The ring filled at 0")
    assert_true(_is_blue(closed_layer, MIDDLE), "and at 24")
    assert_almost_eq(_texel(closed_layer, BESIDE_THE_RING).a, 0.0, 0.001, "and neither reached outside")
    assert_eq(_differing(open_layer, closed_layer), 0, "Every texel of the two fills is the same")


## The same on a ragged ring, whose inner edge dents in and out by about a
## texel every three, the way a stroke's dabs leave it. No disc of the
## setting's half fits into those dents, and `grow` is what fills them: before
## it, 1500 texels of this ring's fill differed, and in the running app the
## Inked Pen's own ring did too.
func test_a_ragged_closed_ring_fills_exactly_as_before_at_0_and_at_24() -> void:
    var open_layer := _ring(0.0, "Ragged ring at 0", RAGGED)
    _fill(0).fill_at(MIDDLE)
    var closed_layer := _ring(0.0, "Ragged ring at 24", RAGGED)
    _fill(SETTING).fill_at(MIDDLE)

    assert_true(_is_blue(closed_layer, MIDDLE), "The ragged ring filled at 24")
    assert_eq(_differing(open_layer, closed_layer), 0, "Every texel of the two fills is the same, dents and all")


## A click nearer the line than half the setting still fills the inside. The
## disc of the setting's half round the seed stays open, so the flood leaves
## it for the texels far from every line rather than stopping at the click.
func test_a_click_beside_the_line_fills_the_whole_inside() -> void:
    var layer := _ring(NARROW_GAP)
    _fill(SETTING).fill_at(NEAR_THE_LINE)
    assert_true(_is_blue(layer, MIDDLE), "The middle is filled from a click by the line")
    assert_true(_is_blue(layer, Vector2i(167, 256)), "and the far side of the inside, by the other wall")
    assert_almost_eq(_texel(layer, PAST_THE_GAP).a, 0.0, 0.001, "and the gap is still shut")
    assert_almost_eq(_texel(layer, BESIDE_THE_RING).a, 0.0, 0.001, "and the line was not crossed by the click")


## The row: its key, its range in steps of two, off by default, and a tooltip
## that says the number is the widest gap closed.
func test_tool_options_offer_close_gaps_and_say_what_the_number_is() -> void:
    var row: SaOptionSpec = null
    for spec: SaOptionSpec in BaseModuleScript.fill_options():
        if spec.key == &"fill_gap_close":
            row = spec
    assert_not_null(row, "The fill has a fill_gap_close row")
    if row == null:
        return
    assert_eq(row.label, "Close gaps", "named Close gaps")
    assert_eq(row.min_value, 0.0, "from 0")
    assert_eq(row.max_value, float(SaWandScript.MAX_GAP), "to the widest the kernel reaches")
    assert_eq(row.max_value, 40.0, "which is 40 pixels")
    assert_eq(row.step, 2.0, "in steps of two")
    assert_eq(row.property, ^"gap_close", "written to the tool's gap_close")
    assert_true(row.tooltip.contains("widest gap"), "The tooltip says the setting is the widest gap closed")
    var fill := StateBucketFillScript.new()
    assert_eq(fill.gap_close, 0, "and a fresh fill closes nothing")
