## The Reference docker shows one picture alone, a "Focusing one image" toggle.
##
## Built outside the tree the way the hover bar's suite builds it, because a
## `Window` in the tree hangs a headless run. The running app's side, the board,
## the solo view and the board again, is
## `scenarios/the-reference-docker-shows-one-picture-alone.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const REFERENCE_IMAGE := "res://ui/icon.png"


func _docker() -> ReferenceDocker:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(300, 200)
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE, REFERENCE_IMAGE, REFERENCE_IMAGE]))
    return docker


func _escape() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.pressed = true
    return event


## Solo on the middle picture of three: only it is drawn, only it answers a
## pick, and the other two's places on screen find nothing.
func test_one_of_three_is_drawn_and_picked_alone() -> void:
    var docker := _docker()
    var board := docker.board()
    var middle := board.pictures[1]
    var others := [board.pictures[0], board.pictures[2]]
    assert_eq(board.ordered().size(), 3, "The board draws three")

    assert_true(docker.board_view.toggle_solo(middle), "Solo takes")
    assert_eq(board.soloed(), middle, "on the middle picture")
    assert_eq(board.ordered(), [middle], "and it is the whole of what is drawn")
    assert_eq(docker.report()["solo"], 1, "the dump names it")
    var rect := board.view_rect(middle)
    assert_true(rect.size.x <= docker.board_view.size.x + 0.5, "fitted across")
    assert_true(rect.size.y <= docker.board_view.size.y + 0.5, "and down")
    assert_true(docker.sample_at(rect.get_center()), "its middle is picked")
    for other: SaReferenceBoard.Picture in others:
        var at := board.to_view(other.rect.get_center())
        assert_eq(docker.board_view.texel_at(at), Vector2i(-1, -1), "a hidden picture's place picks nothing")
        assert_null(board.picture_at(other.rect.get_center()), "and is not under the pointer either")
    docker.free()


## Leaving solo puts back the zoom and offset the board had, whichever of the
## three ways out is taken.
func test_leaving_solo_restores_the_view() -> void:
    var docker := _docker()
    var board := docker.board()
    docker.board_view.zoom_about(Vector2(40, 30), 1.7)
    docker.board_view.pan_by(Vector2(13, -9))
    var zoom := board.zoom
    var offset := board.offset

    docker.board_view.toggle_solo(board.pictures[2])
    docker.board_view.pan_by(Vector2(50, 50))
    docker.board_view.zoom_about(Vector2(10, 10), 2.0)
    assert_true(docker.board_view.toggle_solo(null), "The same toggle leaves")
    assert_almost_eq(board.zoom, zoom, 0.0001, "at the zoom it had")
    assert_true(board.offset.is_equal_approx(offset), "and the offset")
    assert_eq(board.ordered().size(), 3, "with every picture back")
    assert_eq(docker.report()["solo"], -1, "and the dump says so")

    docker.board_view.toggle_on(board.pictures[0], ReferencePictureView.SOLO)
    assert_eq(board.soloed(), board.pictures[0], "The hover bar's toggle id solos too")
    assert_true(docker.board_view.escape(_escape()), "Escape leaves")
    assert_true(board.offset.is_equal_approx(offset), "to the same view")
    docker.board_view.escape(_escape())
    assert_null(board.soloed(), "and a second Escape has no solo to leave")
    assert_null(docker.board_view.selected(), "so it unselects instead, which is the click on the empty board's")
    docker.free()


## The docker's button solos the selected picture and is pressed while it
## holds, and a second press brings the board back.
func test_the_button_solos_the_selected_picture() -> void:
    var docker := _docker()
    var board := docker.board()
    var first := board.pictures[0]
    docker.board_view.select_picture(first)
    var button := docker.find_child("SoloButton", true, false) as Button
    assert_not_null(button, "The bar has a Solo")

    button.pressed.emit()
    assert_eq(board.soloed(), first, "which solos the selected one")
    assert_true(button.button_pressed, "and reads pressed")
    button.pressed.emit()
    assert_null(board.soloed(), "A second press leaves")
    assert_false(button.button_pressed, "and it reads up")
    docker.free()


## The right click's menu offers solo over a picture and the way out while
## solo holds, and its row is the same toggle.
func test_the_menu_row_solos_and_leaves() -> void:
    var docker := _docker()
    var board := docker.board()
    var view := docker.board_view
    assert_true(view.fill_menu(null), "The empty board opens the menu")
    assert_false(view.menu.row_ids().has(ReferencePictureView.SOLO), "with no solo on it")
    assert_true(view.fill_menu(board.pictures[1]), "A picture offers solo")
    assert_true(view.menu.press_row(ReferencePictureView.SOLO), "and the row takes")
    assert_eq(board.soloed(), board.pictures[1], "solo on that picture")
    assert_true(view.fill_menu(null), "In solo the menu opens anywhere")
    assert_true(view.menu.press_row(ReferencePictureView.SOLO), "and its row")
    assert_null(board.soloed(), "leaves")
    docker.free()


