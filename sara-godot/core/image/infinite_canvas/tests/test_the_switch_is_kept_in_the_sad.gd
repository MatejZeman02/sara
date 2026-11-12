## The infinite canvas's switch is kept in the `.sad` header, and a file from
## before it, whose header has no such key, opens with it off.
extends "res://tests/test_framework.gd"

## A save reads chunks back and an open uploads them.
const REQUIRES_GPU := true

static var path_on: String = SaDataRoot.path("test_on.sad")
static var path_off: String = SaDataRoot.path("test_off.sad")

var _docs: Array[SaDocument] = []
var _easels: Array[SaEasel] = []


func after_each() -> void:
    SaSadFile.finish_saves()
    for doc in _docs:
        doc.free()
    _docs.clear()
    for easel in _easels:
        easel.free()
    _easels.clear()
    for path: String in [path_on, path_off]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _document(on: bool) -> SaDocument:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    _easels.append(easel)
    easel.document.infinite_canvas.on = on
    return easel.document


func _save(doc: SaDocument, path: String) -> void:
    var save := SaSadFile.save_in_background(doc, path, 0, null, true, Callable(), true)
    assert_true(SaSadFile.finish_saves(), "The save of %s ends" % path.get_file())
    assert_true(save != null and save.error == OK, "and writes its file")


func _opened(path: String) -> SaDocument:
    var doc := SaDocument.new()
    _docs.append(doc)
    assert_eq(SaExport.load_sad(doc, path, SaCompositor.new()), OK, "%s opens" % path.get_file())
    return doc


func test_a_document_saved_with_the_switch_on_opens_with_it_on() -> void:
    _save(_document(true), path_on)
    assert_true(_opened(path_on).infinite_canvas.on, "The switch reads on after the round trip")


func test_a_document_saved_with_the_switch_off_opens_with_it_off() -> void:
    _save(_document(false), path_off)
    assert_false(_opened(path_off).infinite_canvas.on, "The switch reads off after the round trip")


## A header written before this switch has no key for it, which is what a
## document with the switch off writes too, and a document opened over one
## that had the switch on reads it off.
func test_a_header_from_before_the_switch_reads_off() -> void:
    var doc := _document(false)
    var header := {}
    SaInfiniteCanvas.write_header(doc, header)
    assert_false(header.has(SaInfiniteCanvas.HEADER_KEY), "The switch off writes no key, as every older file has none")
    doc.infinite_canvas.on = true
    SaInfiniteCanvas.read_header(doc, {"version": 4})
    assert_false(doc.infinite_canvas.on, "A header with no key reads the switch off")
    _save(_document(false), path_off)
    var opened := _opened(path_off)
    assert_false(opened.infinite_canvas.on, "and so does the file opened from it")
