## Ungrouping a filtered or masked group writes what the group did into every
## texel of a member at twice the document's resolution.
##
## `SaTreeRender.bake` copied the compositor's answer, which comes down to the
## document's resolution, into a copy of the member's 512 texel chunk, so the
## group's filter landed in one quarter of it and the other three kept the
## texels as they were. The member holds a one texel checker of two colours,
## so an answer that came down and went back up would read their mean rather
## than either, and each case reads every texel of the chunk.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const ONE := Color(0.25, 0.5, 0.75, 1.0)
const TWO := Color(0.75, 0.25, 0.125, 1.0)
const AT := Vector2i(0, 0)
const BESIDE := Vector2i(1, 0)
## The document column the group's mask hides from.
const EDGE := 128
## A point in each quarter of the chunk at the origin, in document pixels.
const QUARTERS: Array[Vector2i] = [Vector2i(64, 64), Vector2i(192, 64), Vector2i(64, 192), Vector2i(192, 192)]

var _easel: SaEasel
var _doc: SaDocument
var _ops: SaLayerOps


func before_each() -> void:
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE))
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)
    # Nothing under the member, so the canvas's alpha is what the group shows.
    for layer in _ops.layers():
        layer.chunks.clear()


func after_each() -> void:
    _ops = null
    _doc = null
    _easel.free()
    _easel = null


static func _checker(x: int, y: int) -> Color:
    return ONE if (x + y) % 2 == 0 else TWO


static func _inverted(x: int, y: int) -> Color:
    var held := _checker(x, y)
    return Color(1.0 - held.r, 1.0 - held.g, 1.0 - held.b, held.a)


## A layer at *scale* holding the checker over the chunk at the origin, made
## the way the Layer menu makes it.
func _checkered(scale: float) -> SaLayer:
    var layer := _ops.add(&"", null, scale)
    var texture := layer.get_or_create_chunk(AT).albedo()
    var wide := texture.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF if wide else Image.FORMAT_RGBAH)
    for y in texture.size.y:
        for x in texture.size.x:
            image.set_pixel(x, y, _checker(x, y))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    _doc.invalidate_chunks([AT])
    return layer


## A group around *member*, isolated by what it carries.
func _group(member: SaLayer) -> SaLayer:
    var group := _ops.group_layers([member])
    assert_not_null(group, "The member is grouped")
    return group


## The group's mask, one left of [constant EDGE] and zero right of it.
func _mask_half(group: SaLayer) -> void:
    assert_true(SaMaskOps.new(_doc).add(group), "The group takes a mask")
    var coverage := group.mask.get_or_create(AT)
    var values := PackedFloat32Array()
    values.resize(coverage.size.x * coverage.size.y)
    for y in coverage.size.y:
        for x in coverage.size.x:
            values[y * coverage.size.x + x] = 1.0 if x < EDGE else 0.0
    GlobalShaderCompiler.get_rd().texture_update(coverage.rid, 0, values.to_byte_array())
    SaLayerStack.invalidate_layer_chunks(_doc, group)


func _output() -> Array[Color]:
    Bench.composite(_easel)
    var found: Array[Color] = []
    for at in QUARTERS:
        found.append(Bench.texel(_easel.output, at))
    return found


func _same(before: Array[Color], after: Array[Color], what: String) -> void:
    for i in before.size():
        var was := before[i]
        var now := after[i]
        var moved := maxf(maxf(absf(was.r - now.r), absf(was.g - now.g)), maxf(absf(was.b - now.b), absf(was.a - now.a)))
        assert_true(moved < 0.01, "%s, at %s: %s became %s" % [what, QUARTERS[i], before[i], after[i]])


## Every texel of *texture* is what *expected* answers for it, or the count of
## those that are not and the first of them is named.
func _every(texture: SaTexture, expected: Callable, what: String) -> void:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var wrong := 0
    var first := ""
    for i in texture.size.x * texture.size.y:
        var x := i % texture.size.x
        @warning_ignore("integer_division")
        var y := i / texture.size.x
        var found := SaFieldSpec.decode_texel(bytes, texture.format, i)
        var want: Color = expected.call(x, y)
        if not found.is_equal_approx(want):
            wrong += 1
            if first.is_empty():
                first = "texel (%d, %d) is %s, not %s" % [x, y, found, want]
    assert_eq(wrong, 0, "%s: %s" % [what, first])


