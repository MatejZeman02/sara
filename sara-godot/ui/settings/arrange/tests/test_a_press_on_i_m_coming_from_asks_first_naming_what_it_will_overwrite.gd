## A press on "I'm coming from" asks first, naming what it will overwrite.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Each "I'm coming from <list>" button needs a warning dialog saying it
## will overwrite the current settings. The row stands
## in the tree over a layout store of the suite's own on a scratch file, its
## docker moved the way a drag forks the layout, to "Default (Custom)". Each of
## the four buttons is pressed as a pointer presses it, through its `pressed`
## signal, and the five values the row writes are read before and after each
## answer. A press is spread over frames, each one an emission of the tree's
## `process_frame` and a call of the row's `_process`, as the Clip Studio Paint suite drives
## it. Escape goes through a `ShortcutRouter` watching the tree's windows, the
## way `test_escape_closes_a_dialog.gd` sends it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const KEYS: Array[String] = ["shortcuts_profile", "theme_name", "color_picker_shape", "reset_zoom"]
const MOST_FRAMES: int = 2000

static var scratch_layout_path: String = SaDataRoot.path("test_coming_from_question_layout.cfg")
static var scratch_presets_dir: String = SaDataRoot.path("layouts")

var _registries: SaRegistries = null
var _host: Node = null
var _router: ShortcutRouter = null
var _store: DockerLayoutStore = null
var _row: SaComingFromRow = null
var _saved_layout_state := ConfigFile.new()
var _saved := {}
var _was_embedding: bool = false


func before_each() -> void:
    for key: String in KEYS:
        _saved[key] = SaSettings.get(key)
        SaSettings.set(key, (SaSettingsValues as Script).get_property_default_value(key))
    _registries = Fixtures.make_menu_registries()
    SaShortcutStore.capture_defaults()
    SaTheme.use_named(SaSettings.theme_name)
    SaShortcutStore.apply_profile(SaSettings.shortcuts_profile)
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "ComingFromQuestionHost"
    EventBus.add_child(_host)
    _router = ShortcutRouter.new()
    _router.name = "ComingFromQuestionRouter"
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _host.add_child(_router)
    _router.watch_windows(tree)
    var surface := Control.new()
    surface.set_anchors_preset(Control.PRESET_FULL_RECT)
    _host.add_child(surface)
    var docker := Window.new()
    docker.size = Vector2i(200, 150)
    surface.add_child(docker)
    _store = DockerLayoutStore.new()
    _store.path = scratch_layout_path
    _store.dockers_provider = func() -> Array: return [{"id": "ProbeDocker", "name": "Probe", "node": docker}]
    _store.save_allowed = func() -> bool: return true
    _saved_layout_state = ConfigFile.new()
    _store.presets().capture(_saved_layout_state)
    _row = SaComingFromRow.new(_store)
    surface.add_child(_row)
    # The docker moved by a drag: the store saves it and forks the shipped
    # layout, as `MainDockers` does on the painter's change.
    docker.position = Vector2i(300, 120)
    _store.save(true)
    _store.fork_for_painter_edit()


func after_each() -> void:
    _settle()
    if _row.question != null and is_instance_valid(_row.question):
        _row.question.free()
    _row.free()
    _store.presets().apply(_saved_layout_state)
    _store.free()
    _host.free()
    _host = null
    _router = null
    _registries = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding
    for key: String in _saved:
        SaSettings.set(key, _saved[key])
    SaTheme.use_named(SaSettings.theme_name)
    SaShortcutStore.apply_profile(SaSettings.shortcuts_profile)
    EventBus.shortcuts_changed.emit()
    var dir := DirAccess.open(scratch_presets_dir)
    if dir != null:
        for file_name in dir.get_files():
            DirAccess.remove_absolute(scratch_presets_dir.path_join(file_name))
    DirAccess.remove_absolute(scratch_layout_path)


## One harness frame.
func _frame() -> void:
    (Engine.get_main_loop() as SceneTree).process_frame.emit()
    _row._process(0.0)


## Frames until no press and no palette slice is left.
func _settle() -> void:
    var frames := 0
    while (_row.pressing() or SaTheme.repainting()) and frames < MOST_FRAMES:
        _frame()
        frames += 1


## The five values the row writes, as they stand.
func _five() -> Array:
    return [
        SaSettings.shortcuts_profile,
        SaSettings.theme_name,
        _store.current_preset(),
        SaSettings.color_picker_shape,
        SaSettings.reset_zoom,
    ]


## *program*'s button pressed as a pointer presses it, and the frames a press
## would take run, answering the question it put up.
func _press_button(program: String) -> SaMessage:
    _row.buttons[program].pressed.emit()
    for i in 10:
        _frame()
    return _row.question


static func _escape() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ESCAPE
    key.physical_keycode = KEY_ESCAPE
    key.pressed = true
    return key


func test_the_moved_docker_forked_the_layout() -> void:
    assert_eq(_store.current_preset(), "default (custom)", "the suite's profile has its own arrangement in force")


func test_every_button_asks_and_writes_nothing_before_the_answer() -> void:
    var before := _five()
    for program: String in SaComingFromRow.PROGRAMS:
        var question := _press_button(program)
        assert_not_null(question, "%s's press put a question up" % program)
        if question == null:
            continue
        assert_true(question.visible, "and the question is on screen")
        assert_eq(_five(), before, "nothing is written while %s's question is up" % program)
        assert_false(_row.pressing(), "and no press is under way")
        assert_false(_row.buttons[program].button_pressed, "the button shows what is in force, not the press")
        question.buttons[SaComingFromQuestion.ANSWER_CANCEL].pressed.emit()
        _settle()


