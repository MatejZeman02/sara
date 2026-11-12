## The search loupe names its shortcut in its hover and stays
## pressed while Search is open.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The loupe shows the shortcut in a tooltip when hovered and the button is a
## toggle. The bar is a
## real `TopMenuBar` over the application's commands, and the presses are mouse
## events pushed into the root viewport at the loupe's middle, the way a
## painter's click arrives. What a painter sees is
## `scenarios/the-search-loupe-names-its-shortcut-and-stays-pressed-while-search-is-open.json`.
##
## The loupe opens the one search F3 opens, and its hover names the
## chord of either command, F3's first. F3's shipped chord is taken away for
## each test, so the hover reads the chord this suite binds to Help's command.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const CHORD := "Ctrl+Alt+F"
const OTHER_CHORD := "Ctrl+Shift+F"

var _host: Node = null
var _registries: SaRegistries = null
var _bar: TopMenuBar = null
var _window: SaSearchWindow = null
var _loupe: Button = null
var _router: ShortcutRouter = null
var _action: StringName = &""
var _shipped: Array[String] = []
var _f3_action: StringName = &""
var _f3_shipped: Array[String] = []
var _was_embedding: bool = true


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U93SearchHost"
    EventBus.add_child(_host)
    # First under EventBus, so the loupe's `find_in` meets this suite's window
    # before one an earlier suite's awaited test has not freed yet (the pick
    # test tears down a frame after its suite has returned).
    EventBus.move_child(_host, 0)

    _registries = Fixtures.make_registries()
    SaAppCommands.register_all(_registries, func(_id: StringName) -> void: pass)
    _action = _registries.commands.get_descriptor(SaSearchWindow.COMMAND).action
    _shipped = SaShortcutStore.chords_for(_action)
    _f3_action = _registries.commands.get_descriptor(SaQuickCommands.SEARCH).action
    _f3_shipped = SaShortcutStore.chords_for(_f3_action)
    SaShortcutStore.set_chords(_f3_action, [])

    # The router hears a chord over the canvas and Escape in a dialog, the two
    # keys the suite presses, the way it does in the app.
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _router.commands = _registries.commands
    _host.add_child(_router)
    _router.watch_windows(tree)

    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(_registries.commands)
    _window = SaSearchWindow.new(SaSearchIndex.new(_registries.context))
    _host.add_child(_window)
    _loupe = _bar.find_child("SearchLoupe", true, false) as Button
    _lay_out()


func after_each() -> void:
    SaShortcutStore.set_chords(_action, _shipped)
    SaShortcutStore.set_chords(_f3_action, _f3_shipped)
    _host.free()
    _host = null
    _bar = null
    _window = null
    _loupe = null
    _router = null
    _registries = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


# --- The hover ----------------------------------------------------------------


## The hover is read when it is shown: the bare name while the command has no
## chord, the chord once one is bound, and the new chord at once after a rebind.
func test_the_hover_reads_the_chord_as_it_stands() -> void:
    var middle := _loupe.size / 2.0
    assert_eq(_loupe.get_tooltip(middle), "Search every action", "With no chord the hover is the bare name")
    SaShortcutStore.set_chords(_action, [CHORD])
    assert_eq(_loupe.get_tooltip(middle), "Search every action (%s)" % CHORD, "A chord bound is in the hover")
    SaShortcutStore.set_chords(_action, [OTHER_CHORD])
    assert_eq(_loupe.get_tooltip(middle), "Search every action (%s)" % OTHER_CHORD, "and a rebind is in the next hover")
    SaShortcutStore.set_chords(_action, [])
    assert_eq(_loupe.get_tooltip(middle), "Search every action", "and the chord taken away leaves the name")
    SaShortcutStore.set_chords(_f3_action, ["F3"])
    SaShortcutStore.set_chords(_action, [CHORD])
    assert_eq(_loupe.get_tooltip(middle), "Search every action (F3)", "and F3's chord is named before Help's")


# --- The toggle ---------------------------------------------------------------


