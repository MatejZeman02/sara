## The lake's mirrors draw the same across a chunk join as
## inside a chunk.
##
## The painting's lake is a chain of effects. Effects reading the paint sit
## in a hidden group, Mirror effects read that group from a second hidden group,
## and a ripple reads the mirrors through a Motion Blur that reaches past the
## edge of the chunk it draws. After a load the budget composites a chunk or
## two a frame, row by row from the left, so the lake's chunk left of a join is
## walked before the ripple's cache right of it holds anything. Unless
## that later write is handed back to the strip left of the join, the lake
## is exported stepped by tens of levels at the joins. This suite builds the same chain, paints a mark
## whose reflection crosses the join at x 512, composites the painting from
## empty caches a chunk a frame, and holds the lake there to the same mark
## painted inside one chunk, which no join touches, within a level.
##
## The painting: four chunks a side, the background hidden, a layer named Land
## holding the mark in the second chunk row, an effect named Source reading it
## inside the hidden group Sources, a Mirror effect reading Sources about the
## canvas's middle inside the hidden group Mirrors, which lands the reflection
## in the third row, and an effect named Ripple reading Mirrors through a level
## Motion Blur of 14.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")
const MotionBlurFilter = preload("res://modules/sara-base-modules/base/usual/motion_blur.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const MIRROR: StringName = &"sara-base-modules.mirror"
const SIZE := Vector2i(1024, 1024)
## The land's colour.
const COLOUR := Color(0.9, 0.3, 0.1, 1.0)
## The mark across the join at x 512, rows 300 to 339, reflected about y 512 to
## rows 684 to 723, the third row.
const ACROSS := Rect2i(440, 300, 140, 40)
## The same mark inside the first chunk, its blur's reach and all.
const INSIDE := Rect2i(60, 300, 140, 40)
## How far the blur reaches either side of the mark, read with it.
const MARGIN := 16
## One level of an eight-bit export.
const LEVEL := 1.0 / 255.0

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## An easel holding the painting with *mark* on the land.
func _painting(mark: Rect2i) -> SaEasel:
    var easel := Bench.easel(SIZE)
    var registry := easel.compositor.filter_chain.registry
    registry.register(MirrorFilter.new(), OWNER)
    var blur := MotionBlurFilter.new()
    registry.register(blur, OWNER)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var land := doc.get_node("Layer 1") as SaLayer
    land.name = "Land"
    _paint(land, mark, COLOUR)
    doc.set_active_layer(land)
    var ops := SaLayerOps.new(doc)
    var source := ops.add(SaEffectLayer.TYPE_ID, _types)
    source.name = "Source"
    if source.source != land:
        SaEffectLayer.read(doc, source, land)
    var sources := ops.group_layers([source])
    sources.name = "Sources"
    sources.visible = false
    doc.set_active_layer(sources)
    var mirror := ops.add(SaEffectLayer.TYPE_ID, _types)
    mirror.name = "Mirror"
    assert_not_null(SaFilterOps.new(doc).attach(mirror, MIRROR), "The Mirror attaches to the effect layer")
    if mirror.source != sources:
        SaEffectLayer.read(doc, mirror, sources)
    var mirrors := ops.group_layers([mirror])
    mirrors.name = "Mirrors"
    mirrors.visible = false
    doc.set_active_layer(mirrors)
    var ripple := ops.add(SaEffectLayer.TYPE_ID, _types)
    ripple.name = "Ripple"
    var key := SaFilterRegistry.key_for(OWNER, blur)
    assert_not_null(SaFilterOps.new(doc).attach(ripple, key, {"angle": 0, "length": 14}), "The blur attaches to the ripple")
    if ripple.source != mirrors:
        SaEffectLayer.read(doc, ripple, mirrors)
    assert_eq(SaEffectLayer.input_of(source), land, "The source reads the land")
    assert_eq(SaEffectLayer.input_of(mirror), sources, "The Mirror reads the hidden group of sources")
    assert_eq(SaEffectLayer.input_of(ripple), mirrors, "The ripple reads the hidden group of mirrors")
    doc.set_active_layer(land)
    _loaded(easel)
    return easel


## Paints *mark* on *land* in *colour*, and answers the chunks it touched.
static func _paint(land: SaLayer, mark: Rect2i, colour: Color) -> Array[Vector2i]:
    var side := SaChunk.SIZE
    var touched: Array[Vector2i] = []
    for x in ceili(float(SIZE.x) / side):
        var grid_pos := Vector2i(x, 1)
        var part := mark.intersection(Rect2i(grid_pos * side, Vector2i(side, side)))
        if part.has_area():
            _fill(land.get_or_create_chunk(grid_pos).albedo(), Rect2i(part.position - grid_pos * side, part.size), colour)
            touched.append(grid_pos)
    return touched


## Writes *colour* over *local* of *texture*, a chunk's albedo.
static func _fill(texture: SaTexture, local: Rect2i, colour: Color) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var bytes := rd.texture_get_data(texture.rid, 0)
    var texel := SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 16) as int
    var one := SaTexture.new(Vector2i.ONE, texture.format)
    one.clear(colour)
    var paint := rd.texture_get_data(one.rid, 0)
    for y in range(local.position.y, local.end.y):
        for x in range(local.position.x, local.end.x):
            var at := (y * texture.size.x + x) * texel
            for i in texel:
                bytes[at + i] = paint[i]
    rd.texture_update(texture.rid, 0, bytes)


