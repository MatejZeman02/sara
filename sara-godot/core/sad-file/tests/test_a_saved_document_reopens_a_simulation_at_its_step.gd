## A saved document reopens a simulation at its step.
##
## The layer's entry keeps the record, the rule's key and its module's id, the
## parameters, the count, the speed, the domain, the ring and the seed as chunk
## blobs, while the layer's chunks are the state at that step. So a document
## opened again reads the step and the texels it was saved at, steps on as the
## unsaved one does, and Reset reaches the paint as it was before any step. A
## rule whose module is missing is kept as data and written back as it was.
##
## Spread is the base module's, registered through the call a stranger uses,
## and `shift_right` is a test rule, registered here under a module of the
## suite's own that the suite then takes away.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## Two chunks side by side, so the paint has an edge to spread across.
const SIZE := Vector2i(512, 256)
## A square in the first chunk, four texels from its right edge.
const SQUARE := Rect2i(244, 100, 8, 8)
const OCHRE := Color(0.8, 0.4, 0.2, 1.0)
## Four texels left of the square, where only Spread puts paint.
const BESIDE := Vector2i(240, 104)
const FLOW := 0.25
const GONE_MODULE := &"k8-gone"
const TOLERANCE := 1.0e-3

var _registries: SaRegistries = null
var _easels: Array[SaEasel] = []
var _paths: Array[String] = []


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _registries = Fixtures.make_registries()
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))
    var gone := _registries.context.for_module(GONE_MODULE)
    gone.register_simulation_rule(&"shift_right", "Shift Right", "sara/simulation_test_rules", "shift_right", 1)


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()
    for path in _paths:
        DirAccess.remove_absolute(path)
    _paths.clear()
    SaProblems.pending_refusals = PackedStringArray()


func _easel() -> SaEasel:
    var made := Bench.easel(SIZE)
    _easels.append(made)
    return made


func _path(file_name: String) -> String:
    var path := ProjectSettings.globalize_path(SaDataRoot.path(file_name))
    _paths.append(path)
    return path


## A paint layer called Simulated over the easel's own, active, holding the
## ochre square in its first chunk and nothing else.
func _painted(easel: SaEasel) -> SaLayer:
    var document := easel.document
    var layer := SaLayerOps.new(document).add(&"")
    layer.name = "Simulated"
    document.set_active_layer(layer)
    var texture := layer.get_or_create_chunk(Vector2i(0, 0)).albedo()
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))
    image.fill_rect(SQUARE, OCHRE)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    return layer


func _step(layer: SaLayer, times: int) -> void:
    var document := layer.get_parent() as SaDocument
    for _i in times:
        assert_true(SaSimulation.step(document, layer, _registries.simulation_rules), "The step is taken")


## Every chunk of *layer*, grid position to the bytes of its `albedo`.
func _bytes(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.get_field(grid_pos).rid, 0)
    return out


func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var side := layer.get_field(Vector2i(0, 0)).size.x
    var grid_pos := Vector2i(floori(at.x / float(side)), floori(at.y / float(side)))
    return Bench.texel(layer.get_field(grid_pos), at - grid_pos * side)


## *easel*'s picture written by the EXR export as a float file and read back.
func _exported(easel: SaEasel, file_name: String) -> Image:
    var path := _path(file_name)
    assert_eq(SaExport.export_exr(easel, path), OK, "%s is written" % file_name)
    return Image.load_from_file(path)


func _reopened(path: String) -> SaLayer:
    var easel := _easel()
    assert_eq(SaExport.load_sad(easel.document, path, easel.compositor), OK, "The file opens")
    return easel.document.get_node_or_null("Simulated") as SaLayer


## The header and the blob region of the `.sad` at *path*, as the v4 reader
## lays them out.
func _container(path: String) -> Array:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    file.get_32()
    var packed_size := file.get_32()
    var raw_size := file.get_32()
    var header := file.get_buffer(packed_size).decompress(raw_size, SaSadFile.SAD_BLOB_COMPRESS)
    var blobs := file.get_buffer(file.get_length() - file.get_position())
    file.close()
    return [SaTyped.strings(JSON.parse_string(header.get_string_from_utf8())), blobs]


