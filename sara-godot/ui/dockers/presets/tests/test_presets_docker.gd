## The brush presets docker: the chooser in a docker of its own.
##
## The docker is a Window, so it is built detached under a plain Node and its
## `_ready` never runs, which is how `test_tool_options_docker` exercises the
## others. What it looks like and what applying does are
## `scenarios/presets-docker.json` and its restart pair, because the claim
## about one settings object is about the running app.
##
## What is asserted here is the wiring nothing else can see: that the docker is
## registered the way every built-in is, that it hosts the chooser rather than a
## copy of it, and that with no bar to ask it says so instead of half working.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")


func _detached() -> Array:
    var host := Node.new()
    var docker := DockerScript.new()
    host.add_child(docker)
    return [host, docker]


func test_the_docker_is_registered_like_every_other_built_in() -> void:
    var source := FileAccess.get_file_as_string("res://ui/main/sa_builtin_dockers.gd")

    assert_true(
        source.contains('[SaDockerIds.BRUSH_PRESETS, "Brush Presets", presets_factory, &"docker_brush_presets"]'),
        "It goes through register_builtin_dockers, which is the door a module uses (hard rule 6)"
    )
    var labels := FileAccess.get_file_as_string("res://ui/settings/keyboard/shortcut_rows.gd")
    assert_true(labels.contains('"docker_brush_presets"'), "and its shortcut row reads as a name rather than as an id")


## The label and the shortcut id were once here and no command was ever
## registered behind either, so the row on the shortcut page named nothing and
## this was the one docker a painter could not bind a key to. A label without a
## command is the shape to watch for, and this is the assertion that would have
## caught it.
func test_a_command_answers_to_the_shortcut_id_the_label_names() -> void:
    var toggled: Array = []
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(docker_id: StringName) -> void: toggled.append(docker_id))

    assert_true(registries.commands.has(&"docker_brush_presets"), "there is a command under the id")
    assert_true(registries.commands.has_chord(&"docker_brush_presets"), "with a chord, like every other docker's")
    assert_true(registries.commands.execute(&"docker_brush_presets"), "and running it does something")
    assert_eq(toggled, [&"BrushPresetsDocker"], "which is toggling this docker by its registered id")


## The id the command hands the manager is the **registered docker id** and not
## the shortcut id, and that is the bug under the missing command: the docker's
## own reveal must not ask `toggle_docker_by_id` with `docker_brush_presets`,
## which matches nothing in the docker list, so the loop returned having toggled
## nothing and the `visible` fallback did the work. The checkmark, the geometry
## restore and the saved layout never followed.
func test_the_command_names_the_docker_rather_than_the_shortcut() -> void:
    var ids: Array[StringName] = []
    for entry: Array in SaAppCommands.DOCKER_COMMANDS:
        ids.append(entry[1])

    assert_true(ids.has(&"BrushPresetsDocker"), "the table carries the registered id")
    assert_false(ids.has(&"docker_brush_presets"), "and not the shortcut id, which the manager matches nothing against")


func test_the_docker_hosts_the_chooser_rather_than_a_second_grid() -> void:
    var pair := _detached()
    var docker: Window = pair[1]

    var chooser: Variant = docker.get("chooser")
    assert_not_null(chooser, "The docker built one")
    assert_true(chooser is SaBrushPresetsChooser, "and it is the chooser's control, not a copy of its grid")
    assert_not_null(docker.find_child("Scroll", true, false), "shown through a scroll, because a grid is taller than a docker")

    (pair[0] as Node).free()


## The docker asks the bar for the store, the tool and the settings source, so
## the two hosts cannot drift. Detached there is no bar, and both answers say so
## rather than reaching for a store of their own.
func test_with_no_bar_it_binds_nothing_and_applies_nothing() -> void:
    var pair := _detached()
    var docker: Window = pair[1]

    assert_false(bool(docker.call("rebind")), "No bar to bind to")
    assert_false(bool(docker.call("apply_preset", "Whatever")), "and nothing to apply through")

    var state: Dictionary = docker.call("capture_state")
    assert_false(bool(state["bound"]), "which the dump says out loud")
    assert_eq(int((state["chooser"] as Dictionary)["count"]), 0, "and the grid is empty rather than showing a stray library")

    (pair[0] as Node).free()


## The geometry the docker asks for, and the reason a docker declares a minimum at
## all: a column narrower than its own content overhangs its right edge.
func test_it_opens_wide_enough_for_two_columns_of_the_default_icon() -> void:
    var pair := _detached()
    var docker: Window = pair[1]

    assert_eq(docker.get("logical_size"), DockerScript.DEFAULT_SIZE, "It opens at the size it declares")
    assert_eq(docker.get("logical_min_size"), DockerScript.MIN_SIZE, "and cannot be dragged under its minimum")
    assert_true(DockerScript.DEFAULT_SIZE.x >= 2 * SaBrushPresetsChooser.MIN_ICON, "which holds two of the smallest icons")

    (pair[0] as Node).free()
