## A save leaves out the chunks that hold nothing, and the
## document lets them go. A chunk whose every authoritative field reads as its
## blank in every texel, compared exactly, is not listed in the saved header,
## and when the document stands as the snapshot found it the layer gives it up
## too, silently. A chunk that holds anything is kept, an undo makes a chunk
## let go again, and a document that moved after the snapshot keeps its chunks
## until the next save asks again.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the sweep runs on the card and a save reads back.
const REQUIRES_GPU := true

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## The chunk the suite paints and empties, and the document pixel at its middle.
const HERE := Vector2i(1, 0)
const MIDDLE := Vector2(384.0, 128.0)
## A chunk of the painted layer the suite leaves holding paint.
const KEPT := Vector2i(0, 1)

const RED := Color(0.8, 0.1, 0.05, 1.0)
const HIDE := Color(0.0, 0.0, 0.0, 1.0)

static var first: String = SaDataRoot.path("test_first.sad")
static var second: String = SaDataRoot.path("test_second.sad")

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    SaSadFile.finish_saves()
    _easel.free()
    _easel = null
    _doc = null
    for path: String in [first, second]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A new empty paint layer on top, made active, holding no chunk anywhere.
func _layer(called: String) -> SaLayer:
    var layer := SaLayer.new()
    layer.name = called
    layer.schema = SaFieldSpec.schema_for_space(_doc.color_space)
    _doc.add_child(layer)
    _doc.active_layer = layer
    return layer


## One hard dab of *color* through the paint context, as a stroke of its own.
func _stroke(pos: Vector2, radius: float, color: Color) -> void:
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    _dab(pos, radius, color)
    _doc.commit_stroke()


func _dab(pos: Vector2, radius: float, color: Color) -> void:
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
    var paint := SaPaintContext.for_region(_doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, color, radius, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()


## Erases the whole of *layer*'s chunk at *grid_pos* at full strength, as the
## Eraser does in build-up: straight into the layer, its region captured first.
func _erase(layer: SaLayer, grid_pos: Vector2i) -> void:
    _doc.active_layer = layer
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.ERASE)
    _doc.capture_direct_stroke_chunk(layer, grid_pos)
    layer.get_field(grid_pos, SaFieldSpec.ALBEDO).clear(Color(0.0, 0.0, 0.0, 0.0))
    _doc.commit_stroke()


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0) if texture != null else PackedByteArray()


## A digest of every byte of *texture*, what two textures equal byte for byte share.
static func _digest(texture: SaTexture) -> String:
    var bytes := _bytes(texture)
    var hashing := HashingContext.new()
    hashing.start(HashingContext.HASH_SHA256)
    hashing.update(bytes)
    return "%d %s" % [bytes.size(), hashing.finish().hex_encode()]


## Whether every byte of *texture* is zero.
static func _all_zero(texture: SaTexture) -> bool:
    var bytes := _bytes(texture)
    if bytes.is_empty():
        return false
    for at in range(0, bytes.size(), 4):
        if bytes.decode_u32(at) != 0:
            return false
    return true


## Saves in the background as File > Save does, and answers whether it ended.
## Without the rounding unless *rounds*, so a reopened chunk that holds
## colour can be read equal to the live one bit for bit.
func _save(path: String, rounds: bool = false) -> bool:
    SaSadFile.save_in_background(_doc, path, 0, null, true, Callable(), rounds)
    return SaSadFile.finish_saves()


