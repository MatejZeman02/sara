## New Document opens from a template, and saves one.
##
## The dialog offers choosing from some templates. The Size row filled the
## width, the height and sometimes the resolution, and nothing else, and a painter could add no entry. These hold
## the Template row: each shipped template fills the rows it names, a moved row
## marks it changed and Create makes what the rows say, a saved template comes
## back in a new dialog, and the dialog opens on the last template used.
##
## The dialog is never added to the tree here: a test that maps a real window
## hangs the run, which is why `test_new_document_rows.gd` says the same.
extends "res://tests/test_framework.gd"

## The dialog builds a colour space browser, which draws a gamut.
const REQUIRES_GPU := true

## Disposable, and under the data root as every folder a run writes is.
var _saved_root: String = SaDataRoot.path("test_d47_templates_%d" % OS.get_process_id())

var _types: SaLayerTypeRegistry = null
var _kept_root: String = ""
var _kept_last: String = ""


func before_each() -> void:
    _types = SaLayerTypeRegistry.new()
    _types.register(SaLayerTypeDescriptor.paper())
    _types.register(SaLayerTypeDescriptor.canvas())
    _kept_root = NewDocumentTemplates.root
    _kept_last = SaSettings.last_template
    NewDocumentTemplates.root = _saved_root
    _empty_saved_root()


func after_each() -> void:
    _empty_saved_root()
    NewDocumentTemplates.root = _kept_root
    SaSettings.last_template = _kept_last
    _types = null


## Removes what a case saved, by hand rather than through the trash, so a run
## leaves nothing in the painter's.
func _empty_saved_root() -> void:
    if not DirAccess.dir_exists_absolute(_saved_root):
        return
    for file: String in DirAccess.get_files_at(_saved_root):
        DirAccess.remove_absolute(_saved_root.path_join(file))
    DirAccess.remove_absolute(_saved_root)


## Every shipped template fills every row it names. A template that names no
## space leaves the one the dialog showed, so it is compared only where named.
func test_each_shipped_template_fills_every_row_it_names() -> void:
    var dialog := NewDocumentDialog.new(_types)
    var depth := dialog.selected_space().depth
    for record: Dictionary in NewDocumentTemplates.SHIPPED:
        var id := String(record[NewDocumentTemplates.ID])
        var label := SaPage.translated(String(record[NewDocumentTemplates.LABEL]))
        assert_true(dialog.select_row(&"template", label), "%s is on the row" % id)
        assert_eq(dialog.template, id, "and picking it takes %s" % id)
        assert_eq(dialog.selected_size(), record[NewDocumentTemplates.SIZE], "%s fills the width and the height" % id)
        var dpi := float(record[NewDocumentTemplates.DPI])
        assert_almost_eq(dialog.selected_dpi(), dpi, 1e-6, "%s fills the resolution" % id)
        if record.has(NewDocumentTemplates.SPACE):
            var space := StringName(record[NewDocumentTemplates.SPACE])
            assert_eq(dialog.selected_space().id, space, "%s fills the colour space" % id)
            assert_eq(dialog.selected_space().depth, depth, "and keeps the depth it does not name")
        var want: Dictionary = record[NewDocumentTemplates.BACKGROUND]
        var have := dialog.selected_background()
        assert_eq(have[SaDocumentBackground.KIND], want[SaDocumentBackground.KIND], "%s fills the background" % id)
        if want[SaDocumentBackground.KIND] == SaDocumentBackground.COLOUR:
            assert_eq(have[SaDocumentBackground.COLOR], want[SaDocumentBackground.COLOR], "%s fills its colour" % id)
            assert_eq(have[SaDocumentBackground.GROUND], want[SaDocumentBackground.GROUND], "%s fills the ground" % id)
        assert_eq(dialog.row_option(&"template").text, label, "and is not marked changed")
    dialog.free()


