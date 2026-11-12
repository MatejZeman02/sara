## The note mode: what an entry says, without a window.
##
## The highlight, the click and the photograph need a display, and
## scenarios/hover-and-click-notes.json proves those. What a headless run can check is the
## text: the entry's shape, the guess from a node name to the setting it
## reads, a control's own value, and that the chord and the command exist.
##
## It also checks the picture's arithmetic, which is `sa_note_image.gd`
## and takes an Image rather than a window.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")


## A stand-in for Main: the one property `install()` asks for.
class FakeMain:
    extends Node
    var registries := SaRegistries.new()


func test_the_entry_carries_the_path_the_value_and_the_setting() -> void:
    var entry := (
        SaNoteMode
        . format_entry(
            {
                "stamp": {"date": "2026-09-02", "time": "10:33:30"},
                "where": "Preferences, Top Menu Bar",
                "text": "The switch sits above the list.",
                "class": "CheckButton",
                "name": "SecondRowCheck",
                "label": "Show second row",
                "value": "pressed: false",
                "path": "/root/Main/Prefs/SecondRowCheck",
                "settings": [["second_row", "false", "by name"]],
                "image": "2026-09-02-103330-SecondRowCheck.png",
                "in_picture": true,
                "build": "v0.1.0  ·  abc1234  ·  working tree, not exported",
            }
        )
    )
    assert_true(entry.contains("### 2026-09-02 10:33:30, Preferences, Top Menu Bar"), "The heading is the moment and the place")
    assert_true(entry.contains("**Note.** The switch sits above the list."), "then the text")
    assert_true(entry.contains('`CheckButton` `SecondRowCheck`, "Show second row", pressed: false'), "the control and its value")
    assert_true(entry.contains("**Path.** `/root/Main/Prefs/SecondRowCheck`"), "the node path")
    assert_true(entry.contains("**Settings.** `second_row` = false (matched by name)"), "the setting, and how it was found")
    assert_true(entry.contains("![SecondRowCheck](2026-09-02-103330-SecondRowCheck.png)"), "the image beside the file")
    assert_true(entry.contains("**Build.** v0.1.0"), "and the build")
    assert_true(entry.begins_with("\n###"), "Entries are separated by a blank line")


func test_an_entry_says_what_it_is_missing() -> void:
    var entry := SaNoteMode.format_entry(
        {"stamp": {"date": "d", "time": "t"}, "where": "w", "path": "p", "settings": [], "image": "", "in_picture": false}
    )
    assert_true(entry.contains("**Note.** (no text)"), "No text is said")
    assert_true(entry.contains("**Settings.** none named"), "No setting is said")
    assert_true(entry.contains("**Image.** none, the readback failed"), "A missing image is said")
    var outside := SaNoteMode.format_entry({"stamp": {}, "settings": [], "image": "x.png", "in_picture": false})
    assert_true(outside.contains("outside the picture"), "and a control in a real OS window is said to be off the picture")


func test_a_node_name_guesses_the_setting_it_reads() -> void:
    assert_eq(SaNoteMode.guess_setting("SecondRowCheck"), "second_row", "The suffix goes and the rest is a property")
    assert_eq(SaNoteMode.guess_setting("KeepBlendMode"), "keep_blend_mode", "A name that is the property works as it is")
    assert_eq(SaNoteMode.guess_setting("ColorThemeOpt"), "", "A name that matches no property guesses nothing")
    assert_eq(SaNoteMode.guess_setting("Save"), "", "and neither does a button")
    assert_eq(SaNoteMode.guess_setting("@HBoxContainer@280"), "", "nor a generated name")


func test_a_named_setting_on_an_ancestor_comes_before_the_guess() -> void:
    var box := VBoxContainer.new()
    box.set_meta(SaNoteMode.SETTINGS_META, ["keep_blend_mode", "not_a_setting"])
    var check := CheckButton.new()
    check.name = "SecondRowCheck"
    box.add_child(check)
    var found := SaNoteMode.settings_for(check)
    assert_eq(found.size(), 2, "The named one and the guessed one, and the unknown name is dropped: %s" % str(found))
    assert_eq(found[0][0], "keep_blend_mode", "Named first")
    assert_eq(found[0][2], "named", "and marked as named")
    assert_eq(found[1][0], "second_row", "The guess second")
    assert_eq(found[1][2], "by name", "and marked as a guess")
    box.free()