## The header of the file at *path*.
static func _header(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    file.get_buffer(4)
    file.get_32()
    var packed := file.get_32()
    var raw := file.get_32()
    var text := file.get_buffer(packed).decompress(raw, SaSadFile.SAD_BLOB_COMPRESS).get_string_from_utf8()
    file.close()
    return SaTyped.strings(JSON.parse_string(text))


## The header's entry of the layer called *called*, at any depth.
static func _entry(header: Dictionary, called: String) -> Dictionary:
    for raw: Variant in header.get("layers", []):
        var entry := SaTyped.strings(raw)
        if str(entry.get("name", "")) == called:
            return entry
        var inner := _entry(SaTyped.strings({"layers": entry.get("children", [])}), called)
        if not inner.is_empty():
            return inner
    return {}


## The positions *list* of chunk entries names.
static func _listed(list: Variant) -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    if list is Array:
        for raw: Variant in list:
            var slot := SaTyped.strings(raw)
            found.append(Vector2i(SaTyped.int_at(slot, "x", 0), SaTyped.int_at(slot, "y", 0)))
    return found


## The positions the header lists for the layer called *called*.
static func _listed_for(path: String, called: String) -> Array[Vector2i]:
    return _listed(_entry(_header(path), called).get("chunks", []))


## The document at *path*, or null when it would not open.
static func _reopened(path: String) -> SaDocument:
    var doc := SaDocument.new()
    if SaExport.load_sad(doc, path, SaCompositor.new()) != OK:
        doc.free()
        return null
    return doc


static func _named(doc: SaDocument, called: String) -> SaLayer:
    for layer in _layers(doc):
        if str(layer.name) == called:
            return layer
    return null


## Every layer of *doc* at any depth but the stroke buffer.
static func _layers(doc: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in doc.find_children("*", "SaLayer", true, false):
        if child != doc.stroke_layer:
            found.append(child as SaLayer)
    return found


## Every stored field of every chunk of every layer of *doc*, keyed by layer
## name, position and field, a chunk the layer does not hold left out.
static func _picture(doc: SaDocument) -> Dictionary:
    var found := {}
    for layer in _layers(doc):
        if layer.is_group:
            continue
        var each := {}
        for grid_pos: Vector2i in layer.chunks:
            var chunk: SaChunk = layer.chunks[grid_pos]
            for field_id: StringName in chunk.fields:
                each["%s %s" % [grid_pos, field_id]] = _digest(chunk.field(field_id))
        found[str(layer.name)] = each
    return found


## The picture *doc* holds with each of *gone* read as a chunk of nothing:
## a chunk the reopened document lacks equals one held blank in the live one.
static func _without(picture: Dictionary, gone: Dictionary) -> Dictionary:
    var trimmed := {}
    for called: String in picture:
        var each := {}
        for key: String in picture[called]:
            var dropped := false
            for grid_pos: Vector2i in gone.get(called, []):
                dropped = dropped or key.begins_with("%s " % grid_pos)
            if not dropped:
                each[key] = picture[called][key]
        trimmed[called] = each
    return trimmed


## The chunks and fields where *found* and *wanted* differ, named, so a
## failure says where rather than printing two pictures.
static func _differences(found: Dictionary, wanted: Dictionary) -> Array[String]:
    var named: Array[String] = []
    for called: String in wanted:
        var have: Dictionary = found.get(called, {})
        for key: String in wanted[called]:
            if have.get(key, "missing") != wanted[called][key]:
                named.append("%s %s %s" % [called, key, "missing" if not have.has(key) else "differs"])
        for key: String in have:
            if not (wanted[called] as Dictionary).has(key):
                named.append("%s %s extra" % [called, key])
    for called: String in found:
        if not wanted.has(called):
            named.append("%s extra layer" % called)
    return named


func _composite() -> String:
    _doc.update_caches()
    _easel.request_full_composite()
    _easel.process_pending_composite()
    return _digest(_easel.output)


func test_an_erased_stroke_s_chunk_is_left_out_and_let_go_and_the_file_reopens_equal() -> void:
    var layer := _layer("stroked")
    _stroke(MIDDLE, 40.0, RED)
    _stroke(Vector2(100.0, 400.0), 30.0, RED)
    assert_true(layer.chunks.has(HERE), "The stroke made a chunk where it landed")
    var painted := _digest(layer.get_field(HERE, SaFieldSpec.ALBEDO))
    _erase(layer, HERE)
    assert_true(_all_zero(layer.get_field(HERE, SaFieldSpec.ALBEDO)), "The erase leaves every texel of the chunk exactly zero")
    var before := _composite()
    var steps := _doc.history.step_count()
    assert_true(_save(first), "The save lands")
    assert_false(HERE in _listed_for(first, "stroked"), "The header lists no chunk where the paint was erased")
    assert_true(KEPT in _listed_for(first, "stroked"), "and still lists the chunk that holds paint")
    assert_false(layer.chunks.has(HERE), "The live layer let the empty chunk go")
    assert_true(layer.chunks.has(KEPT), "and kept the painted one")
    assert_eq(_doc.history.step_count(), steps, "Letting go is no history step")
    assert_false(_doc.modified, "and leaves the document as saved")
    assert_eq(_composite(), before, "The composite is the same with the chunk gone")
    var back := _reopened(first)
    assert_not_null(back, "The file opens")
    if back != null:
        var differing := _differences(_picture(back), _picture(_doc))
        assert_eq(differing, [] as Array[String], "and reads equal to the live document texel for texel")
        assert_false(_named(back, "stroked").chunks.has(HERE), "with nothing where the chunk was")
        back.free()

    assert_true(_doc.undo(), "The erase undoes after the save")
    assert_true(layer.chunks.has(HERE), "which makes the chunk again")
    assert_eq(_digest(layer.get_field(HERE, SaFieldSpec.ALBEDO)), painted, "holding the stroke as painted, texel for texel")
    assert_true(_doc.redo(), "The erase redoes")
    assert_true(_all_zero(layer.get_field(HERE, SaFieldSpec.ALBEDO)), "and the chunk reads clear again")
    assert_eq(_doc.history.step_count(), steps, "The undo and the redo leave the step count as it was")
    assert_true(_save(second), "The next save lands")
    assert_false(HERE in _listed_for(second, "stroked"), "and lists no chunk there either")
    assert_false(layer.chunks.has(HERE), "and lets it go again")


func test_an_erase_on_a_layer_s_own_mask_comes_back_on_undo() -> void:
    var layer := _layer("masked")
    _stroke(Vector2(100.0, 100.0), 30.0, RED)
    var mask := layer.add_mask()
    _doc.mask_target = mask
    _stroke(MIDDLE, 30.0, HIDE)
    assert_true(layer.chunks.has(HERE), "The mask stroke made a chunk of the layer")
    var hidden := _digest(mask.texture_for(HERE))
    _stroke(MIDDLE, 90.0, Color(1.0, 1.0, 1.0, 1.0))
    var shown := mask.texture_for(HERE)
    assert_true(_reads(shown, 1.0), "A wider stroke that shows whole leaves the mask exactly at its rest")
    _doc.mask_target = null
    var steps := _doc.history.step_count()
    assert_true(_save(first), "The save lands")
    assert_false(HERE in _listed_for(first, "masked"), "The header lists no chunk where colour is clear and the mask at rest")
    assert_false(layer.chunks.has(HERE), "and the layer let it go")
    assert_true(_doc.undo(), "The mask's showing stroke undoes")
    assert_true(layer.chunks.has(HERE), "which makes the chunk again")
    assert_eq(_digest(mask.texture_for(HERE)), hidden, "with the mask as the hiding stroke left it")
    assert_true(_doc.redo(), "and redoes")
    assert_true(_reads(mask.texture_for(HERE), 1.0), "to the mask at rest")
    assert_eq(_doc.history.step_count(), steps, "The step count is as it was")
    assert_true(_save(second), "The next save lands")
    assert_false(HERE in _listed_for(second, "masked"), "and lists none there")


func test_an_erase_on_a_group_s_own_mask_comes_back_on_undo() -> void:
    var member := _layer("held")
    _stroke(Vector2(100.0, 100.0), 30.0, RED)
    var group := SaLayerGroups.new(_doc).group_layers([member])
    group.name = "holding"
    var mask := group.add_mask()
    _doc.mask_target = mask
    _stroke(MIDDLE, 30.0, HIDE)
    var hidden := _digest(mask.texture_for(HERE))
    _stroke(MIDDLE, 90.0, Color(1.0, 1.0, 1.0, 1.0))
    assert_true(_reads(mask.texture_for(HERE), 1.0), "A wider stroke that shows whole leaves the group's mask at its rest")
    _doc.mask_target = null
    var steps := _doc.history.step_count()
    assert_true(_save(first), "The save lands")
    assert_false(HERE in mask.grid_positions(), "The group's mask let the chunk at rest go")
    assert_true(_doc.undo(), "The showing stroke undoes")
    assert_eq(_digest(mask.texture_for(HERE)), hidden, "and the chunk is made again as the hiding stroke left it")
    assert_true(_doc.redo(), "and redoes")
    assert_true(_reads(mask.texture_for(HERE), 1.0), "to the mask at rest")
    assert_eq(_doc.history.step_count(), steps, "The step count is as it was")
    assert_true(_save(second), "The next save lands")
    var listed := _listed(SaTyped.strings(_entry(_header(second), "holding").get("mask", {})).get("chunks", []))
    assert_false(HERE in listed, "and lists none there")


func test_the_painter_s_rounding_save_and_the_door_s_save_at_once_leave_it_out_alike() -> void:
    var layer := _layer("either")
    _stroke(MIDDLE, 40.0, RED)
    _stroke(Vector2(100.0, 400.0), 30.0, RED)
    _erase(layer, HERE)
    assert_eq(SaExport.save_sad(_doc, second, 0, null, true), OK, "The save at once lands")
    assert_false(HERE in _listed_for(second, "either"), "and lists no chunk where the paint was erased")
    assert_true(KEPT in _listed_for(second, "either"), "but the painted one")
    assert_false(layer.chunks.has(HERE), "and the layer let it go")
    _erase(layer, KEPT)
    assert_true(_save(first, true), "The painter's save, which rounds, lands")
    assert_eq(_listed_for(first, "either"), [] as Array[Vector2i], "and lists none of the layer's emptied chunks")
    assert_true(layer.chunks.is_empty(), "and the layer holds none")


## Whether every texel of *texture*'s first channel is exactly *value*.
static func _reads(texture: SaTexture, value: float) -> bool:
    if texture == null:
        return false
    var bytes := _bytes(texture)
    var channels := 1 if texture.format == RenderingDevice.DATA_FORMAT_R32_SFLOAT else 0
    if channels == 0:
        for index in texture.size.x * texture.size.y:
            if SaFieldSpec.decode_texel(bytes, texture.format, index).r != value:
                return false
        return true
    for at in range(0, bytes.size(), 4):
        if bytes.decode_float(at) != value:
            return false
    return true


func test_a_chunk_that_holds_anything_is_kept() -> void:
    var hiding := _layer("hiding")
    hiding.get_or_create_chunk(HERE)
    hiding.add_mask()
    hiding.get_field(HERE, SaFieldSpec.MASK).clear(Color(0.0, 0.0, 0.0, 0.0))
    var raised := _layer("raised")
    var with_height: Array[SaFieldSpec] = raised.schema.duplicate()
    with_height.append(SaFieldSpec.height())
    raised.schema = with_height
    raised.get_or_create_chunk(HERE)
    var height := raised.get_or_create_field(HERE, SaFieldSpec.HEIGHT)
    var bump := _bytes(height)
    bump.encode_float(bump.size() - 4, 0.25)
    GlobalShaderCompiler.get_rd().texture_update(height.rid, 0, bump)
    var unseen := _layer("unseen")
    unseen.get_or_create_chunk(HERE)
    unseen.get_field(HERE, SaFieldSpec.ALBEDO).clear(Color(0.3, 0.6, 0.9, 0.0))
    var resting := _layer("resting")
    resting.get_or_create_chunk(HERE)
    resting.add_mask(0.0)
    resting.mask.rest = 0.0
    var picture := _picture(_doc)
    assert_true(_save(first), "The save lands")
    for called: String in ["hiding", "raised", "unseen"]:
        assert_true(HERE in _listed_for(first, called), "%s: the header keeps the chunk" % called)
        assert_true(_named(_doc, called).chunks.has(HERE), "%s: and so does the layer" % called)
    assert_false(HERE in _listed_for(first, "resting"), "A mask at zero is blank where the mask rests at zero")
    assert_false(resting.chunks.has(HERE), "and the layer lets that chunk go")
    var back := _reopened(first)
    assert_not_null(back, "The file opens")
    if back == null:
        return
    var differing := _differences(_picture(back), _without(picture, {"resting": [HERE]}))
    assert_eq(differing, [] as Array[String], "and reads as painted, texel for texel")
    var reopened_resting := _named(back, "resting")
    assert_eq(reopened_resting.mask.rest, 0.0, "The layer whose mask rests at zero reopens resting there")
    assert_true(_reads(reopened_resting.mask.coverage(HERE), 0.0), "and reads zero where its chunk was")
    back.free()


func test_a_group_s_own_mask_at_rest_is_left_out_and_reopens_equal() -> void:
    var member := _layer("member")
    _stroke(MIDDLE, 30.0, RED)
    var group := SaLayerGroups.new(_doc).group_layers([member])
    group.name = "grouped"
    var mask := group.add_mask()
    mask.get_or_create(HERE)
    mask.get_or_create(KEPT).clear(Color(0.25, 0.25, 0.25, 0.25))
    assert_true(_save(first), "The save lands")
    var listed := _listed(SaTyped.strings(_entry(_header(first), "grouped").get("mask", {})).get("chunks", []))
    assert_false(HERE in listed, "The group's mask chunk at rest is not listed")
    assert_true(KEPT in listed, "and the one that hides part is")
    assert_false(HERE in mask.grid_positions(), "The live mask let its chunk at rest go")
    var back := _reopened(first)
    assert_not_null(back, "The file opens")
    if back == null:
        return
    var reopened := _named(back, "grouped").mask
    assert_null(reopened.texture_for(HERE), "The reopened mask holds nothing there, so it reads its rest")
    assert_eq(reopened.rest, mask.rest, "which is the rest the live mask has")
    assert_eq(_digest(reopened.texture_for(KEPT)), _digest(mask.texture_for(KEPT)), "and the hiding chunk is equal")
    back.free()


func test_paint_after_the_snapshot_keeps_the_chunk_for_the_next_save() -> void:
    var layer := _layer("late")
    layer.get_or_create_chunk(HERE)
    SaSadFile.save_in_background(_doc, first, 0, null, true, Callable(), false)
    _stroke(MIDDLE, 30.0, RED)
    var painted := _digest(layer.get_field(HERE, SaFieldSpec.ALBEDO))
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_false(HERE in _listed_for(first, "late"), "The file is of the snapshot, where the chunk was clear")
    assert_true(layer.chunks.has(HERE), "The layer keeps the chunk painted after the snapshot")
    assert_eq(_digest(layer.get_field(HERE, SaFieldSpec.ALBEDO)), painted, "with the new paint in it")
    assert_true(_save(second), "The next save lands")
    assert_true(HERE in _listed_for(second, "late"), "and lists the chunk")


func test_a_stroke_open_at_the_snapshot_keeps_the_chunk() -> void:
    var layer := _layer("open")
    layer.get_or_create_chunk(HERE)
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    _dab(MIDDLE, 30.0, RED)
    SaSadFile.save_in_background(_doc, first, 0, null, true, Callable(), false)
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_false(HERE in _listed_for(first, "open"), "The file leaves the clear chunk out")
    assert_true(layer.chunks.has(HERE), "and the layer keeps it while the stroke is open")
    _doc.commit_stroke()
    assert_true(_save(second), "The next save lands")
    assert_true(HERE in _listed_for(second, "open"), "and lists the chunk the stroke painted")


## An autosave walks once its hashes are in, so a stroke laid while
## they are owed is in the working file, and the layer keeps its chunk either way.
func test_an_autosave_lists_a_chunk_painted_before_its_walk() -> void:
    var layer := _layer("autosaved")
    layer.get_or_create_chunk(HERE)
    _doc.file_path = first
    var autosave := SaAutosave.new()
    autosave.follow_settings = false
    autosave.attach(_doc)
    autosave.write_working_file = true
    _doc.modified = true
    assert_eq(autosave.save_now(), OK, "The autosave is asked for")
    _stroke(MIDDLE, 30.0, RED)
    assert_true(SaSadFile.finish_saves(), "and ends")
    assert_true(HERE in _listed_for(first, "autosaved"), "The working file lists the chunk painted before the walk")
    assert_true(layer.chunks.has(HERE), "and the layer keeps it")
    assert_eq(autosave.save_now(), OK, "A second autosave is asked for")
    assert_true(SaSadFile.finish_saves(), "and ends")
    assert_true(HERE in _listed_for(first, "autosaved"), "and lists it still")
    autosave.free()


func test_the_chunks_after_a_save_are_fewer_by_exactly_the_ones_emptied() -> void:
    var names: Array[String] = ["one", "two", "three"]
    var emptied := {}
    for index in names.size():
        var layer := _layer(names[index])
        _stroke(MIDDLE, 30.0, RED)
        _stroke(Vector2(100.0, 400.0), 30.0, RED)
        _stroke(Vector2(400.0, 400.0), 30.0, RED)
        var gone: Array[Vector2i] = []
        for grid_pos: Vector2i in [HERE, Vector2i(1, 1)].slice(0, index):
            _erase(layer, grid_pos)
            gone.append(grid_pos)
        emptied[names[index]] = gone
    var before := 0
    var emptied_count := 0
    for called in names:
        before += _named(_doc, called).chunks.size()
        emptied_count += (emptied[called] as Array).size()
    assert_eq(before, 3 * names.size(), "Before the save every layer holds the three chunks its strokes made")
    var picture := _picture(_doc)
    assert_true(_save(first), "The save lands")
    var after := 0
    var listed := 0
    for called in names:
        after += _named(_doc, called).chunks.size()
        listed += _listed_for(first, called).size()
        for grid_pos: Vector2i in emptied[called]:
            assert_false(_named(_doc, called).chunks.has(grid_pos), "%s: the chunk emptied at %s is gone" % [called, grid_pos])
    assert_eq(after, before - emptied_count, "After it the layers hold fewer by exactly the chunks emptied")
    assert_eq(listed, after, "and the header lists as many as the layers hold")
    var back := _reopened(first)
    assert_not_null(back, "The file opens")
    if back != null:
        var differing := _differences(_picture(back), _without(picture, emptied))
        assert_eq(differing, [] as Array[String], "and every other chunk reopens equal")
        back.free()
