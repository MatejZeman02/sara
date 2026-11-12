## Every Layers docker operation the note
## named answers to a chord, registered through the public door like
## `layer_clip_to_below` was.
##
## A new paint layer was Insert before it moved
## to Photoshop's Ctrl+Shift+N, which is why the note mode is no longer
## there. `ui/notes/tests/test_note_mode.gd` holds the other half. Ctrl+J
## went to Layer via Copy, which duplicates with nothing
## selected, so the chord still does what this suite reads it doing.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const CHORDS := {
    "layer_duplicate": "Ctrl+Alt+J",
    "layer_via_copy": "Ctrl+J",
    "layer_via_cut": "Ctrl+Shift+J",
    "layer_group": "Ctrl+G",
    "layer_merge_down": "Ctrl+E",
    "layer_new_paint": "Ctrl+Shift+N",
    "layer_delete": "Shift+Delete",
    "layer_move_up": "Ctrl+PageUp",
    "layer_move_down": "Ctrl+PageDown",
}


func test_every_layer_command_has_the_chord_the_plan_named() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    for command_id: String in CHORDS:
        assert_true(registries.commands.has(StringName(command_id)), "%s is registered" % command_id)
        assert_eq(registries.commands.chord_text(StringName(command_id)), CHORDS[command_id], "%s answers to it" % command_id)
    Fixtures.teardown(surface)


func test_ctrl_j_duplicates_the_active_layer() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    var before := doc.get_children().filter(func(c: Node) -> bool: return c is SaLayer).size()

    assert_true(registries.commands.execute(&"layer_via_copy"), "The command runs")
    var after := doc.get_children().filter(func(c: Node) -> bool: return c is SaLayer).size()
    assert_eq(after, before + 1, "and one more layer exists")

    Fixtures.teardown(surface)


func test_ctrl_g_groups_and_ungroups_the_active_layer() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document

    assert_true(registries.commands.execute(&"layer_group"), "Grouping runs")
    assert_true(doc.active_layer.is_group, "and the active layer is now the new group")
    assert_true(registries.commands.execute(&"layer_group"), "Pressed again")
    assert_false(doc.active_layer.is_group, "it ungroups")

    Fixtures.teardown(surface)


func test_delete_removes_the_active_layer() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    SaLayerOps.new(doc).add()
    var before := doc.get_children().filter(func(c: Node) -> bool: return c is SaLayer).size()

    assert_true(registries.commands.execute(&"layer_delete"), "The command runs")
    var after := doc.get_children().filter(func(c: Node) -> bool: return c is SaLayer).size()
    assert_eq(after, before - 1, "and one fewer layer exists")

    Fixtures.teardown(surface)
