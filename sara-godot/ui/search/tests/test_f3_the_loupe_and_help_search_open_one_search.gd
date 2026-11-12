## F3, the loupe and Help's Search command open one search.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The two searches are one, the one with more features. Here the application's commands are
## registered as the app registers them, the list is the one `SaSearchWindow`
## each way in finds in the tree, and its settings' rows are built before the
## suite reads them, as the idle app builds them out of sight. A preset is saved
## in a scratch folder so a preset is a row. What a painter sees is
## `scenarios/f3-the-loupe-and-help-search-open-one-search.json`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

const PRESET := "Lichen Wash"

static var scratch_dir: String = SaDataRoot.path("test_one_search")

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _host: Node = null
var _bar: TopMenuBar = null
var _box: ToolOptionsPresets = null
var _settings: Resource = null
var _window: SaSearchWindow = null
var _was_embedding := false
var _actions_before: Array[StringName] = []


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _actions_before = InputMap.get_actions()
    ScratchFolder.empty(scratch_dir)
    _host = Node.new()
    _host.name = "U128SearchHost"
    EventBus.add_child(_host)
    # First under EventBus, so `find_in` meets this suite's list before one an
    # earlier suite's awaited test has not freed yet.
    EventBus.move_child(_host, 0)

    _registries = Fixtures.make_menu_registries()
    _easel = SaEasel.create_default(Vector2i(256, 256))
    _easel.compositor.set_registry(_registries.blend_modes)

    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(_registries.commands)
    var layer_menu := _bar.menu("Layer") as SaLayerMenu
    layer_menu.document = _easel.document
    layer_menu.layer_types = _registries.layer_types

    _settings = StampSettingsScript.new()
    _box = ToolOptionsPresets.new()
    _box.preset_store.dir = scratch_dir
    _box.settings_source = func() -> Resource: return _settings
    _box.preset_store.save_preset(PRESET, StampSettingsScript.new())
    _host.add_child(_box)

    _window = SaSearchWindow.new(SaSearchIndex.new(_registries.context), _bar)
    _host.add_child(_window)
    _window.index.warm()


func after_each() -> void:
    _host.free()
    _host = null
    _window = null
    _bar = null
    _easel.free()
    _easel = null
    _registries = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding
    ScratchFolder.empty(scratch_dir)
    for action: StringName in InputMap.get_actions():
        if not _actions_before.has(action):
            InputMap.erase_action(action)


# --- One list, three ways in ----------------------------------------------------


## F3's command, the loupe's press and `help_search` open the same list, with
## the same rows in the same order, and a setting's word finds the setting from
## F3's opening, where a pick asks Preferences for it.
func test_three_ways_in_open_the_same_rows_and_f3_finds_a_setting() -> void:
    var word := _a_settings_word()
    assert_false(word.is_empty(), "The catalogue has a setting whose title has a word of its own")
    var seen: Array = []
    for way: String in ["F3", "loupe", "help_search"]:
        await _open_by(way)
        assert_true(_window.visible, "%s opens the list" % way)
        assert_true(SaSearchWindow.find_in(_window.get_tree()) == _window, "and it is the one list in the tree")
        seen.append(_titles(_window.entries))
        _type(word)
        var row := _setting_row()
        assert_true(row != null, "%s's opening finds the setting %s by %s" % [way, _word_title, word])
        _window.hide()
        # The loupe opens nothing in the frame the list closed in, which is the
        # press outside the list that closed it. The runner never waited for
        # this case's frames, so the loupe's line never ran.
        await (Engine.get_main_loop() as SceneTree).process_frame
    assert_eq(seen[1], seen[0], "The loupe's rows are F3's, in F3's order")
    assert_eq(seen[2], seen[0], "and so are help_search's")
    assert_true((seen[0] as Array).size() > 300, "a list of every kind, %d rows" % (seen[0] as Array).size())

    await _open_by("F3")
    _type(word)
    var asked: Array = []
    var listen := func(page: String, title: StringName) -> void: asked.append([page, String(title)])
    # A request an earlier suite deferred goes out in the frame before, not to
    # this listener.
    await (Engine.get_main_loop() as SceneTree).process_frame
    EventBus.settings_row_requested.connect(listen)
    _window.pick(_setting_row())
    await (Engine.get_main_loop() as SceneTree).process_frame
    EventBus.settings_row_requested.disconnect(listen)
    assert_eq(asked, [[_word_page, _word_title]], "A pick from F3's opening asks Preferences for the setting's page and row")
    assert_false(_window.visible, "and closes the list")


## A title the query starts is ranked before a title that holds it as a later
## word, whichever comes first alphabetically.
func test_a_title_that_starts_with_the_query_comes_first() -> void:
    _window.open()
    _type("layer")
    var first := -1
    var later := -1
    for at in _window.shown.size():
        var words := _window.shown[at].title.to_lower().split(" ")
        if first < 0 and words[0].begins_with("layer"):
            first = at
        if later < 0 and words.size() > 1 and not words[0].begins_with("layer") and words[1].begins_with("layer"):
            later = at
    assert_true(first >= 0 and later >= 0, "layer finds a title that starts with it and one that holds it later")
    assert_true(
        first < later,
        (
            "and the one that starts with it comes first, %s before %s"
            % [_window.shown[maxi(first, 0)].title, _window.shown[maxi(later, 0)].title]
        )
    )


