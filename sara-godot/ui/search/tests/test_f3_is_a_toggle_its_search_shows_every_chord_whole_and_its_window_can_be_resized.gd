## F3 is a toggle, the search shows every chord whole, and
## its window can be resized.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The F3 search window is resizeable, shows every command's actual shortcut and
## is a toggle. The application's commands are registered as
## the app registers them, the list is laid out in real frames, and a chord
## cell is whole when its width holds its text in the font it is drawn in. What
## a painter sees is
## `scenarios/f3-is-a-toggle-its-search-shows-every-chord-whole-and-its-window-can-be-resized.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

const PSEUDO := "res://tests/fixtures/modules/pseudo/language-pseudo/en_XA.po"
const PSEUDO_LOCALE := "en_XA"
## The command Brightness/Contrast has always answered to.
const COMMAND := &"filter_brightness_contrast"

var _host: Node = null
var _registries: SaRegistries = null
var _bar: TopMenuBar = null
var _window: SaSearchWindow = null
var _loupe: Button = null
var _router: ShortcutRouter = null
var _was_embedding: bool = true
var _actions_before: Array[StringName] = []
var _kept_size: Vector2i = Vector2i.ZERO
var _kept_scale: float = 1.0
var _kept_locale: String = ""
var _catalogue: Translation = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _actions_before = InputMap.get_actions()
    _kept_size = SaSettings.search_window_size
    _kept_scale = SaSettings.ui_scale
    _kept_locale = TranslationServer.get_locale()
    SaSettings.search_window_size = Vector2i.ZERO
    _host = Node.new()
    _host.name = "U457SearchHost"
    EventBus.add_child(_host)
    # First under EventBus, so `find_in` meets this suite's list before one an
    # earlier suite's awaited test has not freed yet.
    EventBus.move_child(_host, 0)
    _registries = Fixtures.make_menu_registries()
    # The base module, whose filters carry the chords the painter looks for.
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _router.commands = _registries.commands
    _host.add_child(_router)
    _router.watch_windows(tree)
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(_registries.commands)
    _loupe = _bar.find_child("SearchLoupe", true, false) as Button
    _window = SaSearchWindow.new(SaSearchIndex.new(_registries.context), _bar)
    _host.add_child(_window)


func after_each() -> void:
    if _catalogue != null:
        TranslationServer.remove_translation(_catalogue)
        _catalogue = null
    TranslationServer.set_locale(_kept_locale)
    SaSettings.ui_scale = _kept_scale
    SaSettings.search_window_size = _kept_size
    _host.free()
    _host = null
    _bar = null
    _window = null
    _loupe = null
    _router = null
    _registries = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding
    for action: StringName in InputMap.get_actions():
        if not _actions_before.has(action):
            InputMap.erase_action(action)


# --- The chord whole ------------------------------------------------------------


## "contrast" finds Brightness/Contrast with its chord whole, at interface
## scale 1 and 2 and in the test language.
func test_the_brightness_contrast_chord_shows_whole() -> void:
    for way: Array in [[1.0, ""], [2.0, ""], [1.0, PSEUDO_LOCALE]]:
        SaSettings.ui_scale = way[0]
        if not (way[1] as String).is_empty():
            _speak_pseudo()
        await _open()
        _type("contrast")
        await _settle()
        var cell := _chord_cell_of()
        var said := "at scale %s%s" % [way[0], " in the test language" if not (way[1] as String).is_empty() else ""]
        assert_not_null(cell, "contrast finds Brightness/Contrast %s" % said)
        if cell == null:
            _window.hide()
            continue
        assert_eq(cell.text, "Ctrl+Shift+B", "its chord cell reads Ctrl+Shift+B %s" % said)
        assert_true(_whole(cell), "and shows it whole, %s wide for %s, %s" % [cell.size.x, _need(cell), said])
        _window.hide()
        await _settle()


## Every chord of the whole list shows whole, every page drawn.
func test_every_chord_of_the_full_list_shows_whole() -> void:
    await _open()
    var pages := 0
    while _window.row_ids().size() < _window.shown.size() and pages < _window.shown.size():
        _window.add_rows()
        pages += 1
    assert_eq(_window.row_ids().size(), _window.shown.size(), "Every row of the full list is added")
    await _settle()
    var chords := 0
    var cut: Array[String] = []
    for id: StringName in _window.row_ids():
        var cell := _window.row_of(id).get_node("Chord") as Label
        if cell.text.is_empty():
            continue
        chords += 1
        if not _whole(cell):
            cut.append("%s %s" % [_window.entry_of(id).title, cell.text])
    assert_true(chords > 50, "The list holds %d chords" % chords)
    assert_eq(cut, [] as Array[String], "and none is cut")


# --- The toggle -----------------------------------------------------------------


