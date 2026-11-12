## A fold is kept on the group and in the file.
##
## Nothing in the document held a group's fold, so a saved document opened with
## every group open whatever the painter had shut. A fold is now
## `SaLayer.folded`, which the keeper writes when a mark is pressed and reads on
## every rebuild, and the `.sad` writes it for a folded group alone. A fold is
## no undo step. The running app's half, a fold through the door below the
## docker's visible area and the same round trip there, is
## `scripts/test_folding_a_group_out_of_sight_works_and_a_fold_is_saved.py`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_saved: String = SaDataRoot.path("test_folds.sad")
static var scratch_older: String = SaDataRoot.path("test_older.sad")

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _docker: LayersDocker


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _doc.active_layer.name = "Background"
    var background := _doc.active_layer
    # Each group added over the Background, so the two stand side by side
    # rather than one inside the other.
    for layer_name: String in ["Sky", "Hills"]:
        _doc.set_active_layer(background)
        var layer := SaLayerOps.new(_doc).add()
        layer.name = layer_name
        SaLayerOps.new(_doc).group_layers([layer]).name = "%s group" % layer_name
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.list_keeper.listen()
    _docker.sync_layer_list()


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()
    _doc = null
    for path: String in [scratch_saved, scratch_older]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _named(layer_name: String) -> SaLayer:
    return _doc.find_child(layer_name, true, false) as SaLayer


func _row_of(layer_name: String) -> int:
    for i: int in _docker.item_list.rows.size():
        var layer: SaLayer = _docker.item_list.layer_at(i)
        if layer != null and str(layer.name) == layer_name:
            return i
    return -1


## Whether the row of *layer_name* draws its mark shut, as the list reports it.
func _row_folded(layer_name: String) -> bool:
    var row := _row_of(layer_name)
    return row != -1 and bool(_docker.item_list.row_report()[row].get("collapsed", false))


func test_a_fold_mark_writes_the_fold_on_the_group_and_no_undo_step() -> void:
    var group := _named("Sky group")
    var steps := _doc.history.step_count()
    _docker._on_group_toggled(_row_of("Sky group"))
    assert_true(group.folded, "a press on the mark folds the group itself")
    assert_true(_docker._closed_groups.has(group), "and the keeper's set with it")
    assert_eq(_row_of("Sky"), -1, "its member's row is folded away")
    assert_eq(_doc.history.step_count(), steps, "and the fold is no undo step")
    _docker._on_group_toggled(_row_of("Sky group"))
    assert_false(group.folded, "a second press opens it again")
    assert_true(_row_of("Sky") != -1, "and its member's row is back")
    assert_eq(_doc.history.step_count(), steps, "still with no undo step")


func test_a_folded_group_opens_folded_and_an_open_one_open() -> void:
    _docker._on_group_toggled(_row_of("Sky group"))
    assert_eq(SaExport.save_sad(_doc, scratch_saved), OK, "saving succeeds")

    _doc.reset_to_default(Vector2i(128, 128))
    assert_eq(_row_of("Sky group"), -1, "a new document shows none of it")
    assert_eq(SaExport.load_sad(_doc, scratch_saved), OK, "opening it again succeeds")
    _docker.sync_layer_list()

    assert_true(_named("Sky group").folded, "the folded group is read back folded")
    assert_true(_row_folded("Sky group"), "and its row is drawn shut")
    assert_eq(_row_of("Sky"), -1, "with its member folded away")
    assert_false(_named("Hills group").folded, "the open group is read back open")
    assert_false(_row_folded("Hills group"), "and its row is drawn open")
    assert_true(_row_of("Hills") != -1, "with its member listed")


func test_a_file_with_every_group_open_carries_no_fold_key() -> void:
    assert_eq(SaExport.save_sad(_doc, scratch_saved), OK, "saving succeeds")
    var header := _header_of(scratch_saved)
    assert_true((header.get("layers", []) as Array).size() >= 5, "the header lists every layer")
    for entry: Dictionary in header.get("layers", []):
        assert_false(entry.has("folded"), "%s carries no fold, as a file did before folds" % entry.get("name"))


## The JSON header of a v4 file at *path*, laid out as the older file below is
## written.
func _header_of(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(SaSadFile.SAD_MAGIC_V4.length())
    file.get_32()
    var packed_size := file.get_32()
    var raw_size := file.get_32()
    var raw := file.get_buffer(packed_size).decompress(raw_size, SaSadFile.SAD_BLOB_COMPRESS)
    file.close()
    var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
    return parsed if parsed is Dictionary else {}


## A file written before folds were kept: two groups and no `folded` key, laid
## down as the writer did then. It opens with every group open, as it always
## did.
func test_an_older_file_opens_with_every_group_open() -> void:
    var layers: Array = [
        {"name": "Background", "visible": true, "opacity": 1.0, "chunks": []},
        {"name": "Sky", "visible": true, "opacity": 1.0, "chunks": [], "group": "Sky group"},
        {"name": "Sky group", "visible": true, "opacity": 1.0, "chunks": [], "is_group": true},
        {"name": "Hills", "visible": true, "opacity": 1.0, "chunks": [], "group": "Hills group"},
        {"name": "Hills group", "visible": true, "opacity": 1.0, "chunks": [], "is_group": true},
    ]
    var raw := (
        JSON
        . stringify(
            {
                "format": "sad",
                "version": SaSadFile.SAD_VERSION,
                "width": 32,
                "height": 32,
                "layers": layers,
            }
        )
        . to_utf8_buffer()
    )
    var packed := raw.compress(SaSadFile.SAD_BLOB_COMPRESS)
    var file := FileAccess.open(scratch_older, FileAccess.WRITE)
    file.store_buffer(SaSadFile.SAD_MAGIC_V4.to_ascii_buffer())
    file.store_32(SaSadFile.SAD_VERSION)
    file.store_32(packed.size())
    file.store_32(raw.size())
    file.store_buffer(packed)
    file.close()

    assert_eq(SaExport.load_sad(_doc, scratch_older), OK, "the older file opens")
    _docker.sync_layer_list()
    for group_name: String in ["Sky group", "Hills group"]:
        assert_true(_named(group_name) != null and _named(group_name).is_group, "%s is a group" % group_name)
        assert_false(_named(group_name).folded, "%s opens open" % group_name)
        assert_false(_row_folded(group_name), "and its row is drawn open")
    assert_true(_row_of("Sky") != -1 and _row_of("Hills") != -1, "every member is listed")


func test_the_two_groups_stand_side_by_side() -> void:
    assert_eq(SaLayerStack.parent_of(_named("Hills group")), null, "Hills' group is not inside Sky's")
    assert_eq(SaLayerStack.parent_of(_named("Sky group")), null, "nor Sky's inside Hills'")