## A click opens Search and leaves the loupe down, and a second click shuts both.
func test_a_click_opens_search_and_a_second_closes_it() -> void:
    assert_true(_loupe.toggle_mode, "The loupe is a toggle")
    assert_false(_window.visible, "Search starts shut")
    assert_true(_click(), "The click lands on the loupe")
    assert_true(_window.visible, "A click opens Search")
    assert_true(_loupe.button_pressed, "and the loupe reads pressed")
    var under := _loupe.get_global_rect()
    assert_true(
        _window.position.y >= int(under.end.y) and _window.position.x <= int(under.position.x),
        "It opens under the loupe, wherever the pointer was, %s under %s" % [_window.position, under]
    )
    assert_true(_click(), "The second click lands on the loupe")
    assert_false(_window.visible, "A second click shuts Search")
    assert_false(_loupe.button_pressed, "and the loupe is up again")


## The loupe follows the list whichever way it opens or goes: the chord's
## command, Escape, a pick and the list's own close.
func test_the_loupe_follows_the_window_whichever_way_it_moves() -> void:
    SaShortcutStore.set_chords(_action, [CHORD])
    var chord := SaShortcutStore.parse_chord(CHORD)
    chord.pressed = true
    _router.handle_viewport_input(chord, (Engine.get_main_loop() as SceneTree).root)
    assert_eq(_registries.commands.last_command, SaSearchWindow.COMMAND, "as Search's command")
    # The command defers its opening a frame, for the reason its handler records,
    # and a suite has no frame: the deferred call is the window's `open`.
    _window.open()
    assert_true(_loupe.button_pressed, "Search opened by its chord leaves the loupe pressed")

    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.physical_keycode = KEY_ESCAPE
    escape.pressed = true
    # An Escape lets a focused search field go first and the next closes, as
    # the router reads it in a dialog, so a second is sent only when needed.
    for _press: int in 2:
        if not _window.visible:
            break
        _window.window_input.emit(escape)
        _window.push_input(escape)
    assert_false(_window.visible, "Escape shuts Search")
    assert_false(_loupe.button_pressed, "and lets the loupe up")

    _window.open()
    assert_true(_loupe.button_pressed, "Open again, the loupe is down before a pick")
    _window.field.text = "new canvas layer"
    _window.field.text_changed.emit(_window.field.text)
    _window.field.text_submitted.emit(_window.field.text)
    assert_false(_window.visible, "Enter on the marked row shuts Search")
    assert_false(_loupe.button_pressed, "and the pick lets the loupe up")

    _window.open()
    _window.hide()
    assert_false(_loupe.button_pressed, "The window's own close lets the loupe up")


## The pressed state has a box of its own from the toggle family, at the
## title's margins, so it reads as pressed and the row does not move.
func test_the_pressed_loupe_has_a_theme_box_at_the_titles_margins() -> void:
    var normal := _loupe.get_theme_stylebox("normal")
    for state: String in ["pressed", "hover_pressed"]:
        assert_true(_loupe.has_theme_stylebox_override(state), "The %s state has its own box" % state)
        var box := _loupe.get_theme_stylebox(state) as StyleBoxFlat
        assert_not_null(box, "drawn filled")
        assert_eq(box.bg_color, SaTheme.make_toggle_style("pressed").bg_color, "in the toggle family's pressed colour")
        for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
            assert_eq(box.get_content_margin(side), normal.get_content_margin(side), "at the title's margin")
    assert_false(normal is StyleBoxFlat, "and the loupe at rest stays the bare title box")


# --- Helpers ------------------------------------------------------------------


## The bar laid out at a painter's width, synchronously, since a suite has no
## frame for the containers to sort in.
func _lay_out() -> void:
    _bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
    _bar.size = Vector2(1920, _bar.get_combined_minimum_size().y)
    var walk: Node = _loupe
    var chain: Array[Container] = []
    while walk != null and walk != _bar:
        if walk is Container:
            chain.push_front(walk as Container)
        walk = walk.get_parent()
    _bar.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for box: Container in chain:
        box.notification(Container.NOTIFICATION_SORT_CHILDREN)


## A press and a release at the loupe's middle, pushed into the root viewport.
## True when the press was taken by the loupe.
func _click() -> bool:
    var root := (Engine.get_main_loop() as SceneTree).root
    var at := root.get_final_transform() * _loupe.get_global_rect().get_center()
    var was := _loupe.button_pressed
    var signalled := [false]
    var heard := func() -> void: signalled[0] = true
    _loupe.pressed.connect(heard)
    for down: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = down
        event.position = at
        event.global_position = at
        root.push_input(event)
    _loupe.pressed.disconnect(heard)
    return signalled[0] and _loupe.button_pressed != was
