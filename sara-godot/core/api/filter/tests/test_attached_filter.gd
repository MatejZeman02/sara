extends "res://tests/test_framework.gd"
## An attached filter is a record on a node of the layer tree.
## What the record keeps, that each of the five operations is one history step,
## and what `.sad` says of it, the mask's texels read back.

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BRIGHTNESS := &"sara-base-modules.brightness_contrast"
const BLUR := &"box-blur.box_blur"
const LEVELS := &"sara-base-modules.levels"

## A texel a painted mask hides at and one it leaves alone.
const INSIDE := Vector2i(3, 5)
const OUTSIDE := Vector2i(200, 100)
const HIDDEN := 0.25

## Written by the writer as it stood before this unit, a 64 by 64 document of
## one red layer, so the reader is held to a file it did not write.
const FIXTURE := "res://tests/data/plain_v4.sad"


## A filter that writes its one abstract method and overrides nothing else, so
## the base's own answers are what it gives.
class BareFilter:
    extends SaFilter

    func run(_ctx: SaFilterContext) -> void:
        pass


var _easel: SaEasel = null
var _doc: SaDocument = null
var _ops: SaFilterOps = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _ops = SaFilterOps.new(_doc)


func after_each() -> void:
    _ops = null
    _easel.free()
    _easel = null
    _doc = null


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## A mask of its own, one everywhere but HIDDEN at INSIDE.
func _painted_mask() -> SaMask:
    var mask := SaMask.own()
    var texture := mask.get_or_create(Vector2i(0, 0))
    var values := PackedFloat32Array()
    values.resize(texture.size.x * texture.size.y)
    values.fill(1.0)
    values[INSIDE.y * texture.size.x + INSIDE.x] = HIDDEN
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())
    return mask


func _version_of(path: String) -> int:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    var version := file.get_32()
    file.close()
    return version


func _keys(records: Array[SaAttachedFilter]) -> Array:
    var keys: Array = []
    for record in records:
        keys.append(record.key)
    return keys


func test_a_record_keeps_values_and_its_revision_moves_with_them() -> void:
    var values := {"radius": 4.0, "nested": {"a": [1.0, 2.0]}}
    var record := SaAttachedFilter.new(BLUR, values)
    values["radius"] = 9.0
    (values["nested"] as Dictionary)["a"] = []
    assert_eq(record.parameters["radius"], 4.0, "The record holds a copy, not the caller's dictionary")
    assert_eq((record.parameters["nested"] as Dictionary)["a"], [1.0, 2.0], "all the way down")
    assert_true(record.enabled, "A new record is on")
    assert_null(record.mask, "and has no mask until a mask operation gives it one")

    record.cached_pass = RefCounted.new()
    var before := record.revision
    record.replace_parameters({"radius": 2.0})
    assert_eq(record.parameters["radius"], 2.0, "New values replace the old")
    assert_true(record.revision > before, "and the revision moves")
    assert_null(record.cached_pass, "and the pass built from the old values is dropped")


func test_the_base_filter_has_no_parameters_and_takes_any() -> void:
    var filter := BareFilter.new()
    assert_eq(filter.parameters(), {}, "A filter that overrides nothing answers nothing")
    filter.set_parameters({"anything": 1.0})
    assert_eq(filter.parameters(), {}, "and ignores what it is handed")


func test_attach_is_one_step_on_a_layer_and_on_the_root() -> void:
    var layer := _doc.active_layer
    var steps := _doc.undo_redo.get_history_count()
    var first := _ops.attach(layer, BRIGHTNESS, {"brightness": 0.2})
    var second := _ops.attach(layer, BLUR, {"radius": 3.0})
    var global := _ops.attach(null, LEVELS)
    assert_eq(_doc.undo_redo.get_history_count(), steps + 3, "Three attaches are three steps")
    assert_eq(_keys(layer.filters), [BRIGHTNESS, BLUR], "A filter attaches on top of the node's others")
    assert_eq(_keys(_doc.root_filters), [LEVELS], "and a null node is the document's root")
    assert_true(_doc.modified, "The document is modified")

    var lowest := _ops.attach(layer, LEVELS, {}, 0)
    assert_eq(layer.filters[0], lowest, "An index places the record")
    _doc.undo()
    assert_eq(layer.filters, [first, second] as Array[SaAttachedFilter], "Undo takes it out again")
    _doc.undo()
    assert_true(_doc.root_filters.is_empty(), "and the root's")
    _doc.redo()
    assert_eq(_doc.root_filters, [global] as Array[SaAttachedFilter], "Redo brings the same record back")

    assert_null(_ops.attach(layer, &""), "A record with no key is refused")
    var stranger := SaLayer.new()
    assert_null(_ops.attach(stranger, BLUR), "and so is a layer of no document")
    stranger.free()


