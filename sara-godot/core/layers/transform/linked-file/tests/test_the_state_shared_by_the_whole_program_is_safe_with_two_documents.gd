## The state shared by the whole program is safe with two
## documents.
##
## A painter's note, "shared static state". The linked file's folder and blobs
## are held by the save or the open of one document, so a second document
## opening in the middle of a save reads its own file, and the selection
## reminder keeps one word for each document's selection.
##
## The two linked pictures are both named `logo.png`, one in each of two
## folders, so a link read beside the other document's `.sad` would read the
## other picture without a word, and only its bytes would show it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
const PICTURE := Vector2i(300, 200)

var _folder := ""
var _heard: Array[String] = []


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _folder = ProjectSettings.globalize_path(SaDataRoot.path("two_documents"))
    _clear(_folder)
    for side: String in ["one", "two"]:
        DirAccess.make_dir_recursive_absolute(_folder.path_join(side))
    _write(_folder.path_join("one/logo.png"), Color(0.9, 0.1, 0.1, 1.0))
    _write(_folder.path_join("two/logo.png"), Color(0.1, 0.3, 0.9, 1.0))
    _heard.clear()


func after_each() -> void:
    _clear(_folder)
    if EventBus.corner_notice.is_connected(_hear):
        EventBus.corner_notice.disconnect(_hear)


static func _clear(folder: String) -> void:
    for sub: String in ["one", "two", ""]:
        var here := folder.path_join(sub)
        if not DirAccess.dir_exists_absolute(here):
            continue
        for file in DirAccess.get_files_at(here):
            DirAccess.remove_absolute(here.path_join(file))
        DirAccess.remove_absolute(here)


static func _write(path: String, colour: Color) -> void:
    var image := Image.create_empty(PICTURE.x, PICTURE.y, false, Image.FORMAT_RGBA8)
    image.fill(colour)
    image.save_png(path)


static func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(SIZE)
    surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    (surface.get_document().get_node("Background") as SaLayer).visible = false
    return surface


## A smart layer named Paint, linked to *file*.
static func _linked(surface: SaSurface, file: String) -> SaLayer:
    var doc := surface.get_document()
    var paint := SaLayerOps.new(doc).add()
    paint.name = "Paint"
    SaSmartLayer.make(doc, paint)
    SaLinkedFile.link_file(doc, paint, file)
    return paint


## A digest of every chunk's bytes on *layer*, by grid position.
static func _bytes(layer: SaLayer) -> Dictionary:
    var out := {}
    if layer == null:
        return out
    for grid_pos: Vector2i in layer.chunks:
        var texture := (layer.chunks[grid_pos] as SaChunk).albedo()
        var digest := HashingContext.new()
        digest.start(HashingContext.HASH_SHA256)
        digest.update(GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0))
        out[grid_pos] = digest.finish().hex_encode()
    return out


## The bytes an import of *file* puts on a layer of a document of its own.
static func _imported(file: String) -> Dictionary:
    var other := _surface()
    var bytes := _bytes(SaImageImport.open_into(other.get_document(), file))
    Fixtures.teardown(other)
    return bytes


