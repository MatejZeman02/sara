## An adjustment layer saves as its recipe and a file holding
## one is stamped 7, a flatten draws it into the bottom layer, Merge Down
## writes it into the paint under it alone, and the two things it cannot take
## are refused with their sentences. A flatten over one left at the bottom
## draws into a new paint layer, where it was a third refusal.
##
## The painting is F1's: two chunks across, the grey background hidden, an
## opaque layer over the left chunk and a stroke at half alpha over both, the
## adjustment layer at the top carrying a brightness and contrast record.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const LEFT := Vector2i(0, 0)
const RIGHT := Vector2i(1, 0)
const UNDER := Color(0.125, 0.625, 0.25, 1.0)
const HALF := Color(0.75, 0.25, 0.125, 0.5)
const RECORD := {"brightness": 30.0, "contrast": 25.0}
const TOLERANCE := 1.0e-5

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## The painting of the header, with the stroke active. With *alone* the stroke
## sits by itself in an isolated group carrying the record, which is what a
## merged adjustment makes of it.
func _painting(alone: bool = false) -> SaEasel:
    var easel := Bench.easel(SIZE)
    easel.compositor.filter_chain.registry.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")
    easel.compositor.filter_chain.registry.register(SaGaussianBlurFilter.new(), &"sara-base-modules")
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    (doc.get_node("Background") as SaLayer).visible = false
    var under := doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(under)
    under.get_or_create_chunk(LEFT).clear(UNDER)
    var stroke := ops.add()
    stroke.name = "Stroke"
    for grid_pos: Vector2i in [LEFT, RIGHT]:
        stroke.get_or_create_chunk(grid_pos).clear(HALF)
    if alone:
        var group := ops.group_active()
        ops.set_isolated(group, true)
        _attach(doc, group)
        doc.set_active_layer(stroke)
    return easel


## An adjustment layer above the active one, carrying the record, left active.
func _adjust(easel: SaEasel) -> SaLayer:
    var layer := SaLayerOps.new(easel.document).add(SaBackdropLayer.TYPE_ID, _types)
    layer.name = "Adjust"
    _attach(easel.document, layer)
    return layer


func _attach(doc: SaDocument, node: SaLayer) -> SaAttachedFilter:
    var key := SaFilterRegistry.key_for(&"sara-base-modules", SaBrightnessContrastFilter.new())
    var record := SaFilterOps.new(doc).attach(node, key, RECORD)
    assert_not_null(record, "The brightness and contrast attaches to %s" % node.name)
    return record


func _show(easel: SaEasel) -> void:
    easel.document.invalidate_chunks([LEFT, RIGHT])
    Bench.composite(easel)


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


static func _texel(bytes: PackedByteArray, texture: SaTexture, at: Vector2i) -> Color:
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


