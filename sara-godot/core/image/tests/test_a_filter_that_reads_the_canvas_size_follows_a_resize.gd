## A filter that reads the canvas size follows a crop, a rotation and a resize.
## The kaleidoscope works its centre out in pixels from the
## canvas when its pass is recorded, and until the fix nothing recorded it again after
## Crop to Selection, Rotate, Image Size or Canvas Size, so it went on folding
## round the middle of the old canvas. A global one blanked a crop, and an effect
## layer's went empty or off centre, until the eye was turned off and on.
##
## The painting is four chunks across and three down, each a tint of its own.
## The kaleidoscope hangs on the root or on an effect layer reading the painted
## layer, every resize is one `core/image` makes, and what the canvas shows
## after it is compared with the canvas after every record has run again, which
## is the eye turned off and on and what a document saved and reopened draws.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const Kaleidoscope = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")

const REQUIRES_GPU := true

const GRID := Vector2i(4, 3)
const KEY: StringName = &"kaleidoscope.kaleidoscope"
const SIX_MIRRORS := {"mirrors": 6, "angle": 0.0, "centre_x": 50.0, "centre_y": 50.0}
## Off the middle, so the centre of what is kept is not the old one.
const CROPPED := Rect2i(64, 32, 512, 448)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _painted: SaLayer = null
var _presets_dir: String = ""


func before_each() -> void:
    # First, so the filter made below carries nothing into a painter's store.
    _presets_dir = SaDataRoot.path("test_p1_resize_presets_%d" % OS.get_process_id())
    SaFilterPreset.root = _presets_dir
    _easel = Bench.easel(GRID * SaChunk.SIZE)
    _doc = _easel.document
    # The kernels' owner is the folder under modules, sara-base-modules, which
    # a filter registered by hand has to tell the loader.
    ModuleLoader.module_dirs[&"kaleidoscope"] = "res://modules/sara-base-modules/kaleidoscope"
    _easel.compositor.filter_chain.registry.register(Kaleidoscope.new(), &"kaleidoscope")
    _painted = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _painted.chunks.keys():
        _painted.chunks.erase(grid_pos)
    for y in GRID.y:
        for x in GRID.x:
            _painted.get_or_create_chunk(Vector2i(x, y)).clear(Color(float(x) / GRID.x, float(y) / GRID.y, 0.5, 1.0))


func after_each() -> void:
    _painted = null
    _doc = null
    if _easel != null:
        _easel.free()
    _easel = null
    var store := SaFilterPreset.store_for(&"kaleidoscope")
    DirAccess.remove_absolute(store.dir)
    DirAccess.remove_absolute(_presets_dir)
    SaFilterPreset.root = SaFilterPreset.default_root()


## The kaleidoscope on the root, composited whole.
func _on_the_root() -> SaAttachedFilter:
    var record := SaFilterOps.new(_doc).attach(null, KEY, SIX_MIRRORS)
    Bench.composite(_easel)
    return record


## An effect layer above the painting, reading it through the kaleidoscope, and
## the painting's own layer hidden so the canvas is the effect alone.
func _on_an_effect_layer() -> SaAttachedFilter:
    _painted.name = "Source"
    _doc.set_active_layer(_painted)
    var effect := SaLayerOps.new(_doc).add(SaEffectLayer.TYPE_ID, Fixtures.make_registries().layer_types)
    var record := SaFilterOps.new(_doc).attach(effect, KEY, SIX_MIRRORS)
    _painted.visible = false
    Bench.composite(_easel)
    return record


## The new size on the easel, as the canvas view puts it there on
## `document_resized`, and the canvas composited.
func _shown() -> PackedByteArray:
    @warning_ignore("unused_variable")
    var displaced := _easel.resize_output(_doc.canvas_size)
    Bench.composite(_easel)
    return GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)


## The canvas once every record of the document has run again, the eye of
## each turned off and on.
func _afresh() -> PackedByteArray:
    for record: SaAttachedFilter in SaCrop.every_record(_doc):
        record.touch()
    Bench.composite(_easel)
    return GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)


## The centre *record* folds round, from the pass it was last evaluated to.
static func _centre(record: SaAttachedFilter) -> Vector2:
    var recorded := record.cached_pass as SaNeighbourhoodPass
    return recorded.params["centre"] if recorded != null else Vector2(-1.0, -1.0)


func _middle() -> Vector2:
    return Vector2(_doc.canvas_size) / 2.0


