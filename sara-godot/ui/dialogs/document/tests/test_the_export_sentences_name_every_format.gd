## The Export... row and the Author hint name every format.
##
## The File menu's Export... row said "A flattened copy as PNG, JPEG or EXR.
## Only EXR keeps values outside 0 to 1." once the export window had grown TIFF
## and OpenRaster, and the Author row of Preferences named PNG and TIFF once
## OpenRaster wrote the author into every layer. Both sentences are now
## built from `SaExportDialog`'s own lists, and this suite reads them where a
## painter does, off the menu's command and off the Workspace page's row.
##
## That PNG, TIFF and OpenRaster really write the author is proved by
## `test_an_export_names_its_author.gd` and `test_openraster_export.gd`. Here the
## formats registered as naming the author are held to the
## writers Sara owns and nothing a JPG or an EXR would contradict.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The skeleton's formats with the image formats module's after them, as the
## running app registers them, built again before each test.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()


func _export_sentence() -> String:
    for command: SaCommandDescriptor in SaMenuCommands.new(Callable(), Callable(), Callable(), Callable()).commands():
        if command.id == &"file_export":
            return command.sentence
    return ""


func _author_hint() -> String:
    var window := SaSettingsWindow.new()
    window.show_page("Files")
    var files := window.content_container.get_child(window.content_container.get_child_count() - 1)
    var page: SaPage = files.page if files is SaSettingsPage else null
    var row: SaPageRow = page.row(&"export_author") if page != null else null
    var hint := row.explanation if row != null else ""
    window.free()
    return hint


func test_the_export_row_names_every_format_the_window_offers() -> void:
    var sentence := _export_sentence()
    assert_false(sentence.is_empty(), "File has an Export... row with a sentence")
    for format in SaImageImport.formats().exported():
        var label := format.label
        assert_true(sentence.contains(label), "the Export... row names %s: %s" % [label, sentence])


## Which formats keep a value outside 0 to 1
## off the menu's hover and into the dialog, where each format's note says it.
func test_the_export_row_says_which_keeps_the_layers_and_the_dialog_which_keep_the_values() -> void:
    var sentence := _export_sentence()
    assert_true(sentence.begins_with("Save a copy as "), "the hover is a sentence that says what Export does: %s" % sentence)
    assert_true(
        sentence.contains("OpenRaster keeps the layers, the others flatten them."), "OpenRaster is not flattened: %s" % sentence
    )
    assert_false(sentence.contains("0 to 1"), "and the values are the dialog's to say: %s" % sentence)
    for format_id: StringName in [&"exr", &"tiff"]:
        var note := SaImageImport.formats().find(format_id).note
        assert_true(note.begins_with("Every value survives"), "the %s note says it keeps them: %s" % [format_id, note])


func test_the_author_hint_names_every_format_that_writes_an_author() -> void:
    var hint := _author_hint()
    assert_false(hint.is_empty(), "the Author row on Files carries a hint")
    for format: SaImageFormat in _naming():
        var label := format.label
        assert_true(hint.contains(label), "the Author hint names %s: %s" % [label, hint])


func test_the_author_hint_names_no_format_that_writes_none() -> void:
    var hint := _author_hint()
    for format in SaImageImport.formats().exported():
        if format.names_author:
            continue
        var label := format.label
        assert_false(hint.contains(label), "the Author hint leaves out %s, whose writer is not Sara's" % label)
    assert_eq(
        _naming().map(func(format: SaImageFormat) -> StringName: return format.id),
        [&"png", &"tiff", &"ora"],
        "the writers Sara owns, as `SaExportMetadata` says, are the ones named"
    )


## The formats whose writer names the author, in registration order.
func _naming() -> Array:
    return SaImageImport.formats().exported().filter(func(format: SaImageFormat) -> bool: return format.names_author)