## F3 through the input map opens the list with the loupe down, and F3 again,
## the field holding the keyboard, closes it and lets the loupe up.
func test_f3_opens_and_f3_again_closes() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var action := _registries.commands.get_descriptor(SaQuickCommands.SEARCH).action
    var events := InputMap.action_get_events(action)
    assert_false(events.is_empty(), "F3's command is in the input map")
    var f3 := (events[0] as InputEventKey).duplicate() as InputEventKey
    assert_eq(f3.keycode, KEY_F3, "bound to F3")
    f3.pressed = true
    _router.handle_viewport_input(f3, tree.root)
    assert_eq(_registries.commands.last_command, SaQuickCommands.SEARCH, "F3 runs Search Commands")
    await _settle()
    assert_true(_window.visible, "F3 opens the search")
    assert_true(_loupe.button_pressed, "and the loupe reads pressed")
    _window.field.grab_focus()
    await tree.process_frame
    assert_true(_window.field.has_focus(), "The field holds the keyboard")
    # A second press is an event of its own, as a keyboard's is: the router
    # keeps the one it took and its gate in the list's window swallows that.
    var again := f3.duplicate() as InputEventKey
    _window.window_input.emit(again)
    _window.push_input(again)
    assert_false(_window.visible, "F3 again closes the search")
    assert_false(_loupe.button_pressed, "and lets the loupe up")
    # The same press reaching the router as well runs the command, whose
    # opening is deferred to this frame, and opens nothing.
    SaSearchWindow._open_with()
    assert_false(_window.visible, "and the command run by the same press leaves it closed")
    await _settle()
    _router.handle_viewport_input(f3.duplicate() as InputEventKey, tree.root)
    await _settle()
    assert_true(_window.visible, "A third F3 in a later frame opens it again")


# --- The size -------------------------------------------------------------------


## A drag of the grip resizes the list, never below a chord and a title of
## twelve characters, and the next opening takes the size it was left at.
func test_a_resize_is_kept_for_the_next_opening() -> void:
    await _open()
    _type("contrast")
    await _settle()
    var before := _window.size
    _drag(Vector2(140, 90))
    await _settle()
    var resized := _window.size
    assert_true(resized.x > before.x and resized.y > before.y, "The grip grows the list, %s to %s" % [before, resized])
    _window.hide()
    await _settle()
    assert_eq(SaSettings.search_window_size, resized, "The size it was left at is in the settings")
    await _open()
    assert_eq(_window.size, resized, "and the next opening takes it")

    _type("contrast")
    await _settle()
    _drag(Vector2(-4000, -4000))
    await _settle()
    assert_eq(_window.size, _window.min_size, "A drag far in stops at the least size, %s" % _window.min_size)
    var cell := _chord_cell_of()
    assert_not_null(cell, "where the row still shows")
    if cell != null:
        assert_true(_whole(cell), "its chord whole, %s wide for %s" % [cell.size.x, _need(cell)])
        var heading := cell.get_parent() as SaChoiceRow
        var title := heading.label_button()
        var twelve := _width_in(title, "Brightness/Contrast".left(SaSearchWindow.MIN_TITLE_CHARS))
        assert_true(title.size.x >= twelve, "and twelve characters of its title, %s wide for %s" % [title.size.x, twelve])


# --- Helpers --------------------------------------------------------------------


func _open() -> void:
    _window.open()
    await _settle()


func _settle() -> void:
    for _frame in 3:
        await (Engine.get_main_loop() as SceneTree).process_frame


func _type(text: String) -> void:
    _window.field.text = text
    _window.field.text_changed.emit(text)


func _speak_pseudo() -> void:
    _catalogue = load(PSEUDO) as Translation
    assert_not_null(_catalogue, "The test language's catalogue loads")
    if _catalogue != null:
        TranslationServer.add_translation(_catalogue)
        TranslationServer.set_locale(PSEUDO_LOCALE)


## The chord cell of the row that runs the Brightness/Contrast filter, found
## by its command so the test language's title finds it too.
func _chord_cell_of() -> Label:
    for id: StringName in _window.row_ids():
        var entry := _window.entry_of(id)
        if entry != null and entry.command == COMMAND:
            return _window.row_of(id).get_node("Chord") as Label
    return null


func _need(cell: Label) -> float:
    return _width_in(cell, cell.text)


## How wide *text* is in *control*'s font at its size.
func _width_in(control: Control, text: String) -> float:
    var font := control.get_theme_font(&"font")
    return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size(&"font_size")).x


func _whole(cell: Label) -> bool:
    return cell.is_visible_in_tree() and not cell.clip_text and cell.size.x + 0.5 >= _need(cell)


func _drag(travel: Vector2) -> void:
    var grip := _window.grip
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    grip._gui_input(press)
    var motion := InputEventMouseMotion.new()
    motion.relative = travel
    grip._gui_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    grip._gui_input(release)