static func _apart(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


## *got*, an output read earlier or now, against *want* within the tolerance,
## over every third texel of the canvas.
func _alike(texture: SaTexture, got: PackedByteArray, want: PackedByteArray, what: String) -> void:
    var worst := 0.0
    var worst_at := Vector2i.ZERO
    for y in range(0, SIZE.y, 3):
        for x in range(0, SIZE.x, 3):
            var at := Vector2i(x, y)
            var off := _apart(_texel(got, texture, at), _texel(want, texture, at))
            if off > worst:
                worst = off
                worst_at = at
    assert_true(worst <= TOLERANCE, "%s, worst %s at %s" % [what, worst, worst_at])


## The version the file at *path* is stamped with, the word after its magic.
static func _stamp(path: String) -> int:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return -1
    file.get_buffer(4)
    var version := file.get_32()
    file.close()
    return version


static func _layers(doc: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in doc.get_children():
        if child is SaLayer:
            found.append(child)
    return found


func _refused(said: String, what: String) -> void:
    var lines := "\n".join(SaProblems.pending_refusals)
    assert_true(lines.contains(said), "%s, with its sentence: %s" % [what, lines])
    SaProblems.pending_refusals = PackedStringArray()


func test_it_saves_as_its_recipe_in_a_file_stamped_seven() -> void:
    var easel := _painting()
    var layer := _adjust(easel)
    layer.add_mask(1.0).get_or_create(LEFT).clear(Color(0.0, 0.0, 0.0, 0.0))
    _show(easel)
    assert_eq(SaSadFile.version_for(easel.document), 7, "A document holding an adjustment layer is version 7")
    var path := ProjectSettings.globalize_path(SaDataRoot.path("f2_adjustment_layer.sad"))
    assert_eq(SaExport.save_sad(easel.document, path), OK, "It saves")
    assert_eq(_stamp(path), SaSadFile.SAD_VERSION_PLANES, "and the file is stamped 14 for its planes")
    var loaded := Bench.easel(SIZE)
    loaded.compositor.filter_chain.registry.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")
    assert_eq(SaExport.load_sad(loaded.document, path, loaded.compositor), OK, "It opens")
    DirAccess.remove_absolute(path)
    _types.rebind(_layers(loaded.document))
    var reopened := loaded.document.get_node("Adjust") as SaLayer
    assert_true(reopened != null and reopened.is_adjustment(), "as an adjustment layer")
    assert_eq(reopened.filters.size(), 1, "holding its record")
    assert_true(reopened.mask != null and reopened.mask.is_own(), "and a mask of its own")
    assert_true(reopened.chunks.is_empty(), "and no chunk")
    _show(loaded)
    assert_eq(_bytes(loaded.output), _bytes(easel.output), "The output reads the same")
    easel.free()
    loaded.free()


func test_a_document_without_one_is_stamped_as_before() -> void:
    var easel := _painting()
    var plain := ProjectSettings.globalize_path(SaDataRoot.path("f2_plain.sad"))
    assert_eq(SaExport.save_sad(easel.document, plain), OK, "A plain painting saves")
    assert_eq(
        SaSadFile.version_for(easel.document), SaSadFile.SAD_VERSION_PLAIN, "its features ask 4, and its planes stamp the file 14"
    )
    _attach(easel.document, easel.document.get_node("Stroke") as SaLayer)
    assert_eq(SaExport.save_sad(easel.document, plain), OK, "and with a record on a paint layer")
    assert_eq(
        SaSadFile.version_for(easel.document),
        SaSadFile.SAD_VERSION_MASKED,
        "its features ask 5, and its planes stamp the file 14"
    )
    DirAccess.remove_absolute(plain)
    easel.free()


## What 0.16.3 does with a 7 is what this build does with an 8: the one check
## in `SaSadFile._load_v4` against its own `SAD_VERSION`. The sentence it
## pushes names the version, and the printed `ERROR:` line is expected.
func test_a_file_stamped_past_the_version_is_refused() -> void:
    var path := ProjectSettings.globalize_path(SaDataRoot.path("f2_too_new.sad"))
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(SaSadFile.SAD_MAGIC_V4.to_ascii_buffer())
    file.store_32(SaSadFile.SAD_VERSION + 1)
    file.store_32(0)
    file.store_32(0)
    file.close()
    var easel := Bench.easel(SIZE)
    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    var answer := SaExport.load_sad(easel.document, path)
    OS.remove_logger(errors)
    assert_eq(answer, ERR_FILE_UNRECOGNIZED, "A file past this build's version is refused")
    var said := PackedStringArray()
    for line in errors.texts([SaErrorCatcher.ERROR]):
        if line.contains(path):
            said.append(line)
    assert_eq(said.size(), 1, "with one error line naming the file: %s" % [errors.texts([SaErrorCatcher.ERROR])])
    var version := "version %d," % (SaSadFile.SAD_VERSION + 1)
    assert_true(said.size() == 1 and said[0].contains(version), "and the version it carries: %s" % [said])
    assert_not_null(easel.document.get_node_or_null("Layer 1"), "and the document is left as it was")
    DirAccess.remove_absolute(path)
    easel.free()


func test_a_flatten_bakes_it_and_undo_restores_the_tree() -> void:
    var easel := _painting()
    var layer := _adjust(easel)
    _show(easel)
    var before := _bytes(easel.output)
    var doc := easel.document
    var held := _layers(doc).size()
    assert_true(SaLayerOps.new(doc).flatten(), "The flatten runs")
    assert_eq(_layers(doc).size(), 1, "One layer is left")
    _show(easel)
    _alike(easel.output, _bytes(easel.output), before, "The flattened canvas is the canvas before it")
    assert_true(doc.undo(), "One step")
    assert_eq(_layers(doc).size(), held, "whose undo brings every layer back")
    assert_true(layer.get_parent() == doc and layer.is_adjustment(), "the adjustment layer among them")
    assert_true(layer.chunks.is_empty(), "still holding no chunk")
    _show(easel)
    assert_eq(_bytes(easel.output), before, "with the picture it had")
    easel.free()


func test_merge_down_adjusts_the_paint_below_alone() -> void:
    var easel := _painting()
    _show(easel)
    var unadjusted := _bytes(easel.output)
    var layer := _adjust(easel)
    var doc := easel.document
    var stroke := doc.get_node("Stroke") as SaLayer
    var held := stroke.get_field(RIGHT)
    var paint := _bytes(held)
    _show(easel)
    var before := _bytes(easel.output)
    var ops := SaLayerOps.new(doc)
    assert_true(ops.can_merge_down(layer), "Merge Down is live on an adjustment layer over paint")
    assert_true(ops.merge_down(layer), "and it merges")
    assert_true(layer.get_parent() == null, "The adjustment layer is gone")
    assert_true(stroke.filters.is_empty(), "and the paint below carries no record")
    _show(easel)
    var wanted := _painting(true)
    _show(wanted)
    _alike(easel.output, _bytes(easel.output), _bytes(wanted.output), "The paint below is adjusted, the layer under it not")
    var right := _texel(_bytes(stroke.get_field(RIGHT)), stroke.get_field(RIGHT), Vector2i(100, 100))
    assert_true(absf(right.a - HALF.a) <= TOLERANCE, "and the stroke keeps its alpha, %s" % right.a)
    assert_true(_bytes(easel.output) != unadjusted, "which is not the painting without the adjustment")
    assert_true(doc.undo(), "One step")
    assert_true(layer.get_parent() == doc, "whose undo brings the adjustment layer back")
    assert_eq(_bytes(stroke.get_field(RIGHT)), paint, "and the paint below as it was")
    _show(easel)
    assert_eq(_bytes(easel.output), before, "with the picture it had")
    easel.free()
    wanted.free()


func test_what_it_cannot_take_is_refused_with_a_sentence() -> void:
    var easel := _painting()
    var layer := _adjust(easel)
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    SaProblems.announce = false
    var above := ops.add()
    above.get_or_create_chunk(LEFT).clear(UNDER)
    assert_false(ops.can_merge_down(above), "Merge Down onto an adjustment layer is dimmed")
    assert_false(ops.merge_down(above), "and refused")
    _refused("'Adjust' is an adjustment layer and holds no paint to merge onto.", "Merging onto one")
    var record := layer.filters[0]
    assert_false(SaFilterOps.new(doc).flatten(layer, record), "Flattening its record is refused")
    _refused("Merge Down applies it to the layer below.", "A record flattened on one")
    assert_eq(layer.filters.size(), 1, "and the record stays")
    doc.move_child(layer, 0)
    assert_true(ops.flatten(), "A flatten over an adjustment layer at the bottom draws into a new paint layer")
    assert_null(layer.get_parent(), "and takes the adjustment layer out")
    SaProblems.announce = true
    assert_true(layer.chunks.is_empty(), "After all of it the layer holds no chunk")
    easel.free()