func test_a_crop_folds_the_global_kaleidoscope_round_the_middle_of_what_is_kept() -> void:
    var record := _on_the_root()
    assert_eq(_centre(record), Vector2(512.0, 384.0), "Before the crop the fold is round the middle of the canvas")
    assert_true(SaCrop.new(_doc).crop_to(CROPPED), "The crop happens")
    var shown := _shown()
    assert_eq(_centre(record), Vector2(256.0, 224.0), "and after it round the middle of the cropped canvas")
    assert_true(shown == _afresh(), "which is what the record run afresh draws")


func test_undo_and_redo_of_a_crop_fold_round_the_middle_of_each_canvas() -> void:
    var record := _on_the_root()
    assert_true(SaCrop.new(_doc).crop_to(CROPPED), "The crop happens")
    _shown()
    assert_true(_doc.undo(), "and undoes")
    var undone := _shown()
    assert_eq(_centre(record), Vector2(512.0, 384.0), "Undone, the fold is round the old middle again")
    assert_true(undone == _afresh(), "and draws what the record run afresh draws")
    assert_true(_doc.redo(), "Redone")
    var redone := _shown()
    assert_eq(_centre(record), Vector2(256.0, 224.0), "the fold is round the cropped middle")
    assert_true(redone == _afresh(), "and draws what the record run afresh draws")


func test_a_quarter_turn_folds_an_effect_layer_round_the_turned_middle() -> void:
    var record := _on_an_effect_layer()
    assert_true(SaOrient.new(_doc).rotate_image(1), "The quarter turn happens")
    var shown := _shown()
    assert_eq(_doc.canvas_size, Vector2i(768, 1024), "The sides swap")
    assert_eq(_centre(record), Vector2(384.0, 512.0), "and the effect layer's fold is round the middle of the turned canvas")
    assert_true(shown == _afresh(), "which is what the record run afresh draws")


func test_half_the_width_folds_an_effect_layer_round_the_new_middle() -> void:
    var record := _on_an_effect_layer()
    var geometry := SaResample.new(_doc)
    geometry.filter = SaResampleKernel.Filter.NEAREST
    assert_true(geometry.resample_to(Vector2i(512, 768)), "The resize happens")
    var shown := _shown()
    assert_eq(_centre(record), Vector2(256.0, 384.0), "The effect layer's fold is round the middle of the narrower canvas")
    assert_true(shown == _afresh(), "which is what the record run afresh draws")


func test_a_canvas_size_folds_an_effect_layer_round_the_new_middle() -> void:
    var record := _on_an_effect_layer()
    assert_true(SaCrop.new(_doc).resize_to(Vector2i(1280, 640), Vector2i(0, 0)), "The canvas size changes")
    var shown := _shown()
    assert_eq(_centre(record), Vector2(640.0, 320.0), "The effect layer's fold is round the middle of the new canvas")
    assert_true(shown == _afresh(), "which is what the record run afresh draws")


## Every record of the document is told, whether or not it reads the size, on
## the root, on a layer and in an effect layer, so no filter has to say it
## reads the canvas for its pass to follow.
func test_a_resize_runs_every_record_of_the_document_again() -> void:
    var on_effect := _on_an_effect_layer()
    var on_root := SaFilterOps.new(_doc).attach(null, KEY, SIX_MIRRORS)
    var on_layer := SaFilterOps.new(_doc).attach(_painted, Bench.INVERT)
    Bench.composite(_easel)
    var before: Array[int] = [on_effect.revision, on_root.revision, on_layer.revision]
    assert_true(SaCrop.new(_doc).crop_to(CROPPED), "The crop happens")
    var records: Array[SaAttachedFilter] = [on_effect, on_root, on_layer]
    for i in records.size():
        assert_null(records[i].cached_pass, "Record %d dropped the pass it had" % i)
        assert_true(records[i].revision > before[i], "and moved its revision")


## A layer flip keeps the size, so a record whose mask did not move keeps the
## pass it was evaluated to.
func test_a_layer_flip_keeps_the_passes_it_did_not_move() -> void:
    var record := _on_the_root()
    var recorded := record.cached_pass
    assert_not_null(recorded, "The root's record was evaluated")
    assert_true(SaOrient.new(_doc).flip_layer(_painted, true), "The flip happens")
    assert_true(record.cached_pass == recorded, "and the record keeps its pass")