func test_cancel_writes_nothing() -> void:
    var before := _five()
    for program: String in SaComingFromRow.PROGRAMS:
        var question := _press_button(program)
        question.buttons[SaComingFromQuestion.ANSWER_CANCEL].pressed.emit()
        _settle()
        assert_false(question.visible if is_instance_valid(question) else false, "Cancel took %s's question away" % program)
        assert_eq(_five(), before, "and after Cancel on %s nothing was written" % program)
        assert_eq(_store.current_preset(), "default (custom)", "the painter's arrangement is still the one in force")


func test_escape_writes_nothing() -> void:
    var before := _five()
    for program: String in SaComingFromRow.PROGRAMS:
        var question := _press_button(program)
        question.window_input.emit(_escape())
        question.push_input(_escape())
        _settle()
        assert_false(question.visible if is_instance_valid(question) else false, "Escape took %s's question away" % program)
        assert_eq(_five(), before, "and after Escape on %s nothing was written" % program)


func test_overwrite_writes_the_program_s_five() -> void:
    for program: String in SaComingFromRow.PROGRAMS:
        var question := _press_button(program)
        question.buttons[SaComingFromQuestion.ANSWER_OVERWRITE].pressed.emit()
        _settle()
        assert_true(
            SaComingFromRow.holds(SaComingFromRow.values_of(program), _store), "Overwrite put %s's five in force" % program
        )
        assert_true(_row.buttons[program].button_pressed, "and its button shows pressed")
        # The lit button released, which asks as well, back to Sara's own.
        var release := _press_button(program)
        assert_not_null(release, "a press on the lit %s button asks too" % program)
        if release == null:
            continue
        assert_eq(release.title, "Go back to Sara's own settings?", "and says it goes back to Sara's own")
        assert_true(SaComingFromRow.holds(SaComingFromRow.values_of(program), _store), "nothing written before the answer")
        release.buttons[SaComingFromQuestion.ANSWER_OVERWRITE].pressed.emit()
        _settle()
        assert_true(SaComingFromRow.holds(SaComingFromRow.OWN_VALUES, _store), "Overwrite put Sara's own back")


func test_the_question_names_the_program_the_five_and_what_stays() -> void:
    var question := _press_button("krita")
    assert_eq(question.title, "Set Sara up as Krita?", "the title names the program")
    var said := question.text_label.text
    for line: String in [
        "Shortcut profile: 'Sara Default' becomes 'Krita'",
        "Colour theme: 'Sara Green' becomes 'Krita Grey'",
        "Docker layout: 'Default (Custom)' becomes 'Krita'",
        "Colour picker: 'OKHSV, square' becomes 'HSV, triangle'",
        "Ctrl+0 shows: 'The whole picture' becomes 'Actual pixels'",
        "The UI scale stays as it is.",
        "Your own shortcut profiles, palettes and layouts stay on disk and can be picked again.",
    ]:
        assert_true(said.contains(line), 'the question says "%s", it says:\n%s' % [line, said])
    assert_eq(question.buttons[SaComingFromQuestion.ANSWER_CANCEL].text, "Cancel", "the first answer is Cancel")
    assert_eq(question.buttons[SaComingFromQuestion.ANSWER_OVERWRITE].text, "Overwrite", "the second is Overwrite")
    assert_eq(question._default_index, SaComingFromQuestion.ANSWER_CANCEL, "Enter answers Cancel")
    assert_eq(question.cancel_index, SaComingFromQuestion.ANSWER_CANCEL, "and so do Escape and the close button")
    question.buttons[SaComingFromQuestion.ANSWER_CANCEL].pressed.emit()


func test_a_value_already_at_the_program_s_says_it_stays() -> void:
    SaSettings.reset_zoom = SaView.RESET_PIXELS
    var question := _press_button("krita")
    assert_true(question.text_label.text.contains("Ctrl+0 shows: 'Actual pixels' stays"), "a value already Krita's stays")
    question.buttons[SaComingFromQuestion.ANSWER_CANCEL].pressed.emit()


## Where the five already stand at the answer's values a press asks nothing.
## Through the buttons that is a second press before the first has written: the
## answer is Sara's own again and the five are still Sara's own, the shipped
## layout among them, since the fork is not Sara's own layout.
func test_no_question_where_the_five_already_match() -> void:
    _store.load_preset(SaComingFromRow.OWN_VALUES["layout"])
    for program: String in SaComingFromRow.PROGRAMS:
        _row.press(program)
        _row.buttons[program].pressed.emit()
        assert_null(_row.question, "the second press on %s asked nothing" % program)
        _settle()
        assert_true(SaComingFromRow.holds(SaComingFromRow.OWN_VALUES, _store), "and the last press, Sara's own, is in force")
    for program: String in SaComingFromRow.PROGRAMS:
        SaComingFromRow.apply(program, _store)
        assert_eq(
            SaComingFromQuestion.changes(program, _store), [] as Array[Dictionary], "%s's five match, nothing to ask" % program
        )
    SaComingFromRow.apply(SaComingFromRow.OWN, _store)
    assert_eq(SaComingFromQuestion.changes(SaComingFromRow.OWN, _store), [] as Array[Dictionary], "nor for Sara's own")


## A row out of the tree, the welcome window's before the main window has a
## store, asks without the layout's line.
func test_no_store_leaves_the_layout_out_of_the_question() -> void:
    var lines := SaComingFromQuestion.lines("photoshop", null)
    var keys: Array[String] = []
    for line: Dictionary in lines:
        keys.append(String(line["key"]))
    assert_eq(keys, ["shortcuts", "palette", "picker", "zoom"] as Array[String], "four lines and no layout")
