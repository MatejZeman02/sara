## Help, Manual opens the painter's manual inside Sara.
##
## Every page in `res://manual/` is rendered the way the window renders it and
## read back as the painter reads it, with no markdown left over, and every link
## and picture a page names has to resolve. The window's own frame, Help,
## Manual and page 1 on screen, is `scenarios/help-opens-the-manual-inside-sara.json`.
extends "res://tests/test_framework.gd"

## What a reader must never see: a page that shows one of these wrote markdown
## the subset does not know, or wrote it wrong.
const LEFTOVERS := ["**", "*", "`", "](", "![", "[lb]", "[rb]"]
const LINE_LEFTOVERS := ["#", "- ", "> ", "1. "]


func _parsed(bbcode: String) -> String:
    var label := RichTextLabel.new()
    label.bbcode_enabled = true
    label.text = bbcode
    var text := label.get_parsed_text()
    label.free()
    return text


func test_the_folder_holds_the_pages_page_1_first() -> void:
    var pages := SaManualWindow.page_files()
    assert_true(pages.size() >= 1, "The manual has pages")
    if pages.is_empty():
        return
    assert_eq(pages[0].get_file(), "01-the-window.md", "and the first is the window")
    assert_eq(SaManualWindow.title_of(pages[0]), "The window", "titled by its first heading")


func test_every_page_renders_with_no_markdown_left_over() -> void:
    for path: String in SaManualWindow.page_files():
        var page := SaManualWindow.render(path, 600)
        var text := _parsed(String(page["bbcode"]))
        assert_false(text.strip_edges().is_empty(), "%s renders to words" % path.get_file())
        assert_false(String(page["title"]).is_empty(), "%s has a heading to title it in the list" % path.get_file())
        for mark: String in LEFTOVERS:
            assert_false(text.contains(mark), "%s shows no %s" % [path.get_file(), mark])
        for line: String in text.split("\n"):
            for mark: String in LINE_LEFTOVERS:
                var said := "%s starts no line with %s: %s" % [path.get_file(), mark, line]
                assert_false(line.strip_edges().begins_with(mark), said)


func test_every_link_and_picture_resolves() -> void:
    for path: String in SaManualWindow.page_files():
        var page := SaManualWindow.render(path, 600)
        assert_eq(Array(page["problems"]), [], "%s names nothing that is not there" % path.get_file())
        for target: String in page["pictures"]:
            var picture := load(path.get_base_dir().path_join(target)) as Texture2D
            assert_not_null(picture, "%s loads as a picture" % target)


func test_page_1_shows_its_pictures() -> void:
    var page := SaManualWindow.render("res://manual/01-the-window.md", 600)
    assert_eq(
        Array(page["pictures"]),
        ["pictures/01-the-window.png", "pictures/01-the-welcome-window.png"],
        "The window and the welcome window, both shots the manual scenario takes"
    )
    var drawn := "[img width=600]res://manual/pictures/01-the-window.png[/img]"
    assert_true(String(page["bbcode"]).contains(drawn), "drawn no wider than the page")