## An opening draws a page of rows, however many the list holds, and the next
## page is drawn when the keyboard walks past the last.
func test_an_opening_draws_a_page_of_rows() -> void:
    _window.open()
    assert_true(_window.shown.size() > SaSearchWindow.PAGE * 4, "The list holds %d rows" % _window.shown.size())
    assert_eq(_window.row_ids().size(), SaSearchWindow.PAGE, "and its opening draws %d" % SaSearchWindow.PAGE)
    for _step in SaSearchWindow.PAGE:
        _window.move_highlight(1)
    assert_eq(_window.row_ids().size(), SaSearchWindow.PAGE * 2, "Walking past the last draws the next page")


# --- The offer ------------------------------------------------------------------


## A right press and the Menu key on a command's row offer to keep it and to
## give it a chord, and on a setting, a preset and a layer kind both are dimmed.
func test_a_command_row_offers_and_the_others_are_dimmed() -> void:
    _window.open()
    _type("redo")
    var redo := _row_of_kind(SaSearchIndex.COMMAND, "Redo")
    assert_false(redo.is_empty(), "Redo is a command's row")
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_RIGHT
    press.pressed = true
    _window.label_button(redo).gui_input.emit(press)
    _offered(true, "A right press on Redo")
    _window.child_list.hide()

    assert_true(_window.set_highlight(redo), "The keyboard is put on Redo")
    _menu_key()
    _offered(true, "The Menu key on Redo")
    _window.child_list.hide()

    var cases := [
        [SaSearchIndex.SETTING, _a_settings_word()],
        [SaSearchActions.PRESET, "lichen"],
        [SaSearchActions.LAYER, "new canvas layer"]
    ]
    for case: Array in cases:
        _type(case[1])
        var row := _row_of_kind(case[0], "")
        assert_false(row.is_empty(), "%s finds a %s row" % [case[1], case[0]])
        assert_true(_window.set_highlight(row), "and the keyboard is put on it")
        _menu_key()
        _offered(false, "The Menu key on a %s" % case[0])
        _window.child_list.hide()


# --- Helpers --------------------------------------------------------------------

var _word_title: String = ""
var _word_page: String = ""


## A word that starts a word of one setting's title and of no other row's, read
## from the catalogue now, so the suite names no setting.
func _a_settings_word() -> String:
    var everything := _window.index.entries(SaSearchActions.menus_of(_bar))
    for entry: SaSearchIndex.Entry in _window.index._settings:
        for word: String in entry.title.to_lower().split(" "):
            if word.length() < 6 or not word.is_valid_identifier():
                continue
            var found := SaSearchIndex.narrowed(everything, word)
            if found.size() == 1 and found[0] == entry:
                _word_title = entry.title
                _word_page = entry.place
                return word
    return ""


func _setting_row() -> SaSearchIndex.Entry:
    for entry: SaSearchIndex.Entry in _window.shown:
        if entry.kind == SaSearchIndex.SETTING and entry.title == _word_title:
            return entry
    return null


func _open_by(way: String) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    match way:
        "F3":
            assert_true(_registries.commands.execute(SaQuickCommands.SEARCH), "F3's command runs")
        "help_search":
            assert_true(_registries.commands.execute(SaSearchWindow.COMMAND), "help_search runs")
        "loupe":
            var loupe := _bar.find_child("SearchLoupe", true, false) as Button
            loupe.pressed.emit()
    await tree.process_frame


func _titles(entries: Array[SaSearchIndex.Entry]) -> Array[String]:
    var out: Array[String] = []
    for entry: SaSearchIndex.Entry in entries:
        out.append("%s|%s|%s" % [entry.kind, entry.title, entry.place])
    return out


func _type(text: String) -> void:
    _window.field.text = text
    _window.field.text_changed.emit(text)


## The first drawn row of *kind*, titled *title* when it is not empty.
func _row_of_kind(kind: String, title: String) -> StringName:
    for row_id: StringName in _window.row_ids():
        var entry := _window.entry_of(row_id)
        if entry != null and entry.kind == kind and (title.is_empty() or entry.title == title):
            return row_id
    return &""


func _menu_key() -> void:
    var key := InputEventKey.new()
    key.keycode = KEY_MENU
    key.pressed = true
    _window.push_input(key)


func _offered(live: bool, way: String) -> void:
    var asked := _window.child_list
    assert_true(asked != null and asked.visible, "%s opens the offer beside the row" % way)
    if asked == null:
        return
    assert_true(asked.row_ids().has(SaQuickCommands.ROW_ADD), "with Add to Quick Favourites")
    assert_eq(asked.is_disabled(SaQuickCommands.ROW_ADD), not live, "enabled" if live else "dimmed")
    assert_eq(asked.is_disabled(SaQuickCommands.ROW_ASSIGN), not live, "and Assign Shortcut... the same")
