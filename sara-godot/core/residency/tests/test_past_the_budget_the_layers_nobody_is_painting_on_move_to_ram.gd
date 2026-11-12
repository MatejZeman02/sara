## Past the budget, the layers nobody is painting on move to
## RAM and come back before they are read.
##
## The same strokes are painted twice, once on a stood-in card of 0, which has
## no budget, and once on a card so small that its budget is three MiB, which
## every painting here is past. Whatever reads the second document, the
## compositor, the export, the save, a wand click, a merge and a layer switch,
## has to find what the first one holds.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

## A card of 1 GiB and 4 MiB. Its margin is the whole GiB, so the limit is
## the 4 MiB and the budget three quarters of that.
const SMALL_CARD := (1 << 30) + (4 << 20)
const SIZE := Vector2i(1024, 768)
const GROUND := Color(0.85, 0.8, 0.7, 1.0)
const COLOURS: Array[Color] = [Color(0.8, 0.1, 0.1, 1.0), Color(0.1, 0.6, 0.2, 0.7), Color(0.1, 0.2, 0.9, 0.5)]

var _easels: Array[SaEasel] = []
var _surfaces: Array[SaSurface] = []
var _machines: Array[ToolMachine] = []
var _share_before := 0.0
var _folder := ""


func before_each() -> void:
    _share_before = SaSettings.card_memory_share
    SaSettings.card_memory_share = SaSettings.MAX_CARD_MEMORY_SHARE
    _folder = SaDataRoot.path("%d" % Time.get_ticks_usec())
    DirAccess.make_dir_recursive_absolute(_folder)


func after_each() -> void:
    SaCardMemory.stand_in(-1)
    SaSettings.card_memory_share = _share_before
    for easel in _easels:
        easel.free()
    _easels.clear()
    for index in _surfaces.size():
        Fixtures.teardown(_surfaces[index], _machines[index])
    _surfaces.clear()
    _machines.clear()
    for file in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(file))
    DirAccess.remove_absolute(_folder)


## One hard dab of *colour* on *doc*'s active layer, opened and committed as
## the brush does, so its release settles the document.
func _stroke(doc: SaDocument, pos: Vector2, radius: float, colour: Color) -> void:
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    _dab(doc, pos, radius, colour)
    doc.commit_stroke()