func test_detach_keeps_the_record_and_its_mask_inside_the_step() -> void:
    var layer := _doc.active_layer
    var below := _ops.attach(layer, BRIGHTNESS)
    var record := _ops.attach(layer, BLUR, {"radius": 3.0})
    var above := _ops.attach(layer, LEVELS)
    record.mask = _painted_mask()
    assert_true(record.byte_size() > 0, "A masked record is charged for its mask")

    assert_true(_ops.detach(layer, record), "Detach answers true")
    assert_eq(layer.filters, [below, above] as Array[SaAttachedFilter], "and the record is gone from the node")
    assert_false(_ops.detach(layer, record), "A record that is not there is not detached twice")
    _doc.undo()
    assert_eq(layer.filters, [below, record, above] as Array[SaAttachedFilter], "Undo puts it back where it was")
    var texture := record.mask.texture_for(Vector2i(0, 0))
    assert_almost_eq(_texel(texture, INSIDE).r, HIDDEN, 0.0001, "with the mask it had")
    _doc.redo()
    assert_eq(layer.filters, [below, above] as Array[SaAttachedFilter], "and redo takes it out again")


func test_set_enabled_is_a_step_and_moves_the_revision() -> void:
    var record := _ops.attach(_doc.active_layer, BLUR)
    var steps := _doc.undo_redo.get_history_count()
    var before := record.revision
    _ops.set_enabled(record, false)
    assert_false(record.enabled, "The record is off")
    assert_true(record.revision > before, "and evaluates to something else now")
    _ops.set_enabled(record, false)
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "Setting what is already set is no step")
    _doc.undo()
    assert_true(record.enabled, "Undo switches it back on")
    _doc.redo()
    assert_false(record.enabled, "and redo off")


func test_reorder_moves_a_record_and_undo_moves_it_back() -> void:
    var layer := _doc.active_layer
    var a := _ops.attach(layer, BRIGHTNESS)
    var b := _ops.attach(layer, BLUR)
    var c := _ops.attach(layer, LEVELS)
    assert_true(_ops.reorder(layer, a, 2), "The lowest goes to the top")
    assert_eq(layer.filters, [b, c, a] as Array[SaAttachedFilter], "and the others close up under it")
    assert_false(_ops.reorder(layer, a, 9), "An index past the end is the end, where it already is")
    assert_true(_ops.reorder(layer, c, 0), "A middle one goes to the bottom")
    assert_eq(layer.filters, [c, b, a] as Array[SaAttachedFilter], "in one move")
    _doc.undo()
    _doc.undo()
    assert_eq(layer.filters, [a, b, c] as Array[SaAttachedFilter], "Two undos give the order it began with")
    assert_false(_ops.reorder(_doc.active_layer, SaAttachedFilter.new(BLUR), 0), "A record of another node is not moved")


func test_duplicate_copies_the_values_and_the_mask_apart() -> void:
    var layer := _doc.active_layer
    var record := _ops.attach(layer, BLUR, {"radius": 3.0})
    var top := _ops.attach(layer, LEVELS)
    record.mask = _painted_mask()
    record.enabled = false

    var copy := _ops.duplicate(layer, record)
    assert_eq(layer.filters, [record, copy, top] as Array[SaAttachedFilter], "The copy sits directly above its source")
    assert_eq(copy.key, record.key, "with the same key")
    assert_eq(copy.parameters, record.parameters, "the same values")
    assert_false(copy.enabled, "and the same flag")
    assert_true(copy.mask != null and copy.mask != record.mask, "Its mask is its own")
    if copy.mask != null:
        var texture := copy.mask.texture_for(Vector2i(0, 0))
        assert_not_null(texture, "holding a chunk where the source held one")
        if texture != null:
            assert_true(texture != record.mask.texture_for(Vector2i(0, 0)), "in a texture of its own")
            assert_almost_eq(_texel(texture, INSIDE).r, HIDDEN, 0.0001, "with the source's coverage inside")
            assert_almost_eq(_texel(texture, OUTSIDE).r, 1.0, 0.0001, "and outside")
    copy.replace_parameters({"radius": 8.0})
    assert_eq(record.parameters["radius"], 3.0, "A change to the copy leaves the source alone")
    _doc.undo()
    assert_eq(layer.filters, [record, top] as Array[SaAttachedFilter], "Undo takes the copy out")


