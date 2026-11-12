## A crop, a turn, a resample and a projection conversion
## work out a shared source's chunks once. The users of one `SaSharedSource`
## hold one chunk dictionary, so a step that made a new set for each user made
## the same set again for every user after the first and kept the last.
##
## Each step runs on two documents painted alike, one whose smart layer has two
## copies made by Share Source with a Copy and one whose smart layer is alone.
## The step's `chunks_made` counter is the same in both, every user reads one
## dictionary holding the single user's pixels byte for byte, and one undo
## gives every user its old chunks, still shared. The canvas is 600 by 300,
## which no chunk edge divides, so every step moves texels between chunks.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const SIZE := Vector2i(600, 300)
const PAINTED := Rect2i(120, 40, 300, 220)
const COLOUR := Color(0.9, 0.3, 0.1, 1.0)
const CROP := Rect2i(40, 30, 400, 200)
const RESAMPLED := Vector2i(450, 225)

var _easels: Array[SaEasel] = []
var _docs: Array[SaDocument] = []
var _registries: SaRegistries = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    SaProblems.pending_refusals = PackedStringArray()


func after_each() -> void:
    for easel: SaEasel in _easels:
        easel.free()
    _easels.clear()
    _docs.clear()


## The users of one source on a fresh painted document, *users* of them, the
## smart layer first. Their document is `_docs`' last.
func _open(users: int) -> Array[SaLayer]:
    var easel := SaEasel.create_default(SIZE)
    _easels.append(easel)
    var doc := easel.document
    _docs.append(doc)
    var paint := SaLayerOps.new(doc).add()
    _paint(paint)
    assert_true(SaLiveTransform.make_smart(doc, paint), "Make Smart Layer runs")
    var out: Array[SaLayer] = [paint]
    while out.size() < users:
        var copy := SaSharedSource.link(doc, paint)
        assert_not_null(copy, "Share Source with a Copy makes a copy")
        out.append(copy)
    for user: SaLayer in out:
        assert_true(is_same(user.chunks, paint.chunks), "Every user holds the one dictionary")
    return out


static func _paint(layer: SaLayer) -> void:
    var side := SaLayer.CHUNK_SIZE
    for grid_pos: Vector2i in SaLayer.grid_positions(PAINTED.end):
        var tile := Rect2i(grid_pos * side, Vector2i(side, side))
        var part := tile.intersection(PAINTED)
        if not part.has_area():
            continue
        var texture := layer.get_or_create_chunk(grid_pos).albedo()
        var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF)
        image.fill_rect(Rect2i(part.position - tile.position, part.size), COLOUR)
        if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
            image.convert(Image.FORMAT_RGBAH)
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)


## Every chunk's albedo bytes by grid position.
static func _bytes(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        if chunk != null:
            out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(chunk.albedo().rid, 0)
    return out


## Runs *step* on a shared document and a single one and checks the three
## clauses. *step* takes a document and answers the counter it read.
func _check(label: String, step: Callable) -> void:
    var shared := _open(3)
    var doc := _docs[-1]
    var alone := _open(1)
    var old: Dictionary = shared[0].chunks.duplicate()

    var made_shared: int = step.call(doc)
    var made_alone: int = step.call(_docs[-1])
    assert_true(made_alone > 0, "%s: the single user's step makes chunks" % label)
    assert_eq(made_shared, made_alone, "%s: three users make as many chunks as one" % label)

    var wanted := _bytes(alone[0])
    for user: SaLayer in shared:
        assert_true(is_same(user.chunks, shared[0].chunks), "%s: %s holds the one dictionary" % [label, user.name])
        assert_eq(_bytes(user), wanted, "%s: %s holds the single user's pixels" % [label, user.name])

    assert_true(doc.undo(), "%s: one undo" % label)
    for user: SaLayer in shared:
        assert_true(is_same(user.chunks, shared[0].chunks), "%s: %s shares again after the undo" % [label, user.name])
        assert_eq(user.chunks.size(), old.size(), "%s: %s has its old chunk count" % [label, user.name])
        for grid_pos: Vector2i in old:
            assert_true(
                is_same(user.chunks.get(grid_pos), old[grid_pos]), "%s: %s has its old chunk %s" % [label, user.name, grid_pos]
            )


func test_a_crop_works_out_the_shared_source_once() -> void:
    _check(
        "Crop",
        func(doc: SaDocument) -> int:
            var crop := SaCrop.new(doc)
            assert_true(crop.crop_to(CROP), "The crop runs")
            return crop.chunks_made
    )


func test_a_quarter_turn_works_out_the_shared_source_once() -> void:
    _check(
        "Turn",
        func(doc: SaDocument) -> int:
            var orient := SaOrient.new(doc)
            assert_true(orient.rotate_image(1), "The turn runs")
            return orient._walk.chunks_made
    )


func test_a_resample_works_out_the_shared_source_once() -> void:
    _check(
        "Resample",
        func(doc: SaDocument) -> int:
            var resample := SaResample.new(doc)
            assert_true(resample.resample_to(RESAMPLED), "The resample runs")
            return resample.chunks_made
    )


func test_a_projection_conversion_works_out_the_shared_source_once() -> void:
    var polar := SaProjection.new(_registries.projections.find(SaProjection.POLAR))
    _check(
        "Projection",
        func(doc: SaDocument) -> int:
            var conversion := SaProjectionConversion.new(doc, polar)
            assert_true(conversion.run(), "The conversion runs")
            return conversion.chunks_made
    )