func test_a_controls_own_value_is_read_by_kind() -> void:
    var check := CheckButton.new()
    check.button_pressed = true
    assert_eq(SaNoteMode.value_of(check), "pressed: true", "A switch says whether it is on")
    check.free()

    var slider := HSlider.new()
    slider.step = 0.1
    slider.value = 0.5
    assert_eq(SaNoteMode.value_of(slider), "value: 0.5", "A slider says its value")
    slider.free()

    var option := OptionButton.new()
    option.add_item("sRGB")
    option.add_item("Oklab")
    option.selected = 1
    assert_eq(SaNoteMode.value_of(option), "selected: Oklab", "A dropdown says its choice by name")
    option.free()

    var line := LineEdit.new()
    line.text = "#000000"
    assert_eq(SaNoteMode.value_of(line), 'text: "#000000"', "A field says its text")
    line.free()

    var label := Label.new()
    label.text = "Hex:"
    assert_eq(SaNoteMode.value_of(label), "", "A label has no value")
    assert_eq(SaNoteMode.label_of(label), "Hex:", "but its text is its label")
    label.free()

    var button := Button.new()
    button.tooltip_text = "Swap the two colours"
    assert_eq(SaNoteMode.label_of(button), "Swap the two colours", "A button with no text is named by its tooltip")
    button.free()


## The note is on Ctrl+Alt+N, which no shipped map and no Krita action holds,
## because Ctrl+Shift+C is Copy Merged in Krita and Photoshop and a painter's
## hand pressing it tinted the canvas and started a note.
func test_the_chord_and_the_command_go_through_the_public_doors() -> void:
    assert_true(InputMap.has_action(SaNoteMode.ACTION), "The action is in project.godot")
    assert_eq(SaShortcutsPage.keys_for(SaNoteMode.ACTION), "Ctrl+Alt+N", "on Ctrl+Alt+N")
    assert_true(InputMap.event_is_action(_chord(KEY_N, false, true), SaNoteMode.ACTION, true), "which a press of it reaches")

    var main := FakeMain.new()
    var mode := SaNoteMode.install(main)
    assert_not_null(mode, "Installing puts the mode under Main")
    assert_true(main.registries.commands.has(SaNoteMode.ACTION), "and registers its command the way a module would")
    assert_eq(
        SaShortcutsPage.label_for(String(SaNoteMode.ACTION), null, null, main.registries.commands),
        "Take a note on a control",
        "and the dialog names it by the command's title"
    )
    assert_eq(SaNoteMode.install(main), mode, "A second install finds the first")
    assert_eq(main.get_node_or_null(SaNoteMode.NODE_NAME), mode, "by name")
    main.free()


## Ctrl+Shift+C starts no note. It is Copy Merged's, which the shortcut table
## registers, and the app's own map below holds nothing on it.
func test_ctrl_shift_c_starts_nothing() -> void:
    var old := _chord(KEY_C, true, false)
    assert_false(InputMap.event_is_action(old, SaNoteMode.ACTION, true), "Ctrl+Shift+C is not the note's")

    var main := FakeMain.new()
    var registries := Fixtures.make_registries()
    main.registries = registries
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var mode := SaNoteMode.install(main)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands)

    assert_false(router.handle(old), "The router finds no command on Ctrl+Shift+C")
    assert_false(mode.active, "and the note did not start")
    router.free()
    main.free()


## A chord as a keyboard sends it, Ctrl held with Shift or with Alt.
func _chord(keycode: Key, shift: bool, alt: bool) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.ctrl_pressed = true
    event.shift_pressed = shift
    event.alt_pressed = alt
    event.pressed = true
    return event


## A note taken on an open menu says which line of the list it is about. The
## dropdown alone does not, and its value is the item that is still selected.
func test_an_entry_names_the_menu_item_it_was_taken_on() -> void:
    var entry := (
        SaNoteMode
        . format_entry(
            {
                "stamp": {"date": "2026-09-02", "time": "13:00:11"},
                "where": "the main window, CustomTitleBar",
                "text": "Normal (sRGB) is in this list twice.",
                "class": "OptionButton",
                "name": "BlendModeOpt",
                "value": "selected: Normal (sRGB)",
                "item": "Screen, item 8 of 20",
                "path": "/root/MainRoot/BlendModeOpt",
                "settings": [],
                "image": "2026-09-02-130011-BlendModeOpt.png",
            }
        )
    )
    assert_true(entry.contains("**Item.** Screen, item 8 of 20"), "The entry names the item under the pointer")
    assert_true(entry.contains("selected: Normal (sRGB)"), "and the value the click did not change")


