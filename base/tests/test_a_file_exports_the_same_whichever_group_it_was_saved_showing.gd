## A file's exports are the same whichever season and light
## it was saved showing.
##
## The lake of the seasons file is a ripple reading a group of Mirrors, and a
## Mirror's record reads the land in one chunk for the lake in another. What a
## file was saved showing reached another season's pixels through the first
## frames after its load alone: the budget pays them a few chunks a frame, the
## top rows first and each row from the left, and how many a frame follows the
## weight of what is shown and how fast the last frames ran. A ripple refreshed
## in the lake's frame read the Mirror before the land's frame had drawn it,
## and kept that reading unless a Mirror's written chunks were handed on to the
## effects reading it.
##
## This suite saves one painting twice, once showing a group named Spring and
## once showing one named Autumn, loads each into a fresh easel and pays its
## first frames as the painter's two loads were paid: the Spring file's in one
## frame, which is how a load saved at spring's dawn was paid, and the Autumn
## file's a chunk a frame, as the heavier first frames of a file saved at
## autumn's clear day were. Then both show a third group, Winter, and are
## exported, and the two exports are held pixel equal.
##
## The painting: four chunks a side, the background hidden, a layer named Land
## holding a red mark in chunk (2, 1), a Mirror effect reading it about an
## upright line through the canvas's middle, which lands the reflection in
## chunk (1, 1), left of the land in the same row and so paid before it, and an
## effect named Ripple reading the Mirror through the fixture invert. Each
## season group holds a layer with a mark of its own in the last row, away
## from the lake.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")

## A save reads chunks back and a load uploads them.
const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const MIRROR: StringName = &"sara-base-modules.mirror"
const SIZE := Vector2i(1024, 1024)
const RED := Color(1.0, 0.0, 0.0, 1.0)
## Columns 600 to 679, reflected about x 512 to columns 344 to 423.
const MARK := Rect2i(600, 300, 80, 40)
## The line turned upright, so the land on its right reflects to its left.
const ANGLE := 90.0
const SEASONS: Array[String] = ["Spring", "Autumn", "Winter"]
## A cost a chunk so large that the budget pays one chunk a frame.
const HEAVY_USEC := 1.0e9

static var path_spring: String = SaDataRoot.path("test_spring.sad")
static var path_autumn: String = SaDataRoot.path("test_autumn.sad")

var _types: SaLayerTypeRegistry
var _easels: Array[SaEasel] = []


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


func after_each() -> void:
    SaSadFile.finish_saves()
    for easel in _easels:
        easel.free()
    _easels.clear()
    for path: String in [path_spring, path_autumn]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _easel() -> SaEasel:
    var easel := Bench.easel(SIZE)
    easel.compositor.filter_chain.registry.register(MirrorFilter.new(), OWNER)
    _easels.append(easel)
    return easel


func _painting() -> SaEasel:
    var easel := _easel()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    (doc.get_node("Background") as SaLayer).visible = false
    var land := doc.get_node("Layer 1") as SaLayer
    land.name = "Land"
    _mark(land, MARK)
    doc.set_active_layer(land)
    var mirror := ops.add(SaEffectLayer.TYPE_ID, _types)
    mirror.name = "Mirror"
    assert_not_null(SaFilterOps.new(doc).attach(mirror, MIRROR, {"angle": ANGLE}), "The Mirror attaches to the effect layer")
    if mirror.source != land:
        SaEffectLayer.read(doc, mirror, land)
    doc.set_active_layer(mirror)
    var ripple := ops.add(SaEffectLayer.TYPE_ID, _types)
    ripple.name = "Ripple"
    assert_not_null(SaFilterOps.new(doc).attach(ripple, Bench.INVERT), "The invert attaches to the ripple")
    if ripple.source != mirror:
        SaEffectLayer.read(doc, ripple, mirror)
    assert_eq(SaEffectLayer.input_of(ripple), mirror, "The ripple reads the Mirror")
    for i in SEASONS.size():
        doc.set_active_layer(ripple)
        var paint := ops.add(&"", _types)
        paint.name = "%s paint" % SEASONS[i]
        _mark(paint, Rect2i(100 + 300 * i, 900, 60, 60))
        var group := ops.group_layers([paint])
        group.name = SEASONS[i]
    doc.set_active_layer(land)
    Bench.composite(easel)
    return easel


