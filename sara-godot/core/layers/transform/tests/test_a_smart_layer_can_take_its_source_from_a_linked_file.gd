## A smart layer can take its source from a linked file.
## Layer > Link to File... reads a PNG through the format registry's reader
## into the layer's source, a save writes the path relative to the `.sad` with
## the absolute form beside it, Make Path Absolute and Make Path Relative turn
## it, an open reads the file again, a missing file keeps the last picture and
## says so, a changed file is marked and never applied by itself, and Reload
## Linked File is one history step that keeps the map and the settings.
##
## The fixtures are two PNGs written by the suite into a folder of its own
## under the data root: a red square with a blue bar, and a green one with
## noise in it, so the two differ in size on disk as well as in their pixels.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const LayersReport = preload("res://harness/report/sa_layers_report.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
const PICTURE := Vector2i(300, 200)
const MIDDLE := Vector2(256.0, 256.0)
## The layer's map, turned and moved, which a reload must leave alone.
const MOVE := Vector2(40.0, 60.0)
const TURN := 20.0
const SCALE := Vector2(1.2, 1.2)

var _folder := ""
var _fixture := ""


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _folder = ProjectSettings.globalize_path(SaDataRoot.path("linked_file"))
    _clear(_folder)
    DirAccess.make_dir_recursive_absolute(_folder.path_join("sub/deeper"))
    _fixture = _folder.path_join("logo.png")
    _write(_fixture, false)


func after_each() -> void:
    _clear(_folder)


static func _clear(folder: String) -> void:
    for sub: String in ["sub/deeper", "sub", ""]:
        var here := folder.path_join(sub)
        for file in DirAccess.get_files_at(here):
            DirAccess.remove_absolute(here.path_join(file))
        DirAccess.remove_absolute(here)


## The first picture, or the second when *second*.
static func _write(path: String, second: bool) -> void:
    var image := Image.create_empty(PICTURE.x, PICTURE.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.1, 0.7, 0.2, 1.0) if second else Color(0.9, 0.1, 0.1, 1.0))
    if second:
        var noise := RandomNumberGenerator.new()
        noise.seed = 136
        for y in PICTURE.y:
            for x in PICTURE.x:
                image.set_pixel(x, y, Color(0.1, noise.randf(), 0.2, 1.0))
    else:
        image.fill_rect(Rect2i(20, 80, 260, 40), Color(0.1, 0.2, 0.9, 1.0))
    image.save_png(path)


static func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(SIZE)
    surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    (surface.get_document().get_node("Background") as SaLayer).visible = false
    return surface


static func _map() -> Basis:
    return SaLiveTransform.composed(MOVE, TURN, SCALE, MIDDLE)


## A smart layer named Paint at the map, linked to *file*.
static func _linked(surface: SaSurface, file: String) -> SaLayer:
    var doc := surface.get_document()
    var paint := SaLayerOps.new(doc).add()
    paint.name = "Paint"
    SaSmartLayer.make(doc, paint)
    SaLiveTransform.put(doc, paint, _map())
    SaLinkedFile.link_file(doc, paint, file)
    return paint


