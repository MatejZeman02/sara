## An export taken right after a layer is shown or hidden carries the change.
##
## A layer or a group shown or hidden owes the fold to `SaFoldDebt`, which
## holds the picture as it was until the fold is paid over the frames after the
## click. A stroke's press paid it and an export did not, so a painter who hid
## a layer and exported inside that half second wrote the picture with the
## layer still showing. Now every reader of the whole picture pays it first,
## `SaFoldDebt.before_reading` through `SaEasel.catch_up`.
##
## Two easels are built alike: a red layer under a blue one, both opaque over
## the whole canvas. The one under test is in the tree with its idle frame put
## off for a minute, so the debt waits as it does under a painter, and nothing
## here calls a frame. Its twin is outside the tree and folds and composites
## whole after each change, which is the true picture. Each export is read
## back off the file and set against the twin's.
extends "res://tests/test_framework.gd"

## The pictures and the caches are compute dispatches, read back here.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ExportDialogScript = preload("res://ui/dialogs/document/export_dialog.gd")

const DOC_SIZE := Vector2i(256, 192)
const LOWER := Color(0.8, 0.1, 0.1, 1.0)
const UPPER := Color(0.1, 0.2, 0.9, 1.0)

var _canvas: SaCanvas
var _twin: SaEasel
var _formats: SaRegistries
var _paths: Array[String] = []


static func _built(easel: SaEasel) -> void:
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    doc.fold.debt.quiet_msec = 60000
    doc.active_layer.name = "Lower"
    doc.fill_layer(LOWER, doc.active_layer)
    var upper := SaLayerOps.new(doc).add()
    upper.name = "Upper"
    doc.fill_layer(UPPER, upper)
    SaLayerOps.new(doc).group_layers([upper]).name = "Group"
    doc.set_active_layer(doc.find_child("Lower", true, false) as SaLayer)
    doc.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    easel.flush()


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    _canvas = SaCanvas.new()
    _canvas.canvas_size = DOC_SIZE
    _canvas.easel = SaEasel.create_default(DOC_SIZE)
    _canvas.add_child(_canvas.easel)
    EventBus.add_child(_canvas)
    _built(_canvas.easel)
    _twin = SaEasel.create_default(DOC_SIZE)
    _built(_twin)


func after_each() -> void:
    _canvas.free()
    _twin.free()
    for path in _paths:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _paths.clear()


static func _named(doc: SaDocument, layer_name: String) -> SaLayer:
    return doc.find_child(layer_name, true, false) as SaLayer


## *act* run on the document under test and on the twin's, the twin folded and
## composited whole after it.
func _both(act: Callable) -> void:
    act.call(_canvas.document)
    act.call(_twin.document)
    _twin.document.fold.debt.settle(_twin.document)
    _twin.document.update_caches()
    _twin.request_full_composite()
    _twin.process_pending_composite()
    _twin.flush()


func _path(label: String) -> String:
    var path := SaDataRoot.path("%s.png" % label)
    _paths.append(path)
    return path


## The PNG at *path* read back as bytes of RGBA8.
static func _texels(path: String) -> PackedByteArray:
    var image := Image.load_from_file(ProjectSettings.globalize_path(path))
    if image == null:
        return PackedByteArray()
    image.convert(Image.FORMAT_RGBA8)
    return image.get_data()


## The twin's picture written as the truth for *label*.
func _truth(label: String) -> PackedByteArray:
    var path := _path("%s_truth" % label)
    assert_eq(SaExport.export_png(_twin, path), OK, "The twin's export of %s is written" % label)
    return _texels(path)


## The export the door's `export` step makes, the PNG format's writer, taken
## in the frame of *act* with the debt still owed, read against the twin's.
func _exported_at_once(label: String, act: Callable) -> PackedByteArray:
    var before := _path("%s_before" % label)
    SaExport.export_png(_canvas.easel, before)
    _both(act)
    assert_true(_canvas.document.fold.debt.is_owed(), "%s owes the fold, as under a painter" % label)
    var path := _path(label)
    assert_eq(SaExport.export_png(_canvas.easel, path), OK, "The export after %s is written" % label)
    var read := _texels(path)
    assert_false(read.is_empty(), "and reads back")
    assert_true(read != _texels(before), "The export after %s differs from the one before it" % label)
    assert_true(read == _truth(label), "and the export after %s is the picture with the change" % label)
    return read


func test_a_layer_hidden_and_exported_in_the_same_frame_is_left_out() -> void:
    var hide := func(doc: SaDocument) -> void: SaLayerOps.new(doc).set_visible(_named(doc, "Upper"), false)
    var hidden := _exported_at_once("hiding Upper", hide)
    var centre := ((DOC_SIZE.y >> 1) * DOC_SIZE.x + (DOC_SIZE.x >> 1)) * 4
    assert_true(hidden[centre] > hidden[centre + 2], "The texel at the centre is the red of the lower layer alone")
    assert_false(_canvas.document.fold.debt.is_owed(), "The export paid the fold, as a press does")
    var show := func(doc: SaDocument) -> void: SaLayerOps.new(doc).set_visible(_named(doc, "Upper"), true)
    var shown := _exported_at_once("showing Upper again", show)
    assert_true(shown[centre + 2] > shown[centre], "and with it shown again the blue of the upper one")


func test_a_group_hidden_and_exported_in_the_same_frame_is_left_out() -> void:
    var hide := func(doc: SaDocument) -> void: SaLayerOps.new(doc).set_visible(_named(doc, "Group"), false)
    _exported_at_once("hiding the group", hide)
    var show := func(doc: SaDocument) -> void: SaLayerOps.new(doc).set_visible(_named(doc, "Group"), true)
    _exported_at_once("showing the group again", show)


## The File menu's Export... writes through the dialog, `_export_to` being
## what the file picker calls with the name the painter typed.
func test_the_file_menu_s_export_after_a_hide_leaves_the_layer_out() -> void:
    var before := _path("menu_before")
    SaExport.export_png(_canvas.easel, before)
    _both(func(doc: SaDocument) -> void: SaLayerOps.new(doc).set_visible(_named(doc, "Upper"), false))
    assert_true(_canvas.document.fold.debt.is_owed(), "The hide owes the fold")
    var dialog := ExportDialogScript.new(_canvas, &"png")
    _canvas.add_child(dialog)
    var path := _path("menu")
    dialog._export_to(path)
    SaExportInTurns.finish_all()
    var read := _texels(path)
    assert_false(read.is_empty(), "The dialog's export is written")
    assert_true(read != _texels(before), "and differs from the picture before the hide")
    assert_true(read == _truth("menu"), "and is the picture with the layer hidden")


## An activation alone draws the same picture, so a read leaves its fold to
## the idle frame rather than folding the stack under the painter.
func test_a_read_leaves_a_debt_of_the_active_layer_alone_owed() -> void:
    var doc := _canvas.document
    var lower := _named(doc, "Lower")
    var second := SaLayerOps.new(doc).add()
    doc.update_caches()
    doc.set_active_layer(lower)
    doc.update_caches()
    doc.set_active_layer(second)
    assert_true(doc.fold.debt.is_owed(), "A click on a row owes the fold")
    assert_false(doc.fold.debt.owes_whole(), "of the active layer alone")
    SaFoldDebt.before_reading(doc)
    assert_true(doc.fold.debt.is_owed(), "and a read leaves it owed")