## Composites the whole painting from empty caches a chunk a frame, as the
## budget pays the first composite after a load. The mirrors' refresh is paced
## in the same frames and walks only in the room the budget leaves, which a
## frame of one chunk leaves none of, so the painting takes some 190 frames.
static func _loaded(easel: SaEasel) -> void:
    var every: Array[Vector2i] = []
    for y in ceili(float(SIZE.y) / SaChunk.SIZE):
        for x in ceili(float(SIZE.x) / SaChunk.SIZE):
            every.append(Vector2i(x, y))
    easel.document.invalidate_chunks(every)
    easel.request_composite()
    for frame in 512:
        easel.budget.usec_per_unit = SaCompositeBudget.FRAME_USEC
        easel.process_pending_composite(true)
        if not easel.backlog.reaches(Rect2(Vector2.ZERO, Vector2(SIZE))):
            break


## The output's texels over the reflection of *mark*, grown by the blur's
## reach either side, each row's values in order.
static func _lake(easel: SaEasel, mark: Rect2i) -> Array[Color]:
    var output := easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(output.rid, 0)
    var found: Array[Color] = []
    for y in range(SIZE.y - mark.end.y, SIZE.y - mark.position.y):
        for x in range(mark.position.x - MARGIN, mark.end.x + MARGIN):
            found.append(SaFieldSpec.decode_texel(bytes, output.format, y * output.size.x + x))
    return found


## *mark*'s lake on a fresh painting, the painting freed after.
func _lake_of(mark: Rect2i) -> Array[Color]:
    var easel := _painting(mark)
    var found := _lake(easel, mark)
    easel.free()
    return found


## The largest gap over the four channels between *a* and *b*.
static func _gap(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


func test_the_lake_across_a_join_matches_the_same_mark_inside_a_chunk() -> void:
    var inside := _lake_of(INSIDE)
    var across := _lake_of(ACROSS)
    assert_eq(across.size(), inside.size(), "Both readings cover the same texels")
    var worst := 0.0
    var at := -1
    for i in inside.size():
        var gap := _gap(across[i], inside[i])
        if gap > worst:
            worst = gap
            at = i
    var width := ACROSS.size.x + 2 * MARGIN
    var where := "nowhere"
    if at >= 0:
        where = "x %d, y %d" % [ACROSS.position.x - MARGIN + at % width, SIZE.y - ACROSS.end.y + floori(float(at) / width)]
    var said := "The lake across the join at x 512 is within a level of the mark inside a chunk, %.1f levels off at %s"
    assert_true(worst <= LEVEL, said % [worst * 255.0, where])


func test_the_reflection_is_drawn() -> void:
    var lake := _lake_of(ACROSS)
    var row := floori(ACROSS.size.y / 2.0) * (ACROSS.size.x + 2 * MARGIN)
    var middle := lake[row + MARGIN + floori(ACROSS.size.x / 2.0)]
    assert_true(middle.a > 0.5, "The reflection shows in the lake, alpha %.2f" % middle.a)
