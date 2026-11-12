## A `write_pixels` names the file it read, and a relative
## name is a name in the run's folder.
##
## A painter sent a relative name and Sara looked for it in the run's folder,
## not the caller's, and the refusal named neither, so the search was the
## painter's. Here a missing file's refusal names the absolute path looked for
## and the run's folder, and a write that took names the file it read.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")

## Reads chunks back.
const REQUIRES_GPU := true

const SIZE := Vector2i(256, 256)


## The refusal for a name that is not there spells where it was looked for and
## the folder a relative name is read from, both as the machine's own paths.
func test_a_missing_relative_name_names_the_path_and_the_runs_folder() -> void:
    var doc := _document()
    var folder := _folder()
    var looked := ProjectSettings.globalize_path(folder.path_join("nowhere.npy"))

    var answer := PixelDriver.write_from(doc, {"layer": _index(doc), "rect": [0, 0, 2, 2], "file": "nowhere.npy"}, folder)

    var error := String(answer.get("error", ""))
    assert_true(error.contains(looked), "the refusal names the absolute path looked for: %s" % error)
    var named := "run's folder, which a relative name is read from, is " + ProjectSettings.globalize_path(folder)
    assert_true(error.contains(named), "and the run's folder: %s" % error)
    assert_true(doc.active_layer.chunks.is_empty(), "with the layer left alone")
    doc.free()
    _clear(folder)


## A write that took answers the absolute path of the file it read.
func test_a_write_answers_the_file_it_read() -> void:
    var doc := _document()
    var folder := _folder()
    var file := FileAccess.open(folder.path_join("patch.npy"), FileAccess.WRITE)
    file.store_buffer(PixelDriver.Npy.header(Vector2i(2, 2)))
    var floats := PackedFloat32Array()
    for _i in 4:
        floats.append_array([1.0, 0.5, 0.25, 1.0])
    file.store_buffer(floats.to_byte_array())
    file.close()

    var answer := PixelDriver.write_from(doc, {"layer": _index(doc), "rect": [0, 0, 2, 2], "file": "patch.npy"}, folder)

    assert_false(answer.has("error"), "the write answers without a refusal: %s" % answer)
    assert_eq(String(answer.get("path", "")), ProjectSettings.globalize_path(folder.path_join("patch.npy")), "and names the file")
    doc.free()
    _clear(folder)


func _index(doc: SaDocument) -> int:
    return SaLayerOps.new(doc).layers().find(doc.active_layer)


func _document() -> SaDocument:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(SIZE, compositor)
    return doc


func _folder() -> String:
    var folder := OS.get_temp_dir().path_join("sara-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(folder)
    return folder


func _clear(folder: String) -> void:
    for name in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(name))
    DirAccess.remove_absolute(folder)