## The `"simulation"` key of the layer called Simulated in the file at *path*,
## with the seed's offsets taken out, and the seed's bytes, grid position to
## the decompressed blob.
func _entry(path: String) -> Array:
    var opened := _container(path)
    var header: Dictionary = opened[0]
    var blobs: PackedByteArray = opened[1]
    for raw_layer: Variant in header.get("layers", []):
        var layer_data := SaTyped.strings(raw_layer)
        if layer_data.get("name") != "Simulated":
            continue
        var entry: Dictionary = SaTyped.strings(layer_data.get("simulation")).duplicate(true)
        var seed_bytes := {}
        for slot: Dictionary in entry.get("seed", []):
            var offset := SaTyped.int_at(slot, "offset", 0)
            var packed := blobs.slice(offset, offset + SaTyped.int_at(slot, "size", 0))
            seed_bytes[[slot["x"], slot["y"]]] = packed.decompress(
                SaTyped.int_at(slot, "raw_size", 0), SaSadFile.SAD_BLOB_COMPRESS
            )
            slot.erase("offset")
        return [entry, seed_bytes]
    return [{}, {}]


func test_spread_stepped_to_fifty_reopens_at_fifty_with_its_texels_and_resets_to_its_seed() -> void:
    var easel := _easel()
    var layer := _painted(easel)
    var painted := _bytes(layer)
    var spread := _registries.simulation_rules.find(&"spread")
    assert_not_null(SaSimulation.put_on(layer, spread, {"flow": FLOW}), "Spread goes on")
    _step(layer, 50)
    assert_true(_texel(layer, BESIDE).a > 0.0, "Fifty steps spread paint where there was none, %s" % _texel(layer, BESIDE))
    var stepped := _bytes(layer)
    assert_eq(stepped.size(), 2, "and the ring holds both chunks of the canvas")
    assert_eq(SaSadFile.version_for(easel.document), SaSadFile.SAD_VERSION_SIMULATION, "A simulation stamps the file 13")
    assert_eq(SaSadFile.SAD_VERSION_SIMULATION, 13, "the version after 12")
    var path := _path("k8_spread_at_fifty.sad")
    assert_eq(SaExport.save_sad(easel.document, path, 0), OK, "It saves")
    assert_eq(SaSadFile.version_at(path), SaSadFile.SAD_VERSION_PLANES, "at the planes' stamp above it")

    var reopened := _reopened(path)
    assert_not_null(reopened, "The simulated layer is in the file")
    var record := SaSimulation.record_of(reopened)
    assert_not_null(record, "with its simulation")
    if reopened == null or record == null:
        return
    assert_eq(record.rule, &"spread", "Spread")
    assert_eq(record.module, &"sara-base-modules", "of the base module")
    assert_almost_eq(float(record.params.get("flow", 0.0)), FLOW, 1.0e-6, "at the flow it was given")
    assert_eq(record.steps, 50, "at step fifty")
    assert_false(record.playing, "and paused")
    assert_eq(_bytes(reopened), stepped, "holding the texels of step fifty, every chunk bit for bit")
    assert_eq(SaSimulation.missing(reopened, _registries.simulation_rules), "", "The rule is registered, so nothing is missing")

    _step(layer, 1)
    _step(reopened, 1)
    assert_eq(_bytes(reopened), _bytes(layer), "Stepped once more it is the picture the unsaved document steps to")
    assert_eq(record.steps, 51, "at step 51")

    var document := reopened.get_parent() as SaDocument
    assert_true(SaSimulation.reset(document, reopened), "Reset is taken")
    assert_eq(record.steps, 0, "and counts from nought")
    assert_eq(_bytes(reopened), painted, "and reaches the seed, the square as painted and the first chunk alone")


func test_flatten_and_export_take_the_paint_as_it_stands_at_its_step() -> void:
    var easel := _easel()
    var layer := _painted(easel)
    SaSimulation.put_on(layer, _registries.simulation_rules.find(&"spread"), {"flow": FLOW})
    _step(layer, 50)
    Bench.composite(easel)
    var shown := Bench.texel(easel.output, BESIDE)
    var path := _path("k8_spread_exported.sad")
    assert_eq(SaExport.save_sad(easel.document, path, 0), OK, "It saves")
    var reopened := _reopened(path)
    var loaded := _easels[-1]
    Bench.composite(loaded)
    var unsaved := _exported(easel, "k8_spread_unsaved.exr")
    var exported := _exported(loaded, "k8_spread_reopened.exr")
    assert_not_null(exported, "The reopened document exports")
    if unsaved == null or exported == null:
        return
    var export_read := exported.get_pixelv(BESIDE)
    assert_true(_near(export_read, unsaved.get_pixelv(BESIDE)), "The export holds step fifty's colour, %s" % export_read)
    assert_eq(exported.get_data(), unsaved.get_data(), "and is the unsaved document's export at step fifty, every pixel")
    assert_false(_near(export_read, exported.get_pixel(20, 20)), "with the spread paint where the seed held none")
    assert_true(SaLayerOps.new(loaded.document).flatten(), "Flatten is taken")
    var flat := loaded.document.active_layer
    assert_false(flat == reopened, "into one layer")
    Bench.composite(loaded)
    var flattened := Bench.texel(loaded.output, BESIDE)
    assert_true(_near(flattened, shown), "and draws the paint as it stood at step fifty, %s against %s" % [flattened, shown])