## The subset, each piece once, against exactly what it becomes.
func test_the_subset_becomes_rich_text() -> void:
    var path := SaDataRoot.path("m1_subset.md")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(
        (
            "# Title\n\nA **bold** and *slanted* [link](01-the-window.md) with `code` and [brackets].\n\n"
            + "- one\n- two\n  more\n\n1. first\n"
        )
    )
    file.close()
    var markdown := SaMarkdown.new("res://manual", 0)
    var bbcode := markdown.to_bbcode(FileAccess.get_file_as_string(path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    assert_true(bbcode.contains("[b]Title[/b]"), "A heading is bold")
    assert_eq(markdown.title, "Title", "and the first one titles the page")
    assert_true(bbcode.contains("A [b]bold[/b] and [i]slanted[/i] [url=01-the-window.md]link[/url]"), "Bold, italic and a link")
    assert_true(bbcode.contains("[code]code[/code] and [lb]brackets[rb]."), "code, and brackets written as prose stay brackets")
    assert_true(bbcode.contains("[ul]one\ntwo more[/ul]"), "A list, with a line carried on")
    assert_true(bbcode.contains("[ol type=1]first[/ol]"), "A numbered list")
    assert_eq(Array(markdown.problems), [], "and a link to a page that exists is no problem")


func test_a_broken_link_and_a_missing_picture_are_problems() -> void:
    var markdown := SaMarkdown.new("res://manual", 0)
    markdown.to_bbcode("[gone](99-nowhere.md)\n\n![none](pictures/none.png)\n\n[web](https://example.org)")
    assert_eq(markdown.problems.size(), 2, "The missing page and the missing picture, and the web link is not checked")


## Both presets carry the pages, so a build with no checkout beside it has
## them. The pictures are carried by `*.png` and as imported resources.
func test_both_export_presets_include_the_pages() -> void:
    var presets := ConfigFile.new()
    assert_eq(presets.load("res://export_presets.cfg"), OK, "The presets read")
    for section: String in ["preset.0", "preset.1"]:
        var filter := String(presets.get_value(section, "include_filter", ""))
        assert_true(filter.contains("manual/*.md"), "%s includes the manual's pages" % section)


func test_help_manual_asks_the_bus_and_main_dialogs_answers() -> void:
    var commands := FileAccess.get_file_as_string("res://ui/menus/sa_menu_commands.gd")
    assert_true(commands.contains("_emit_later.bind(EventBus.manual_requested)"), "Help, Manual emits the request")
    var dialogs := FileAccess.get_file_as_string("res://ui/main/main_dialogs.gd")
    assert_true(dialogs.contains("EventBus.manual_requested.connect(open_manual)"), "and MainDialogs opens the window")
    assert_eq(SaHelpMenu.ID_MANUAL, 506, "506 was free, so no stored order moves")


## F1 opens the manual, the key nearly every desktop program answers with its
## help, and leaves the Info docker, whose toggle went to F9. The press goes
## through the router the app answers keys with, the docker toggles before the
## commands as there, and `MainDialogs` answers the request it sends. The row
## sends that request a frame later, which a suite cannot wait for (a test that
## awaits drops what follows), so it is sent here by hand, and the frame between
## is the scenario of the same name's.
func test_f1_opens_the_manual() -> void:
    var saved := {}
    for action: StringName in InputMap.get_actions():
        saved[action] = InputMap.action_get_events(action).duplicate()
    # The action as the boot first makes it, from the chord the row ships.
    if InputMap.has_action(&"help_manual"):
        InputMap.erase_action(&"help_manual")
    var registry := SaCommandRegistry.new()
    var router := ShortcutRouter.new()
    var toggled: Array[int] = []
    router.dockers_provider = func() -> Array: return [{"shortcut": "info_docker"}]
    router.toggle_docker = func(index: int) -> void: toggled.append(index)
    router.bind_commands(registry)

    assert_eq(SaShortcutStore.chords_for(&"help_manual"), ["F1"] as Array[String], "Help, Manual ships on F1")
    assert_true(router.handle(_press(KEY_F1)), "F1 is answered")
    assert_eq(registry.last_command, &"help_manual", "by Help, Manual")
    assert_eq(toggled, [] as Array[int], "and the Info docker stays as it was")
    assert_true(router.handle(_press(KEY_F9)), "F9 is answered")
    assert_eq(toggled, [0] as Array[int], "by the Info docker's toggle")
    router.free()

    var tree := Engine.get_main_loop() as SceneTree
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "N87ManualTestHost"
    EventBus.add_child(host)
    var dialogs := MainDialogs.new(null, func() -> SaCanvas: return null)
    host.add_child(dialogs)
    dialogs.connect_event_bus()
    EventBus.manual_requested.emit()
    var window := dialogs.get_node_or_null("ManualWindow") as SaManualWindow
    assert_not_null(window, "the request builds the manual")
    assert_true(window != null and window.visible, "and shows it")
    assert_eq(window.current if window != null else -1, 0, "on page 1")
    if window != null:
        window.hide()
    host.free()
    tree.root.gui_embed_subwindows = was_embedding

    for action: StringName in InputMap.get_actions():
        if not saved.has(action):
            InputMap.erase_action(action)
    for action: StringName in saved:
        InputMap.action_erase_events(action)
        for event: InputEvent in saved[action]:
            InputMap.action_add_event(action, event)


## The press a keyboard sends, its character and its position both set.
func _press(key: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = key
    event.physical_keycode = key
    event.pressed = true
    return event