## The first clause: one document holding a linked file saves while a second,
## holding another linked file, opens in the middle of the save, and each
## reads back with its own file's bytes.
func test_a_save_and_an_open_at_once_each_keep_their_own_linked_file() -> void:
    var one_png := _folder.path_join("one/logo.png")
    var two_png := _folder.path_join("two/logo.png")
    var one_sad := _folder.path_join("one/one.sad")
    var two_sad := _folder.path_join("two/two.sad")
    var one_bytes := _imported(one_png)
    var two_bytes := _imported(two_png)
    assert_true(one_bytes != two_bytes, "The two pictures differ")

    var second := _surface()
    _linked(second, two_png)
    assert_eq(SaSadFile.save_file(second.get_document(), two_sad, 0), OK, "The second document is saved beside its file")
    Fixtures.teardown(second)

    var first := _surface()
    var first_doc := first.get_document()
    _linked(first, one_png)
    var opened := _surface()
    var opened_doc := opened.get_document()
    var rd := GlobalShaderCompiler.get_rd()
    var blobs := PackedByteArray()
    var seen: Array = []
    var errors: Array[Error] = []
    # The open of the second document runs in the middle of the first one's
    # save, after its folder and blobs are set and before its layers are written.
    var work := func() -> Dictionary:
        errors.append(SaExport.load_sad(opened_doc, two_sad, opened.easel.compositor))
        SaLinkedFile.beside(opened_doc, two_sad, func() -> void: seen.append(SaLinkedFile._beside.duplicate()))
        return SaSadFile.header_of(first_doc, blobs, rd)
    var header: Dictionary[String, Variant] = SaLinkedFile.beside(first_doc, one_sad, work, blobs)
    assert_eq(SaSadSave.write_out(one_sad, header, blobs, 0), OK, "The first document's save is written")
    assert_eq(errors, [OK] as Array[Error], "and the second opened while it ran")

    var back := opened_doc.get_node_or_null("Paint") as SaLayer
    var link := SaLinkedFile.link_of(back) if back != null else null
    assert_not_null(link, "The second document opened with its link")
    if link != null:
        assert_eq(link.path, two_png, "to its own file")
        assert_eq(link.state, SaLinkedFile.LINKED, "read again")
        assert_eq(_bytes(back), two_bytes, "with its own file's bytes")

    var reread := _surface()
    var error := SaExport.load_sad(reread.get_document(), one_sad, reread.easel.compositor)
    assert_eq(error, OK, "The first document's file opens")
    var first_back := reread.get_document().get_node_or_null("Paint") as SaLayer
    var first_link := SaLinkedFile.link_of(first_back) if first_back != null else null
    assert_not_null(first_link, "with its link")
    if first_link != null:
        assert_eq(first_link.path, one_png, "to its own file")
        assert_eq(_bytes(first_back), one_bytes, "with its own file's bytes")
    var entry := {}
    for raw: Variant in header.get("layers", []):
        if str((raw as Dictionary).get("name", "")) == "Paint":
            entry = (raw as Dictionary).get(SaLinkedFile.ENTRY, {})
    assert_eq(str(entry.get("path", "")), "logo.png", "written relative to its own folder")

    # The second clause: the moved state holds two values with two documents.
    assert_eq(seen.size(), 1, "The state was read with both documents' work under way")
    if seen.size() == 1:
        var both: Dictionary = seen[0]
        assert_eq(both.size(), 2, "and held one entry for each document")
        var mine: SaLinkedFile.Beside = both.get(first_doc.get_instance_id(), null)
        var theirs: SaLinkedFile.Beside = both.get(opened_doc.get_instance_id(), null)
        assert_true(mine != null and mine.file == one_sad, "the first's naming its own .sad")
        assert_true(theirs != null and theirs.file == two_sad, "the second's naming its own")
    assert_false(SaLinkedFile._beside.has(first_doc.get_instance_id()), "Once the save ends it holds nothing for it")
    assert_true(SaLinkedFile._opened_blobs.is_empty(), "and an ended open leaves no blobs behind")
    for surface: SaSurface in [first, opened, reread]:
        Fixtures.teardown(surface)


## The selection reminder, moved onto each document's selection: a word said
## about one document's selection leaves the other's armed, and a stroke back
## in the first says nothing more.
func test_the_selection_reminder_holds_a_word_for_each_document() -> void:
    EventBus.corner_notice.connect(_hear)
    var first := _surface()
    var second := _surface()
    var docs: Array[SaDocument] = [first.get_document(), second.get_document()]
    for doc in docs:
        doc.selection.select_rect(Rect2i(400, 400, 60, 60))
    var painted := Rect2i(10, 10, 20, 20)
    SaSelectionReminder.after_stroke(docs[0], true, painted, 0.0)
    assert_eq(_heard.size(), 1, "A stroke outside the first document's selection is told about")
    SaSelectionReminder.after_stroke(docs[1], true, painted, 0.0)
    assert_eq(_heard.size(), 2, "and one outside the second's as well")
    var held := 0
    for doc in docs:
        var told: WeakRef = SaSelectionReminder._told_for.get(doc.selection.get_instance_id(), null)
        if told != null and told.get_ref() == doc.selection:
            held += 1
    assert_eq(held, 2, "The reminder holds two values with two documents")
    SaSelectionReminder.after_stroke(docs[0], true, painted, 0.0)
    assert_eq(_heard.size(), 2, "and a second stroke back in the first says nothing more")
    docs[0].selection.select_rect(Rect2i(300, 300, 40, 40))
    SaSelectionReminder.after_stroke(docs[0], true, painted, 0.0)
    assert_eq(_heard.size(), 3, "A changed selection in the first arms only its own")
    SaSelectionReminder.after_stroke(docs[1], true, painted, 0.0)
    assert_eq(_heard.size(), 3, "while the second's stays told")
    Fixtures.teardown(first)
    Fixtures.teardown(second)


func _hear(line: String) -> void:
    _heard.append(line)