func test_a_rule_whose_module_is_missing_keeps_its_record_and_saves_it_back_unchanged() -> void:
    var easel := _easel()
    var layer := _painted(easel)
    var record := SaSimulation.put_on(layer, _registries.simulation_rules.find(&"shift_right"), {"lean": 0.5})
    _step(layer, 5)
    record.speed = 24.0
    record.domain = Rect2i(0, 64, 512, 128)
    var moved := _texel(layer, SQUARE.position + Vector2i(5, 0))
    var first := _path("k8_gone_first.sad")
    assert_eq(SaExport.save_sad(easel.document, first, 0), OK, "It saves")

    _registries.simulation_rules.unregister_module(GONE_MODULE)
    assert_null(_registries.simulation_rules.find(&"shift_right"), "The module that registered the rule is gone")
    var reopened := _reopened(first)
    var kept := SaSimulation.record_of(reopened)
    assert_not_null(kept, "The record is kept")
    if kept == null:
        return
    assert_eq(kept.rule, &"shift_right", "naming its rule")
    assert_eq(kept.module, GONE_MODULE, "and the module it needs")
    assert_eq(kept.steps, 5, "at its step")
    assert_almost_eq(kept.speed, 24.0, 1.0e-6, "its speed")
    assert_eq(kept.domain, Rect2i(0, 64, 512, 128), "and its domain")
    assert_almost_eq(float(kept.params.get("lean", 0.0)), 0.5, 1.0e-6, "with its parameters")
    assert_true(_near(_texel(reopened, SQUARE.position + Vector2i(5, 0)), moved), "The layer shows its paint at step five")
    var said := SaSimulation.missing(reopened, _registries.simulation_rules)
    assert_true(said.contains(String(GONE_MODULE)), "The line the panel shows names the module, '%s'" % said)
    var document := reopened.get_parent() as SaDocument
    assert_false(SaSimulation.step(document, reopened, _registries.simulation_rules), "A step is refused")
    var refused := "\n".join(SaProblems.pending_refusals)
    assert_true(refused.contains("shift_right"), "and the refusal names the rule, '%s'" % refused)
    assert_eq(kept.steps, 5, "and the count stands")

    var second := _path("k8_gone_second.sad")
    assert_eq(SaExport.save_sad(document, second, 0), OK, "It saves again")
    assert_eq(SaSadFile.version_at(second), SaSadFile.SAD_VERSION_PLANES, "at the planes' stamp above the simulation's")
    var before := _entry(first)
    var after := _entry(second)
    assert_false((before[0] as Dictionary).is_empty(), "The first file holds the record")
    assert_eq(after[0], before[0], "and the second the same record, %s" % JSON.stringify(after[0]))
    assert_eq((before[1] as Dictionary).size(), 1, "with a seed of one chunk")
    assert_eq(after[1], before[1], "whose bytes are the same")


func test_a_document_with_no_simulation_keeps_its_stamp_and_an_older_file_opens_with_none() -> void:
    var easel := _easel()
    _painted(easel)
    assert_true(SaSadFile.version_for(easel.document) < SaSadFile.SAD_VERSION_SIMULATION, "No simulation, no new stamp")
    var path := _path("k8_no_simulation.sad")
    assert_eq(SaExport.save_sad(easel.document, path, 0), OK, "It saves")
    for raw_layer: Variant in (_container(path)[0] as Dictionary).get("layers", []):
        assert_false(SaTyped.strings(raw_layer).has("simulation"), "and no entry holds the key")
    var older := _easel()
    var old_file := ProjectSettings.globalize_path("res://tests/data/plain_v4.sad")
    assert_eq(SaExport.load_sad(older.document, old_file, older.compositor), OK, "A file from before the key opens")
    for child in older.document.get_children():
        if child is SaLayer:
            assert_null(SaSimulation.record_of(child as SaLayer), "and %s carries no simulation" % child.name)


func _near(got: Color, want: Color) -> bool:
    return (
        absf(got.r - want.r) <= TOLERANCE
        and absf(got.g - want.g) <= TOLERANCE
        and absf(got.b - want.b) <= TOLERANCE
        and absf(got.a - want.a) <= TOLERANCE
    )
