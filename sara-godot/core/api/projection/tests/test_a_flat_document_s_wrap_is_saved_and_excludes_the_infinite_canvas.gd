## A flat document's wrap is NONE, X or XY, every reader of
## `projection.wrapping` sees it, the `.sad` keeps it, a file from before it
## opens with none, and it and the infinite canvas turn each other off.
extends "res://tests/test_framework.gd"

## A save reads chunks back and an open uploads them.
const REQUIRES_GPU := true

## A file written before the wrap had a key.
const BEFORE := "res://tests/data/plain_v4.sad"

static var path_x: String = SaDataRoot.path("test_x.sad")
static var path_xy: String = SaDataRoot.path("test_xy.sad")
static var path_none: String = SaDataRoot.path("test_none.sad")

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
    for path: String in [path_x, path_xy, path_none]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _document() -> SaDocument:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    _easels.append(easel)
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


func test_a_flat_document_wraps_as_it_is_told_and_stays_flat() -> void:
    var doc := _document()
    assert_eq(doc.projection.wrapping, SaProjection.Wrap.NONE, "A new flat document does not wrap")
    SaProjection.wrap_flat(doc, SaProjection.Wrap.XY)
    assert_eq(doc.projection.wrapping, SaProjection.Wrap.XY, "Wrap All Edges reads XY on the one wrapping every reader asks")
    assert_eq(doc.projection.kind.id, SaProjection.FLAT, "and the document is still flat")
    assert_true(doc.modified, "and has changed, since the .sad keeps the wrap")
    SaProjection.wrap_flat(doc, SaProjection.Wrap.X)
    assert_eq(doc.projection.wrapping, SaProjection.Wrap.X, "The Sides Only reads X")
    SaProjection.wrap_flat(doc, SaProjection.Wrap.NONE)
    assert_eq(doc.projection.wrapping, SaProjection.Wrap.NONE, "and off reads NONE")


func test_a_panorama_keeps_its_kind_s_wrap() -> void:
    var doc := _document()
    doc.projection = SaProjection.new(SaProjection.Equirectangular.new())
    SaProjection.wrap_flat(doc, SaProjection.Wrap.XY)
    assert_eq(doc.projection.wrapping, SaProjection.Wrap.X, "A panorama's wrap is its kind's and the flat wrap leaves it")
    assert_eq(
        SaProjection.new(SaProjection.Equirectangular.new(), null, SaProjection.Wrap.XY).wrapping,
        SaProjection.Wrap.X,
        "even made with one"
    )


func test_wrap_on_turns_the_infinite_canvas_off_and_the_reverse() -> void:
    var doc := _document()
    doc.infinite_canvas.on = true
    assert_true(SaProjection.wrap_flat(doc, SaProjection.Wrap.XY), "Turning wrap on says it turned the infinite canvas off")
    assert_false(doc.infinite_canvas.on, "and the infinite canvas reads off")
    assert_eq(doc.projection.wrapping, SaProjection.Wrap.XY, "with the wrap on")
    assert_true(SaInfiniteCanvas.turn(doc, true), "Turning the infinite canvas on says it stopped the wrap")
    assert_true(doc.infinite_canvas.on, "and the infinite canvas reads on")
    assert_eq(doc.projection.wrapping, SaProjection.Wrap.NONE, "with the wrap off")
    assert_false(SaProjection.wrap_flat(doc, SaProjection.Wrap.NONE), "Turning wrap off leaves the infinite canvas alone")
    assert_true(doc.infinite_canvas.on, "which still reads on")
    SaInfiniteCanvas.turn(doc, false)
    SaProjection.wrap_flat(doc, SaProjection.Wrap.X)
    assert_false(SaInfiniteCanvas.turn(doc, false), "Turning the infinite canvas off leaves the wrap alone")
    assert_eq(doc.projection.wrapping, SaProjection.Wrap.X, "which still reads X")


func test_the_header_keeps_the_wrap_and_an_older_one_reads_none() -> void:
    for edges: SaProjection.Wrap in [SaProjection.Wrap.X, SaProjection.Wrap.XY]:
        var header := SaProjection.new(null, null, edges).to_header()
        assert_eq(header.get("wrap"), SaProjection.WRAP_WORDS[edges], "The header names the wrap")
        assert_eq(SaProjection.from_header(header, null).wrapping, edges, "and reads it back")
    assert_true(SaProjection.new().is_default(), "A flat document with no wrap writes no projection key")
    assert_false(SaProjection.new(null, null, SaProjection.Wrap.X).is_default(), "and one that wraps writes one")
    assert_eq(
        SaProjection.from_header({"kind": "flat"}, null).wrapping, SaProjection.Wrap.NONE, "A header with no wrap reads none"
    )
    assert_eq(SaProjection.from_header(null, null).wrapping, SaProjection.Wrap.NONE, "and so does one with no projection")
    assert_eq(
        SaProjection.from_header({"kind": "flat", "wrap": "sideways"}, null).wrapping,
        SaProjection.Wrap.NONE,
        "and one with a word this build does not know"
    )


func test_each_wrap_is_saved_and_opened() -> void:
    var cases := {path_x: SaProjection.Wrap.X, path_xy: SaProjection.Wrap.XY, path_none: SaProjection.Wrap.NONE}
    for path: String in cases:
        var doc := _document()
        SaProjection.wrap_flat(doc, cases[path])
        _save(doc, path)
        var opened := _opened(path)
        assert_eq(opened.projection.wrapping, cases[path], "%s opens with the wrap it was saved with" % path.get_file())
        assert_eq(opened.projection.kind.id, SaProjection.FLAT, "and flat")


func test_a_sad_from_before_the_wrap_opens_with_none() -> void:
    var doc := _opened(BEFORE)
    assert_eq(doc.projection.wrapping, SaProjection.Wrap.NONE, "A file from before this row opens with no wrap")
