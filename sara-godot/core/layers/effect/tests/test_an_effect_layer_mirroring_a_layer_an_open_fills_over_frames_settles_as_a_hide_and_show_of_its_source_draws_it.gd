## The lake's live reflections are right straight after a
## load. On a large painting the mirrors that read `Background` kept a picture
## of the lake without the domes after an open, up to 131 levels off in
## winter, until the painter hid and showed `Background` once.
##
## This suite saves a file whose Lake, an effect layer of Mirror, reflects
## Ground, a paint layer that fills every chunk with a colour of its own,
## opens it over frames as File > Open does, the view first and Ground's
## chunks after the landing, and settles it. The settled float picture is
## then read, Ground hidden and shown, the picture settled and read again,
## and the two are equal byte for byte.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const MIRROR: StringName = &"sara-base-modules.mirror"
## Four chunks across and three down, the mirror's level line through the
## middle row, so every chunk of the reflection reads one the open filled.
const SIZE := Vector2i(1024, 768)

var _types: SaLayerTypeRegistry
var _easels: Array[SaEasel] = []
var _paths: Array[String] = []


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()
    for path in _paths:
        DirAccess.remove_absolute(path)
    _paths.clear()


func _easel() -> SaEasel:
    var easel := Bench.easel(SIZE)
    easel.compositor.filter_chain.registry.register(MirrorFilter.new(), OWNER)
    _easels.append(easel)
    return easel


## A colour of its own for each chunk, so a reflection that read a chunk
## before it arrived shows as another colour.
static func _colour(grid_pos: Vector2i) -> Color:
    return Color(0.15 + 0.2 * grid_pos.x, 0.25 + 0.3 * grid_pos.y, 0.9 - 0.2 * grid_pos.x, 1.0)


## The file of the header, written, and its path.
func _saved() -> String:
    var easel := _easel()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    (doc.get_node("Background") as SaLayer).visible = false
    var ground := doc.get_node("Layer 1") as SaLayer
    ground.name = "Ground"
    for grid_pos in SaLayer.grid_positions(SIZE):
        ground.get_or_create_chunk(grid_pos).clear(_colour(grid_pos))
    doc.set_active_layer(ground)
    var dome := ops.add(&"")
    dome.name = "Dome"
    dome.get_or_create_chunk(Vector2i(2, 0)).clear(Color(0.9, 0.85, 0.2, 1.0))
    var sources: Array[SaLayer] = []
    for input: SaLayer in [ground, dome]:
        doc.set_active_layer(dome)
        var source := ops.add(SaEffectLayer.TYPE_ID, _types)
        source.name = "Source %s" % input.name
        if source.source != input:
            SaEffectLayer.read(doc, source, input)
        sources.append(source)
    var group := ops.group_layers(sources)
    group.name = "Sources"
    ops.set_visible(group, false)
    doc.set_active_layer(group)
    var lake := ops.add(SaEffectLayer.TYPE_ID, _types)
    lake.name = "Lake"
    if lake.source != group:
        SaEffectLayer.read(doc, lake, group)
    assert_not_null(SaFilterOps.new(doc).attach(lake, MIRROR, {}), "The Mirror attaches to Lake")
    doc.set_active_layer(ground)
    Bench.composite(easel)
    var path := ProjectSettings.globalize_path(SaDataRoot.path("test_%d.sad" % _paths.size()))
    _paths.append(path)
    assert_eq(SaExport.save_sad(doc, path), OK, "The file is written")
    return path


static func _layers(doc: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in doc.get_children():
        if child is SaLayer:
            found.append(child)
    return found


## The file at *path* opened over frames into a fresh easel, as File > Open
## does it with *view* in the window and a budgeted frame of the easel after
## each frame of the tree, and answers the easel once the open has answered
## and the frames after it have drawn everything they owe.
func _opened(path: String, view: Rect2i) -> SaEasel:
    var easel := _easel()
    var document := easel.document
    var answers: Array[Error] = []
    # The window binds each layer's type where the load announces itself,
    # before the fold is built over the landed stack, and so does this.
    var bind := func(loaded: SaDocument) -> void: _types.rebind(_layers(loaded))
    EventBus.document_loaded.connect(bind)
    var land := func() -> Rect2i: return view
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    SaSadOpening.new(document, file, path).over_frames(answers.append, land, 0)
    var frames := 0
    var filled := 0
    while answers.is_empty() and frames < 400:
        await (Engine.get_main_loop() as SceneTree).process_frame
        frames += 1
        if SaSadOpening.still_filling(document) != null:
            filled += 1
            easel.process_pending_composite(true)
    EventBus.document_loaded.disconnect(bind)
    assert_eq(answers, [OK] as Array[Error], "The open answers OK, after %d frames" % frames)
    assert_true(filled > 1, "and it filled over %d frames" % filled)
    _settle(easel)
    return easel


## Composites budgeted frames of *easel* until nothing is held and no refresh
## goes on, as the window's own frames would.
func _settle(easel: SaEasel) -> void:
    var frames := 0
    while frames < 400:
        easel.process_pending_composite(true)
        frames += 1
        if easel.backlog.is_empty() and not easel.compositor.effect._pace.running(easel.document, {}):
            break
    assert_true(easel.backlog.is_empty(), "The frames settle, in %d" % frames)


## The settled picture of *easel* after its *name* is hidden and shown, the
## painter's step that drew the lake right.
func _after_hide_and_show(easel: SaEasel, name: String) -> PackedByteArray:
    var doc := easel.document
    var layer := doc.get_node(name) as SaLayer
    SaLayerOps.new(doc).set_visible(layer, false)
    _settle(easel)
    SaLayerOps.new(doc).set_visible(layer, true)
    _settle(easel)
    return SaExport.get_texture_image_float(easel.output).get_data()


func test_the_settled_picture_after_an_open_is_the_one_a_hide_and_show_of_the_source_gives() -> void:
    for view: Rect2i in [Rect2i(Vector2i.ZERO, SIZE), Rect2i(Vector2i(300, 100), Vector2i(200, 150))]:
        var easel: SaEasel = await _opened(_saved(), view)
        var lake := easel.document.get_node("Lake") as SaLayer
        assert_false(lake.chunks.is_empty(), "Lake holds its reflection once the open settles, view %s" % view)
        var settled := SaExport.get_texture_image_float(easel.output).get_data()
        var refreshed := _after_hide_and_show(easel, "Ground")
        assert_eq(settled.size(), refreshed.size(), "The two pictures are one size")
        var apart := _first_apart(settled, refreshed)
        assert_true(settled == refreshed, "The settled picture is the refreshed one byte for byte, view %s, %s" % [view, apart])


## Where *a* and *b* first differ, as a byte offset, or an empty line.
static func _first_apart(a: PackedByteArray, b: PackedByteArray) -> String:
    for i in mini(a.size(), b.size()):
        if a[i] != b[i]:
            return "byte %d, %d against %d" % [i, a[i], b[i]]
    return ""
