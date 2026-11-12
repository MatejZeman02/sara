## One owner knows the open documents and says when the front
## one changes. Two surfaces, the way two tabs will hold them, in one
## `SaDocuments`, and a context built on it the way main builds its own.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _first: SaSurface = null
var _second: SaSurface = null
var _first_machine: ToolMachine = null
var _documents: SaDocuments = null
var _context: SaContext = null
var _heard: Array = []


func before_each() -> void:
    _first = Fixtures.make_surface(Vector2i(512, 256))
    _first.id = &"first"
    _second = Fixtures.make_surface(Vector2i(256, 512))
    _second.id = &"second"
    _first_machine = Fixtures.make_bound_machine(_first)
    _documents = SaDocuments.new()
    _context = SaContext.new(_documents.front_easel, func() -> Array: return _documents.surfaces.duplicate())
    _heard = []
    EventBus.active_document_changed.connect(_on_changed)


func after_each() -> void:
    EventBus.active_document_changed.disconnect(_on_changed)
    Fixtures.teardown(_first, _first_machine)
    Fixtures.teardown(_second)
    _first = null
    _second = null
    _first_machine = null
    _documents = null
    _context = null


func _on_changed(surface: SaSurface) -> void:
    _heard.append(surface)


## Both held, the first in front, and what that sent forgotten.
func _hold_both() -> void:
    assert_true(_documents.add(_first), "The first surface is held")
    assert_true(_documents.add(_second), "and the second")
    assert_eq(_documents.front, _first, "The first one held is in front")
    _heard.clear()


func test_bringing_the_second_forward_says_so_once_and_the_context_follows() -> void:
    _hold_both()
    assert_eq(_context.get_easel(), _first.easel, "Before the switch the context answers the first easel")

    assert_true(_documents.bring_to_front(_second), "The second comes forward")
    assert_eq(_heard.size(), 1, "active_document_changed is sent once")
    assert_eq(_heard[0] if not _heard.is_empty() else null, _second, "with the second surface")
    assert_eq(_context.get_easel(), _second.easel, "SaContext.get_easel() answers the second easel")
    var open := _context.open_documents()
    assert_eq(open.size(), 2, "open_documents() still lists both")
    assert_true(open.has(_first.get_document()) and open.has(_second.get_document()), "the first and the second")

    assert_false(_documents.bring_to_front(_second), "Bringing the front one forward again changes nothing")
    assert_eq(_heard.size(), 1, "and sends nothing")


func test_a_transform_open_on_the_first_is_closed_by_the_switch_and_the_second_is_untouched() -> void:
    _hold_both()
    var first_document := _first.get_document()
    var layer := SaLayerOps.new(first_document).add(&"", null, 1.0)
    first_document.active_layer = layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    chunk.clear(Color.TRANSPARENT)
    var side := chunk.pixel_size()
    var before := {Vector2i.ZERO: SaChunkDelta.capture(chunk, Rect2i(0, 0, side, side))}
    chunk.clear(Color.RED)
    layer.mark_unresolved(Vector2i.ZERO)
    first_document.record_pixel_step("Paint", layer, before)
    _first_machine.set_active_tool(&"transform")
    _first_machine.active_tool.set(&"move_x", 100.0)
    assert_true(_first_machine.active_tool.call(&"is_moving"), "A move is in the air on the first surface")
    var first_steps := first_document.undo_redo.get_history_count()

    var second_document := _second.get_document()
    var second_layers := SaLayerOps.new(second_document).layers().size()
    var second_steps := second_document.undo_redo.get_history_count()
    var second_version := second_document.undo_redo.get_version()
    var second_modified := second_document.modified

    assert_true(_documents.bring_to_front(_second), "The second comes forward")
    assert_false(_first_machine.active_tool.call(&"is_moving"), "The switch closed the first surface's transform session")
    assert_eq(first_document.undo_redo.get_history_count(), first_steps + 1, "and the move is a step of the first document")
    assert_eq(SaLayerOps.new(second_document).layers().size(), second_layers, "The second document has the layers it had")
    assert_eq(second_document.undo_redo.get_history_count(), second_steps, "and the history it had")
    assert_eq(second_document.undo_redo.get_version(), second_version, "at the same version")
    assert_eq(second_document.modified, second_modified, "and is no more modified than it was")


func test_letting_the_front_one_go_brings_its_neighbour_forward() -> void:
    _hold_both()
    assert_true(_documents.remove(_first), "The front surface is let go")
    assert_eq(_documents.front, _second, "Its neighbour is in front")
    assert_eq(_heard, [_second], "and the bus heard it once")
    assert_true(_documents.remove(_second), "The last one is let go")
    assert_null(_documents.front, "Nothing is in front")
    assert_eq(_heard, [_second, null], "and the bus heard that too")
    assert_null(_context.get_easel(), "The context answers no easel")
    assert_eq(_documents.state(), {"count": 0, "ids": [], "front": ""}, "and the dump's block says none is open")