func test_records_survive_a_save_with_their_order_flags_and_mask() -> void:
    var layer := _doc.active_layer
    var name_was := str(layer.name)
    layer.fill(RED)
    _ops.attach(layer, BRIGHTNESS, {"brightness": 0.25, "contrast": -0.5})
    var masked := _ops.attach(layer, BLUR, {"radius": 3, "wrap": true, "label": "soft"})
    masked.mask = _painted_mask()
    masked.mask.enabled = false
    _ops.set_enabled(masked, false)
    _ops.attach(null, LEVELS, {"black": 0.1, "points": [0.0, 0.5, 1.0]})

    var path := SaDataRoot.path("test_attached_filter.sad")
    assert_eq(SaSadFile.version_for(_doc), 5, "A document carrying a filter is version 5")
    assert_eq(SaExport.save_sad(_doc, path, 0), OK, "It saves")
    assert_eq(_version_of(path), SaSadFile.SAD_VERSION_PLANES, "and its header says 14, for its planes")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loads")
    var back: SaLayer = loaded.get_node_or_null(name_was)
    assert_not_null(back, "The layer is back")
    if back != null:
        assert_eq(_keys(back.filters), [BRIGHTNESS, BLUR], "with its two records in their order")
        if back.filters.size() == 2:
            assert_eq(back.filters[0].parameters, {"brightness": 0.25, "contrast": -0.5}, "The first one's values")
            assert_true(back.filters[0].enabled, "and its flag")
            assert_null(back.filters[0].mask, "and no mask where none was given")
            var second := back.filters[1]
            assert_eq(second.parameters, {"radius": 3.0, "wrap": true, "label": "soft"}, "The second one's, a number a float")
            assert_false(second.enabled, "switched off as it was saved")
            assert_not_null(second.mask, "with its mask")
            if second.mask != null:
                assert_true(second.mask.is_own(), "holding chunks of its own")
                assert_false(second.mask.enabled, "the mask's own flag kept apart from the record's")
                var texture := second.mask.texture_for(Vector2i(0, 0))
                assert_not_null(texture, "and a chunk where one was painted")
                if texture != null:
                    assert_almost_eq(_texel(texture, INSIDE).r, HIDDEN, 0.0001, "The texel inside reads what was painted")
                    assert_almost_eq(_texel(texture, OUTSIDE).r, 1.0, 0.0001, "and the one outside reads one")
                assert_null(second.mask.texture_for(Vector2i(1, 0)), "A chunk never painted is still not allocated")
    assert_eq(_keys(loaded.root_filters), [LEVELS], "The root's record is back")
    if loaded.root_filters.size() == 1:
        assert_eq(loaded.root_filters[0].parameters, {"black": 0.1, "points": [0.0, 0.5, 1.0]}, "with its values")

    # The second save of what was loaded says the same thing, which is the
    # fixed point the parameters were written in.
    var again := SaDataRoot.path("test_attached_filter_again.sad")
    assert_eq(SaExport.save_sad(loaded, again, 0), OK, "What was loaded saves again")
    assert_eq(FileAccess.get_file_as_bytes(again), FileAccess.get_file_as_bytes(path), "byte for byte what the first save wrote")
    DirAccess.remove_absolute(path)
    DirAccess.remove_absolute(again)
    loaded.free()


func test_a_document_with_no_filter_is_still_version_four() -> void:
    var layer := _doc.active_layer
    layer.fill(RED)
    var record := _ops.attach(layer, BLUR)
    assert_eq(SaSadFile.version_for(_doc), 5, "Attached, the document is version 5")
    _ops.detach(layer, record)
    assert_eq(SaSadFile.version_for(_doc), 4, "and detached it is version 4 again, the step keeping the record or not")
    var path := SaDataRoot.path("test_attached_filter_plain.sad")
    assert_eq(SaExport.save_sad(_doc, path, 0), OK, "A plain document saves")
    assert_eq(_version_of(path), SaSadFile.SAD_VERSION_PLANES, "as 14, for its planes")
    DirAccess.remove_absolute(path)

    var global := _ops.attach(null, LEVELS)
    assert_eq(SaSadFile.version_for(_doc), 5, "A filter on the root alone makes it version 5")
    _ops.detach(null, global)


func test_a_v4_file_written_before_the_key_opens_with_no_filters() -> void:
    assert_eq(_version_of(FIXTURE), 4, "The fixture is a version 4 file")
    # Loaded over a document that has filters, so an absent key is seen to
    # mean none and not to mean keep.
    _ops.attach(null, LEVELS)
    assert_eq(SaExport.load_sad(_doc, ProjectSettings.globalize_path(FIXTURE)), OK, "It opens")
    assert_eq(_doc.canvas_size, Vector2i(64, 64), "as the document it was")
    assert_true(_doc.root_filters.is_empty(), "with no filter on the root")
    var layers := 0
    var red := false
    for child in _doc.get_children():
        var layer := child as SaLayer
        if layer == null or layer == _doc.stroke_layer:
            continue
        layers += 1
        assert_true(layer.filters.is_empty(), "and none on '%s'" % layer.name)
        var paint := layer.get_field(Vector2i(0, 0))
        # The default document's grey ground is a layer too, so the red one is
        # looked for rather than assumed to be the active one.
        if paint != null and _texel(paint, Vector2i(10, 10)).is_equal_approx(RED):
            red = true
    assert_true(layers > 0, "and its layers")
    assert_true(red, "and the red it was painted with")


func test_a_record_with_no_key_is_left_out_and_a_stray_value_is_no_filters() -> void:
    var blobs := PackedByteArray()
    var records := SaSadFile.read_filters([{"key": "a.b", "params": "nonsense"}, {"params": {}}, "stray"], blobs)
    assert_eq(_keys(records), [&"a.b"], "Only the entry that names a key is a record")
    assert_eq(records[0].parameters, {}, "and parameters that are no dictionary read as none")
    assert_true(records[0].enabled, "An absent flag reads as on")
    assert_true(SaSadFile.read_filters(null, blobs).is_empty(), "An absent key is no filters")
    assert_true(SaSadFile.read_filters("filters", blobs).is_empty(), "and so is anything that is no array")
