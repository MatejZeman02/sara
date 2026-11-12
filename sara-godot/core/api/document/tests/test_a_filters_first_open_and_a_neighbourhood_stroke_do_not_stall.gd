## A filter's first open and a neighbourhood pass cost less than they did, and what they answer is what it was.
##
## Two costs went. The dialect translated a shader's text again for every storage
## format it was built at, 6 ms to 8 ms for a filter's own file and more for each
## library it imports, so a filter's first use on an F16 document paid for a
## translation boot had already done at F32. And the neighbourhood runner built
## each chunk's padding out of a clear and up to nine copies, about thirty
## microseconds of CPU a dispatch, which were most of an Apply. The first suite
## pins the translation to once a text, the second pins the padding the one
## dispatch writes to the texels the clear and the copies wrote, and counts it.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const MODULE_DIR := "res://modules/sara-base-modules/base"
const KEY: StringName = &"sara-base-modules.box_blur"
const RADIUS := 4
const F16: int = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
const PAD_SHADER := "res://shaders/compute/pad_chunk.gmacs"
## The chunk the padding is built for, in the middle of a three by three grid.
const MIDDLE := Vector2i(1, 1)
## The one neighbour never painted, which has to read as transparent.
const MISSING := Vector2i(2, 2)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _record: SaAttachedFilter = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(3 * SaChunk.SIZE, 3 * SaChunk.SIZE))
    _doc = _easel.document
    ModuleLoader.module_dirs[&"sara-base-modules"] = MODULE_DIR
    _easel.compositor.filter_chain.registry.register(BoxBlurFilter.new(), &"sara-base-modules")
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    for y in range(3):
        for x in range(3):
            if Vector2i(x, y) != MISSING:
                _layer.get_or_create_chunk(Vector2i(x, y)).clear(_colour_of(Vector2i(x, y)))
    _record = SaFilterOps.new(_doc).attach(_layer, KEY, {"radius": RADIUS})
    Bench.composite(_easel)


func after_each() -> void:
    _record = null
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## A colour of the chunk at *grid_pos* no other chunk has.
func _colour_of(grid_pos: Vector2i) -> Color:
    return Color(0.2 + 0.3 * grid_pos.x, 0.2 + 0.3 * grid_pos.y, 0.5, 1.0)


## What the padding of the chunk at [const MIDDLE] over *work* should hold at
## the chunk pixel *at*, the texel the clear and the copies left there.
func _expected(at: Vector2i, work: Rect2i) -> Color:
    var cell := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    if cell == Vector2i.ZERO:
        return _colour_of(MIDDLE) if work.has_point(at) else CLEAR
    if MIDDLE + cell == MISSING:
        return CLEAR
    return _colour_of(MIDDLE + cell)


## The texels the runner's padding holds after a run over *work*, read at every
## point of *probes*, in chunk pixels, and what each should be.
func _padding_after(work: Rect2i, probes: Array[Vector2i]) -> Array:
    var recorded := _record.cached_pass as SaNeighbourhoodPass
    var runner := SaNeighbourhoodPass.Runner.new()
    var compute := SaCompute.new(recorded.shader)
    var centre := _layer.get_field(MIDDLE)
    var target := SaTexture.new(centre.size, centre.format)
    var mask := _doc.selection.everything()
    SaCompute.reset_counters()
    runner.run(recorded, compute, target, centre, _layer.get_field, MIDDLE, work, mask)
    var pads := int(SaCompute.kernel_counters().get("pad_chunk/pad_chunk", {}).get("dispatches", 0))
    var copies := int(SaCompute.kernel_counters().get("copy_region/copy_region", {}).get("dispatches", 0))
    var padded: SaTexture = runner._padding.texture
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(padded.rid, 0)
    var found: Array = []
    for at: Vector2i in probes:
        var texel := at + Vector2i(RADIUS, RADIUS)
        var index := texel.y * padded.size.x + texel.x
        found.append([at, SaFieldSpec.decode_texel(bytes, padded.format, index), _expected(at, work)])
    padded = null
    target = null
    return [pads, copies, found]


## The pixels either side of every edge of *work* and the halo's corners past
## them, and for a whole chunk a pixel of each cell across its sides as well.
func _probes(work: Rect2i) -> Array[Vector2i]:
    var half := SaChunk.SIZE >> 1
    var out: Array[Vector2i] = []
    for y: int in [work.position.y - RADIUS, work.position.y, work.end.y - 1, work.end.y + RADIUS - 1]:
        for x: int in [work.position.x - RADIUS, work.position.x, work.end.x - 1, work.end.x + RADIUS - 1]:
            out.append(Vector2i(x, y))
    if work.size != Vector2i(SaChunk.SIZE, SaChunk.SIZE):
        return out
    out.append(Vector2i(half, -1))
    out.append(Vector2i(-1, half))
    out.append(Vector2i(SaChunk.SIZE, SaChunk.SIZE))
    return out


func _assert_padding(work: Rect2i, what: String) -> void:
    var answer := _padding_after(work, _probes(work))
    assert_eq(answer[0], 1, "%s: the padding is one dispatch" % what)
    assert_eq(answer[1], 0, "%s: and no copy" % what)
    for probe: Array in answer[2]:
        var got: Color = probe[1]
        var want: Color = probe[2]
        var said := "%s: at %s the padding reads %s, the copies wrote %s" % [what, probe[0], got, want]
        assert_true(got.is_equal_approx(want), said)


func test_a_whole_chunk_is_padded_by_its_eight_neighbours_in_one_dispatch() -> void:
    _assert_padding(Rect2i(Vector2i.ZERO, Vector2i(SaChunk.SIZE, SaChunk.SIZE)), "A whole chunk")


func test_a_part_of_a_chunk_reads_transparent_where_the_chunk_lies_outside_it() -> void:
    _assert_padding(Rect2i(Vector2i(40, 60), Vector2i(100, 80)), "A part in the middle")
    _assert_padding(Rect2i(Vector2i(0, SaChunk.SIZE - 30), Vector2i(50, 30)), "A part along the bottom left")


func test_a_text_is_translated_once_however_often_it_is_read() -> void:
    var source := GlobalShaderCompiler.source
    var text := "# a test's own text\nkernel q22_probe\nimage target\n\ndef q22_probe():\n    return\n"
    var first := source.glsl_of(text)
    assert_true(source._glsl_by_text.has(text), "The first read keeps the translation")
    assert_eq(source.glsl_of(text), first, "and the second answers it unchanged")
    assert_false(first.contains("def "), "The answer is GLSL and not the dialect")


func test_a_second_format_translates_nothing() -> void:
    var source := GlobalShaderCompiler.source
    GlobalShaderCompiler.compile_compute_shader(PAD_SHADER, GlobalShaderCompiler.DEFAULT_STORAGE_FORMAT)
    var kept := source._glsl_by_text.size()
    GlobalShaderCompiler.compile_compute_shader(PAD_SHADER, F16)
    assert_eq(source._glsl_by_text.size(), kept, "Building the pad at F16 after F32 read no text it had not translated")