## A moved row leaves the template's name on the row with "(changed)" after
## it, moving it back takes the mark away, and Create makes what the rows say.
func test_a_moved_row_marks_the_template_changed_and_create_makes_the_rows() -> void:
    var dialog := NewDocumentDialog.new(_types)
    assert_true(dialog.select_row(&"template", "A4 portrait, 300 dpi"), "A4 is on the row")
    dialog.page.row(&"width").drive(2000)
    assert_eq(dialog.template, "a4", "a moved width keeps the template")
    assert_eq(dialog.row_option(&"template").text, "A4 portrait, 300 dpi (changed)", "and marks it changed")
    dialog.page.row(&"width").drive(2480)
    assert_eq(dialog.row_option(&"template").text, "A4 portrait, 300 dpi", "moving it back takes the mark away")
    dialog.select_row(&"background", "Transparent")
    assert_eq(dialog.row_option(&"template").text, "A4 portrait, 300 dpi (changed)", "and the background is a row it names")

    var made: Array = []
    dialog.document_requested.connect(
        func(size: Vector2i, space: SaColorSpace, dpi: float, background: Dictionary) -> void:
            made.append([size, space, dpi, background])
    )
    dialog.create_button.pressed.emit()
    assert_eq(made.size(), 1, "Create asks for one document")
    assert_eq(made[0][0], Vector2i(2480, 3508), "of the size the rows say")
    assert_almost_eq(float(made[0][2]), 300.0, 1e-6, "at their resolution")
    var asked: Dictionary = made[0][3]
    var said := "and on what they say, not on the template's white"
    assert_eq(asked[SaDocumentBackground.KIND], SaDocumentBackground.TRANSPARENT, said)
    assert_eq(SaSettings.last_template, "a4", "and the template is kept as the last one used")
    dialog.free()


## Save as template writes the rows to a file, and a new dialog lists it after
## the shipped ones and fills the same rows from it, a toned paper in Oklab.
func test_a_saved_template_survives_a_new_dialog_and_fills_the_same_rows() -> void:
    var dialog := NewDocumentDialog.new(_types)
    dialog.page.row(&"width").drive(1234)
    dialog.page.row(&"height").drive(987)
    dialog.page.row(&"dpi").drive(150)
    dialog.select_row(&"space", SaColorSpace.display_name(SaColorSpace.ID_OKLAB))
    dialog.select_row(&"depth", "32-bit float")
    dialog.page.row(&"background_colour").drive("#d9b380")
    dialog.select_row(&"ground", "Paper")
    var space := dialog.selected_space()
    var id := dialog.save_template("  Toned study ")
    assert_eq(id, "saved:Toned study", "the template is saved under its trimmed name")
    assert_true(FileAccess.file_exists(_saved_root.path_join("Toned study.json")), "as one JSON file in the templates folder")
    assert_eq(dialog.row_option(&"template").text, "Toned study", "and the row shows it")
    assert_false(dialog.template_saver.delete_button.disabled, "which can be deleted")
    dialog.free()

    var again := NewDocumentDialog.new(_types)
    var labels := again.row_option(&"template").choice_labels()
    assert_eq(labels.size(), NewDocumentTemplates.SHIPPED.size() + 1, "a new dialog lists it")
    assert_eq(labels[labels.size() - 1], "Toned study", "after the shipped ones")
    assert_true(again.select_row(&"template", "Toned study"), "and it can be picked")
    assert_eq(again.selected_size(), Vector2i(1234, 987), "it fills the size")
    assert_almost_eq(again.selected_dpi(), 150.0, 1e-6, "the resolution")
    assert_true(again.selected_space().matches(space), "the colour space and the depth")
    var background := again.selected_background()
    assert_eq((background[SaDocumentBackground.COLOR] as Color).to_html(false), "d9b380", "the colour")
    assert_eq(background[SaDocumentBackground.GROUND], &"paper", "and the ground")
    assert_eq(again.row_option(&"template").text, "Toned study", "so the row reads unchanged")
    again.free()


## A shipped template is no file, so it cannot be deleted, and Delete says so.
func test_a_shipped_template_cannot_be_deleted() -> void:
    var dialog := NewDocumentDialog.new(_types)
    dialog.select_row(&"template", "Square, 2048 × 2048 px")
    assert_true(dialog.template_saver.delete_button.disabled, "Delete is off for a shipped template")
    assert_false(dialog.delete_template(), "and pressing it anyway deletes nothing")
    assert_eq(dialog.template, "sketch", "and the row stays on it")
    dialog.free()


## The dialog opens on the template last used, and on the first shipped one
## when the profile names none or one that is gone.
func test_the_dialog_opens_on_the_last_template_used() -> void:
    SaSettings.last_template = "comic"
    var dialog := NewDocumentDialog.new(_types)
    assert_eq(dialog.template, "comic", "the dialog opens on the comic page")
    assert_eq(dialog.selected_size(), Vector2i(4125, 6263), "with its size")
    assert_almost_eq(dialog.selected_dpi(), 600.0, 1e-6, "and its resolution")
    dialog.free()

    SaSettings.last_template = "saved:gone"
    var fallback := NewDocumentDialog.new(_types)
    assert_eq(fallback.template, "screen", "a template that is gone opens the first shipped one")
    assert_eq(fallback.selected_size(), NewDocumentDialog.DEFAULT_SIZE, "at the size the dialog always opened on")
    assert_almost_eq(fallback.selected_dpi(), SaDocument.DEFAULT_DPI, 1e-6, "and its resolution")
    fallback.free()