## A dropdown's menu is a window nobody in Sara builds, and a note taken while
## one is open is a note about the dropdown.
func test_an_open_menu_answers_with_the_control_it_belongs_to() -> void:
    var option := OptionButton.new()
    option.name = "BlendModeOpt"
    var popup := option.get_popup()

    assert_eq(SaNoteMode.popup_owner(popup), option, "The menu belongs to its OptionButton")
    assert_eq(SaNoteMode.control_at(popup, Vector2(4.0, 4.0)), option, "so a click anywhere in it names the button")

    option.free()


## The release that follows the freezing press is swallowed, or the control
## under it acts on it: an open blend menu picked the item and the note changed
## the blend mode on its way out.
func test_the_release_after_a_freeze_is_swallowed() -> void:
    var mode := SaNoteMode.new()
    var button := Button.new()
    mode.active = true
    mode.frozen = button
    mode.swallow_release = true
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false

    assert_true(mode.handle_window_input(release, null), "The release the freeze is waiting for is eaten")
    assert_false(mode.handle_window_input(release, null), "and the next one is the box's own")

    button.free()
    mode.free()


func test_the_default_notes_directory_is_the_notes_folder_beside_the_logs() -> void:
    if not OS.get_environment(SaNoteFile.NOTES_DIR_ENV).is_empty():
        assert_eq(SaNoteFile.default_notes_dir(), OS.get_environment(SaNoteFile.NOTES_DIR_ENV), "The variable wins")
        return
    var expected := ProjectSettings.globalize_path(SaDataRoot.path("notes"))
    assert_eq(SaNoteFile.default_notes_dir(), expected, "The notes folder the painter's guide names, beside the logs")


func test_a_notes_directory_may_be_a_godot_path_and_a_half_one_says_why() -> void:
    # `user://` is the portable way to name a notes directory, and it
    # works. What does not is the same path with one slash, which is what
    # `pathlib` hands over when a Python caller runs it through `Path`, and
    # `DirAccess` refuses that without a word, so the note would fail one
    # step later against the markdown file, whose name is the half of the
    # sentence a reader does not doubt.
    #
    # The engine's own "Could not create directory" in the run log is the thing
    # under test rather than a fault of the suite, and there is no way to ask
    # for a refusal without it.
    var good := SaDataRoot.path("test-d15-notes/%d" % Time.get_ticks_usec())
    assert_eq(SaNoteFile.make_run_dir(good), "", "A whole user:// path is made")
    assert_true(DirAccess.dir_exists_absolute(good), "and it is there afterwards")
    DirAccess.remove_absolute(good)

    var half := "user:/test-d15-notes/half"
    var complaint := SaNoteFile.make_run_dir(half)
    assert_false(complaint.is_empty(), "A path with one slash is refused")
    assert_true(complaint.contains(half), "The refusal names the path it was given")
    assert_true(complaint.contains("two"), "and says the slash is what is wrong with it")
    assert_false(DirAccess.dir_exists_absolute(half), "and nothing was made")


func test_a_run_directory_hangs_the_session_folder_off_whatever_base_it_is_given() -> void:
    var at := {"date": "2026-09-10", "time": "05:34:00", "short": "0534"}
    SaNoteFile.run_file = ""
    assert_eq(
        SaNoteFile.run_dir(SaDataRoot.path("painter-notes"), at),
        SaDataRoot.path("painter-notes/2026-09-10-0534"),
        "A Godot base keeps its scheme"
    )
    assert_eq(
        SaNoteFile.run_dir("/home/someone/notes", at),
        "/home/someone/notes/2026-09-10-0534",
        "and an absolute one is joined the same way"
    )
    SaNoteFile.run_file = ""


func test_the_notes_file_is_named_once_per_launch() -> void:
    var first := {"date": "2026-09-03", "time": "14:07:31", "short": "1407"}
    var later := {"date": "2026-09-03", "time": "15:52:04", "short": "1552"}

    SaNoteFile.run_file = ""
    assert_eq(SaNoteFile.run_file_name(first), "2026-09-03-1407.md", "Named after the first note of the run")
    assert_eq(SaNoteFile.run_file_name(later), "2026-09-03-1407.md", "and a later note the same run appends to it")

    var header := SaNoteFile.run_file_header(first)
    assert_true(header.begins_with("# Notes, 2026-09-03 14:07:31"), "The header says when the run started")
    assert_true(header.contains("Build: v"), "and which build the notes are about")

    # A fresh launch starts with the static unset, which is what this stands in
    # for. It also leaves the suite as it found it.
    SaNoteFile.run_file = ""
    assert_eq(SaNoteFile.run_file_name(later), "2026-09-03-1552.md", "The next run takes a name of its own")
    SaNoteFile.run_file = ""


