## Menu chords read like the Shortcuts page.
##
## Zoom In's row must not say "Ctrl+Equal, Ctrl+Plus, Ctrl+Kp Add",
## three chords in Godot's key names, where the Shortcuts page says "Numpad"
## for the same key, and the View menu's "Shape Check" keeps its chord in the
## chord column and not inside the label.
extends "res://tests/test_framework.gd"


## A bar bound the way main binds it, with the router's view mode commands in
## the registry and the modes on the View menu.
func _make_bar(registries: SaRegistries, router: ShortcutRouter) -> TopMenuBar:
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return null
    router.bind_commands(registries.commands)
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(registries.commands)
    (bar.menu("View") as SaViewMenu).view_transforms = registries.view_transforms
    return bar


## The row of *menu* whose label is *name*, or null.
func _row(menu: SaMenu, name: String) -> SaChoiceRow:
    for list: SaChoicePopup in SaMenu.lists_of(menu.popup):
        for id: StringName in list.row_ids():
            var row := list.row_of(id)
            if row != null and row.label_button().text == name:
                return row
    return null


func test_zoom_in_reads_one_chord_in_plain_key_names() -> void:
    var registries := SaTestFixtures.make_menu_registries()
    var router := ShortcutRouter.new()
    var bar := _make_bar(registries, router)
    var row := _row(bar.menu("View"), "Zoom In")
    assert_not_null(row, "the View menu has a Zoom In row")
    if row != null:
        assert_eq(row.hint_text(), "Ctrl+=", "its chord column names the first chord alone, the key as it is printed")
        assert_false(row.hint_text().contains(","), "one chord, not a list")
    bar.free()
    router.free()


func test_the_shortcuts_page_names_the_keys_in_the_same_words() -> void:
    var registries := SaTestFixtures.make_menu_registries()
    var router := ShortcutRouter.new()
    var bar := _make_bar(registries, router)
    var row := _row(bar.menu("View"), "Zoom In")
    var page := SaShortcutsPage.new()
    var shown := page.chords_shown(&"view_zoom_in")
    assert_eq(
        shown, ["Ctrl+=", "Ctrl++", "Ctrl+Numpad +"] as Array[String], "the page lists every chord, the numpad's by that name"
    )
    if row != null and not shown.is_empty():
        assert_eq(row.hint_text(), shown[0], "and the menu's chord is the page's first, word for word")
    assert_eq(
        registries.commands.chord_text(&"view_zoom_in"),
        ", ".join(shown),
        "the registry's own sentence is the page's, so a tooltip reads the same"
    )
    page.free()
    bar.free()
    router.free()


func test_shape_check_carries_its_chord_in_the_column_and_not_the_label() -> void:
    var registries := SaTestFixtures.make_menu_registries()
    var router := ShortcutRouter.new()
    var bar := _make_bar(registries, router)
    var row := _row(bar.menu("View"), "Shape Check")
    assert_not_null(row, "the View menu's Shape Check row is labelled with the mode's name alone")
    if row != null:
        assert_false(row.label_button().text.contains("("), "no chord in brackets in the label")
        assert_eq(row.hint_text(), "Ctrl+Shift+Q", "the chord is in the chord column")
    bar.free()
    router.free()


## Every key the table respells reads back as the key it names, so a profile
## the page writes in the new words opens, and one written in Godot's words
## by an older build still does.
func test_every_spelling_parses_back_to_its_key() -> void:
    for code: int in SaCommandRegistry.KEY_GLYPHS:
        var key := InputEventKey.new()
        key.keycode = code as Key
        key.ctrl_pressed = true
        var text := SaCommandRegistry.key_text(key)
        var back := SaShortcutStore.parse_chord(text)
        assert_not_null(back, "%s reads back" % text)
        if back != null:
            assert_eq(int(back.keycode), code, "%s is the key it names" % text)
            assert_true(back.ctrl_pressed, "%s keeps its modifier" % text)
        var old := SaShortcutStore.parse_chord("Ctrl+" + OS.get_keycode_string(code as Key))
        assert_true(old != null and int(old.keycode) == code, "Godot's own word for %s still reads" % text)
    var plus := SaShortcutStore.parse_chord("+")
    assert_true(plus != null and plus.keycode == KEY_PLUS, "a bare plus key reads as the plus key")
