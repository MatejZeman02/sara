## The Minimap's proof has a switch of its own, and the mode
## beside it reads whole.
##
## The mode once showed as a dropdown cut to 'Lightn' with no label, doing nothing
## until Ctrl+Shift+Y turned the proof on. Beside the switch it got what Flip H
## and Flip V left, so it has a row of its own, ProofRow, shown while the proof
## is on. The switch ends the flip row and shares `toggle_proof` with the chord.
extends "res://tests/test_framework.gd"

var _embedded: bool = false
var _host: Node = null
var _registries: SaRegistries = null
## Held, because a Callable does not keep its object alive, and a command whose
## handler's object was freed does nothing.
var _commands: SaShortcutCommands = null


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded
    _host = null
    _registries = null
    _commands = null


## The docker in a tree, with the built-in view transforms and the chord's
## command registered. In the tree rather than detached because the command
## finds the docker by its name from the root, the way it does in the app.
func _docker() -> MinimapDocker:
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    _registries.register_builtins()
    _commands = SaShortcutCommands.new(Callable(), Callable(), Callable(), null)
    _commands.register_into(_registries.commands)
    var tree := Engine.get_main_loop() as SceneTree
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    # Not `tree.root`, which is mid-`_ready` when a suite runs.
    _host = Node.new()
    _host.name = "MinimapProofHost"
    EventBus.add_child(_host)
    var docker := MinimapDocker.new()
    docker.view_transforms = _registries.view_transforms
    _host.add_child(docker)
    docker.show()
    var body := Theme.new()
    body.default_font = SaFonts.regular()
    body.default_font_size = SaUI.get_font_size()
    docker._control_node.theme = SaUI.shared_theme if SaUI.shared_theme != null else body
    return docker


## One layout pass from *node* down, the one the engine would run next frame.
func _sort(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort(child)


## What *button* needs to show *words* whole beside its arrow.
func _needed(button: Button, words: String) -> float:
    var font := button.get_theme_font(&"font")
    var font_size := button.get_theme_font_size(&"font_size")
    var arrow := 0.0
    if button.icon != null:
        arrow = float(button.icon.get_width())
        var cap := button.get_theme_constant(&"icon_max_width")
        if cap > 0:
            arrow = minf(arrow, float(cap))
        arrow += float(button.get_theme_constant(&"h_separation"))
    var words_width := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    return words_width + arrow + button.get_theme_stylebox(&"normal").get_minimum_size().x


func test_pressing_the_switch_turns_the_proof_on_and_off() -> void:
    var docker := _docker()
    var switch := docker.find_child("ProofSwitch", true, false) as Button
    assert_not_null(switch, "The docker has a Proof switch")
    if switch == null:
        return
    var row := switch.get_parent()
    assert_eq(String(row.name), "FlipRow", "at the end of the flip row, so the controls cost one band")
    assert_eq(row.get_child(row.get_child_count() - 1), switch, "after both flip buttons")
    assert_true(switch.toggle_mode, "It is a toggle")
    assert_false(docker.proof_on, "The proof starts off")
    assert_false(switch.button_pressed, "and the switch shows it off")

    switch.button_pressed = true
    switch.pressed.emit()
    assert_true(docker.proof_on, "A press turns the proof on")
    assert_true(switch.button_pressed, "and the switch shows it on")

    switch.button_pressed = false
    switch.pressed.emit()
    assert_false(docker.proof_on, "A second press turns it off")
    assert_false(switch.button_pressed, "and the switch shows it off")


func test_the_chords_command_moves_the_switch() -> void:
    var docker := _docker()
    var switch := docker.find_child("ProofSwitch", true, false) as Button
    assert_not_null(switch, "The docker has a Proof switch")
    if switch == null:
        return
    assert_true(_registries.commands.has(MinimapDocker.PROOF_COMMAND), "The chord's command is registered")
    _registries.commands.execute(MinimapDocker.PROOF_COMMAND)
    assert_true(docker.proof_on, "The chord's command turns the proof on")
    assert_true(switch.button_pressed, "and the switch shows pressed")
    _registries.commands.execute(MinimapDocker.PROOF_COMMAND)
    assert_false(docker.proof_on, "and off again")
    assert_false(switch.button_pressed, "and the switch lets go")

    var chord := _registries.commands.chord_text(MinimapDocker.PROOF_COMMAND)
    assert_false(chord.is_empty(), "The command has a chord")
    switch.mouse_entered.emit()
    assert_true(switch.tooltip_text.contains(chord), "and the switch's tooltip names it, '%s'" % switch.tooltip_text)
    var choice := docker.find_child("ProofMode", true, false) as Control
    assert_false(choice.tooltip_text.contains("turns it on"), "The mode's tooltip leaves turning it on to the switch")


func test_the_mode_reads_its_whole_name_at_the_default_width() -> void:
    var docker := _docker()
    docker.size = MinimapDocker.DEFAULT_SIZE
    var column := docker._control_node.get_node("VBoxContainer") as Control
    var choice := docker.find_child("ProofMode", true, false) as SaChoiceButton
    assert_not_null(choice, "The docker has its mode choice")
    if choice == null:
        return
    var was := SaSettings.minimap_proof_mode
    # The mode's row is there while the proof is on.
    docker.toggle_proof()
    docker._sync_proof_option()
    var modes := choice.choice_values()
    assert_true(modes.size() >= 2, "The built-in modes are offered, %d of them" % modes.size())
    for mode: Variant in modes:
        SaSettings.minimap_proof_mode = String(mode)
        docker._sync_proof_option()
        _sort(column)
        _sort(column)
        var name := String(_registries.view_transforms.get_descriptor(StringName(String(mode))).display_name)
        assert_eq(choice.text, name, "The choice shows %s by its name" % mode)
        var needed := _needed(choice, name)
        var cut := "At %d the choice is %.1f of the %.1f '%s' needs" % [docker.size.x, choice.size.x, needed, name]
        assert_true(choice.size.x + 0.5 >= needed, cut)
        var right := choice.position.x + choice.size.x
        assert_true(right <= choice.get_parent_control().size.x + 0.5, "and it ends inside its row for %s" % mode)
    SaSettings.minimap_proof_mode = was
