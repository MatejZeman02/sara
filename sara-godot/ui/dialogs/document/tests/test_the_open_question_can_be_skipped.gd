## Opening a picture as a document can skip the colour space and depth question
##
## The window was too much for artists, so it carries
## "Show this next time" and Preferences > Files has the row that brings it back.
## A `Window` added to the tree in a headless run hangs, so the dialog here is
## detached and what it can hold is its switch, what pressing Open writes and
## what the skipped path answers. The window itself, and the second picture that
## opens without it, are read off the running app by
## `scenarios/opening-a-picture-as-a-document-can-skip-the-colour-space-and-depth.json`.
extends "res://tests/test_framework.gd"

static var scratch_path: String = SaDataRoot.path("test_b8_scratch.cfg")
static var other_path: String = SaDataRoot.path("test_b8_other.cfg")

var _asks: bool
var _depth: String
var _path: String


func before_each() -> void:
    _asks = SaSettings.ask_when_opening
    _depth = SaSettings.import_depth
    _path = SaSettings.settings_path


func after_each() -> void:
    SaSettings.settings_path = _path
    SaSettings.ask_when_opening = _asks
    SaSettings.import_depth = _depth
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(other_path))


func test_the_question_is_asked_until_it_is_turned_off() -> void:
    var bare := SaSettingsValues.new()
    assert_true(bare.ask_when_opening, "A bare profile asks")
    bare.free()
    assert_true(SaSettingsKeys.place_of(&"ask_when_opening").size() == 2, "and the preference has a place in the file")


## The third clause: a profile saved with the switch off reads it off.
func test_a_profile_saved_with_the_switch_off_loads_it_off() -> void:
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.ask_when_opening = false
    # Every setter saves, so moving off the values has to happen against another
    # file or the one under test would be overwritten.
    SaSettings.settings_path = ProjectSettings.globalize_path(other_path)
    SaSettings.ask_when_opening = true
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.load_settings()
    assert_false(SaSettings.ask_when_opening, "The switch comes back off")


func test_the_window_opens_with_its_switch_on_and_open_writes_it_off() -> void:
    var dialog := SaImportFitDialog.new()
    dialog.configure_open(Vector2i(64, 64), SaColorSpace.srgb(), -1)
    assert_true(dialog.show_next_time, "The window opens with Show this next time on")
    assert_true(dialog.find_child("ShowNextTimeCheck", true, false) != null, "and the row is there")
    dialog.show_next_time = false
    (dialog.default_button as Button).pressed.emit()
    assert_false(SaSettings.ask_when_opening, "Open with it off keeps the question away")
    dialog.free()


func test_open_with_the_switch_on_leaves_the_preference_alone() -> void:
    var dialog := SaImportFitDialog.new()
    SaSettings.ask_when_opening = true
    dialog.configure_open(Vector2i(64, 64), SaColorSpace.srgb(), -1)
    (dialog.default_button as Button).pressed.emit()
    assert_true(SaSettings.ask_when_opening, "Open with it on asks again next time")
    dialog.free()


func test_the_fit_question_has_no_such_switch() -> void:
    var dialog := SaImportFitDialog.new()
    dialog.configure(Vector2i(64, 64), Vector2i(128, 128), SaColorSpace.srgb())
    assert_false(dialog._show_row.line.visible, "An import is not asked whether to show an open question")
    dialog.free()


## A host in the tree cannot be built here, the root being busy while a suite
## runs, so this is the quick path's answer from a host that is not in one. That
## it is the switch and not the missing tree that sends a host in the tree down
## it is what the scenario's second open shows.
func test_with_the_switch_off_the_open_answers_at_once() -> void:
    var host := Node.new()
    SaSettings.ask_when_opening = false
    SaSettings.import_depth = "f32"
    var answers: Array[SaColorSpace] = []
    var image := SaImageImport.read("res://tests/data/import_gradient.png")
    SaImportFitDialog.choose_depth(host, image, SaColorSpace.srgb(), func(space: SaColorSpace) -> void: answers.append(space))
    assert_eq(answers.size(), 1, "The picture opens at once")
    assert_eq(answers[0].depth, SaColorSpace.Depth.F32, "at the remembered depth, a PNG naming none")
    assert_eq(String(answers[0].id), String(SaColorSpace.srgb().id), "in the space it was read as")
    assert_true(host.get_node_or_null(NodePath("ImportFitDialog")) == null, "and no window was built")
    host.free()
