## The view mirror's two chords.
##
## The H key for flipping horizontally did nothing. It was bound to nothing, so
## `SaAppCommands` registers a command for each mirror.
##
## The chord is the whole of the fix, so it is pinned three ways: what the two
## commands answer to, that nothing else answers to the same, and that neither
## shipped profile binds either. A chord that works on Sara Default and lands on
## another command under Krita is a chord that works for the person who wrote it
## and nobody else.
##
## The mirror itself is proved by `scenarios/mirror-chord.json`, because
## `_mirror` reaches the main canvas through the running scene and a headless
## suite has none.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Command id -> the chord it ships with.
const EXPECTED := {
    &"view_mirror_horizontal": "H",
    &"view_mirror_vertical": "Ctrl+Shift+H",
}


func _commands() -> SaCommandRegistry:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, Callable())
    return registries.commands


func test_the_two_mirrors_answer_to_h() -> void:
    var commands := _commands()
    for command_id: StringName in EXPECTED:
        assert_true(commands.has(command_id), "%s is registered" % command_id)
        assert_eq(commands.chord_text(command_id), EXPECTED[command_id], "%s answers to it" % command_id)


## Plain H was free when this was written and the point is that it stays free.
## The router's own chords are in too, because they are commands like any other.
func test_nothing_else_holds_either_chord() -> void:
    var router := ShortcutRouter.new()
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, Callable())
    router.bind_commands(registries.commands)
    var commands := registries.commands

    for command_id: StringName in commands.list_ids():
        if EXPECTED.has(command_id):
            continue
        for chord in commands.chord_text(command_id).split(", ", false):
            assert_false(
                chord == EXPECTED[&"view_mirror_horizontal"] or chord == EXPECTED[&"view_mirror_vertical"],
                "%s answers to %s, which the view mirror needs" % [command_id, chord]
            )
    router.free()


## The two profiles shipped in `SaShortcutStore`, checked because a profile is
## an override on top of the build's map: an entry there would take the chord
## away from the mirror for anyone on that profile and leave it working here.
func test_neither_shipped_profile_binds_either_chord() -> void:
    for profile: String in SaShortcutStore.SHIPPED_PROFILES:
        var table: Dictionary = SaShortcutStore.SHIPPED_PROFILES[profile]
        for action: String in table:
            for chord: String in SaShortcutStore.entry_chords(table[action]):
                assert_false(
                    chord == EXPECTED[&"view_mirror_horizontal"] or chord == EXPECTED[&"view_mirror_vertical"],
                    "the %s profile puts %s on %s" % [profile, action, chord]
                )