## Solo is a view state: the header written during it carries the board's own
## view and no mark of solo, so the board opens whole.
func test_solo_is_not_saved() -> void:
    var docker := _docker()
    var board := docker.board()
    var before := board.to_header()
    docker.board_view.toggle_solo(board.pictures[1])
    var during := board.to_header()
    assert_eq(during, before, "The header in solo is the header before it")
    var back := SaReferenceBoard.from_header(during)
    assert_null(back.soloed(), "and a board read from it is whole")
    docker.free()


## A picture taken off the board takes solo with it, and the view comes back.
func test_removing_the_soloed_picture_leaves_solo() -> void:
    var docker := _docker()
    var board := docker.board()
    var offset := board.offset
    docker.board_view.toggle_solo(board.pictures[1])
    board.remove(board.pictures[1])
    assert_null(board.soloed(), "Solo is gone with the picture")
    assert_true(board.offset.is_equal_approx(offset), "and the view is the board's")
    assert_eq(board.ordered().size(), 2, "the other two drawn")
    docker.free()


## The shortcut profile can bind it: a command with a chord, under the dockers.
func test_the_solo_is_a_command_with_a_chord() -> void:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_id: StringName) -> void: pass)
    var command := registries.commands.get_descriptor(ReferencePictureView.SOLO_COMMAND)
    assert_not_null(command, "The solo is registered")
    assert_eq(SaCommandRegistry.format_events(command.default_events), "Ctrl+Alt+S", "on Ctrl+Alt+S")
    assert_eq(String(command.category), "docker", "under the dockers")


## The solo moves to Ctrl+Alt+D under Krita alone, where
## Ctrl+Alt+S saves as Krita's Save Incremental Version does, so Sara Default
## still solos on Ctrl+Alt+S, a trip to Krita and back included.
func test_sara_default_keeps_the_solo_on_ctrl_alt_s() -> void:
    var saved := _saved()
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_id: StringName) -> void: pass)
    var solo := ReferencePictureView.SOLO_COMMAND
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(solo), ["Ctrl+Alt+S"] as Array[String], "Sara Default solos on Ctrl+Alt+S")
    SaShortcutStore.apply_profile("Krita")
    assert_eq(SaShortcutStore.chords_for(solo), ["Ctrl+Alt+D"] as Array[String], "Krita on Ctrl+Alt+D")
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(solo), ["Ctrl+Alt+S"] as Array[String], "and Sara Default on Ctrl+Alt+S again")
    assert_false(SaShortcutStore.chords_for(&"file_save").has("Ctrl+Alt+S"), "which Save gave back")
    _restore(saved)


## Ctrl+Alt+S with the Reference docker hidden runs nothing and
## says in the corner what it does and that Shift+F shows the docker, rather
## than declining in silence. The registry's half, a docker shown again
## running the handler, is `test_a_dockers_chord_says_what_it_does_while_its_docker_is_hidden.gd`.
func test_the_chord_with_the_docker_hidden_says_what_it_does() -> void:
    var saved := _saved()
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_id: StringName) -> void: pass)
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    var docker := _docker()
    docker.visible = false
    registries.ui.register_docker(SaDockerIds.REFERENCE, "Reference", func() -> Window: return null, &"docker_reference")
    registries.ui.set_docker_node(SaDockerIds.REFERENCE, docker)
    var press := InputEventKey.new()
    press.keycode = KEY_S
    press.ctrl_pressed = true
    press.alt_pressed = true
    press.pressed = true

    var said: Array[String] = []
    var ear := func(text: String) -> void: said.append(text)
    EventBus.corner_notice.connect(ear)
    var answered := registries.commands.try_handle_input(press)
    EventBus.corner_notice.disconnect(ear)
    assert_true(answered, "The chord is answered")
    assert_eq(registries.commands.last_command, ReferencePictureView.SOLO_COMMAND, "by the solo")
    var line := 'Ctrl+Alt+S would run "Reference: show one picture alone".'
    line += " Show the Reference docker first (Shift+F)."
    assert_eq(said, [line] as Array[String], "which says what it does and how to show the docker")
    assert_null(docker.board().soloed(), "and solos nothing")

    docker.free()
    _restore(saved)


## Every action's chords, for [method _restore] to put back after a suite moved
## the profile.
func _saved() -> Dictionary:
    var saved := {}
    for action: StringName in InputMap.get_actions():
        saved[action] = InputMap.action_get_events(action).duplicate()
    return saved


func _restore(saved: Dictionary) -> void:
    for action: StringName in InputMap.get_actions():
        if not saved.has(action):
            InputMap.erase_action(action)
    for action: StringName in saved:
        InputMap.action_erase_events(action)
        for event: InputEvent in saved[action]:
            InputMap.action_add_event(action, event)
