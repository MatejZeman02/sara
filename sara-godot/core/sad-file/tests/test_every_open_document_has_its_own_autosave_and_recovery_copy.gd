## Every open document has its own autosave and recovery copy.
##
## One `SaAutosave` held one document, and an untitled copy was named for the
## session alone, so two untitled documents would have written one file and a
## crash would have lost one of them. `SaAutosave.PerDocument` holds one autosave per open
## document, and an untitled copy is named for its document too. The clock is
## handed to `tick()`, so the interval passes in a call.
extends "res://tests/test_framework.gd"

## The autosave writes a `.sad`, which reads every chunk back off the GPU.
const REQUIRES_GPU := true

var _autosaves: SaAutosave.PerDocument = null
var _easels: Array[SaEasel] = []
var _copies: Array[String] = []


func after_each() -> void:
    SaSadFile.finish_saves()
    for copy in _copies:
        SaAutosave.delete_recovery(copy)
    _copies.clear()
    if _autosaves != null:
        _autosaves.free()
        _autosaves = null
    for easel in _easels:
        easel.free()
    _easels.clear()


## An untitled document with a layer named *layer_name* above the default
## ones, painted, so it holds unsaved work.
func _untitled(layer_name: String) -> SaDocument:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    _easels.append(easel)
    var doc: SaDocument = easel.document
    var layer := SaLayer.new()
    layer.name = layer_name
    layer.schema = SaFieldSpec.schema_for_space(doc.color_space)
    doc.add_child(layer)
    doc.fill_layer(Color.RED, layer)
    assert_true(doc.modified, "%s holds unsaved work" % layer_name)
    assert_true(doc.file_path.is_empty(), "and has never been saved")
    return doc


func _layer_names(doc: SaDocument) -> Array[String]:
    var found: Array[String] = []
    for child in doc.get_children():
        if child is SaLayer and child != doc.stroke_layer:
            found.append(str(child.name))
    return found


## The layer names of the `.sad` at *path*, read into a document of its own.
func _layers_in(path: String) -> Array[String]:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    _easels.append(easel)
    assert_eq(SaExport.load_sad(easel.document, path), OK, "%s opens" % path.get_file())
    return _layer_names(easel.document)


## Two untitled documents, each with its autosave, both fired and written.
func _two_written() -> Array[SaDocument]:
    _autosaves = SaAutosave.PerDocument.new()
    var docs: Array[SaDocument] = [_untitled("Sky"), _untitled("Sea")]
    for doc in docs:
        var autosave := _autosaves.attach(doc)
        autosave.follow_settings = false
        autosave.interval_seconds = 60.0
        autosave.note_activity(0)
    assert_eq(_autosaves.held.size(), 2, "Each document has an autosave of its own")
    assert_true(_autosaves.of(docs[0]) != _autosaves.of(docs[1]), "and they are two")
    assert_eq(_autosaves.attach(docs[0]), _autosaves.of(docs[0]), "Attaching again keeps the one it has")
    var quiet := int(SaSettings.idle_after_seconds * 1000.0)
    for doc in docs:
        assert_true(_autosaves.of(doc).tick(120.0, quiet), "Two minutes of work and quiet, and it fires")
        assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
        _copies.append(_autosaves.of(doc).last_written)
    return docs


func test_two_untitled_documents_write_two_copies_each_with_its_own_layers() -> void:
    var docs := _two_written()
    var sky := _autosaves.of(docs[0]).last_written
    var sea := _autosaves.of(docs[1]).last_written
    assert_true(sky != sea, "Two untitled documents name two files: %s, %s" % [sky, sea])
    for copy: String in [sky, sea]:
        assert_true(copy.begins_with(SaAutosave.recovery_dir()), "%s is under the recovery folder" % copy)
        assert_true(FileAccess.file_exists(copy), "%s is on disk" % copy)
    assert_eq(_layers_in(sky), _layer_names(docs[0]), "The first copy holds the first document's layers")
    assert_eq(_layers_in(sea), _layer_names(docs[1]), "and the second the second's")
    assert_true(_layers_in(sky).has("Sky") and not _layers_in(sky).has("Sea"), "Sky and not Sea in the first")
    assert_true(_layers_in(sea).has("Sea") and not _layers_in(sea).has("Sky"), "Sea and not Sky in the second")
    var offered: Array = SaAutosave.find_recoveries([]).map(func(entry: Dictionary) -> String: return entry["copy"])
    assert_true(offered.has(sky) and offered.has(sea), "A start after a crash would offer both")


func test_closing_one_stops_its_autosave_and_removes_its_copy_and_keeps_the_other() -> void:
    var docs := _two_written()
    var closing := _autosaves.of(docs[0])
    var sky := closing.last_written
    var sea := _autosaves.of(docs[1]).last_written
    assert_true(_autosaves.detach(docs[0]), "The first document closes")
    assert_false(FileAccess.file_exists(sky), "Its copy is removed")
    assert_null(_autosaves.of(docs[0]), "Its autosave is no longer held")
    assert_eq(_autosaves.held.size(), 1, "and one is left")
    assert_false(is_instance_valid(closing), "and freed, so its timer asks for nothing more")
    assert_true(FileAccess.file_exists(sea), "The other's copy is kept")
    assert_eq(_autosaves.of(docs[1]).document, docs[1], "and its autosave still watches it")
    assert_false(_autosaves.detach(docs[0]), "Closing it a second time finds nothing")


func test_a_copy_landing_after_its_document_closed_is_deleted_as_it_lands() -> void:
    _autosaves = SaAutosave.PerDocument.new()
    var doc := _untitled("Dusk")
    var autosave := _autosaves.attach(doc)
    autosave.follow_settings = false
    assert_eq(autosave.save_now(), OK, "A copy is asked for")
    var path := autosave.recovery_path()
    _copies.append(path)
    assert_true(_autosaves.detach(doc), "and the document closes before it lands")
    assert_true(is_instance_valid(autosave), "It lives while its save runs")
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_false(FileAccess.file_exists(path), "and the copy it wrote is gone")
    assert_false(is_instance_valid(autosave), "and so is the autosave")
