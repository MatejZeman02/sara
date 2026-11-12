## The Minimap's flip row, proof row, gamut row and map are elements of its
## Preferences page, and each hides alone while its command keeps working.
##
## A painter can hide all of it except the actual minimap. The page once offered
## the drag handle and the resizer and nothing else.
extends "res://tests/test_framework.gd"

const CATEGORY := "MinimapDocker"
const ROWS: Dictionary[String, String] = {
    "Flip Buttons": "FlipRow",
    "Proof": "ProofRow",
    "Proof Gamut": "GamutRow",
    "Map": "MarginContainer",
}

var _embedded: bool = false
var _host: Node = null
var _registries: SaRegistries = null
## Held, because a Callable does not keep its object alive.
var _commands: SaShortcutCommands = null
var _easel: SaEasel = null
var _shown_before: Dictionary[String, bool] = {}
var _proof_mode_before: String = ""


func before_each() -> void:
    _shown_before.clear()
    for element: String in ROWS:
        _shown_before[element] = SaSettings.get_element_visible(CATEGORY, element)
    _proof_mode_before = SaSettings.minimap_proof_mode


func after_each() -> void:
    for element: String in _shown_before:
        SaSettings.set_element_visible(CATEGORY, element, _shown_before[element])
    SaSettings.minimap_proof_mode = _proof_mode_before
    if _host != null and is_instance_valid(_host):
        _host.free()
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded
    if _easel != null and is_instance_valid(_easel):
        _easel.free()
    _host = null
    _easel = null
    _registries = null
    _commands = null


## The docker in a tree with the built-in view transforms and the proof's
## chord registered, every row shown to begin with.
func _docker() -> MinimapDocker:
    for element: String in ROWS:
        SaSettings.set_element_visible(CATEGORY, element, true)
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    _registries.register_builtins()
    _commands = SaShortcutCommands.new(Callable(), Callable(), Callable(), null)
    _commands.register_into(_registries.commands)
    var tree := Engine.get_main_loop() as SceneTree
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "MinimapHost"
    EventBus.add_child(_host)
    var docker := MinimapDocker.new()
    docker.view_transforms = _registries.view_transforms
    _host.add_child(docker)
    docker.show()
    docker.apply_layout_settings()
    return docker


func _row(docker: MinimapDocker, element: String) -> Control:
    return docker.find_child(ROWS[element], true, false) as Control