func test_an_ungroup_inverts_every_texel_of_a_double_resolution_member() -> void:
    var member := _checkered(2.0)
    var group := _group(member)
    SaFilterOps.new(_doc).attach(group, Bench.INVERT, {"strength": 1.0})
    var before := _output()

    assert_true(_ops.ungroup(group), "The ungroup runs")
    var chunk: SaChunk = member.chunks[AT]
    assert_eq(chunk.albedo().size, Vector2i(512, 512), "The member's chunk is 512 texels across still")
    _every(chunk.albedo(), _inverted, "Every texel of all four quarters is inverted")
    _same(before, _output(), "No pixel the painter saw moved")

    assert_true(_doc.undo(), "Undo")
    _every((member.chunks[AT] as SaChunk).albedo(), _checker, "gives the member its checker back")
    _same(before, _output(), "with the picture it had")
    assert_true(_doc.redo(), "Redo")
    _every((member.chunks[AT] as SaChunk).albedo(), _inverted, "inverts every texel again")


func test_an_ungroup_hides_every_texel_of_a_double_resolution_member_its_mask_hid() -> void:
    var member := _checkered(2.0)
    var group := _group(member)
    _mask_half(group)
    var before := _output()
    assert_almost_eq(before[1].a, 0.0, 0.001, "The group's mask hides the right half before the ungroup")

    assert_true(_ops.ungroup(group), "The ungroup runs")
    var shown := func(x: int, y: int) -> Color:
        var held := _checker(x, y)
        return held if x < 2 * EDGE else Color(held.r, held.g, held.b, 0.0)
    _every((member.chunks[AT] as SaChunk).albedo(), shown, "Left of the edge shows and right of it is hidden, texel for texel")
    _same(before, _output(), "No pixel the painter saw moved")


func test_an_ungroup_inverts_a_member_at_the_documents_resolution_as_before() -> void:
    var member := _checkered(1.0)
    var group := _group(member)
    SaFilterOps.new(_doc).attach(group, Bench.INVERT, {"strength": 1.0})
    _mask_half(group)
    var before := _output()

    assert_true(_ops.ungroup(group), "The ungroup runs")
    var chunk: SaChunk = member.chunks[AT]
    assert_eq(chunk.albedo().size, Vector2i(256, 256), "The member's chunk is 256 texels across")
    var shown := func(x: int, y: int) -> Color:
        var held := _inverted(x, y)
        return held if x < EDGE else Color(held.r, held.g, held.b, 0.0)
    _every(chunk.albedo(), shown, "Every texel is inverted and the right half hidden")
    _same(before, _output(), "No pixel the painter saw moved")


func test_a_blur_carries_a_double_resolution_member_into_a_chunk_at_its_density() -> void:
    ModuleLoader.module_dirs[&"sara-base-modules"] = "res://modules/sara-base-modules/base"
    _easel.compositor.filter_chain.registry.register(BoxBlurFilter.new(), &"sara-base-modules")
    var member := _checkered(2.0)
    var group := _group(member)
    SaFilterOps.new(_doc).attach(group, &"sara-base-modules.box_blur", {"radius": 8})
    # The active layer below the group, because with the member active the
    # canvas draws no spill into a position the member holds nothing at, which
    # is the compositor's and not the bake's.
    _doc.set_active_layer(_ops.layers()[0])
    Bench.composite(_easel)
    var spilled := Bench.texel(_easel.output, Vector2i(SaChunk.SIZE + 3, 128))
    assert_true(spilled.a > 0.0, "The blur carries the member past its chunk before the ungroup, %s" % spilled)

    assert_true(_ops.ungroup(group), "The ungroup runs")
    assert_true(member.chunks.has(BESIDE), "The member gains the chunk the blur carried paint into")
    var beside: SaChunk = member.chunks[BESIDE]
    assert_eq(beside.pixel_size(), 512, "at the member's density")
    assert_eq(beside.albedo().size, Vector2i(512, 512), "and its texture is as wide")
    # The four texels under the document pixel the canvas read, whose mean is
    # what it draws.
    var carried := 0.0
    for at: Vector2i in [Vector2i(6, 256), Vector2i(7, 256), Vector2i(6, 257), Vector2i(7, 257)]:
        carried += Bench.texel(beside.albedo(), at).a / 4.0
    assert_almost_eq(carried, spilled.a, 0.01, "holding what the canvas showed there")
