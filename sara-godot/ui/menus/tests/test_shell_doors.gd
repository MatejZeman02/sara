## Three doors onto the shell that a scenario must be able to reach.
##
## Each one is a gesture a painter makes every day. All three live in the
## capture harness: a `capture_move` seam beside `capture_resize`, a fall
## through to the popup for a menu with no `SaMenu` behind it, and a `key` step
## that no longer capitalizes the name it is given.
extends "res://tests/test_framework.gd"

const CAPTURE_PATH := "res://harness/sa_capture.gd"
const CAPTURE_MENUS_PATH := "res://harness/drivers/menu/sa_menu_driver.gd"


func _source(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""


## The body of a declaration in *source*, from its `func` line to the next one,
## or to the end of the file when it is the last.
func _body_from(source: String, opening: String) -> String:
    var at := source.find(opening)
    if at == -1:
        return ""
    var end := source.find("\nfunc ", at + 1)
    if end == -1:
        end = source.find("\nstatic func ", at + 1)
    return source.substr(at, end - at) if end != -1 else source.substr(at)


# --- The docker rows, which no step could press --------------------------------


## There is no Dockers menu:
## its rows and the layouts under them are the Window menu's, and `MainDockers`
## appends them into a popup that class opened and cleared. What the tests held
## about the seam is still held, one menu along.
func test_the_docker_rows_are_the_window_menus_and_have_no_menu_of_their_own() -> void:
    assert_false(TopMenuBar.MENU_NAMES.has("Dockers"), "The bar makes no Dockers button any more")
    var body := _source("res://ui/top_bar/top_menu_bar.gd")
    var table := body.substr(body.find("var menu_classes := {"), 500)
    assert_false(table.contains('"Dockers"'), "and nothing in the table ever filled it, because main did")
    assert_true(table.contains('"Window": SaWindowMenu'), "The Window menu is the class those rows arrive through")


func test_a_menu_item_step_can_only_reach_a_menu_with_an_object_behind_it() -> void:
    var body := _source(CAPTURE_MENUS_PATH)
    var click := _body_from(body, "func click_menu_item(")
    assert_true(not click.is_empty(), "The menu_item step is where a row is fired from")
    assert_true(click.contains("bar.menu(menu_name)"), "and it asks the bar for an SaMenu")
    assert_true(click.contains("no menu called"), "which is what it answers with when there is none")


## `{"menu_item": {"menu": "Dockers", "id": 0}}`
## warned ten times and toggled nothing, so the ten menu rows were undriven
## while the ten chords were driven in scenarios/tour-dockers.json. The step falls
## through to the popup itself, which is where a row `MainDockers` built lives,
## and that fall-through is asked first: the Window menu has an
## `SaMenu` behind it, and its own ids start at six hundred so that a docker row
## numbered from zero is never one of them.
func test_a_scenario_can_press_a_docker_row() -> void:
    var click := _body_from(_source(CAPTURE_MENUS_PATH), "func click_menu_item(")
    assert_true(click.contains("bar.menus.get(menu_name)"), "The step reaches the popup the row lives on")
    assert_true(click.contains("holder.press_row("), "and presses the row a click presses, on the submenu that holds it")
    assert_true(click.contains("SaMenu.list_holding(popup, docker_row)"), "asking for a docker row by number first")

    var bar := TopMenuBar.new()
    bar._ready()
    assert_true(bar.menus.has("Window"), "The Window popup is on the bar's map")
    assert_true(bar.menu("Window") is SaWindowMenu, "and has an SaWindowMenu behind it, which is what fills the docker half")
    bar.free()


# --- A function key, which the key step cannot spell ---------------------------


## The one measurement here that could not survive its own fix. It asserted that
## the step capitalizes the name it is given, which was the defect rather than
## the reason for it, so the fix had to rewrite it. Kept as the negative, because
## a step that starts capitalizing again is exactly the regression.
func test_the_key_step_does_not_capitalize_the_name_it_is_given() -> void:
    # On the input driver, with the runner's own steps left
    # on `sa_capture.gd` and the keyboard where the pointer is.
    var body := _source("res://harness/drivers/sa_input_driver.gd")
    var at := body.find("func key(")
    assert_true(at != -1, "The key step is on sa_input_driver.gd")
    assert_false(body.substr(at, 800).contains(".capitalize()"), "and the name goes to the lookup as it stands")


## Why the capitalize went rather than being made cleverer: the lookup never
## needed it. Every name a committed scenario writes resolves without it, and
## none of them resolves with it once a digit is in the name.
func test_no_spelling_of_f1_survives_that_capitalize() -> void:
    assert_true(OS.find_keycode_from_string("F1") == KEY_F1, "Godot knows the key as F1")
    assert_true(OS.find_keycode_from_string("f1") == KEY_F1, "and matches without regard to case")
    assert_false(String("f1").capitalize() == "F1", "and capitalize does not leave it spelled that way")
    assert_true(OS.find_keycode_from_string(String("f1").capitalize()) == KEY_NONE, "so the step found nothing")
    assert_true(OS.find_keycode_from_string(String("F1").capitalize()) == KEY_NONE, "however it was typed")


## The Info docker was the row that cost, its toggle then the one function key a
## scenario pressed. F1 went to the manual, the key nearly every desktop program
## answers with its help, and the toggle to F9, a function key all the same.
func test_the_info_docker_is_the_row_that_costs() -> void:
    assert_true(InputMap.has_action(&"info_docker"), "The Info docker has a chord")
    var events := InputMap.action_get_events(&"info_docker")
    assert_eq(events.size(), 1, "and one key")
    var key := events[0] as InputEventKey if not events.is_empty() else null
    assert_true(key != null and key.physical_keycode == KEY_F9, "F9, a function key the step has to send")
    assert_true(key != null and not (key.ctrl_pressed or key.shift_pressed or key.alt_pressed), "bare")
    assert_true(OS.find_keycode_from_string("f9") == KEY_F9, "which a scenario's name for it reaches")


## The summon and its locked twin follow the toggle to F9 under the rule every
## docker keeps, Alt and Shift with the toggle's key and Ctrl on top for the
## lock. F12 was the first pick, but KDE Plasma's compositor holds Alt+Shift+F12
## to suspend itself, and F1 is the manual's.
func test_the_info_dockers_summon_follows_it_to_f9() -> void:
    var before := InputMap.get_actions()
    var registries := SaRegistries.new()
    registries.build_context(func() -> SaEasel: return null, func() -> Array: return [])
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var shipped := {
        SaAppCommands.summon_id(&"info_docker"): "Alt+Shift+F9",
        SaAppCommands.locked_summon_id(&"info_docker"): "Ctrl+Alt+Shift+F9",
    }
    for id: StringName in shipped:
        var command := registries.commands.get_descriptor(id)
        assert_not_null(command, "%s is registered" % id)
        if command == null:
            continue
        var chords: Array[String] = []
        for event: InputEvent in command.default_events:
            chords.append(SaShortcutStore.chord_text(event))
        assert_eq(chords, [shipped[id]] as Array[String], "%s ships on %s" % [id, shipped[id]])
    for chord: String in ["F1", "Alt+Shift+F1", "Ctrl+Alt+Shift+F1"]:
        for id: StringName in shipped:
            assert_false(SaShortcutStore.chords_for(id).has(chord), "%s keeps off %s" % [id, chord])
    for action: StringName in InputMap.get_actions():
        if not before.has(action):
            InputMap.erase_action(action)


## Fixed by f32. `{"key": {"key": "f1"}}` was a warning and
## scenarios/tour-dockers.json left one of the ten dockers untoggled.
##
## The capitalize was not replaced with anything: `OS.find_keycode_from_string`
## already matches without regard to case, so it bought nothing and cost the
## function keys.
func test_the_key_step_can_send_a_function_key() -> void:
    var body := _source("res://harness/drivers/sa_input_driver.gd")
    var at := body.find("func key(")
    var step := body.substr(at, 800)
    assert_false(step.contains(".capitalize()"), "The name is no longer capitalized blindly")
    assert_true(OS.find_keycode_from_string("f1") == KEY_F1, "and the name a scenario writes resolves as it stands")
    for name: String in ["escape", "bracketleft", "pageup", "enter", "backspace", "comma", "delete"]:
        assert_true(OS.find_keycode_from_string(name) != KEY_NONE, "'%s' still resolves without it" % name)


# --- Moving a docker, which has no seam at all ---------------------------------


func test_the_resize_gestures_have_a_seam_of_their_own() -> void:
    var handle := _source("res://ui/dockers/docker_drag_handle.gd")
    assert_true(handle.contains("static func capture_resize("), "The ALT-right resize and the grip are drivable")
    var body := _body_from(handle, "static func _drive_alt_drag(")
    assert_true(body.contains("press.alt_pressed = true"), "because the seam holds ALT down itself")
    assert_true(
        (
            body
            . contains(
                'handle.call("handle_input"',
            )
        ),
        "and hands the events straight to the handle"
    )


func test_the_handle_wants_alt_before_it_moves_anything() -> void:
    var handle := _source("res://ui/dockers/docker_drag_handle.gd")
    var body := _body_from(handle, "func handle_input(")
    assert_true(body.contains("is_alt and is_left"), "A move begins on ALT and the left button")


## Fixed by f32. scenarios/tour-dockers.json asked for the Minimap to move 120 by
## 60 and its printed line read moved=(0, 0) both times. The door is a
## `capture_move` beside `capture_resize` rather than an `alt` on the press step,
## which `capture-press-alt` owns.
func test_a_scenario_can_move_a_docker() -> void:
    var handle := _source("res://ui/dockers/docker_drag_handle.gd")
    assert_true(handle.contains("static func capture_move("), "The ALT-left drag has a seam of its own")
    var body := _body_from(handle, "static func _drive_alt_left_drag(")
    assert_true(body.contains("press.alt_pressed = true"), "which holds ALT down itself")
    assert_true(body.contains("MOUSE_BUTTON_LEFT"), "on the left button, which is what a move is")

    # The `drag` step reaches it, and still falls through for a spec this seam
    # cannot serve: `scenarios/note-image.json` drags a note window `via`
    # `input`, and a note has no DragHandleInput behind it.
    # The dispatch chain is `harness/sa_step_table.gd`, and the
    # fallback is an instance method on the input driver rather than a static
    # handed the runner back.
    var dispatch := _source("res://harness/sa_step_table.gd")
    assert_true(dispatch.contains("DockerDragHandle.capture_move(_run.tree()"), "The drag step tries the seam")
    assert_true(dispatch.contains("_input.drag_window("), "and falls back when it answers nothing")
