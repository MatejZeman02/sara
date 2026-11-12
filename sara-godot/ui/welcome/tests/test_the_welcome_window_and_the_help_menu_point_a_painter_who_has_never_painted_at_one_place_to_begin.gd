## The welcome window and the Help menu point a painter who
## has never painted at one place to begin.
##
## The window is built and never added to a tree, for the reason
## `test_welcome_window.gd` gives: a `Window` in a suite hangs the whole run.
## The line's registry is handed in the way the Tips pane's is, and the menu is
## a detached bar `_ready()`ed by hand, the way `test_help_menu.gd` builds it.
extends "res://tests/test_framework.gd"

var _pressed: Array[StringName] = []


func before_each() -> void:
    _pressed.clear()


## The menu registries, with a stand-in for the tutorials module's command
## when *lessons*, registered the way the module registers its own.
func _registries(lessons: bool, note_mode: SaNoteMode = null) -> SaRegistries:
    var registries := SaTestFixtures.make_menu_registries(note_mode)
    if lessons:
        var run := func() -> void: _pressed.append(&"help_tutorials")
        var command := SaCommandDescriptor.create(&"help_tutorials", "Open the tutorials", run)
        command.category = &"help"
        command.label = "Start with a stand-in..."
        command.sentence = "A stand-in sentence for the module's button."
        command.beginner_line = "New to painting? Begin with the stand-in, or with the manual's first page."
        command.show_in_help_menu = true
        registries.commands.register(command, &"tutorials")
    return registries


func _line(window: SaWelcomeWindow, registries: SaRegistries) -> WelcomeBeginnerLine:
    var line := window.beginner_line
    if line != null:
        line.commands = registries.commands
        line.refresh()
    return line


## The first case: a fresh profile's window carries the line and its
## two buttons, between the panes and New and Open.
func test_a_first_launch_shows_the_line_and_its_two_buttons() -> void:
    var registries := _registries(true)
    var window := SaWelcomeWindow.new(false, true)
    var line := _line(window, registries)
    assert_not_null(line, "the first launch's window draws the line")
    if line == null:
        window.free()
        return
    var text := line.find_child(WelcomeBeginnerLine.TEXT, true, false) as Label
    var tutorials := line.find_child(WelcomeBeginnerLine.TUTORIALS, true, false) as Button
    var manual := line.find_child(WelcomeBeginnerLine.MANUAL, true, false) as Button
    assert_true(text.text.begins_with("New to painting?"), "the line speaks to a painter who has not painted: %s" % text.text)
    assert_true(text.text.contains("stand-in"), "and says the module's own words")
    assert_eq(tutorials.tooltip_text, "A stand-in sentence for the module's button.", "the button carries the module's sentence")
    assert_true(tutorials.visible and line.offers_lessons(), "the Tutorials button is there with the module loaded")
    assert_eq(tutorials.text, "Tutorials", "and says what it opens")
    assert_true(manual.visible, "the Manual button is there")
    assert_eq(manual.text, "Manual", "and says what it opens")
    var column := line.get_parent()
    var buttons := column.find_child("Buttons", false, false)
    assert_true(line.get_index() > window.tabs.get_index(), "the line sits under the panes")
    assert_true(line.get_index() < buttons.get_index(), "and above New and Open")
    tutorials.pressed.emit()
    assert_eq(_pressed, [&"help_tutorials"] as Array[StringName], "the Tutorials button runs the module's own command")
    window.free()


## The Tutorials button is absent when the module is not loaded, and the line
## then names the manual alone.
func test_with_no_tutorials_module_the_line_offers_the_manual_alone() -> void:
    var registries := _registries(false)
    var window := SaWelcomeWindow.new(false, true)
    var line := _line(window, registries)
    var tutorials := line.find_child(WelcomeBeginnerLine.TUTORIALS, true, false) as Button
    var text := line.find_child(WelcomeBeginnerLine.TEXT, true, false) as Label
    assert_false(tutorials.visible, "no Tutorials button without the module")
    assert_false(line.offers_lessons(), "and the line says so")
    assert_false(text.text.contains("stand-in"), "the sentence names no module's words: %s" % text.text)
    assert_true((line.find_child(WelcomeBeginnerLine.MANUAL, true, false) as Button).visible, "the Manual button stays")
    window.free()


## A window that is not the first launch's draws no line, so the welcome window
## Help reopens is the one it was.
func test_a_later_window_draws_no_line() -> void:
    var window := SaWelcomeWindow.new(false, false)
    assert_null(window.beginner_line, "only the first launch's window draws the line")
    assert_null(window.find_child(WelcomeBeginnerLine.NODE_NAME, true, false), "and no node of it stands in the tree")
    window.free()


func _help(lessons: bool) -> Array:
    var bar := TopMenuBar.new()
    bar._ready()
    # The note mode under the bar, as `test_help_menu.gd` gives it, so Take a
    # Note has its command.
    var note_mode := SaNoteMode.new()
    bar.add_child(note_mode)
    bar.bind_commands(_registries(lessons, note_mode).commands)
    var menu := bar.menu("Help") as SaHelpMenu
    var rows := []
    for child in menu.popup.get_node(NodePath("ChoiceBody/ChoiceScroll/ChoiceColumn")).get_children():
        if child is HSeparator:
            rows.append("---")
        elif child is Label:
            rows.append("> " + (child as Label).text)
        elif child is SaChoiceRow:
            rows.append(menu.popup.label_button((child as SaChoiceRow).id).text)
    bar.free()
    return rows


## The second case: the Manual and Tutorials stand first under one
## heading, the three settings rows under a heading of their own, the lessons'
## row carries the word Start, and no row is gone.
func test_the_help_menu_puts_the_ways_to_learn_first_and_the_settings_under_their_own_heading() -> void:
    var rows := _help(true)
    assert_eq(
        rows,
        [
            "> Learn to paint",
            "Manual",
            "Start with a stand-in...",
            "---",
            "Welcome",
            "Colour Spaces...",
            "Report a Problem",
            "Take a Note",
            "---",
            "> Settings",
            "Display Settings...",
            "Tablet Settings...",
            "Keyboard Shortcuts",
            "---",
            "About Sara",
        ],
        "Help's rows in order"
    )
    assert_true(String(rows[2]).begins_with("Start"), "the module's row carries its own label")


## Without the module the heading holds the Manual alone and nothing else moves.
func test_without_the_module_the_learning_heading_holds_the_manual() -> void:
    var rows := _help(false)
    assert_eq(rows.slice(0, 3), ["> Learn to paint", "Manual", "---"], "the Manual alone under the heading")
    assert_false(rows.has("Start with a stand-in..."), "and no module's row")
    var settings := ["> Settings", "Display Settings...", "Tablet Settings...", "Keyboard Shortcuts"]
    assert_eq(rows.slice(8, 12), settings, "the settings under theirs")