## One layout pass from *node* down, the one the engine would run next frame.
func _sort(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort(child)


## A canvas in the tree for the docker to show, freed with the host.
func _canvas(docker: MinimapDocker) -> SaCanvas:
    _easel = SaEasel.create_default(Vector2i(400, 300))
    var canvas := SaCanvas.new()
    canvas.easel = _easel
    _host.add_child(canvas)
    docker.target_canvas = canvas
    return canvas


func _soft_proof_on(docker: MinimapDocker) -> void:
    SaSettings.minimap_proof_mode = "soft_proof"
    docker._sync_proof_option()
    if not docker.proof_on:
        docker.toggle_proof()


func test_the_page_lists_the_four_rows_after_the_base_elements() -> void:
    var order := SaSettings.get_layout_order(CATEGORY)
    assert_eq(order.slice(0, 2), ["Drag Handle", "Resizer"], "The base elements lead, %s" % [order])
    for element: String in ROWS:
        assert_true(order.has(element), "The Minimap's page lists %s" % element)
        assert_false(SaSettings.DEFAULT_HIDDEN.get(CATEGORY, []).has(element), "and a fresh profile shows %s" % element)
    var titles := SaSettings.reorderable_categories().map(func(entry: Dictionary) -> String: return entry["title"])
    assert_eq(titles.count("Minimap"), 1, "Preferences has one Minimap page, %s" % [titles])


func test_each_row_hides_alone() -> void:
    var docker := _docker()
    _soft_proof_on(docker)
    for element: String in ROWS:
        SaSettings.set_element_visible(CATEGORY, element, false)
        docker.apply_layout_settings()
        for other: String in ROWS:
            var row := _row(docker, other)
            assert_not_null(row, "The docker has its %s row" % other)
            if row == null:
                return
            # The flip row also holds the proof switch, so it stands while
            # either of its two elements is shown, and each control answers to
            # its own element.
            var expected := other != element
            if other == "Flip Buttons":
                expected = true
            assert_eq(row.visible, expected, "With %s hidden, %s is %s" % [element, other, "shown" if expected else "hidden"])
        var flips := docker.find_child("FlipHorizontal", true, false) as Control
        var switch := docker.find_child("ProofSwitch", true, false) as Control
        assert_eq(flips.visible, element != "Flip Buttons", "With %s hidden, the flip buttons follow their element" % element)
        assert_eq(switch.visible, element != "Proof", "and so does the proof switch")
        SaSettings.set_element_visible(CATEGORY, element, true)
        docker.apply_layout_settings()


func test_with_the_three_rows_hidden_the_map_fills_the_content_and_a_click_still_centres_the_view() -> void:
    var docker := _docker()
    docker.size = MinimapDocker.DEFAULT_SIZE
    for element: String in ["Flip Buttons", "Proof", "Proof Gamut"]:
        SaSettings.set_element_visible(CATEGORY, element, false)
    docker.apply_layout_settings()
    assert_false(_row(docker, "Flip Buttons").visible, "The flip row has nothing left to hold, so it is hidden")
    var column := docker._control_node.get_node("VBoxContainer") as VBoxContainer
    _sort(docker._control_node)
    _sort(docker._control_node)
    var map := _row(docker, "Map")
    var above := 0.0
    if docker.drag_handle.visible:
        above = docker.drag_handle.size.y + column.get_theme_constant(&"separation")
    assert_almost_eq(
        map.size.y,
        column.size.y - above,
        0.5,
        "The map fills the content under the drag bar, %.1f of %.1f" % [map.size.y, column.size.y]
    )

    var canvas := _canvas(docker)
    var overlay := docker.find_child("ViewOverlay", true, false) as Control
    var rect := MinimapDocker.picture_rect(overlay.size, canvas.document.canvas_size)
    var target := Vector2(300, 100)
    var click := InputEventMouseButton.new()
    click.button_index = MOUSE_BUTTON_LEFT
    click.pressed = true
    click.position = MinimapDocker.document_to_map(target, rect, canvas.document.canvas_size)
    docker.overlay_input(click)
    var view := SaCanvasView.for_canvas(canvas)
    var middle := view.screen_to_document(view.get_viewport_size() * 0.5)
    assert_almost_eq(middle.x, target.x, 0.5, "A click on the map alone still centres the view there")
    assert_almost_eq(middle.y, target.y, 0.5, "on both axes")


func test_the_chord_turns_the_proof_on_with_the_proof_row_hidden() -> void:
    var docker := _docker()
    SaSettings.set_element_visible(CATEGORY, "Proof", false)
    docker.apply_layout_settings()
    assert_false(_row(docker, "Proof").visible, "The proof row is hidden")
    assert_false((docker.find_child("ProofSwitch", true, false) as Control).visible, "with its switch")
    assert_false(docker.proof_on, "and the proof starts off")
    var key := InputEventKey.new()
    key.keycode = KEY_Y
    key.ctrl_pressed = true
    key.shift_pressed = true
    key.pressed = true
    assert_eq(_registries.commands.chord_text(MinimapDocker.PROOF_COMMAND), "Ctrl+Shift+Y", "The proof's chord is Ctrl+Shift+Y")
    assert_true(_registries.commands.try_handle_input(key), "Ctrl+Shift+Y is taken")
    assert_true(docker.proof_on, "and turns the minimap's proof on")


func test_a_hidden_gamut_row_stays_hidden_when_a_soft_proof_comes_on() -> void:
    var docker := _docker()
    _soft_proof_on(docker)
    assert_true(_row(docker, "Proof Gamut").visible, "Shown, a soft proof brings the gamut row")
    docker.toggle_proof()
    SaSettings.set_element_visible(CATEGORY, "Proof Gamut", false)
    docker.apply_layout_settings()
    _soft_proof_on(docker)
    assert_true(docker.proof_on, "The soft proof is on")
    assert_false(_row(docker, "Proof Gamut").visible, "and the hidden gamut row stays hidden")
    docker._sync_proof_option()
    assert_false(_row(docker, "Proof Gamut").visible, "after the next poll as well")


func test_the_flip_still_mirrors_the_map_with_the_flip_row_hidden() -> void:
    var docker := _docker()
    SaSettings.set_element_visible(CATEGORY, "Flip Buttons", false)
    docker.apply_layout_settings()
    assert_false((docker.find_child("FlipHorizontal", true, false) as Control).visible, "The flip buttons are hidden")
    var canvas := _canvas(docker)
    SaCanvasView.for_canvas(canvas).set_flip(Vector2(-1, 1))
    docker._sync_flip()
    var picture := docker.find_child("Picture", true, false) as TextureRect
    assert_true(picture.flip_h, "and the view's flip still mirrors the map")