## A digest of the bytes of every chunk *layer* holds, by grid position, so a
## failed comparison prints a line rather than the pixels.
static func _bytes(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        var texture := (layer.chunks[grid_pos] as SaChunk).albedo()
        var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var digest := HashingContext.new()
        digest.start(HashingContext.HASH_SHA256)
        digest.update(data)
        out[grid_pos] = digest.finish().hex_encode()
    return out


## The bytes of the picture an import of *file* puts on a layer of *doc*, which
## is what the registry's reader gives for it, through the import's colour. The
## import goes into a surface of its own so the linked document's history keeps
## its steps.
static func _imported(file: String) -> Dictionary:
    var other := _surface()
    var bytes := _bytes(SaImageImport.open_into(other.get_document(), file))
    Fixtures.teardown(other)
    return bytes


## The entry a save of *doc* into *sad* writes for the layer *name*.
static func _entry(doc: SaDocument, sad: String, name: String) -> Dictionary:
    var blobs := PackedByteArray()
    var header: Dictionary = SaLinkedFile.beside(doc, sad, SaSadFile.header_of.bind(doc, blobs, GlobalShaderCompiler.get_rd()))
    for raw: Variant in header.get("layers", []):
        var entry := SaTyped.strings(raw)
        if str(entry.get("name", "")) == name:
            return entry
    return {}


static func _written(doc: SaDocument, sad: String) -> String:
    return str((_entry(doc, sad, "Paint").get(SaLinkedFile.ENTRY, {}) as Dictionary).get("path", ""))


## *sad* opened into a surface of its own, answered with its Paint layer.
static func _opened(sad: String) -> Array:
    var loaded := _surface()
    var error := SaExport.load_sad(loaded.get_document(), sad, loaded.easel.compositor)
    return [loaded, loaded.get_document().get_node_or_null("Paint") as SaLayer, error]


## The first clause: the source is the picture the reader gives, a save and an
## open bring the link and the picture back, the path is written relative beside
## the file and elsewhere, the two path commands turn it, and a link whose
## relative form no longer resolves is found through the absolute one.
func test_a_link_reads_the_file_and_saves_its_path_both_ways() -> void:
    var surface := _surface()
    var doc := surface.get_document()
    var paint := _linked(surface, _fixture)
    var link := SaLinkedFile.link_of(paint)
    assert_not_null(link, "Link to File links the smart layer")
    if link == null:
        Fixtures.teardown(surface)
        return
    assert_eq(link.path, _fixture, "to the file's absolute path")
    var picture := _bytes(paint)
    assert_true(picture.size() > 0, "The source holds chunks")
    assert_eq(picture, _imported(_fixture), "the picture the registry's reader gives, as an import puts it")
    assert_true(SaLiveTransform.of(paint).matrix.is_equal_approx(_map()), "drawn through the map it had")
    var report: Dictionary = LayersReport.stack(doc).filter(func(e: Dictionary) -> bool: return e["name"] == "Paint")[0]
    assert_eq(report["link"]["state"], SaLinkedFile.LINKED, "The layers report says linked")
    assert_eq(report["link"]["path"], _fixture, "and names the file")

    assert_true(doc.undo(), "The link undoes")
    assert_null(SaLinkedFile.link_of(paint), "to no link")
    assert_eq(paint.chunks.size(), 0, "and the paint the layer had, none")
    assert_true(doc.redo(), "and redoes")
    assert_eq(_bytes(paint), picture, "to the file's picture")

    var beside := _folder.path_join("beside.sad")
    assert_eq(_written(doc, beside), "logo.png", "Saved beside the file, the path is written relative")
    var elsewhere := _folder.path_join("sub/elsewhere.sad")
    assert_eq(_written(doc, elsewhere), "../logo.png", "and relative from another folder")
    assert_eq(_written(doc, ""), _fixture, "and absolute for a document never saved")

    assert_true(SaLinkedFile.make_absolute(doc, paint), "Make Path Absolute turns it")
    assert_eq(_written(doc, elsewhere), _fixture, "to the absolute path")
    assert_false(SaLinkedFile.make_absolute(doc, paint), "and a second time says it is absolute already")
    assert_true(doc.undo(), "Its undo")
    assert_eq(_written(doc, elsewhere), "../logo.png", "writes it relative again")
    assert_true(SaLinkedFile.make_absolute(doc, paint), "Absolute once more")
    assert_true(SaLinkedFile.make_relative(doc, paint), "and Make Path Relative turns it back")
    assert_eq(_written(doc, elsewhere), "../logo.png", "to the relative path")

    assert_eq(SaSadFile.save_file(doc, beside, 0), OK, "It saves beside the file")
    var made := _opened(beside)
    var back: SaLayer = made[1]
    assert_eq(made[2], OK, "and opens")
    assert_not_null(SaLinkedFile.link_of(back), "with the link")
    if back != null and SaLinkedFile.link_of(back) != null:
        assert_eq(SaLinkedFile.link_of(back).path, _fixture, "to the file")
        assert_eq(SaLinkedFile.link_of(back).state, SaLinkedFile.LINKED, "read again")
        assert_eq(_bytes(back), picture, "and the picture")
        assert_true(SaLiveTransform.of(back).matrix.is_equal_approx(_map()), "at the map")
    Fixtures.teardown(made[0])

    assert_eq(SaSadFile.save_file(doc, elsewhere, 0), OK, "It saves in a folder below the file")
    var moved := _folder.path_join("sub/deeper/moved.sad")
    DirAccess.copy_absolute(elsewhere, moved)
    made = _opened(moved)
    back = made[1]
    assert_eq(made[2], OK, "A copy of it one folder deeper opens")
    var found := SaLinkedFile.link_of(back) if back != null else null
    assert_not_null(found, "with the link")
    if found != null:
        assert_eq(found.path, _fixture, "where its relative path names nothing, through the absolute one")
        assert_eq(found.state, SaLinkedFile.LINKED, "and reads it")
        assert_eq(_bytes(back), picture, "the same picture")
    Fixtures.teardown(made[0])
    Fixtures.teardown(surface)


## The second clause: with the file gone, the document opens with no script
## error, the layer says the link is broken in words and keeps the picture the
## `.sad` stored, and with the file back a reload links it again.
func test_a_missing_file_keeps_the_last_picture_until_it_is_back() -> void:
    var surface := _surface()
    var doc := surface.get_document()
    var paint := _linked(surface, _fixture)
    var picture := _bytes(paint)
    var sad := _folder.path_join("missing.sad")
    assert_eq(SaSadFile.save_file(doc, sad, 0), OK, "It saves")
    DirAccess.rename_absolute(_fixture, _fixture + ".away")
    var made := _opened(sad)
    var back: SaLayer = made[1]
    assert_eq(made[2], OK, "With the file gone the document opens")
    var link := SaLinkedFile.link_of(back) if back != null else null
    assert_not_null(link, "and the layer keeps its link")
    if link == null:
        Fixtures.teardown(made[0])
        Fixtures.teardown(surface)
        return
    var reopened := (made[0] as SaSurface).get_document()
    var report: Dictionary = LayersReport.stack(reopened).filter(func(e: Dictionary) -> bool: return e["name"] == "Paint")[0]
    assert_eq(report["link"]["state"], SaLinkedFile.MISSING, "The layers report says the file is missing")
    assert_true(str(report["link"]["reason"]).contains("not there any more"), "in words: %s" % report["link"]["reason"])
    assert_eq(_bytes(back), picture, "and the layer keeps the picture the file stored")
    assert_false(SaLinkedFile.reload_file(reopened, back), "A reload with the file still gone does nothing")
    assert_eq(_bytes(back), picture, "and keeps the picture")

    DirAccess.rename_absolute(_fixture + ".away", _fixture)
    assert_true(SaLinkedFile.reload_file(reopened, back), "With the file back, Reload Linked File reads it")
    assert_eq(SaLinkedFile.link_of(back).state, SaLinkedFile.LINKED, "and the link works again")
    assert_eq(_bytes(back), picture, "with the file's picture")
    Fixtures.teardown(made[0])
    Fixtures.teardown(surface)


## A new ordinary layer is linked by the one command, made smart in the same
## step, and one undo gives the ordinary layer back.
func test_a_new_layer_is_linked_and_made_smart_in_one_step() -> void:
    var surface := _surface()
    var doc := surface.get_document()
    var paint := SaLayerOps.new(doc).add()
    paint.name = "Paint"
    var steps := doc.undo_redo.get_history_count()
    assert_true(SaLinkedFile.link_file(doc, paint, _fixture), "Link to File links an ordinary layer")
    assert_true(SaSmartLayer.is_marked(paint), "made smart")
    assert_not_null(SaLinkedFile.link_of(paint), "and linked")
    assert_eq(doc.undo_redo.get_history_count(), steps + 1, "as one history step")
    assert_true(doc.undo(), "One undo")
    assert_false(SaSmartLayer.is_marked(paint), "gives the ordinary layer back")
    assert_null(SaLinkedFile.link_of(paint), "with no link")
    assert_eq(paint.chunks.size(), 0, "and the paint it had, none")
    Fixtures.teardown(surface)


## The third clause: a file changed under an open document marks the layer and
## leaves its picture, and Reload Linked File puts the new picture in, keeps
## the map and the settings, and undoes in one step.
func test_a_changed_file_is_marked_and_reloaded_in_one_step() -> void:
    var surface := _surface()
    var doc := surface.get_document()
    var paint := _linked(surface, _fixture)
    paint.opacity = 0.6
    paint.blend_mode = &"multiply"
    var picture := _bytes(paint)
    var was := FileAccess.get_file_as_bytes(_fixture).size()
    _write(_fixture, true)
    assert_true(FileAccess.get_file_as_bytes(_fixture).size() != was, "The second picture is of another size on disk")
    var marked := SaLinkedFile.check(doc)
    assert_eq(marked, [paint] as Array[SaLayer], "The check marks the layer")
    assert_eq(SaLinkedFile.link_of(paint).state, SaLinkedFile.CHANGED, "as changed")
    assert_eq(_bytes(paint), picture, "and its picture has not moved")
    assert_eq(SaLinkedFile.check(doc).size(), 0, "A second check marks nothing new")

    assert_true(SaLinkedFile.reload_file(doc, paint), "Reload Linked File reads it")
    var fresh := _bytes(paint)
    assert_eq(fresh, _imported(_fixture), "and the picture is the new one")
    assert_true(fresh != picture, "which is not the old")
    assert_eq(SaLinkedFile.link_of(paint).state, SaLinkedFile.LINKED, "The link is no longer marked")
    assert_true(SaLiveTransform.of(paint).matrix.is_equal_approx(_map()), "The map is unchanged")
    assert_almost_eq(paint.opacity, 0.6, 1.0e-6, "and so are the opacity")
    assert_eq(paint.blend_mode, &"multiply", "and the blend mode")
    assert_true(SaSmartLayer.is_marked(paint), "and it is a smart layer still")
    assert_true(doc.undo(), "One undo")
    assert_eq(_bytes(paint), picture, "gives the old source back")
    assert_true(SaLiveTransform.of(paint).matrix.is_equal_approx(_map()), "at the same map")
    Fixtures.teardown(surface)


## The fourth clause: a layered document and a file that is no picture are
## refused with the reason, and the ordinary layer asked is left as it was,
## not made smart.
func test_a_layered_file_and_one_that_is_no_picture_are_refused() -> void:
    var surface := _surface()
    var doc := surface.get_document()
    var paint := SaLayerOps.new(doc).add()
    paint.name = "Paint"
    var steps := doc.undo_redo.get_history_count()

    var layered := _folder.path_join("other.sad")
    FileAccess.open(layered, FileAccess.WRITE).store_string("SAD4")
    assert_false(SaLinkedFile.link_file(doc, paint, layered), "A `.sad` is refused")
    assert_true(SaProblems.pending_refusals[-1].contains("layered document"), "as a layered document")

    var text := _folder.path_join("notes.png")
    FileAccess.open(text, FileAccess.WRITE).store_string("Not a picture at all.")
    assert_false(SaLinkedFile.link_file(doc, paint, text), "A file that is no picture is refused")
    var said := "\n".join(SaProblems.pending_refusals)
    assert_true(said.contains("Could not read"), "in the reader's own words: %s" % said)
    assert_true(said.contains("could not be read as a picture"), "and the link's")

    assert_null(SaLinkedFile.link_of(paint), "The layer has no link")
    assert_false(SaSmartLayer.is_marked(paint), "and is the ordinary layer it was")
    assert_eq(paint.chunks.size(), 0, "holding the paint it held")
    assert_eq(doc.undo_redo.get_history_count(), steps, "with no step written")
    Fixtures.teardown(surface)
