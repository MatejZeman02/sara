## The Info docker's Name row reads the document's name, a
## star while it has unsaved changes, and "autosaved" once a recovery copy holds
## them, and the star is the window title's own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row shows the document name, a star if unsaved, and the autosaved mark
## if autosaved, or nothing extra if saved. The running app is
## `scenarios/the-document-info-row-shows-the-name-a-star-when-unsaved-and-an-autosaved-mark.json`.
extends "res://tests/test_framework.gd"

## A document is built, and a window title read over a real surface.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _host: Node = null


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func test_the_text_for_every_name_change_and_copy() -> void:
    var read := 0
    for file_name: String in ["", "picture.sad"]:
        var shown := file_name if not file_name.is_empty() else "Untitled"
        for modified: bool in [false, true]:
            for copy: bool in [false, true]:
                var text := SaDocumentLabel.text_for(file_name, modified, copy)
                var expected := shown
                if modified:
                    expected = "%s*, autosaved" % shown if copy else "%s*" % shown
                assert_eq(text, expected, "'%s', modified %s, copy %s" % [file_name, modified, copy])
                read += 1
    assert_eq(read, 8, "every combination was read")


func test_a_saved_document_never_shows_the_autosaved_mark() -> void:
    for file_name: String in ["", "picture.sad"]:
        var text := SaDocumentLabel.text_for(file_name, false, true)
        assert_false(text.contains("autosaved"), "a clean '%s' reads '%s', no mark" % [file_name, text])
        assert_false(text.contains("*"), "and no star")


## The four states the scenario walks, driven by the signals the app sends: a
## change, a copy landing, a change after it, and a save.
func test_the_label_follows_the_document_and_the_autosave() -> void:
    var doc := SaDocument.new()
    doc.file_path = "/pictures/picture.sad"
    var autosave := SaAutosave.new()
    var label := SaDocumentLabel.new(doc, autosave.saved)
    var heard: Array[String] = []
    label.changed.connect(func(text: String) -> void: heard.append(text))
    assert_eq(label.text, "picture.sad", "a saved document reads its name alone")

    doc.modified = true
    assert_eq(label.text, "picture.sad*", "a change adds the star")
    autosave.saved.emit("/pictures/picture.autosave.sad")
    assert_eq(label.text, "picture.sad*, autosaved", "a copy landing adds the mark")
    doc.document_changed.emit()
    assert_eq(label.text, "picture.sad*", "a change after the copy takes the mark away")
    autosave.saved.emit("/pictures/picture.autosave.sad")
    doc.chunks_invalidated.emit([Vector2i.ZERO])
    assert_eq(label.text, "picture.sad*", "and so does a stroke's chunks")
    autosave.saved.emit("/pictures/picture.autosave.sad")
    doc.modified = false
    assert_eq(label.text, "picture.sad", "a save leaves the name alone")
    autosave.saved.emit("/pictures/picture.autosave.sad")
    assert_eq(label.text, "picture.sad", "and a copy landing after it adds nothing")
    doc.file_path = "/pictures/renamed.sad"
    assert_eq(label.text, "renamed.sad", "a Save As renames the row")
    assert_eq(
        heard,
        [
            "picture.sad*",
            "picture.sad*, autosaved",
            "picture.sad*",
            "picture.sad*, autosaved",
            "picture.sad*",
            "picture.sad*, autosaved",
            "picture.sad",
            "renamed.sad",
        ],
        "every change was announced once, and nothing else was"
    )
    autosave.free()
    doc.free()


## The window title is written by `SaWindowTitle` and the row here, so the
## suite builds both over the same document and reads that the name and the
## star agree in every state, an unsaved one with no file included. The
## title node is built over an owner holding one surface, which is what main
## hands it.
func test_the_star_and_the_title_s_own_star_agree() -> void:
    _host = Node.new()
    _host.name = "U146TestHost"
    EventBus.add_child(_host)
    var window := Window.new()
    window.visible = false
    _host.add_child(window)
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var documents := SaDocuments.new()
    documents.add(surface)
    var doc := surface.get_document()
    var title_node := SaWindowTitle.new(documents)
    window.add_child(title_node)
    var label := SaDocumentLabel.new(doc)
    var read := 0
    for path: String in ["", "/pictures/title.sad"]:
        doc.file_path = path
        for modified: bool in [false, true]:
            doc.modified = modified
            var title := window.title
            assert_true(title.begins_with("%s (" % label.text), "the title '%s' starts with the row's '%s'" % [title, label.text])
            assert_eq(title.contains("* ("), label.text.ends_with("*"), "and the two stars agree on '%s'" % title)
            read += 1
    assert_eq(read, 4, "every state was read")
    title_node.free()
    Fixtures.teardown(surface)