func _dab(doc: SaDocument, pos: Vector2, radius: float, colour: Color) -> void:
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
    var paint := SaPaintContext.for_region(doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, colour, radius, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()


## Four layers across many chunks: a ground over the whole canvas and three
## layers each painted in a band of dabs crossing the chunks' seams, on a card
## of *card* bytes.
func _paint(doc: SaDocument, card: int) -> void:
    SaCardMemory.stand_in(card)
    doc.fill_layer(GROUND, doc.active_layer)
    for index in COLOURS.size():
        SaLayerOps.new(doc).add()
        for step in 6:
            var pos := Vector2(80.0 + step * 170.0, 120.0 + index * 230.0 + step * 20.0)
            _stroke(doc, pos, 70.0, COLOURS[index])


func _painted_easel(card: int) -> SaEasel:
    var easel := SaEasel.create_default(SIZE)
    _easels.append(easel)
    _paint(easel.document, card)
    return easel


## The whole canvas composited again from the layers, the fold rebuilt, so
## every layer's chunks are read.
func _composite(easel: SaEasel) -> PackedByteArray:
    var doc := easel.document
    doc.fold.rebuild(doc, doc.compositor, Rect2(Vector2.ZERO, Vector2(doc.canvas_size)))
    doc.invalidate_all_allocated_chunks()
    easel.process_pending_composite()
    return SaExport.get_easel_image_float(easel).get_data()


func _stored_in(doc: SaDocument) -> int:
    var count := 0
    for layer: SaLayer in SaResidency.candidates(doc):
        for chunk: SaChunk in layer.chunks.values():
            if chunk.is_stored():
                count += 1
    if doc.active_layer != null:
        for chunk: SaChunk in doc.active_layer.chunks.values():
            if chunk.is_stored():
                count += 1
    return count


func _png(easel: SaEasel) -> PackedByteArray:
    var said := SaExportMetadata.new("probe", 1760000000)
    return SaExport.png_bytes(easel.output, easel.document.color_space, 8, PackedFloat32Array(), SaGamutMapping.CLIP, said)


func test_four_layers_past_the_budget_composite_export_and_save_as_with_none() -> void:
    var plain := _painted_easel(0)
    var tight := _painted_easel(SMALL_CARD)
    assert_eq(_stored_in(plain.document), 0, "with no budget nothing goes to RAM")
    var evicted := _stored_in(tight.document)
    assert_true(evicted > 0, "past the budget the layers nobody paints on are in RAM, %d chunks" % evicted)
    assert_true(SaCardMemory.held() > SaMemoryBudget.budget(), "the painting ends over the budget")
    assert_eq(_stored_in_layer(tight.document.active_layer), 0, "the layer painted on keeps its chunks")
    SaCardMemory.stand_in(0)

    var expected := _composite(plain)
    assert_eq(_composite(tight), expected, "the composite reads the same pixels")
    assert_true(_stored_in(tight.document) < evicted, "and brought the chunks it read back")
    SaResidency.settle(tight.document, 1)
    assert_true(_stored_in(tight.document) > 0, "evicted again before the export")
    assert_eq(_composite(tight), expected, "composited again from RAM")
    var png := _png(tight)
    assert_true(png.size() > 0, "the export wrote a file")
    assert_eq(png, _png(plain), "the export's file is equal byte for byte")

    SaResidency.settle(tight.document, 1)
    assert_true(_stored_in(tight.document) > 0, "evicted again before the save")
    var tight_path := _folder.path_join("tight.sad")
    var plain_path := _folder.path_join("plain.sad")
    assert_eq(SaSadFile.save_file(tight.document, tight_path), OK, "the evicted document saves")
    assert_eq(SaSadFile.save_file(plain.document, plain_path), OK, "and so does the plain one")
    var opened_tight := SaEasel.create_default(SIZE)
    var opened_plain := SaEasel.create_default(SIZE)
    _easels.append(opened_tight)
    _easels.append(opened_plain)
    assert_eq(SaSadFile.load_file(opened_tight.document, tight_path), OK, "the saved file opens")
    assert_eq(SaSadFile.load_file(opened_plain.document, plain_path), OK, "beside the plain one")
    var reopened := _composite(opened_tight)
    assert_eq(reopened, _composite(opened_plain), "to the same pixels as the plain document's file")
    assert_eq(reopened, expected, "which are the painting's")


func _stored_in_layer(layer: SaLayer) -> int:
    var count := 0
    for chunk: SaChunk in layer.chunks.values():
        if chunk.is_stored():
            count += 1
    return count


func test_an_eviction_gives_back_the_chunks_bytes_and_keeps_less_in_ram() -> void:
    SaCardMemory.stand_in(0)
    var easel := SaEasel.create_default(Vector2i(1024, 512))
    _easels.append(easel)
    var doc := easel.document
    doc.fill_layer(GROUND, doc.active_layer)
    for colour: Color in COLOURS:
        SaLayerOps.new(doc).add()
        doc.fill_layer(colour, doc.active_layer)
    _stroke(doc, Vector2(256, 256), 60.0, COLOURS[0])
    var painted := doc.active_layer
    var had := painted.chunks.keys()
    var expected := 0
    var chunks: Array[SaChunk] = []
    for layer: SaLayer in SaResidency.candidates(doc):
        for chunk: SaChunk in layer.chunks.values():
            expected += chunk.byte_size()
            chunks.append(chunk)
    assert_true(chunks.size() >= 24, "three flat layers of eight chunks each, %d" % chunks.size())
    # The history's snapshots go to RAM before any layer's chunks now,
    # so a budget of one byte takes them as well.
    var snapshots := 0
    for state: Dictionary in doc.history.snapshot_states():
        for entry: Variant in state.values():
            if entry is SaChunk and (entry as SaChunk).byte_size() > 0:
                expected += (entry as SaChunk).byte_size()
                snapshots += 1
            elif entry is SaChunkDelta and (entry as SaChunkDelta).byte_size() > 0:
                expected += (entry as SaChunkDelta).byte_size()
                snapshots += 1

    var before := SaTexture.allocated_bytes
    var stored_before := SaChunk.stored_count
    var reads := SaResidency.readbacks
    assert_eq(SaResidency.settle(doc, 1), chunks.size() + snapshots, "every chunk of the layers not painted on moves")
    assert_eq(before - SaTexture.allocated_bytes, expected, "and the card holds exactly their bytes less")
    assert_eq(SaChunk.stored_count - stored_before, chunks.size(), "they are counted in RAM")
    assert_true(SaResidency.readbacks > reads, "read back by the eviction file")
    for chunk in chunks:
        assert_true(chunk.is_stored(), "each chunk is in RAM")
        var raw := 0
        for field_id: StringName in chunk.stored.raw_sizes:
            raw += chunk.stored.raw_sizes[field_id]
        var kept := chunk.stored.bytes()
        assert_true(kept * 10 < raw, "a flat chunk keeps far less than its raw %d bytes, %d" % [raw, kept])
        assert_eq(chunk.byte_size(), 0, "and holds nothing on the card")
    assert_eq(painted.chunks.keys(), had, "the layer being painted holds every chunk it had")
    for chunk: SaChunk in painted.chunks.values():
        assert_false(chunk.is_stored(), "on the card")
        assert_true(chunk.byte_size() > 0, "with its textures")


func test_nothing_moves_between_a_press_and_its_release() -> void:
    var easel := _painted_easel(0)
    var doc := easel.document
    SaCardMemory.stand_in(SMALL_CARD)
    var stored := SaChunk.stored_count
    var reads := SaResidency.readbacks
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    assert_eq(SaChunk.stored_count, stored, "the press moves nothing")
    for step in 4:
        _dab(doc, Vector2(100.0 + step * 200.0, 600.0), 50.0, COLOURS[0])
        assert_eq(SaResidency.settle(doc), 0, "a settle asked mid stroke moves nothing")
        assert_eq(SaChunk.stored_count, stored, "no chunk goes to RAM mid stroke")
        assert_eq(SaResidency.readbacks, reads, "and nothing is read back")
    assert_true(SaCardMemory.held() > SaMemoryBudget.budget(), "though the stroke is held over the budget")
    doc.commit_stroke()
    assert_true(SaChunk.stored_count > stored, "the release moves chunks")
    assert_true(SaResidency.readbacks > reads, "reading them back")


func test_a_spared_document_keeps_its_chunks_past_the_budget() -> void:
    var easel := _painted_easel(0)
    var doc := easel.document
    SaResidency.spare(doc)
    SaCardMemory.stand_in(SMALL_CARD)
    var stored := SaChunk.stored_count
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    _dab(doc, Vector2(300.0, 300.0), 50.0, COLOURS[0])
    doc.commit_stroke()
    assert_true(SaCardMemory.held() > SaMemoryBudget.budget(), "the release ends over the budget")
    assert_eq(SaChunk.stored_count, stored, "and a preset thumbnail's kind of document moves nothing")


## Paints both documents, evicts the second whole but its active layer, and
## answers the layer below the active one in each.
func _evicted_pair(card: int) -> Array[SaEasel]:
    var plain := _painted_easel(0)
    var tight := _painted_easel(card)
    SaCardMemory.stand_in(0)
    SaResidency.settle(tight.document, 1)
    return [plain, tight]


func _layer_below(doc: SaDocument) -> SaLayer:
    var layers := SaLayerOps.new(doc).layers()
    return layers[layers.find(doc.active_layer) - 1]


func test_a_layer_switch_meets_an_evicted_chunk() -> void:
    var pair := _evicted_pair(SMALL_CARD)
    var expected := _composite(pair[0])
    var tight := pair[1].document
    var below := _layer_below(tight)
    assert_true(_stored_in_layer(below) > 0, "the layer switched to is in RAM")
    tight.set_active_layer(below)
    pair[0].document.set_active_layer(_layer_below(pair[0].document))
    assert_eq(_composite(pair[1]), expected, "the canvas reads the same after the switch")
    _stroke(tight, Vector2(500, 380), 30.0, COLOURS[2])
    _stroke(pair[0].document, Vector2(500, 380), 30.0, COLOURS[2])
    assert_eq(_composite(pair[1]), _composite(pair[0]), "and a stroke on the switched layer lands alike")


func test_a_merge_meets_an_evicted_chunk() -> void:
    var pair := _evicted_pair(SMALL_CARD)
    for easel in pair:
        var doc := easel.document
        var below := _layer_below(doc)
        doc.set_active_layer(below)
        assert_true(SaLayerOps.new(doc).merge_down(below), "the merge runs")
    assert_eq(_composite(pair[1]), _composite(pair[0]), "the merged canvas reads the same")
    var merged_plain := pair[0].document.active_layer
    var merged_tight := pair[1].document.active_layer
    assert_eq(merged_tight.chunks.keys(), merged_plain.chunks.keys(), "the merged layer holds the same chunks")
    var rd := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in merged_plain.chunks:
        var a := rd.texture_get_data(merged_plain.chunks[grid_pos].albedo().rid, 0)
        var b := rd.texture_get_data(merged_tight.chunks[grid_pos].albedo().rid, 0)
        assert_eq(b, a, "with the same texels at %s" % grid_pos)


func test_a_wand_click_meets_an_evicted_chunk() -> void:
    var masks: Array[Dictionary] = []
    for card: int in [0, SMALL_CARD]:
        var surface := Fixtures.make_surface(SIZE)
        var machine := Fixtures.make_bound_machine(surface)
        _surfaces.append(surface)
        _machines.append(machine)
        var doc := surface.get_document()
        _paint(doc, card)
        SaCardMemory.stand_in(0)
        if card > 0:
            SaResidency.settle(doc, 1)
        var below := _layer_below(doc)
        doc.set_active_layer(below)
        if card > 0:
            assert_true(_stored_in_layer(below) > 0, "the wand's layer is in RAM")
        machine.set_active_tool(&"wand")
        machine.active_tool.sample_merged = false
        surface.view.mouse_position = Vector2(80, 350)
        machine.active_tool.handle_input(_button(true))
        machine.active_tool.handle_input(_button(false))
        assert_true(doc.selection.active, "the click selected")
        masks.append(_mask(doc))
    assert_eq(masks[1].keys(), masks[0].keys(), "the wand selects the same chunks")
    for grid_pos: Vector2i in masks[0]:
        assert_eq(masks[1][grid_pos], masks[0][grid_pos], "and the same coverage at %s" % grid_pos)


func _mask(doc: SaDocument) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in doc.selection.chunks:
        var texture := (doc.selection.chunks[grid_pos] as SaChunk).field(SaSelection.FIELD)
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return out


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