## Writes red over *rect* of *layer*, in document pixels.
static func _mark(layer: SaLayer, rect: Rect2i) -> void:
    var side := SaChunk.SIZE
    var first := Vector2i(floori(float(rect.position.x) / side), floori(float(rect.position.y) / side))
    var last := Vector2i(floori(float(rect.end.x - 1) / side), floori(float(rect.end.y - 1) / side))
    for gy in range(first.y, last.y + 1):
        for gx in range(first.x, last.x + 1):
            var grid_pos := Vector2i(gx, gy)
            var part := rect.intersection(Rect2i(grid_pos * side, Vector2i(side, side)))
            _fill(layer.get_or_create_chunk(grid_pos).albedo(), Rect2i(part.position - grid_pos * side, part.size))


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


## Shows the season group *shown* of *easel*'s document and hides the others.
static func _show(easel: SaEasel, shown: String) -> void:
    var ops := SaLayerOps.new(easel.document)
    for season in SEASONS:
        ops.set_visible(easel.document.get_node(season) as SaLayer, season == shown)


func _save(easel: SaEasel, path: String) -> void:
    var save := SaSadFile.save_in_background(easel.document, path, 0, null, true, Callable(), true)
    assert_true(SaSadFile.finish_saves(), "The save of %s ends" % path.get_file())
    assert_true(save != null and save.error == OK, "and writes its file")


## *path* loaded into a fresh easel, its first frames paid a chunk a frame
## when *cut*, and in one frame otherwise, until nothing is held back.
func _loaded(path: String, cut: bool) -> SaEasel:
    var easel := _easel()
    assert_eq(SaExport.load_sad(easel.document, path, easel.compositor), OK, "%s opens" % path.get_file())
    # The types are bound to a loaded stack as the window binds them.
    _types.rebind(easel.document.get_children())
    easel.document.update_caches()
    easel.request_full_composite()
    var frames := 0
    while frames < 64:
        if cut:
            easel.budget.usec_per_unit = HEAVY_USEC
        easel.process_pending_composite(true)
        frames += 1
        if easel.backlog.is_empty() and easel.document._dirty_chunks.is_empty():
            break
    if cut:
        assert_true(frames > 4, "The cut load is paid over several frames, here %d" % frames)
    return easel


static func _differing(a: Image, b: Image) -> int:
    var found := 0
    for y in a.get_height():
        for x in a.get_width():
            if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
                found += 1
    return found


func test_a_file_saved_showing_either_season_exports_the_third_the_same() -> void:
    var easel := _painting()
    _show(easel, "Spring")
    Bench.composite(easel)
    _save(easel, path_spring)
    _show(easel, "Autumn")
    Bench.composite(easel)
    _save(easel, path_autumn)
    var exports: Array[Image] = []
    for loaded: SaEasel in [_loaded(path_spring, false), _loaded(path_autumn, true)]:
        _show(loaded, "Winter")
        loaded.process_pending_composite(true)
        exports.append(SaExport.get_easel_image_float(loaded))
    assert_eq(exports[0].get_size(), exports[1].get_size(), "The two exports are one size")
    var lake := Vector2i(SIZE.x - 1 - (MARK.position.x + 10), MARK.position.y + 10)
    var spring := exports[0].get_pixel(lake.x, lake.y)
    var cyan := Color(0.0, 1.0, 1.0, 1.0)
    assert_true(spring.is_equal_approx(cyan), "The Ripple's inverted reflection shows in the lake, %s" % spring)
    assert_eq(_differing(exports[0], exports[1]), 0, "The two exports of Winter are pixel equal")