# --- The picture ---------------------------------------------------------


## A whole-window shot is shrunk to the long side and a region is not, because
## a region is drawn precisely when the pixels matter.
func test_a_whole_window_is_shrunk_and_a_region_is_not() -> void:
    var shot := Image.create(3840, 2160, false, Image.FORMAT_RGBA8)
    var whole := SaNoteImage.for_note(shot, Rect2(), Vector2(1920.0, 1080.0))
    assert_eq(whole.get_width(), SaNoteImage.LONG_SIDE, "The long side is the limit")
    assert_eq(whole.get_height(), 900, "and the shape is kept")

    var region := SaNoteImage.for_note(shot, Rect2(100.0, 50.0, 200.0, 100.0), Vector2(1920.0, 1080.0))
    assert_eq(region.get_size(), Vector2i(400, 200), "A region is cut at the readback's own resolution")

    var small := Image.create(800, 600, false, Image.FORMAT_RGBA8)
    assert_eq(SaNoteImage.shrink(small, SaNoteImage.LONG_SIDE), small, "A window smaller than the limit is left alone")


## The pointer is read in logical units and the readback is physical pixels. A
## region cropped without the ratio takes the top-left quarter at 2x.
func test_a_region_is_measured_in_logical_units_and_cut_in_pixels() -> void:
    var box := SaNoteImage.in_pixels(Rect2(10.0, 20.0, 100.0, 50.0), Vector2(960.0, 540.0), Vector2(1920.0, 1080.0))
    assert_eq(box, Rect2i(20, 40, 200, 100), "Twice the scale is twice the rectangle")

    var clipped := SaNoteImage.in_pixels(Rect2(-40.0, -10.0, 200.0, 100.0), Vector2(100.0, 100.0), Vector2(100.0, 100.0))
    assert_eq(clipped, Rect2i(0, 0, 100, 90), "and a region dragged off the edge is clipped to the picture")

    var square := SaNoteImage.in_pixels(Rect2(0.0, 0.0, 10.0, 10.0), Vector2.ZERO, Vector2(100.0, 100.0))
    assert_eq(square, Rect2i(0, 0, 10, 10), "A logical size of nothing is read as one to one rather than a division by zero")


## A drag frames the same rectangle whichever corner it started at, and a slip
## of a few pixels is not a region at all.
func test_a_drag_frames_a_region_only_when_it_is_one() -> void:
    var forwards := SaNoteImage.region_between(Vector2(10.0, 10.0), Vector2(110.0, 60.0))
    var backwards := SaNoteImage.region_between(Vector2(110.0, 60.0), Vector2(10.0, 10.0))
    assert_eq(forwards, backwards, "The corner it started at does not matter")
    assert_true(SaNoteImage.is_region(forwards), "and a hundred by fifty is a region")
    assert_false(SaNoteImage.is_region(SaNoteImage.region_between(Vector2.ZERO, Vector2(4.0, 40.0))), "A slip is not")


## The picture is a WebP, which is the whole point: a PNG per note averaged
## 600 KB.
func test_the_picture_is_written_as_a_webp() -> void:
    var shot := Image.create(64, 48, false, Image.FORMAT_RGBA8)
    shot.fill(Color(0.2, 0.4, 0.6))
    var path := ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("note-image-test.%s" % SaNoteImage.EXTENSION)
    assert_eq(SaNoteImage.save(shot, path), OK, "It writes")
    var read_back := Image.load_from_file(path)
    assert_not_null(read_back, "and reads back as an image")
    assert_eq(read_back.get_size(), Vector2i(64, 48), "of the size it was given")
    DirAccess.remove_absolute(path)


