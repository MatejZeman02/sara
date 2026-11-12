## The document knows which file it is and whether it has unsaved work.
##
## Neither fact was recorded anywhere before, which is why nothing
## could prompt before Escape quit the application. The flag is raised by every
## mutation the document offers and cleared by `mark_saved()`, and both fields
## announce from their setters so the title bar and the prompts mirror one bit.
extends "res://tests/test_framework.gd"


func _fresh() -> SaEasel:
    return SaEasel.create_default(Vector2i(256, 256))


func test_a_new_document_belongs_to_no_file_and_has_nothing_to_lose() -> void:
    var easel := _fresh()
    var doc := easel.document
    assert_eq(doc.file_path, "", "No path until saved or opened")
    assert_false(doc.modified, "Building the default layers is not a change the painter made")
    easel.free()


func test_every_mutation_raises_the_flag() -> void:
    var easel := _fresh()
    var doc := easel.document
    var mutations := {
        "fill_layer": func() -> void: doc.fill_layer(Color.RED),
        "clear_layer": func() -> void: doc.clear_layer(),
        "set_layer_visible": func() -> void: SaLayerOps.new(doc).set_visible(doc.active_layer, false),
        "set_layer_opacity": func() -> void: SaLayerOps.new(doc).set_opacity(doc.active_layer, 0.5),
        "set_layer_blend_mode": func() -> void: SaLayerOps.new(doc).set_blend_mode(doc.active_layer, &"multiply"),
        "set_layer_locked": func() -> void: SaLayerOps.new(doc).set_locked(doc.active_layer, true),
        "set_layer_alpha_locked": func() -> void: SaLayerOps.new(doc).set_alpha_locked(doc.active_layer, true),
        "add_paint_layer": func() -> void: SaLayerOps.new(doc).add(),
        "duplicate_layer": func() -> void: SaLayerOps.new(doc).duplicate(doc.active_layer),
        "remove_layer": func() -> void: SaLayerOps.new(doc).remove(doc.active_layer),
        "assign_color_space": func() -> void: SaColorConversion.new(doc).assign(SaColorSpace.acescg()),
        "undo": func() -> void: doc.undo(),
        "redo": func() -> void: doc.redo(),
    }
    for name: String in mutations:
        doc.mark_saved(SaDataRoot.path("identity_probe.sad"))
        assert_false(doc.modified, "Clean before %s" % name)
        mutations[name].call()
        assert_true(doc.modified, "%s raises the flag" % name)
    easel.free()


func test_a_stroke_raises_the_flag() -> void:
    var easel := _fresh()
    var doc := easel.document
    doc.mark_saved(SaDataRoot.path("identity_probe.sad"))
    doc.begin_stroke(1.0, &"normal")
    doc.stroke_layer.get_or_create_chunk(Vector2i.ZERO)
    doc.commit_stroke()
    assert_true(doc.modified, "Committing a stroke is a change")
    easel.free()


func test_mark_saved_sets_the_path_and_clears_the_flag_and_both_announce() -> void:
    var easel := _fresh()
    var doc := easel.document
    var paths: Array = []
    var flags: Array = []
    doc.path_changed.connect(func(path: String) -> void: paths.append(path))
    doc.modified_changed.connect(func(value: bool) -> void: flags.append(value))

    doc.fill_layer(Color.BLUE)
    doc.mark_saved(SaDataRoot.path("identity_probe.sad"))

    assert_eq(doc.file_path, SaDataRoot.path("identity_probe.sad"), "The document is that file now")
    assert_false(doc.modified, "and has nothing unsaved")
    assert_eq(paths, [SaDataRoot.path("identity_probe.sad")], "The path announced once")
    assert_eq(flags, [true, false], "The flag announced going up and coming down, and not again for a repeat")

    doc.mark_saved(SaDataRoot.path("identity_probe.sad"))
    assert_eq(paths.size(), 1, "Saving to the same path again says nothing new")
    easel.free()


func test_file_new_forgets_the_file() -> void:
    var easel := _fresh()
    var doc := easel.document
    doc.mark_saved(SaDataRoot.path("identity_probe.sad"))
    doc.fill_layer(Color.GREEN)
    doc.reset_to_default(Vector2i(128, 128))
    assert_eq(doc.file_path, "", "A new document is nobody's file")
    assert_false(doc.modified, "and starts clean, whatever the colour space setter said on the way")
    easel.free()


func test_a_loaded_file_starts_clean() -> void:
    var easel := _fresh()
    var doc := easel.document
    doc.fill_layer(Color.YELLOW)
    var path := SaDataRoot.path("identity_load.sad")
    assert_eq(SaExport.save_sad(doc, path, 0), OK, "Saved")

    var loaded := _fresh()
    loaded.document.fill_layer(Color.RED)
    assert_true(loaded.document.modified, "Dirty before the load")
    assert_eq(SaExport.load_sad(loaded.document, path), OK, "Loaded")
    assert_false(loaded.document.modified, "What is loaded is what is on disk")

    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    loaded.free()
    easel.free()
