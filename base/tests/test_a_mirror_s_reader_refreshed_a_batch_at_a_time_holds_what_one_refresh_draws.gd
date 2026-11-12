## An export of an untouched file gives the same pixels
## however soon after the load it runs, and twice in a row.
##
## The lake of the seasons file is a ripple reading a Mirror's composite, and
## the Mirror's record reads the land in one chunk row for the lake in the
## next. After a load the budget refreshes the effect caches a batch of chunks
## a frame, and a ripple refreshed in the lake's batch read the Mirror's land
## before the land's batch had drawn it. This suite refreshes the two rows in
## that order, the lake first, and holds the ripple to what one refresh of both
## draws.
##
## The painting: four chunks a side, the background hidden, a layer named Land
## holding a red mark in the second chunk row, a Mirror effect reading it about
## the canvas's middle, which lands the reflection in the third row, and an
## effect named Ripple reading the Mirror through the fixture invert.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const MIRROR: StringName = &"sara-base-modules.mirror"
const SIZE := Vector2i(1024, 1024)
const RED := Color(1.0, 0.0, 0.0, 1.0)
## Rows 300 to 339, reflected about y 512 to rows 684 to 723, the third row.
const MARK := Rect2i(200, 300, 112, 40)
const LAND_ROW := 1
const LAKE_ROW := 2

var _types: SaLayerTypeRegistry
var _easel: SaEasel = null


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## An easel is a Node that no tree owns here, so the suite frees it.
func after_each() -> void:
    if _easel != null:
        _easel.free()
        _easel = null


func _painting() -> Dictionary:
    var easel := Bench.easel(SIZE)
    _easel = easel
    easel.compositor.filter_chain.registry.register(MirrorFilter.new(), OWNER)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var land := doc.get_node("Layer 1") as SaLayer
    land.name = "Land"
    for grid_pos: Vector2i in [Vector2i(0, LAND_ROW), Vector2i(1, LAND_ROW)]:
        var side := SaChunk.SIZE
        var part := MARK.intersection(Rect2i(grid_pos * side, Vector2i(side, side)))
        _fill(land.get_or_create_chunk(grid_pos).albedo(), Rect2i(part.position - grid_pos * side, part.size))
    doc.set_active_layer(land)
    var mirror := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
    mirror.name = "Mirror"
    assert_not_null(SaFilterOps.new(doc).attach(mirror, MIRROR), "The Mirror attaches to the effect layer")
    if mirror.source != land:
        SaEffectLayer.read(doc, mirror, land)
    doc.set_active_layer(mirror)
    var ripple := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
    ripple.name = "Ripple"
    assert_not_null(SaFilterOps.new(doc).attach(ripple, Bench.INVERT), "The invert attaches to the ripple")
    if ripple.source != mirror:
        SaEffectLayer.read(doc, ripple, mirror)
    assert_eq(SaEffectLayer.input_of(ripple), mirror, "The ripple reads the Mirror")
    doc.set_active_layer(land)
    Bench.composite(easel)
    return {"easel": easel, "mirror": mirror, "ripple": ripple}


## Writes red over *local* of *texture*, a chunk's albedo.
static func _fill(texture: SaTexture, local: Rect2i) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var bytes := rd.texture_get_data(texture.rid, 0)
    var texel := SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 16) as int
    var one := SaTexture.new(Vector2i.ONE, texture.format)
    one.clear(RED)
    var paint := rd.texture_get_data(one.rid, 0)
    for y in range(local.position.y, local.end.y):
        for x in range(local.position.x, local.end.x):
            var at := (y * texture.size.x + x) * texel
            for i in texel:
                bytes[at + i] = paint[i]
    rd.texture_update(texture.rid, 0, bytes)


## Drops every chunk of the caches, as a load leaves them.
static func _emptied(made: Dictionary) -> void:
    for key: String in ["mirror", "ripple"]:
        var effect := made[key] as SaLayer
        for grid_pos: Vector2i in effect.chunks.keys():
            effect.set_chunk(grid_pos, null)


## The whole of every chunk in *rows*.
static func _rows(rows: Array[int]) -> Dictionary[Vector2i, Rect2i]:
    var found: Dictionary[Vector2i, Rect2i] = {}
    for row in rows:
        for x in ceili(float(SIZE.x) / SaChunk.SIZE):
            found[Vector2i(x, row)] = SaDocument.WHOLE_CHUNK
    return found


static func _refresh(made: Dictionary, regions: Dictionary[Vector2i, Rect2i]) -> void:
    var easel := made["easel"] as SaEasel
    easel.compositor.effect.refresh(easel.compositor, easel.document, regions)


## The ripple's cache in the lake, a chunk's bytes keyed by its position, and
## a chunk it does not hold as the transparent bytes it composites as.
static func _lake(made: Dictionary) -> Dictionary:
    var ripple := made["ripple"] as SaLayer
    var found := {}
    var format := (made["easel"] as SaEasel).document.color_space.texel_format()
    for x in ceili(float(SIZE.x) / SaChunk.SIZE):
        var grid_pos := Vector2i(x, LAKE_ROW)
        var texture: SaTexture = ripple.chunks[grid_pos].albedo() if ripple.chunks.has(grid_pos) else null
        if texture == null:
            texture = SaTexture.new(Vector2i(SaChunk.SIZE, SaChunk.SIZE), format)
            texture.clear(Color(0.0, 0.0, 0.0, 0.0))
        found[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return found


## Whether *bytes* hold anything but transparent.
static func _holds(bytes: PackedByteArray) -> bool:
    for value in bytes:
        if value != 0:
            return true
    return false


func test_the_lake_refreshed_before_the_land_holds_what_one_refresh_draws() -> void:
    var made := _painting()
    _emptied(made)
    _refresh(made, _rows([LAND_ROW, LAKE_ROW]))
    var once := _lake(made)
    var drawn := _holds(once[Vector2i(0, LAKE_ROW)]) and _holds(once[Vector2i(1, LAKE_ROW)])
    assert_true(drawn, "One refresh of both rows draws the reflection into the ripple's lake")
    _emptied(made)
    _refresh(made, _rows([LAKE_ROW]))
    _refresh(made, _rows([LAND_ROW]))
    var batched := _lake(made)
    for grid_pos: Vector2i in once:
        assert_true(batched[grid_pos] == once[grid_pos], "The ripple's lake chunk %s matches one refresh's" % grid_pos)


func test_the_land_s_batch_marks_the_lake_for_the_walk() -> void:
    var made := _painting()
    _emptied(made)
    _refresh(made, _rows([LAKE_ROW]))
    var land := _rows([LAND_ROW])
    _refresh(made, land)
    for x in ceili(float(SIZE.x) / SaChunk.SIZE):
        if x < 2:
            assert_true(land.has(Vector2i(x, LAKE_ROW)), "The land's batch hands the walk the lake chunk at x %d" % x)