## The box opens at the size it was left at, and a stored size below the floor
## is a corrupt file rather than a preference.
func test_the_note_box_opens_at_the_size_it_was_left_at() -> void:
    var smallest := Vector2(360.0, 200.0)
    assert_eq(SaNoteOverlay.box_size_for(smallest, Vector2i(520, 400)), Vector2(520.0, 400.0), "A kept size wins")
    assert_eq(SaNoteOverlay.box_size_for(smallest, Vector2i.ZERO), smallest, "Nothing kept means fit the contents")
    assert_eq(SaNoteOverlay.box_size_for(smallest, Vector2i(40, 900)), smallest, "and half a corrupt pair is not a preference")
    assert_eq(
        SaNoteOverlay.box_size_for(smallest, Vector2i(400, 210)), Vector2(400.0, 210.0), "A kept size never shrinks the box"
    )


## A row of Sara's own menu is a control, so a note over the Image menu names
## the entry under the pointer rather than the bar the menu hangs from.
## Detached, so the item is read off the row and not off a rect.
func test_a_choice_row_is_the_item_of_its_list() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"item_303", "Image Size...")
    popup.add_row(&"item_302", "Canvas Size...")
    popup.add_row(&"item_301", "Crop to Selection")
    var row := popup.row_of(&"item_301")
    var menu := SaNoteMenu.new()

    menu.take(SaNoteMenu.item_of(popup, row))
    assert_true(menu.is_set(), "The row is an item of its list")
    assert_eq(menu.tag(), "Crop to Selection, item 3 of 3", "named and counted among the rows")
    assert_eq(SaNoteMenu.row_holding(row.label_button()), row, "and the row's own button is the row")
    assert_null(SaNoteMenu.row_holding(popup.search), "where the search field is nobody's row")
    assert_eq(SaNoteDescribe.label_of(row), "Crop to Selection", "The control line carries the entry's text")
    assert_true(SaNoteMenu.item_of(popup, null).is_empty(), "and no row is no item")

    menu.clear()
    assert_false(menu.is_set(), "Cleared, the note is about no menu")
    assert_eq(menu.tag(), "", "and has no tag")
    popup.free()


# --- The export ---------------------------------------------


## The export zips the session folder at the bare names the markdown links, so
## the links still resolve inside the zip.
func test_an_export_zips_the_session_folder_at_bare_names() -> void:
    var run_dir := ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("n1-export-%d" % Time.get_ticks_usec())
    assert_eq(DirAccess.make_dir_recursive_absolute(run_dir), OK, "The run directory is made")
    var markdown := "# Notes, 2026-09-14 15:30\n\nBuild: v0\n".to_utf8_buffer()
    var file := FileAccess.open(run_dir.path_join("2026-09-14-1530.md"), FileAccess.WRITE)
    file.store_buffer(markdown)
    file.close()
    for name: String in ["a.webp", "b.webp"]:
        var shot := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
        assert_eq(shot.save_webp(run_dir.path_join(name), true, SaNoteImage.QUALITY), OK, "A WebP is written")

    var zip_path := SaNoteFile.export_run_dir(run_dir)
    assert_eq(zip_path, run_dir + ".zip", "The export returns the zip beside the folder")
    var zip := ZIPReader.new()
    assert_eq(zip.open(zip_path), OK, "The zip opens")
    var entries := zip.get_files()
    entries.sort()
    assert_eq(entries, PackedStringArray(["2026-09-14-1530.md", "a.webp", "b.webp"]), "One entry per file at the bare name")
    assert_eq(zip.read_file("2026-09-14-1530.md"), markdown, "The markdown's bytes come back unchanged")
    zip.close()
    DirAccess.remove_absolute(run_dir)


## An empty or missing run directory exports nothing, through the empty path the
## caller turns into the notice, and writes no file.
func test_an_empty_directory_exports_nothing() -> void:
    var run_dir := ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("n1-export-empty-%d" % Time.get_ticks_usec())
    assert_eq(DirAccess.make_dir_recursive_absolute(run_dir), OK, "The directory is made")
    assert_eq(SaNoteFile.export_run_dir(run_dir), "", "An empty directory exports nothing")
    assert_false(FileAccess.file_exists(run_dir + ".zip"), "and writes no file")
    DirAccess.remove_absolute(run_dir)

    var missing := ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("n1-export-missing-%d" % Time.get_ticks_usec())
    assert_eq(SaNoteFile.export_run_dir(missing), "", "A missing directory exports nothing either")
    assert_false(FileAccess.file_exists(missing + ".zip"), "and writes no file")


