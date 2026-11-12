## The attached filter's edit window previews through the write an Edit Filter
## step makes, so a moved widget redraws the record's node's chunks and folds
## no cache that never baked it. Its own redraw marked every allocated
## chunk and rebuilt every cache, as `SaFilterOps` did.
##
## A three-chunk document: the filtered layer holds chunk (0,0) and is
## active, and the bottom cache holds the background and the layer under it,
## which holds (2,0). Built and never added to the tree, for the reason
## `test_the_filter_editor.gd` gives.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const KNOB := &"k11_suite.knob"
## A colour no fold writes, so a cache chunk that still holds it was not
## folded again.
const SENTINEL := Color(7.0, -3.0, 0.5, 2.0)

var _easel: SaEasel
var _doc: SaDocument
var _registry: SaFilterRegistry
var _record: SaAttachedFilter
var _window: SaFilterEditWindow
var _grid: Array[Vector2i] = []


## A filter with one number, the shape `test_the_filter_editor.gd` brings.
class Knob:
    extends SaFilter

    var amount: SaSlider

    func title() -> String:
        return "Knob"

    func build(ui: SaDialog) -> void:
        ui.title("Knob")
        amount = ui.slider("Amount", 0, 10, 3)
        ui.apply_cancel()

    func parameters() -> Dictionary:
        return {"amount": float(amount.value)}

    func set_parameters(values: Dictionary) -> void:
        if values.has("amount"):
            amount.value = values["amount"]

    func run(_ctx: SaFilterContext) -> void:
        pass


func before_each() -> void:
    var size := Vector2i(SaLayer.CHUNK_SIZE * 3, SaLayer.CHUNK_SIZE)
    _grid = SaLayer.grid_positions(size)
    _easel = SaEasel.create_default(size)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _registry = SaFilterRegistry.new()
    _registry.register(Knob.new(), &"k11_suite")
    var under := _doc.active_layer
    var over := SaLayerOps.new(_doc).add()
    under.get_or_create_chunk(_grid[2]).clear(Color(0.1, 0.6, 0.3, 1.0))
    over.get_or_create_chunk(_grid[0]).clear(Color(0.9, 0.2, 0.05, 1.0))
    _record = SaFilterOps.new(_doc).attach(over, KNOB, {"amount": 7.0})
    _window = SaFilterEditWindow.new()
    _window.watch(_registry)
    _window.open(_record, _doc)
    for grid_pos: Vector2i in _doc.fold.bottom_cache.chunks:
        (_doc.fold.bottom_cache.chunks[grid_pos] as SaChunk).clear(SENTINEL)
    _doc.consume_dirty_chunks()


func after_each() -> void:
    _window.free()
    _easel.free()
    _registry = null


## The sorted grid positions the document marked since the last call.
func _dirty() -> Array[Vector2i]:
    var keys: Array[Vector2i] = []
    keys.assign(_doc.consume_dirty_chunks().keys())
    keys.sort()
    return keys


## The bottom cache's chunks still holding [const SENTINEL] at their corner.
func _untouched() -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    for grid_pos: Vector2i in _grid:
        var chunk: SaChunk = _doc.fold.bottom_cache.chunks.get(grid_pos, null)
        if chunk == null:
            continue
        var texture := chunk.albedo()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var texel := SaFieldSpec.decode_texel(bytes, texture.format, 0)
        if texel.is_equal_approx(SENTINEL):
            found.append(grid_pos)
    return found


func test_a_moved_widget_redraws_the_records_chunk_alone() -> void:
    assert_eq(_untouched(), _grid, "The bottom cache holds the colour no fold writes")
    _window.dialog.row(&"amount").drive(2.0)
    _window.dialog.flush_rerun()
    assert_eq(_record.parameters, {"amount": 2.0}, "The widget's value is on the record")
    assert_eq(_dirty(), [_grid[0]] as Array[Vector2i], "and the preview marked the filtered layer's chunk alone")
    assert_eq(_untouched(), _grid, "with no cache folded again")


func test_cancel_redraws_the_records_chunk_alone() -> void:
    _window.dialog.row(&"amount").drive(2.0)
    _window.dialog.flush_rerun()
    _doc.consume_dirty_chunks()
    _window.cancel()
    assert_eq(_record.parameters, {"amount": 7.0}, "Cancel put the values back")
    assert_eq(_dirty(), [_grid[0]] as Array[Vector2i], "and marked the filtered layer's chunk alone")
    assert_eq(_untouched(), _grid, "with no cache folded again")