## The export takes the engine's own log too, godot.log and the two
## newest rotated files, beside the notes it already zipped, under a `logs/`
## prefix.
func test_the_export_adds_the_engines_log_beside_the_notes() -> void:
    var run_dir := ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("f2-export-%d" % Time.get_ticks_usec())
    assert_eq(DirAccess.make_dir_recursive_absolute(run_dir), OK, "The run directory is made")
    var markdown := "# Notes, 2026-09-17 12:00\n\nBuild: v0\n".to_utf8_buffer()
    var note_file := FileAccess.open(run_dir.path_join("2026-09-17-1200.md"), FileAccess.WRITE)
    note_file.store_buffer(markdown)
    note_file.close()
    var shot := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
    assert_eq(shot.save_webp(run_dir.path_join("a.webp"), true, SaNoteImage.QUALITY), OK, "A WebP is written")

    var log_dir := ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("f2-logs-%d" % Time.get_ticks_usec())
    assert_eq(DirAccess.make_dir_recursive_absolute(log_dir), OK, "The log directory is made")
    var log_names := ["godot.log", "godot2026-09-17T20.00.00.log", "godot2026-09-17T20.05.00.log", "godot2026-09-17T20.10.00.log"]
    for name: String in log_names:
        var log_file := FileAccess.open(log_dir.path_join(name), FileAccess.WRITE)
        log_file.store_string(name)
        log_file.close()

    assert_eq(
        SaNoteFile.log_files_for(log_dir),
        PackedStringArray(["godot.log", "godot2026-09-17T20.10.00.log", "godot2026-09-17T20.05.00.log"]),
        "godot.log and the two newest rotated files, newest first"
    )

    var zip_path := SaNoteFile.export_run_dir(run_dir, log_dir)
    assert_eq(zip_path, run_dir + ".zip", "The export returns the zip beside the folder, as it did with no log")
    var zip := ZIPReader.new()
    assert_eq(zip.open(zip_path), OK, "The zip opens")
    var entries := zip.get_files()
    entries.sort()
    assert_eq(
        entries,
        PackedStringArray(
            [
                "2026-09-17-1200.md",
                "a.webp",
                "logs/",
                "logs/godot.log",
                "logs/godot2026-09-17T20.05.00.log",
                "logs/godot2026-09-17T20.10.00.log",
            ]
        ),
        "The two notes and the three logs/ files, godot.log and the two newest rotated ones, under their prefix"
    )
    zip.close()
    DirAccess.remove_absolute(run_dir)
    DirAccess.remove_absolute(zip_path)
    for name: String in log_names:
        DirAccess.remove_absolute(log_dir.path_join(name))
    DirAccess.remove_absolute(log_dir)


## An empty run directory, the shape a crash's restart leaves with no note
## taken yet, still exports when the engine's log holds something.
func test_an_empty_run_directory_with_a_log_exports_the_log_alone() -> void:
    var run_dir := ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("f2-export-empty-%d" % Time.get_ticks_usec())
    assert_eq(DirAccess.make_dir_recursive_absolute(run_dir), OK, "The directory is made")

    var log_dir := ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("f2-logs-empty-%d" % Time.get_ticks_usec())
    assert_eq(DirAccess.make_dir_recursive_absolute(log_dir), OK, "The log directory is made")
    var log_file := FileAccess.open(log_dir.path_join("godot.log"), FileAccess.WRITE)
    log_file.store_string("boot")
    log_file.close()

    var zip_path := SaNoteFile.export_run_dir(run_dir, log_dir)
    assert_eq(zip_path, run_dir + ".zip", "An empty note folder still exports when the log holds something")
    var zip := ZIPReader.new()
    assert_eq(zip.open(zip_path), OK, "The zip opens")
    assert_eq(zip.get_files(), PackedStringArray(["logs/", "logs/godot.log"]), "The log alone, under its prefix")
    zip.close()
    DirAccess.remove_absolute(run_dir)
    DirAccess.remove_absolute(zip_path)
    DirAccess.remove_absolute(log_dir.path_join("godot.log"))
    DirAccess.remove_absolute(log_dir)


## Neither folder existing is still nothing to export, log argument or not.
func test_no_log_dir_is_the_old_behaviour() -> void:
    var missing := ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("f2-export-neither-%d" % Time.get_ticks_usec())
    assert_eq(SaNoteFile.export_run_dir(missing, missing + "-logs"), "", "Neither folder existing exports nothing")
    assert_false(FileAccess.file_exists(missing + ".zip"), "and writes no file")
